#!/usr/bin/env bash
# ============================================================
#  setup-ollama.sh -- LLM LOCALE: decide dall'hardware, installa, verifica
#  ogni passo, annulla da solo se un passo fallisce, e si rimuove.
#
#  Uso:  ./setup-ollama.sh --plan                 cosa regge l'hardware (nessuna modifica)
#        ./setup-ollama.sh --dry-run              cosa farebbe
#        ./setup-ollama.sh                        installa / configura / verifica
#        ./setup-ollama.sh --rollback [RUN]       annulla un run (default: l'ultimo)
#        ./setup-ollama.sh --rollback --list      elenca i run annullabili
#        ./setup-ollama.sh --remove [--keep-models]  disinstalla tutto
#        opzioni: --yes (niente conferme), KEEP_ON_FAIL=1 (niente rollback automatico)
#        MODELS="qwen2.5-coder:3b" ./setup-ollama.sh   forza i modelli
#        LOCAL_ONLY=1                             senza virbr0: bind su 127.0.0.1 (la VM non lo vede)
#
#  Uscita: 0 ok (anche "ok con avvertenze") · 1 passo fallito (gia' annullato)
#          2 prerequisito mancante, nessuna modifica · 3 hardware non adatto, nessuna modifica
#
#  Scelte (vedi docs/GPU-LOCAL-LLM.md, ADR-0008, ADR-0016, ADR-0018):
#  - i modelli sono quelli del gateway (litellm_config.yaml); l'hardware decide
#    quali entrano (scripts/lib/llm-plan.sh), non quali altri scaricare;
#  - bind SOLO su virbr0, mai 0.0.0.0 (Ollama non ha autenticazione): se dopo il
#    riavvio Ollama ascolta su tutte le interfacce, il run si annulla;
#  - ogni modifica finisce nel registro del run (scripts/lib/journal.sh);
#  - su OS atomico (Bazzite) l'installer upstream non si lancia: crea l'utente
#    con home in /usr/share, che li' e' in sola lettura. Si raccomanda, non si forza.
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/hw-detect.sh
. "$HERE/lib/hw-detect.sh"
# shellcheck source=lib/llm-plan.sh
. "$HERE/lib/llm-plan.sh"
# shellcheck source=lib/journal.sh
. "$HERE/lib/journal.sh"
# shellcheck source=../stack/versions.conf
. "$HERE/../stack/versions.conf"

MODE=install; DRY=0; YES=0; KEEP_MODELS=0; TARGET=""; LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --plan) MODE=plan ;;
    --rollback) MODE=rollback; case "${2:-}" in ""|-*) ;; *) TARGET=$2; shift ;; esac ;;
    --list) LIST=1 ;;
    --remove) MODE=remove ;;
    --keep-models) KEEP_MODELS=1 ;;
    --yes) YES=1 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "opzione sconosciuta: $1 (--help)" >&2; exit 2 ;;
  esac; shift
done

run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else eval "$*"; fi; }
say(){ echo -e "\n\033[36m━━ $* ━━\033[0m"; }
ok(){ echo -e "  \033[32m✓\033[0m $*"; }
warn(){ echo -e "  \033[33m!\033[0m $*"; WARNS=$((WARNS+1)); }
WARNS=0

# Prefisso dei percorsi di sistema: vuoto in produzione, una dir temporanea nei
# test (tests/setup-ollama/), cosi' l'intero ciclo si prova senza toccare l'host.
ROOT="${OLLAMA_ROOT:-}"
UNIT="$ROOT/etc/systemd/system/ollama.service"
OVR_DIR="$ROOT/etc/systemd/system/ollama.service.d"
OVR="$OVR_DIR/override.conf"
OLLAMA_HOME="$ROOT/usr/share/ollama"
INSTALL_CMD="${OLLAMA_INSTALL_CMD:-curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION=$OLLAMA_VERSION sh}"
# Allineato a num_ctx della lane 'auto' (services/litellm_config.yaml, ADR-0016):
# col default Ollama tronca in silenzio i prompt lunghi degli agenti.
CTX=16384
LLM_MIN_TPS="${LLM_MIN_TPS:-5}"   # sotto questa velocita' il locale e' piu' lento del cloud

# --- funzioni usate anche dal rollback (le righe `undo` del registro le chiamano)
svc_reload(){ $SUDO systemctl daemon-reload && { ! $SUDO systemctl cat ollama >/dev/null 2>&1 || $SUDO systemctl restart ollama; }; }
ollama_uninstall_binary(){
  local bin; bin=$(command -v ollama 2>/dev/null || echo "$ROOT/usr/local/bin/ollama")
  $SUDO systemctl stop ollama 2>/dev/null; $SUDO systemctl disable ollama 2>/dev/null
  $SUDO rm -f "$UNIT"; $SUDO rm -rf "$OVR_DIR"; $SUDO systemctl daemon-reload
  $SUDO rm -f "$bin"; $SUDO rm -rf "$(dirname "$(dirname "$bin")")/lib/ollama"
  if [ "$KEEP_MODELS" = 0 ]; then
    $SUDO rm -rf "$OLLAMA_HOME"
    $SUDO userdel ollama 2>/dev/null; $SUDO groupdel ollama 2>/dev/null
  fi
  return 0
}
fw_del_ufw(){ $SUDO ufw delete allow from 192.168.122.0/24 to any port 11434 proto tcp; }
fw_del_firewalld(){ $SUDO firewall-cmd --permanent --zone="$1" --remove-rich-rule="$FW_RULE" && $SUDO firewall-cmd --reload; }
FW_RULE='rule family="ipv4" source address="192.168.122.0/24" port port="11434" protocol="tcp" accept'

# Il CLI di ollama parla col server su OLLAMA_HOST (default 127.0.0.1): col bind
# su virbr0 va detto esplicitamente, altrimenti `ollama pull` non si connette.
ol(){ OLLAMA_HOST="$BRIP:11434" ollama "$@"; }
has_model(){ ol list 2>/dev/null | awk 'NR>1{print $1}' | grep -qxF "$1"; }
listening(){ ss -tln 2>/dev/null | awk 'NR>1{print $4}' | grep -qxF "$1"; }
wait_for(){ local _; for _ in $(seq 1 "${2:-15}"); do eval "$1" && return 0; sleep 1; done; return 1; }

# Un passo "duro" fallito annulla l'intero run: meglio nessun LLM locale che uno
# a meta' (bind sbagliato, modello mancante dietro una lane del gateway).
hard_fail(){
  echo -e "  \033[31m✗\033[0m $1" >&2; [ -n "${2:-}" ] && echo -e "     \033[2m→ $2\033[0m" >&2
  [ "$DRY" = 1 ] && return 0
  if [ -n "$JRUN" ] && [ "${KEEP_ON_FAIL:-0}" != 1 ]; then
    say "Rollback automatico del run $(basename "$JRUN")"
    journal_rollback "$JRUN" || echo "  ✗ rollback incompleto: vedi sopra e $JRUN/actions.log" >&2
  elif [ -n "$JRUN" ]; then
    echo "  KEEP_ON_FAIL=1: stato lasciato com'e'. Annulla con: $0 --rollback $(basename "$JRUN")" >&2
  fi
  exit 1
}

# ================================================================ fatti hw
hw_facts(){
  BRIP=$(ip -4 -o addr show virbr0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  VRAM_MB=${HW_VRAM_MB:-}
  GPU_ADDRS=$(nvidia_pci_devices)
  if [ -z "$VRAM_MB" ]; then
    VRAM_MB=0
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
      VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | tr -d ' ')
      GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    fi
  fi
  RAM_GB=${HW_RAM_GB:-$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)}
  local d="$OLLAMA_HOME"; while [ ! -d "$d" ] && [ "$d" != / ] && [ -n "$d" ]; do d=$(dirname "$d"); done
  DISK_GB=${HW_DISK_GB:-$(df -BG --output=avail "${d:-/}" 2>/dev/null | tail -1 | tr -dc '0-9')}
  IFS='|' read -r VERDICT PLAN_MODELS LAYERS NOTE <<<"$(llm_plan "$VRAM_MB" "$RAM_GB" "${DISK_GB:-0}")"
  MODELS_TO_PULL="${MODELS:-$PLAN_MODELS}"
  CHASSIS=$(hostnamectl chassis 2>/dev/null || echo unknown)
  [ -d /sys/class/power_supply/BAT0 ] && CHASSIS=laptop
}

print_plan(){
  say "Hardware → LLM locale"
  if [ "${VRAM_MB:-0}" -gt 0 ]; then ok "GPU: ${GPU_NAME:-NVIDIA} — ${VRAM_MB} MiB VRAM"
  elif [ -n "$GPU_ADDRS" ]; then
    for a in $GPU_ADDRS; do echo "  GPU: $(nvidia_pci_name "$a")  [driver: $(nvidia_pci_driver_label "$a")]"; done
    warn "GPU presente ma nvidia-smi non risponde: la VRAM non e' misurabile, il piano e' per CPU"
    warn "$(nvidia_missing_hint "$(nvidia_pci_driver "${GPU_ADDRS%%$'\n'*}")")"
  else echo "  GPU: nessuna NVIDIA sul bus PCI"; fi
  echo "  RAM: ${RAM_GB} GB totali, $(llm_usable_ram_gb "$RAM_GB") utilizzabili (meno VM ${VM_RAM_MB:-4096} MB e host)"
  echo "  disco per i modelli: ${DISK_GB:-?} GB liberi"
  echo "  OS: $(os_pretty)$(os_is_atomic && echo '  (atomico)')"
  echo "  virbr0: ${BRIP:-assente}"
  echo -e "  \033[1mverdetto: $VERDICT\033[0m — $NOTE"
  [ -n "$MODELS_TO_PULL" ] && echo "  modelli: $MODELS_TO_PULL${MODELS:+  (forzati da MODELS)}"
  [ -n "${LAYERS:-}" ] && echo "  offload: ~${LAYERS}/28 layer in GPU (stima; Ollama decide da solo)"
  return 0
}

# ================================================================ --plan
if [ "$MODE" = plan ]; then hw_facts; print_plan; exit 0; fi

# Prima di QUALUNQUE ramo che modifica (installa, annulla o rimuove): da un
# sandbox si scriverebbe nel sandbox. Il guard sta qui, prima di tutti i rami.
sandbox_guard "scripts/setup-ollama.sh" "$DRY" || exit 1

confirm(){
  [ "$YES" = 1 ] || [ "$DRY" = 1 ] && return 0
  local a; read -rp "  → $1 Scrivi '$2' per confermare: " a; [ "$a" = "$2" ]
}

# ================================================================ --rollback
if [ "$MODE" = rollback ]; then
  say "Rollback dell'LLM locale"
  if [ "$LIST" = 1 ]; then journal_list ollama; exit 0; fi
  DIR=$(journal_resolve "${TARGET:-ollama-latest}") || { echo "  ✗ run '${TARGET:-ollama-latest}' non trovato. Elenco: $0 --rollback --list" >&2; exit 2; }
  echo "  run: $(basename "$DIR")"; sed 's/^/    /' "$DIR/actions.log"
  confirm "Annullare queste azioni (ordine inverso)?" annulla || { echo "  annullato dall'utente"; exit 1; }
  journal_rollback "$DIR"; rc=$?
  [ "$rc" = 0 ] && ok "rollback completato" || echo "  ✗ rollback incompleto (vedi sopra)" >&2
  exit "$rc"
fi

# ================================================================ --remove
if [ "$MODE" = remove ]; then
  say "Rimozione dell'LLM locale"
  BRIP=$(ip -4 -o addr show virbr0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1); BRIP=${BRIP:-127.0.0.1}
  echo "  rimuove: servizio ollama, override, binario e librerie, regola firewall sulla 11434"
  [ "$KEEP_MODELS" = 0 ] && echo "  e i MODELLI ($OLLAMA_HOME$(du -sh "$OLLAMA_HOME" 2>/dev/null | awk '{print ", "$1}'), utente 'ollama')" \
                         || echo "  modelli conservati in $OLLAMA_HOME (--keep-models)"
  echo "  Non e' annullabile: per tornare indietro si reinstalla (questo script)."
  confirm "Procedere?" rimuovi || { echo "  annullato dall'utente"; exit 1; }
  if [ "$DRY" = 1 ]; then
    echo "  [dry] systemctl stop/disable ollama; rm $UNIT $OVR_DIR; daemon-reload"
    echo "  [dry] rm binario e lib; $([ "$KEEP_MODELS" = 0 ] && echo "rm -rf $OLLAMA_HOME; userdel/groupdel ollama")"
    echo "  [dry] rimuove la regola 11434 da ufw/firewalld se presente"
    exit 0
  fi
  if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q 11434; then fw_del_ufw && ok "regola ufw rimossa"; fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    Z=$($SUDO firewall-cmd --get-zone-of-interface=virbr0 2>/dev/null); Z=${Z:-libvirt}
    $SUDO firewall-cmd --zone="$Z" --list-rich-rules 2>/dev/null | grep -q 11434 && fw_del_firewalld "$Z" && ok "regola firewalld rimossa (zona $Z)"
  fi
  ollama_uninstall_binary
  # Verifica: la rimozione dice il vero solo se non resta niente.
  left=""
  command -v ollama >/dev/null 2>&1 && left="$left binario($(command -v ollama))"
  [ -e "$UNIT" ] && left="$left unit"; [ -e "$OVR" ] && left="$left override"
  listening "$BRIP:11434" && left="$left porta-11434"
  [ "$KEEP_MODELS" = 0 ] && [ -e "$OLLAMA_HOME" ] && left="$left modelli"
  if [ -z "$left" ]; then ok "rimosso: nessuna traccia di Ollama"; exit 0
  else echo "  ✗ restano:$left" >&2; exit 1; fi
fi

# ================================================================ install
# ---------------------------------------------------------------- 0. preflight
say "0. Preflight (nessuna modifica)"
hw_facts
if [ -z "$BRIP" ]; then
  if [ "${LOCAL_ONLY:-0}" = 1 ]; then BRIP=127.0.0.1; warn "LOCAL_ONLY=1: bind su 127.0.0.1, la VM NON vedra' Ollama"
  elif [ "$DRY" = 1 ]; then BRIP=192.168.122.1; warn "virbr0 assente: il run reale si fermerebbe qui (crea prima la VM, o LOCAL_ONLY=1)"
  else
    echo "  ✗ virbr0 assente: Ollama sarebbe invisibile alla VM del gateway" >&2
    echo "     → crea prima la VM (./create-vm.sh), oppure LOCAL_ONLY=1 per un uso solo dall'host" >&2
    exit 2
  fi
fi
print_plan
if os_is_atomic && ! command -v ollama >/dev/null 2>&1; then
  echo "  ✗ OS atomico senza Ollama: l'installer upstream crea l'utente con home in /usr/share (sola lettura qui)" >&2
  echo "     → strato S1 (ADR-0018): raccomandazione, non azione automatica. Opzioni:" >&2
  echo "       brew install ollama   (poi un servizio utente con OLLAMA_HOST=$BRIP:11434)" >&2
  echo "       oppure Ollama in un container (podman) con la GPU passata" >&2
  echo "     Lo script configura e verifica il resto solo con un servizio di SISTEMA 'ollama';" >&2
  echo "     il servizio utente di brew non e' ancora gestito (P2): configuralo a mano (docs/GPU-LOCAL-LLM.md)." >&2
  [ "$DRY" = 1 ] || exit 2
fi
if [ "$VERDICT" = none ] && [ -z "${MODELS:-}" ]; then
  echo "  L'hardware non regge un LLM locale utile: niente da installare. Il gateway usa le lane cloud."
  [ "$DRY" = 1 ] && exit 0
  exit 3
fi

PREV_LATEST=$(readlink "$JOURNAL_ROOT/ollama-latest" 2>/dev/null || true)
journal_begin ollama || exit 1
trap 'hard_fail "interrotto (segnale)" "il run viene annullato"' INT TERM

# ---------------------------------------------------------------- 1. binario
say "1. Ollama $OLLAMA_VERSION"
if command -v ollama >/dev/null 2>&1; then
  HAVE=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  ok "gia' installato ($HAVE): non lo tocco"
  [ -n "$HAVE" ] && [ "$HAVE" != "$OLLAMA_VERSION" ] && warn "versione $HAVE diversa dal pin $OLLAMA_VERSION (stack/versions.conf): aggiornala tu, con un run dedicato"
else
  run "$INSTALL_CMD" || hard_fail "installazione di Ollama fallita" "rete? ollama.com raggiungibile?"
  journal_undo "ollama_uninstall_binary"
  if [ "$DRY" = 0 ]; then
    command -v ollama >/dev/null 2>&1 && ollama --version >/dev/null 2>&1 \
      && ok "installato: $(ollama --version 2>/dev/null | head -1)" \
      || hard_fail "dopo l'installazione 'ollama' non risponde"
  fi
fi

# ---------------------------------------------------------------- 2. servizio
say "2. Servizio: bind su virbr0 + tuning"
CONF="[Unit]
# virbr0 deve esistere prima del bind, altrimenti il servizio fallisce
After=libvirtd.service network-online.target
Wants=network-online.target

[Service]
# SOLO sul bridge libvirt: raggiungibile dalle VM, invisibile alla LAN.
# Ollama NON ha autenticazione: per questo il bind e' ristretto.
Environment=\"OLLAMA_HOST=${BRIP}:11434\"
Environment=\"OLLAMA_FLASH_ATTENTION=1\"
Environment=\"OLLAMA_KV_CACHE_TYPE=q8_0\"
Environment=\"OLLAMA_MAX_LOADED_MODELS=1\"
Environment=\"OLLAMA_CONTEXT_LENGTH=${CTX}\"$([ "$CHASSIS" = laptop ] && echo "
Environment=\"OLLAMA_KEEP_ALIVE=2m\"")
"
if [ -f "$OVR" ] && [ "$(printf '%s' "$CONF" | sha256sum)" = "$($SUDO cat "$OVR" | sha256sum)" ]; then
  ok "override gia' conforme: nessuna scrittura"
elif [ "$DRY" = 1 ]; then
  echo "  [dry] scriverebbe $OVR:"; echo "$CONF" | sed 's/^/      /'
  echo "  [dry] systemctl daemon-reload && systemctl restart ollama"
else
  journal_undo "svc_reload"          # prima del file: nel rollback viene DOPO il ripristino
  journal_file "$OVR"
  $SUDO install -d "$OVR_DIR" && printf '%s' "$CONF" | $SUDO tee "$OVR" >/dev/null \
    || hard_fail "non posso scrivere $OVR"
  $SUDO systemctl daemon-reload && $SUDO systemctl enable ollama >/dev/null 2>&1; $SUDO systemctl restart ollama \
    || hard_fail "systemctl restart ollama fallito" "journalctl -u ollama -n 50"
  ok "$OVR scritto, servizio riavviato"
fi
[ "$CHASSIS" = laptop ] && ok "laptop: KEEP_ALIVE=2m (termico/batteria)"
if [ "$DRY" = 0 ]; then
  wait_for "$SUDO systemctl is-active --quiet ollama" 15 || hard_fail "il servizio ollama non e' attivo" "journalctl -u ollama -n 50"
  # Invariante #3 PRIMA del controllo su virbr0: un Ollama su 0.0.0.0 non
  # risulta "in ascolto su virbr0" (ss mostra 0.0.0.0:11434) e l'errore generico
  # nasconderebbe quello vero. Mai su tutte le interfacce: il run si annulla.
  wait_for "listening '$BRIP:11434' || listening '0.0.0.0:11434' || listening '*:11434' || listening '[::]:11434'" 15
  for any in "0.0.0.0:11434" "*:11434" "[::]:11434"; do
    listening "$any" && hard_fail "Ollama ascolta su $any: esposto alla LAN senza autenticazione" "invariante #3; un OLLAMA_HOST in un altro drop-in?"
  done
  listening "$BRIP:11434" || hard_fail "Ollama non ascolta su $BRIP:11434" "ss -tln | grep 11434"
  curl -fsS --max-time 5 "http://$BRIP:11434/api/version" >/dev/null 2>&1 \
    && ok "in ascolto SOLO su $BRIP:11434, API risponde" || hard_fail "API di Ollama non risponde su $BRIP:11434"
fi

# ---------------------------------------------------------------- 3. firewall
# Il firewall non e' ufw dappertutto: su Fedora/Bazzite e' firewalld, e libvirt
# mette virbr0 in una zona che rifiuta il traffico verso l'host. La regola va
# nella zona DI virbr0, non nella default (trappola nota in AGENTS.md).
say "3. Firewall (porta 11434 dalla sola subnet libvirt)"
if [ "$DRY" = 1 ]; then
  echo "  [dry] rileverebbe ufw/firewalld e aprirebbe la 11434 alla sola 192.168.122.0/24 (zona di virbr0)"
elif command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
  if $SUDO ufw status 2>/dev/null | grep -q '11434.*192.168.122.0/24'; then ok "ufw: regola gia' presente"
  else
    $SUDO ufw allow from 192.168.122.0/24 to any port 11434 proto tcp >/dev/null && journal_undo "fw_del_ufw"
    $SUDO ufw status 2>/dev/null | grep -q '11434.*192.168.122.0/24' && ok "ufw: consentito solo dalla subnet libvirt" \
      || warn "ufw: la regola non risulta dopo l'aggiunta"
  fi
elif command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state >/dev/null 2>&1; then
  ZONE=$($SUDO firewall-cmd --get-zone-of-interface=virbr0 2>/dev/null); ZONE=${ZONE:-libvirt}
  if $SUDO firewall-cmd --permanent --zone="$ZONE" --list-rich-rules 2>/dev/null | grep -q 11434; then ok "firewalld: regola gia' presente (zona $ZONE)"
  else
    $SUDO firewall-cmd --permanent --zone="$ZONE" --add-rich-rule="$FW_RULE" >/dev/null && $SUDO firewall-cmd --reload >/dev/null \
      && journal_undo "fw_del_firewalld '$ZONE'"
    $SUDO firewall-cmd --zone="$ZONE" --list-rich-rules 2>/dev/null | grep -q 11434 && ok "firewalld: aperta nella zona '$ZONE'" \
      || warn "firewalld: la regola non risulta nella zona '$ZONE'"
  fi
else
  ok "nessun firewall attivo fra ufw e firewalld: niente da aprire"
fi

# ---------------------------------------------------------------- 4. modelli
say "4. Modelli: $MODELS_TO_PULL"
for m in $MODELS_TO_PULL; do
  if [ "$DRY" = 1 ]; then echo "  [dry] OLLAMA_HOST=$BRIP:11434 ollama pull $m"; continue; fi
  if has_model "$m"; then ok "$m gia' presente"; continue; fi
  ol pull "$m" || hard_fail "download di $m fallito" "spazio su disco? rete?"
  # Host esplicito: il rollback gira in un processo nuovo, dove $BRIP non c'e'.
  journal_undo "OLLAMA_HOST='$BRIP:11434' ollama rm '$m'"
  has_model "$m" && ok "$m scaricato" || hard_fail "$m non risulta dopo il pull"
done

# ---------------------------------------------------------------- 5. prova reale
# Il modello deve RISPONDERE, non solo esistere. La velocita' decide se il
# locale serve davvero come primo anello di `auto`.
say "5. Prova: il modello risponde?"
MAIN=$(echo "$MODELS_TO_PULL" | awk '{print $NF}')
TPS=""
if [ "$DRY" = 1 ]; then echo "  [dry] POST /api/generate su $MAIN, misura token/s"
elif [ -n "$MAIN" ]; then
  R=$(curl -fsS --max-time 600 "http://$BRIP:11434/api/generate" \
      -d "{\"model\":\"$MAIN\",\"prompt\":\"Rispondi solo: OK\",\"stream\":false,\"options\":{\"num_predict\":8}}" 2>/dev/null)
  read -r RESP TPS < <(printf '%s' "$R" | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = {}
dur = d.get("eval_duration") or 0
tps = (d.get("eval_count") or 0) / (dur / 1e9) if dur else 0
# "-" esplicito per "nessuna risposta": con un campo vuoto `read` sposterebbe
# i token/s nella variabile della risposta, e un modello muto passerebbe.
print((d.get("response") or "").strip().replace(" ", "_")[:20] or "-", f"{tps:.1f}")')
  [ -n "$RESP" ] && [ "$RESP" != "-" ] || hard_fail "$MAIN non risponde a una richiesta reale" "ollama ps; journalctl -u ollama -n 50 (VRAM/RAM esaurite?)"
  ok "$MAIN risponde ($TPS token/s)"
  awk -v t="$TPS" -v m="$LLM_MIN_TPS" 'BEGIN{exit !(t+0 < m+0)}' \
    && warn "$TPS token/s < $LLM_MIN_TPS: come primo anello di 'auto' sara' piu' lento del cloud"
fi

# ---------------------------------------------------------------- 6. dalla VM
say "6. Raggiungibile dalla VM?"
if [ "$DRY" = 1 ]; then echo "  [dry] ssh nella VM: curl http://$BRIP:11434/api/tags"
elif [ -f "$HOME/.config/litellm/forward.env" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.config/litellm/forward.env"
  ssh -o ConnectTimeout=5 -o BatchMode=yes "${VM_USER:-${USER:-$(id -un)}}@${VM_IP}" \
    "curl -fsS --max-time 5 http://${BRIP}:11434/api/tags >/dev/null" 2>/dev/null \
    && ok "raggiungibile DALLA VM (il test che conta)" \
    || warn "la VM non lo raggiunge: firewall (passo 3) o VM spenta. Il run NON viene annullato: verifica e rilancia"
else
  warn "\$HOME/.config/litellm/forward.env assente: verifica dalla VM non eseguita (deploy-all.sh fase 2)"
fi

# ---------------------------------------------------------------- 7. gateway
say "7. Coerenza con il gateway (services/litellm_config.yaml)"
CFG="$HERE/../services/litellm_config.yaml"
if [ -f "$CFG" ]; then
  while read -r lane model; do
    if [ "$DRY" = 1 ]; then echo "  [dry] lane $lane → $model: scaricato?"
    elif has_model "$model"; then ok "lane $lane → $model: disponibile"
    elif [ "$lane" = auto ]; then warn "lane auto → $model NON scaricato: 'auto' saltera' sempre il locale (fallback al cloud)"
    else warn "lane $lane → $model non scaricato: quella lane rispondera' errore"; fi
  done < <(awk '/model_name:/{n=$NF} /model: ollama_chat\//{sub("ollama_chat/","",$2); print n, $2}' "$CFG")
fi

# ---------------------------------------------------------------- esito
say "Esito"
if [ "$DRY" = 1 ]; then echo "  dry-run: nessuna modifica"; exit 0; fi
if [ "$JCHANGES" = 0 ]; then
  # Run idempotente: niente da annullare. Si toglie il registro vuoto e
  # `--rollback` continua a puntare all'ultimo run che ha cambiato qualcosa.
  rm -rf "$JRUN"
  if [ -n "$PREV_LATEST" ]; then ln -sfn "$PREV_LATEST" "$JOURNAL_ROOT/ollama-latest"; else rm -f "$JOURNAL_ROOT/ollama-latest"; fi
  ok "nessuna modifica: lo stato era gia' quello voluto (run idempotente)"
else
  printf '{"verdict":"%s","models":"%s","main":"%s","tps":"%s","warnings":%d}\n' \
    "$VERDICT" "$MODELS_TO_PULL" "$MAIN" "$TPS" "$WARNS" > "$JRUN/result.json"
  ok "$JCHANGES modifiche registrate in $JRUN"
  echo "  annulla questo run:  $0 --rollback $(basename "$JRUN")"
fi
echo "  rimuovi tutto:       $0 --remove"
[ "$WARNS" -gt 0 ] && echo -e "  \033[33mOk con $WARNS avvertenze\033[0m (sopra)." || echo -e "  \033[32mLLM locale operativo.\033[0m"
echo "  Gateway: se il config nella VM e' cambiato, docker compose up -d; poi ./test-all.sh local"
exit 0
