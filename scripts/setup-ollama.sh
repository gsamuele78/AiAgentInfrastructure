#!/usr/bin/env bash
# ============================================================
#  setup-ollama.sh -- installa e configura l'LLM LOCALE, applicando
#  ciò che detect-hardware.sh si limitava a stampare.
#
#  Sceglie il modello in base alla VRAM, binda su virbr0 (mai 0.0.0.0),
#  applica il tuning per VRAM stretta, verifica dalla VM e stampa il
#  blocco da aggiungere a litellm_config.yaml.
#
#  Uso:  ./setup-ollama.sh
#        ./setup-ollama.sh --dry-run
#        MODEL=qwen2.5-coder:7b ./setup-ollama.sh    forza il modello
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/hw-detect.sh
. "$HERE/lib/hw-detect.sh"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else eval "$*"; fi; }
say(){ echo -e "\n\033[36m━━ $* ━━\033[0m"; }
ok(){ echo -e "  \033[32m✓\033[0m $*"; }
warn(){ echo -e "  \033[33m!\033[0m $*"; }
die(){ echo -e "  \033[31m✗\033[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. rete
say "1. Bridge libvirt (dove la VM raggiunge l'host)"
BRIP=$(ip -4 -o addr show virbr0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
if [ -z "$BRIP" ]; then
  warn "virbr0 assente: la rete libvirt 'default' non è attiva"
  warn "Ollama verrà bindato su 127.0.0.1 e la VM NON lo vedrà"
  BRIP="127.0.0.1"
else ok "virbr0 = $BRIP  → Ollama ascolterà qui (non su 0.0.0.0)"; fi

# ---------------------------------------------------------------- 2. gpu
say "2. GPU e scelta del modello"
VRAM=0; LAYERS=""
# Come in detect-hardware.sh: l'hardware si cerca sul bus PCI, non nella
# presenza di nvidia-smi. Dire "nessuna GPU" a chi ce l'ha ma senza driver
# lo manderebbe su CPU senza spiegargli perche'.
GPU_ADDRS=$(nvidia_pci_devices)
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | sed 's/^/  GPU: /'
  VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | tr -d ' ')
elif [ -n "$GPU_ADDRS" ]; then
  for a in $GPU_ADDRS; do echo "  GPU: $(nvidia_pci_name "$a")  [driver: $(nvidia_pci_driver_label "$a")]"; done
  warn "GPU presente ma nvidia-smi non risponde: Ollama girera' su CPU"
  warn "$(nvidia_missing_hint "$(nvidia_pci_driver "${GPU_ADDRS%%$'\n'*}")")"
else warn "nessuna GPU NVIDIA sul bus PCI: inferenza su CPU (lenta, adatta solo a batch)"; fi
RAM_AV=$(awk '/MemAvailable/{printf "%d", $2/1024/1024}' /proc/meminfo)

if [ -n "${MODEL:-}" ]; then
  ok "modello forzato: $MODEL"
elif [ "$VRAM" -ge 20000 ]; then MODEL="qwen2.5-coder:14b"
elif [ "$VRAM" -ge 10000 ]; then MODEL="qwen2.5-coder:7b"
elif [ "$VRAM" -ge 6000 ];  then MODEL="qwen2.5-coder:7b"; LAYERS=24
elif [ "$VRAM" -ge 3500 ];  then
  MODEL="qwen2.5-coder:3b"
  if [ "$RAM_AV" -ge 12 ]; then
    SECOND="qwen2.5-coder:7b"; LAYERS=28
    ok "VRAM ${VRAM}MiB + ${RAM_AV}GB RAM libera → 3B in VRAM + 7B in offload parziale"
  fi
else MODEL="qwen2.5-coder:3b"; warn "VRAM insufficiente: girerà quasi tutto su CPU"; fi
ok "modello principale: $MODEL${SECOND:+  (secondario: $SECOND)}"

# ---------------------------------------------------------------- 3. install
say "3. Installazione Ollama"
if command -v ollama >/dev/null 2>&1; then ok "già installato ($(ollama --version 2>/dev/null | head -1))"
else run "curl -fsSL https://ollama.com/install.sh | sh"; fi

# ---------------------------------------------------------------- 4. config
say "4. Configurazione systemd (bind + tuning VRAM stretta)"
CHASSIS=$(hostnamectl chassis 2>/dev/null || echo unknown)
[ -d /sys/class/power_supply/BAT0 ] && CHASSIS=laptop
OVR=/etc/systemd/system/ollama.service.d/override.conf
run "sudo install -d /etc/systemd/system/ollama.service.d"
CONF="[Unit]
# virbr0 deve esistere prima del bind, altrimenti il servizio fallisce
After=libvirtd.service network-online.target
Wants=network-online.target

[Service]
# SOLO sul bridge libvirt: raggiungibile dalle VM, invisibile alla LAN.
# Ollama NON ha autenticazione: per questo il bind è ristretto.
Environment=\"OLLAMA_HOST=${BRIP}:11434\"
Environment=\"OLLAMA_FLASH_ATTENTION=1\"
Environment=\"OLLAMA_KV_CACHE_TYPE=q8_0\"
Environment=\"OLLAMA_MAX_LOADED_MODELS=1\"$([ "$CHASSIS" = laptop ] && echo "
Environment=\"OLLAMA_KEEP_ALIVE=2m\"")
"
if [ "$DRY" = 1 ]; then echo "  [dry] scriverebbe $OVR:"; echo "$CONF" | sed 's/^/      /'
else echo "$CONF" | sudo tee "$OVR" >/dev/null; ok "$OVR scritto"; fi
[ "$CHASSIS" = laptop ] && ok "laptop rilevato: KEEP_ALIVE=2m (termico/batteria)"
run "sudo systemctl daemon-reload && sudo systemctl restart ollama"
sleep 3

# ---------------------------------------------------------------- 5. firewall
# Il firewall non e' ufw dappertutto: su Fedora/RHEL (e quindi su Bazzite e
# sugli altri OS atomici) e' firewalld. Aprire la porta col comando sbagliato
# non da' errore: semplicemente non apre niente, e la VM non vede Ollama.
if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
  say "5. Firewall (ufw)"
  run "sudo ufw allow from 192.168.122.0/24 to any port 11434 proto tcp"
  ok "consentito solo dalla subnet libvirt"
elif command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then
  say "5. Firewall (firewalld)"
  # rich rule: consente la 11434 SOLO dalla subnet libvirt, non da tutta la rete
  run "sudo firewall-cmd --permanent --add-rich-rule='rule family=\"ipv4\" source address=\"192.168.122.0/24\" port port=\"11434\" protocol=\"tcp\" accept'"
  run "sudo firewall-cmd --reload"
  ok "consentito solo dalla subnet libvirt"
else
  say "5. Firewall"
  echo "  nessun firewall attivo fra ufw e firewalld: niente da aprire"
fi

# ---------------------------------------------------------------- 6. modelli
say "6. Download modelli"
run "ollama pull $MODEL"
[ -n "${SECOND:-}" ] && run "ollama pull $SECOND"

# ---------------------------------------------------------------- 7. verifica
say "7. Verifica"
if [ "$DRY" = 0 ]; then
  ss -tlnp 2>/dev/null | grep -q "${BRIP}:11434" && ok "in ascolto su ${BRIP}:11434" \
    || warn "non in ascolto dove atteso: systemctl status ollama"
  curl -fsS --max-time 5 "http://${BRIP}:11434/api/tags" >/dev/null 2>&1 \
    && ok "API risponde" || warn "API non risponde"
  if [ -f "$HOME/.config/litellm/forward.env" ]; then
    . "$HOME/.config/litellm/forward.env"
    ssh -o ConnectTimeout=5 "${VM_USER:-$USER}@${VM_IP}" \
      "curl -fsS --max-time 5 http://${BRIP}:11434/api/tags >/dev/null" 2>/dev/null \
      && ok "raggiungibile DALLA VM (il test che conta)" \
      || warn "la VM non lo raggiunge: controlla il bind e il firewall"
  fi
fi

# ---------------------------------------------------------------- 8. litellm
say "8. Confronto con services/litellm_config.yaml"
echo "  Le lane local-fast / local-good sono GIA' nel config versionato con"
echo "  qwen2.5-coder:3b e :7b su http://${BRIP}:11434."
echo "  Ti serve modificarlo solo se hai scaricato taglie diverse da quelle qui sotto."
cat <<YML

  - model_name: local-fast
    litellm_params:
      model: ollama_chat/${MODEL}
      api_base: http://${BRIP}:11434
      timeout: 300
$([ -n "${SECOND:-}" ] && cat <<Y2
  - model_name: local-good
    litellm_params:
      model: ollama_chat/${SECOND}
      api_base: http://${BRIP}:11434
      timeout: 300
Y2
)
# in litellm_settings.fallbacks:
#   - local: [$([ -n "${SECOND:-}" ] && echo '"local-good", ')"local-fast"]
YML
[ -n "${LAYERS:-}" ] && cat <<TUN

  OFFLOAD PARZIALE: il modello non entra tutto in VRAM.
    ollama run ${SECOND:-$MODEL} --verbose
    >>> /set parameter num_gpu ${LAYERS}
  Alza finché non rallenta o va in errore; 'ollama ps' mostra la ripartizione.
  ⚠️ Mai far toccare lo swap: la velocità crolla di ordini di grandezza.
TUN
echo
echo "  Se hai modificato il config nella VM:  docker compose up -d"
echo "  Test:  ./test-all.sh local"
