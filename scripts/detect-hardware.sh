#!/usr/bin/env bash
# Rileva l'hardware e RACCOMANDA sizing VM, modello locale, tuning Ollama.
# Solo lettura.  --emit-config stampa i frammenti pronti da incollare.
set -uo pipefail
EMIT=0; [ "${1:-}" = "--emit-config" ] && EMIT=1
sec(){ echo -e "\n\033[36m━━ $* ━━\033[0m"; }
kv(){ printf "  %-22s %s\n" "$1" "$2"; }
rec(){ echo -e "  \033[32m→\033[0m $*"; }
warn(){ echo -e "  \033[33m!\033[0m $*"; }

sec "CPU e memoria"
CORES=$(nproc 2>/dev/null || echo 0)
MODEL=$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//')
RAM_GB=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
RAM_AV=$(awk '/MemAvailable/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
SWAP=$(awk '/SwapTotal/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
CHASSIS=$(hostnamectl chassis 2>/dev/null || echo unknown)
[ -d /sys/class/power_supply/BAT0 ] && CHASSIS=laptop
kv "CPU" "${MODEL:-n/d} (${CORES} core)"; kv "RAM" "${RAM_GB} GB (liberi ${RAM_AV} GB)"
kv "Swap" "${SWAP} GB"; kv "Macchina" "$CHASSIS"

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
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null \
    | while IFS=, read -r i n m; do kv "GPU $i" "$n —$m"; done
  V=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' '); V=${V:-0}
  NG=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
  if   [ "$V" -ge 40000 ]; then
    rec "Fascia server: usa vLLM (multi-utente), non Ollama"
    rec "Modello: Qwen3-Coder-Next 80B-A3B (MoE, ~35-40 GB Q4/FP8) — vedi docs/BIOME-L40S.md"
    [ "$NG" -ge 2 ] && rec "$NG GPU: UN modello per GPU (no NVLink su L40S → evita tensor-parallel)"
  elif [ "$V" -ge 20000 ]; then OLL="qwen2.5-coder:14b"; rec "14B interamente in VRAM"
  elif [ "$V" -ge 10000 ]; then OLL="qwen2.5-coder:7b";  rec "7B interamente in VRAM (~30 tok/s)"
  elif [ "$V" -ge 6000 ];  then OLL="qwen2.5-coder:7b"; NGPU_LAYERS=24; rec "7B con offload parziale (num_gpu ~24)"
  elif [ "$V" -ge 3500 ];  then
    OLL="qwen2.5-coder:3b"
    rec "3B in VRAM (veloce: FIM e task bounded)"
    [ "$RAM_AV" -ge 12 ] && { NGPU_LAYERS=28; rec "Con ${RAM_AV} GB liberi: ANCHE 7B in offload (num_gpu ~28, 8-15 tok/s)"; }
    warn "Un 3B non regge il coding agentico complesso: usalo come Tier 0"
  else warn "VRAM ${V} MiB: solo CPU (lento, adatto a batch)"; fi
  [ "$CHASSIS" = laptop ] && warn "Laptop: OLLAMA_KEEP_ALIVE=2m (termico/batteria)"
else
  kv "GPU NVIDIA" "non rilevata"; rec "Nessuna inferenza locale: usa le lane cloud/BIOME"
fi

sec "Virtualizzazione e rete"
grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null && kv KVM supportato || warn "virtualizzazione HW non attiva (BIOS?)"
command -v virsh >/dev/null 2>&1 && kv libvirt presente || warn "libvirt assente: apt install virt-manager libvirt-daemon-system"
BRIP=""
if ip -4 addr show virbr0 >/dev/null 2>&1; then
  BRIP=$(ip -4 -o addr show virbr0 | awk '{print $4}' | cut -d/ -f1)
  kv virbr0 "$BRIP"; rec "Ollama va bindato su $BRIP (NON 0.0.0.0)"
else warn "virbr0 assente: rete libvirt 'default' non attiva"; fi
command -v docker >/dev/null 2>&1 && kv docker "$(docker --version 2>/dev/null)" || warn "docker assente (serve nella VM)"

sec "Disco"; df -h / 2>/dev/null | awk 'NR<=2{printf "  %s\n",$0}'

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
