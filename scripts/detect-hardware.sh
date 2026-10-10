#!/usr/bin/env bash
# Rileva l'hardware e RACCOMANDA sizing VM, modello locale, tuning Ollama.
# Solo lettura.  --emit-config stampa i frammenti pronti da incollare.
#                --json stampa i FATTI (non le raccomandazioni) per gli script
#                che decidono (P2, ADR-0018). Schema: "schema": 1.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/hw-detect.sh
. "$HERE/lib/hw-detect.sh"
# shellcheck source=lib/llm-plan.sh
. "$HERE/lib/llm-plan.sh"
EMIT=0; [ "${1:-}" = "--emit-config" ] && EMIT=1

# --json: fatti, niente testo. JSON generato con la stdlib di Python (HC-12
# adattata, ADR-0022): niente jq, niente JSON concatenato a mano.
if [ "${1:-}" = "--json" ]; then
  GPU_ROWS=""
  for a in $(nvidia_pci_devices); do
    GPU_ROWS="$GPU_ROWS$a"$'\t'"$(nvidia_pci_name "$a")"$'\t'"$(nvidia_pci_driver "$a")"$'\n'
  done
  VRAM=$(hw_vram_mb); DISKP=$(vm_disk_path)
  IFS='|' read -r LV LM _ _ <<<"$(llm_plan "${VRAM:-0}" "$(hw_ram_gb)" "$(hw_disk_free_gb)")"
  BR=$(ip -4 -o addr show virbr0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  # Una riga per fatto, chiave=valore; i booleani come 0/1. Python li tipizza.
  {
    echo "os_id=$(os_field ID)"; echo "os_version_id=$(os_field VERSION_ID)"
    echo "os_variant_id=$(os_field VARIANT_ID)"; echo "os_pretty=$(os_pretty)"
    echo "os_family=$(os_family)"
    echo "atomic=$(os_is_atomic && echo 1 || echo 0)"; echo "ublue=$(os_is_ublue && echo 1 || echo 0)"
    echo "sandbox=$(sandbox_kind)"
    echo "cpu_model=$(hw_cpu_model)"; echo "cpu_cores=$(hw_cores)"; echo "ram_gb=$(hw_ram_gb)"
    echo "chassis=$(hw_chassis)"; echo "kvm=$(hw_kvm && echo 1 || echo 0)"
    echo "vram_mb=$VRAM"; echo "nvidia_module=$(nvidia_kernel_module_loaded && echo 1 || echo 0)"
    echo "disk_path=$DISKP"; echo "disk_free_gb=$(hw_disk_free_gb)"
    echo "virbr0_ip=$BR"
    echo "libvirt=$(command -v virsh >/dev/null 2>&1 && echo 1 || echo 0)"
    echo "docker=$(command -v docker >/dev/null 2>&1 && echo 1 || echo 0)"
    echo "llm_verdict=$LV"; echo "llm_models=$LM"
  } | GPU_ROWS="$GPU_ROWS" python3 -c '
import json, os, sys
BOOL = {"atomic", "ublue", "kvm", "nvidia_module", "libvirt", "docker"}
INT = {"cpu_cores", "ram_gb", "vram_mb", "disk_free_gb"}
f = {"schema": 1}
for line in sys.stdin.read().splitlines():
    k, _, v = line.partition("=")
    if k in BOOL: f[k] = v == "1"
    elif k in INT: f[k] = int(v) if v.isdigit() else None
    elif k == "llm_models": f[k] = v.split()
    else: f[k] = v or None
f["gpus"] = [dict(zip(("pci", "name", "driver"), (r.split("	") + ["", "", ""])[:3]))
             for r in os.environ.get("GPU_ROWS", "").splitlines() if r]
for g in f["gpus"]: g["driver"] = g["driver"] or None
print(json.dumps(f, indent=2, ensure_ascii=False))'
  exit $?
fi
sec(){ echo -e "\n\033[36m━━ $* ━━\033[0m"; }
kv(){ printf "  %-22s %s\n" "$1" "$2"; }
rec(){ echo -e "  \033[32m→\033[0m $*"; }
warn(){ echo -e "  \033[33m!\033[0m $*"; }

sec "CPU e memoria"
CORES=$(hw_cores); MODEL=$(hw_cpu_model); RAM_GB=$(hw_ram_gb)
RAM_AV=$(awk '/MemAvailable/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
SWAP=$(awk '/SwapTotal/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
CHASSIS=$(hw_chassis)
kv "CPU" "${MODEL:-n/d} (${CORES} core)"; kv "RAM" "${RAM_GB} GB (liberi ${RAM_AV} GB)"
kv "Swap" "${SWAP} GB"; kv "Macchina" "$CHASSIS"
kv "Sistema" "$(os_pretty)$(os_is_atomic && echo '  [atomico: /usr in sola lettura]')"
SANDBOX=$(sandbox_kind)
if [ -n "$SANDBOX" ]; then
  warn "SANDBOX \033[1m$SANDBOX\033[0m: qui non vedi i comandi dell'host."
  warn "Ogni 'assente' qui sotto significa 'non esposto nel sandbox', NON 'non installato'."
  rec "per un quadro vero: $(host_run_hint './scripts/detect-hardware.sh')"
fi

sec "Sizing VM servizi"
if [ "$RAM_GB" -ge 24 ]; then
  rec "VM: 2 vCPU, 4 GB RAM (compose: litellm 2G / postgres 1G)"
  rec "Restano ~$((RAM_AV-4)) GB per IDE, agenti e offload LLM"
elif [ "$RAM_GB" -ge 12 ]; then
  rec "VM: 2 vCPU, 3 GB RAM"; warn "abbassa i limiti compose (litellm 1.5G / postgres 768M)"
else
  warn "RAM ${RAM_GB} GB insufficiente per VM + IDE + LLM: valuta i servizi sull'host"
fi
kv "Disco VM" "20 GB qcow2 thin (qcow2 OBBLIGATORIO per gli snapshot)"

sec "GPU e inferenza locale"
OLL=""; NGPU_LAYERS=""
# L'hardware si cerca sul bus PCI, PRIMA di chiedere a nvidia-smi: dedurre
# l'assenza di una GPU dall'assenza di un binario e' sbagliato su un OS
# atomico senza driver proprietari, a dGPU spenta e dentro un container.
GPU_ADDRS=$(nvidia_pci_devices)
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null \
    | while IFS=, read -r i n m; do kv "GPU $i" "$n —$m"; done
  V=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' '); V=${V:-0}
  NG=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
  VRAM_SEEN=$V
  if [ "$V" -ge 40000 ]; then
    rec "Fascia server: usa vLLM (multi-utente), non Ollama"
    rec "Modello: Qwen3-Coder-Next 80B-A3B (MoE, ~35-40 GB Q4/FP8) — vedi docs/BIOME-L40S.md"
    [ "$NG" -ge 2 ] && rec "$NG GPU: UN modello per GPU (no NVLink su L40S → evita tensor-parallel)"
  fi
  [ "$CHASSIS" = laptop ] && warn "Laptop: OLLAMA_KEEP_ALIVE=2m (termico/batteria)"
elif [ -n "$GPU_ADDRS" ]; then
  # C'E' l'hardware ma non gli strumenti: dirlo, invece di dichiarare
  # "non rilevata" e mandare l'utente sulle lane cloud per niente.
  for a in $GPU_ADDRS; do
    kv "GPU NVIDIA" "$(nvidia_pci_name "$a")"
    kv "" "PCI $a · driver: $(nvidia_pci_driver_label "$a")"
  done
  warn "hardware presente ma nvidia-smi non risponde: VRAM non misurabile"
  rec "$(nvidia_missing_hint "$(nvidia_pci_driver "${GPU_ADDRS%%$'\n'*}")")"
  nvidia_kernel_module_loaded && rec "il modulo kernel nvidia E' caricato"
  if [ -n "$SANDBOX" ]; then
    # Da qui non si puo' dire se l'host possa fare inferenza: si puo' solo
    # dire che da QUI non si vede. Affermare il resto sarebbe inventare.
    warn "da dentro il sandbox non posso dire se l'host regga l'inferenza locale: rilancia sull'host"
  else
    warn "finche' resta cosi', l'inferenza locale non e' disponibile: usa le lane cloud/BIOME"
  fi
else
  kv "GPU NVIDIA" "non rilevata"
  kv "" "nessun dispositivo 0x10de di classe 0x03 sul bus PCI"
  rec "Nessuna inferenza locale: usa le lane cloud/BIOME"
fi

# Una sola tabella hardware → modelli, la stessa che setup-ollama.sh applica
# (scripts/lib/llm-plan.sh): i modelli sono quelli del gateway, l'hardware
# decide quali entrano.
sec "LLM locale: cosa regge questa macchina"
DISK_LLM=$(hw_disk_free_gb)
IFS='|' read -r LLM_VERDICT LLM_MODELS NGPU_LAYERS LLM_NOTE <<<"$(llm_plan "${VRAM_SEEN:-0}" "$RAM_GB" "${DISK_LLM:-0}")"
kv "Verdetto" "$LLM_VERDICT"
kv "Modelli" "${LLM_MODELS:-nessuno}"
rec "$LLM_NOTE"
[ -n "$NGPU_LAYERS" ] && rec "offload stimato: ~${NGPU_LAYERS}/28 layer in GPU (Ollama decide da solo)"
[ -n "$SANDBOX" ] && warn "sandbox: GPU, RAM e disco visti da qui possono non essere quelli dell'host"
OLL=$(echo "$LLM_MODELS" | awk '{print $NF}')
[ -n "$OLL" ] && rec "per installare, verificare e poter annullare: ./scripts/setup-ollama.sh (--plan per rivedere)"

sec "Virtualizzazione e rete"
hw_kvm && kv KVM supportato || warn "virtualizzazione HW non attiva (BIOS?)"
if command -v virsh >/dev/null 2>&1; then kv libvirt presente
elif [ -n "$SANDBOX" ]; then warn "virsh non visibile nel sandbox (sull'host puo' esserci)"
else warn "libvirt assente"; rec "$(pkg_hint libvirt)"; fi
BRIP=""
if ip -4 addr show virbr0 >/dev/null 2>&1; then
  BRIP=$(ip -4 -o addr show virbr0 | awk '{print $4}' | cut -d/ -f1)
  kv virbr0 "$BRIP"; rec "Ollama va bindato su $BRIP (NON 0.0.0.0)"
else warn "virbr0 assente: rete libvirt 'default' non attiva"; fi
if command -v docker >/dev/null 2>&1; then kv docker "$(docker --version 2>/dev/null)"
elif [ -n "$SANDBOX" ]; then warn "docker non visibile nel sandbox (serve comunque solo NELLA VM)"
else warn "docker assente sull'host"; rec "$(pkg_hint docker)"; fi

sec "Disco"
# Si guarda dove finira' il qcow2, non "/": su un OS atomico "/" e' l'overlay
# composefs e riporta ~meta' della RAM, che col disco non c'entra niente.
DISKP=$(vm_disk_path)
kv "Percorso valutato" "$DISKP"
df -h "$DISKP" 2>/dev/null | awk 'NR<=2{printf "  %s\n",$0}'
if [ -n "$SANDBOX" ]; then
  warn "sandbox: questo filesystem e' quello del sandbox, non il disco dell'host"
elif os_is_atomic && [ "$DISKP" = "/" ]; then
  warn "OS atomico: '/' e' un overlay composefs, la dimensione NON e' quella del disco"
fi

if [ "$EMIT" = 1 ] && [ -n "$OLL" ]; then
sec "Frammenti pronti"
BRIP=${BRIP:-192.168.122.1}
cat <<EOC

# --- systemctl edit ollama.service ---
[Unit]
After=libvirtd.service network-online.target
Wants=network-online.target
[Service]
Environment="OLLAMA_HOST=${BRIP}:11434"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
$([ "$CHASSIS" = laptop ] && echo 'Environment="OLLAMA_KEEP_ALIVE=2m"')

# --- services/litellm_config.yaml ---
  - model_name: local-fast
    litellm_params:
      model: ollama_chat/${OLL}
      api_base: http://${BRIP}:11434
      timeout: 300

ollama pull ${OLL}
$([ -n "$NGPU_LAYERS" ] && echo "# offload parziale:  /set parameter num_gpu ${NGPU_LAYERS}")
EOC
fi
if [ "$EMIT" = 1 ] && [ -z "$OLL" ]; then
  echo -e "\n\033[2m--emit-config: nessun frammento da emettere (i frammenti Ollama\033[0m"
  echo -e "\033[2msi generano solo con una GPU rilevata; su questa macchina non ce n'e').\033[0m"
elif [ "$EMIT" = 0 ]; then
  echo -e "\n\033[2mRilancia con --emit-config per i frammenti.\033[0m"
fi
