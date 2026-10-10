#!/usr/bin/env bash
# Deploy COMPLETO a fasi con checkpoint. --dry-run | numero fase
# ORDINE PSE: la VM va su e verificata PRIMA di pulire l'host.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
# shellcheck source=lib/hw-detect.sh
. "$HERE/lib/hw-detect.sh"
DRY=0; ONLY=""
for a in "$@"; do case "$a" in --dry-run) DRY=1;; [0-9]*) ONLY="$a";; esac; done
run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else eval "$*"; fi; }
say(){ echo -e "\n\033[36m━━ $* ━━\033[0m"; }
ok(){ echo -e "  \033[32m✓\033[0m $*"; }
warn(){ echo -e "  \033[33m!\033[0m $*"; }
ask(){ [ "$DRY" = 1 ] && return 0; read -rp "  → $1 [Invio=continua, s=salta] " a; [ "$a" != s ]; }
ph(){ [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
# Stessi default di create-vm.sh e del runbook: la VM che crea e' quella che si usa.
VM_NAME="${VM_NAME:-llm-vm}"; VM_IP="${VM_IP:-192.168.122.50}"
VM_USER="${VM_USER:-${USER:-$(id -un)}}"; VM_DIR="${VM_DIR:-llm-services}"
VM_SSH="$VM_USER@$VM_IP"
# vm "cosa fa" <<'SH' ... SH -- esegue lo script (stdin) sulla VM, in ~/$D.
# In dry-run stampa solo la descrizione. I segreti nascono e restano NELLA VM:
# nessuno passa dalla riga di comando dell'host (HC-04).
vm(){ if [ "$DRY" = 1 ]; then echo "  [dry] sulla VM ($VM_SSH): $1"; cat >/dev/null; return 0; fi
      ssh -o BatchMode=yes "$VM_SSH" "D='$VM_DIR' bash -s"; }

sandbox_guard "scripts/deploy-all.sh" "$DRY" || exit 1

echo "╔════════════════════════════════════════════════════════╗"
echo "║ DEPLOY — gateway + agenti + tooling + locale           ║"
echo "║ Claude Code su ABBONAMENTO · opencode su GATEWAY       ║"
echo "╚════════════════════════════════════════════════════════╝"

if ph 0; then say "FASE 0 — Rilevamento hardware"
run "./detect-hardware.sh"; ask "Continuare?" || exit 0; fi

if ph 1; then say "FASE 1 — VM: creazione + servizi"
ask "Creare la VM ora con create-vm.sh (cloud-init, automatico)?" \
  && run "./create-vm.sh" || warn "creazione VM saltata (manuale: docs/VM-DEBIAN-INSTALL.md)"
# Servizi nella VM: copia, .env (segreti interni generati li', chiavi API scritte
# da te), build, avvio, attesa della liveness. Idempotente: un .env esistente non
# si rigenera, la build riusa la cache, `up -d` non tocca cio' che e' gia' su.
if ask "Copiare services/ nella VM ($VM_SSH) e avviare lo stack?"; then
  P1=0
  run "ssh -o BatchMode=yes '$VM_SSH' 'mkdir -p ~/$VM_DIR'" || P1=1
  # services/* non include i dotfile: .env.example va nominato, e un services/.env
  # locale resta fuori apposta. backup-db.sh non sta in services/ (rilievo A17).
  [ "$P1" = 0 ] && { run "scp -q ../services/* ../services/.env.example ./backup-db.sh '$VM_SSH:$VM_DIR/'" || P1=1; }
  [ "$P1" = 0 ] && { vm ".env 600 con POSTGRES_PASSWORD, LITELLM_MASTER_KEY, VLLM_API_KEY generati (solo se assente)" <<'SH' || P1=1
set -u; cd ~/"$D" || exit 1
if [ ! -f .env ]; then
  ( umask 077; cp .env.example .env ) || exit 1
  for v in POSTGRES_PASSWORD VLLM_API_KEY; do sed -i "s|^$v=.*|$v=$(openssl rand -hex 32)|" .env; done
  sed -i "s|^LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=sk-$(openssl rand -hex 32)|" .env
  echo "  .env creato: segreti interni generati"
fi
chmod 600 .env
SH
  }
  # Le chiavi API dei provider le scrivi tu: non si generano e non passano di qui.
  if [ "$P1" = 0 ] && [ "$DRY" = 0 ] && ssh -o BatchMode=yes "$VM_SSH" "grep -q CHANGEME ~/$VM_DIR/.env"; then
    warn "nel .env della VM restano valori CHANGEME (chiavi API dei provider)"
    ask "Aprirlo ora nell'editor della VM?" && ssh -t "$VM_SSH" "\${EDITOR:-editor} ~/$VM_DIR/.env"
  fi
  [ "$P1" = 0 ] && { vm "docker compose build && up -d, poi attesa della liveness (max 180 s)" <<'SH' || P1=1
set -u; cd ~/"$D" || exit 1
[ "$(stat -c %a .env)" = 600 ] || { echo "  .env non e' 600"; exit 1; }
docker compose build </dev/null && docker compose up -d </dev/null || exit 1
for _ in $(seq 36); do
  curl -fsS --max-time 3 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1 && { echo "  liveness OK nella VM"; exit 0; }
  sleep 5
done
echo "  nessuna liveness dopo 180 s: docker compose logs litellm | tail -50"; exit 1
SH
  }
  if [ "$P1" = 0 ]; then ok "servizi su nella VM"
  else warn "servizi NON su: correggi e rilancia './deploy-all.sh 1' (il .env esistente non si tocca)"; exit 1; fi
else warn "servizi saltati (manuale: docs/DEPLOY-RUNBOOK.md passo 3)"; fi; fi

if ph 2; then say "FASE 2 — Forward host → VM"
# socat: nome uguale ovunque, comando no. Su un OS atomico serve rpm-ostree
# (e un reboot), quindi qui si avvisa invece di eseguire alla cieca.
if ! command -v socat >/dev/null 2>&1; then
  SOCAT_CMD=$(pkg_install_cmd socat)
  if [ -n "$SOCAT_CMD" ]; then
    run "$SOCAT_CMD"
  elif os_is_atomic; then
    # Su un OS atomico non si installa al volo: serve un layer e un reboot.
    warn "socat assente. OS atomico: rpm-ostree install socat && systemctl reboot"
    ask "installato e riavviato?" || true
  else
    warn "socat assente: installalo col gestore di pacchetti del tuo OS"
    ask "installato?" || true
  fi
fi
run "install -d ~/.config/litellm ~/.config/systemd/user"
# forward.env si scrive da VM_IP (lo stesso che create-vm.sh riserva in DHCP).
# Se esiste gia' e punta altrove, e' una deriva: si segnala, non si sovrascrive.
FWD=~/.config/litellm/forward.env
if [ -f "$FWD" ]; then
  cur=$(sed -n 's/^VM_IP=//p' "$FWD" | tail -1)
  [ "$cur" = "$VM_IP" ] && ok "forward.env -> $VM_IP" \
    || warn "forward.env punta a '$cur', la VM e' $VM_IP: correggi il file o rilancia con VM_IP=$cur"
else
  run "( umask 077; printf 'VM_IP=%s\n' '$VM_IP' > '$FWD' )"
fi
run "cp ../systemd/litellm-forward.service ~/.config/systemd/user/"
run "systemctl --user daemon-reload && systemctl --user enable --now litellm-forward.service"
sleep 2
[ "$DRY" = 0 ] && { curl -fsS --max-time 5 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1 \
  && ok "gateway su 127.0.0.1:4000" || { warn "NON raggiungibile: non proseguire con la Fase 3"; exit 1; }; }
# master key sull'host: file 600 letto da clients/shell-env.sh. Arriva dalla VM
# via ssh su stdout, mai come argomento di un comando (HC-04).
MK=~/.config/litellm/master.key
if [ -s "$MK" ]; then ok "master.key presente"
elif [ "$DRY" = 1 ]; then echo "  [dry] master key dal .env della VM -> $MK (600)"
elif ( umask 077; ssh -o BatchMode=yes "$VM_SSH" "sed -n 's/^LITELLM_MASTER_KEY=//p' ~/$VM_DIR/.env" > "$MK" ) && [ -s "$MK" ]; then
  ok "master.key copiata (600)"
else rm -f "$MK"; warn "master key non copiata: DEPLOY-RUNBOOK.md passo 5"; fi; fi

if ph 3; then say "FASE 3 — Pulizia host"
run "./cleanup-host.sh --dry-run"; ask "Applicare?" && run "./cleanup-host.sh" || warn saltata; fi

if ph 4; then say "FASE 4 — Tooling (Serena, graphify, mattpocock, AgentShield)"
run "./stack-selective-install.sh '${REPO:-$HERE/..}'"; ok "tooling installato"; fi

if ph 5; then say "FASE 5 — Doppia autenticazione"
cat <<'X'
  opencode/codex -> gateway (fatto in Fase 4).
  Claude Code    -> ABBONAMENTO, scegli UNA variante (docs/DUAL-AUTH.md):
    (A) diretto     : nessuna variabile; 'claude' -> /login
    (B) + headroom  : ANTHROPIC_BASE_URL=http://127.0.0.1:8787
    (C) via LiteLLM : BASE_URL=:4000 + ANTHROPIC_CUSTOM_HEADERS
  SEMPRE:  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
X
# idempotente: rilanciare la fase non deve duplicare la riga in .bashrc
run "grep -qF 'clients/shell-env.sh' ~/.bashrc 2>/dev/null || echo 'source $HERE/../clients/shell-env.sh' >> ~/.bashrc"
ask "Fatto?" && ok "dual-auth pronta" || warn "da completare"; fi

if ph 6; then say "FASE 6 — LLM locale (deciso dall'hardware)"
# setup-ollama.sh decide dall'hardware QUALI modelli del gateway reggere
# (scripts/lib/llm-plan.sh), verifica ogni passo e, se uno fallisce, annulla da
# solo il proprio run. Il piano si mostra prima: nessuna modifica senza conferma.
run "./setup-ollama.sh --plan"
if ask "Installare, verificare e avviare l'LLM locale secondo questo piano?"; then
  if [ "$DRY" = 1 ]; then run "./setup-ollama.sh --dry-run"; rc=0
  else ./setup-ollama.sh; rc=$?; fi
  case "$rc" in
    0) ok "LLM locale operativo (annulla: ./setup-ollama.sh --rollback · rimuovi: ./setup-ollama.sh --remove)" ;;
    1) warn "un passo e' fallito: il run e' gia' stato annullato (vedi sopra). Il gateway usa il cloud." ;;
    2) warn "prerequisito mancante (virbr0 o OS atomico): nessuna modifica fatta" ;;
    3) warn "hardware non adatto a un LLM locale: nessuna modifica, il gateway usa il cloud" ;;
  esac
else warn "LLM locale saltato"; fi; fi

if ph 7; then say "FASE 7 — Verifica"
# La verifica DEVE poter fallire: con `|| true` uno stack rosso arrivava alla
# baseline come se fosse verde. Si eseguono tutte, poi si decide.
[ -z "${LITELLM_MASTER_KEY:-}" ] && [ -r ~/.config/litellm/master.key ] \
  && LITELLM_MASTER_KEY="$(cat ~/.config/litellm/master.key)" && export LITELLM_MASTER_KEY
VFAIL=""
verify(){ if [ "$DRY" = 1 ]; then echo "  [dry] ./$1"; return 0; fi; "./$1" || VFAIL="$VFAIL $1"; }
verify devops-audit.sh; verify audit-integration.py; verify test-all.sh
if [ -n "$VFAIL" ]; then
  warn "verifica ROSSA:$VFAIL"
  echo "  nessuna baseline di uno stack rosso: correggi, poi './deploy-all.sh 7' e './deploy-all.sh 8'"
  exit 1
fi
ok "verifica verde"; fi

if ph 8; then say "FASE 8 — Baseline, backup e TEST del restore"
SNAP="${SNAP:-baseline}"; BFAIL=0
# Idempotente: una baseline esistente non si sovrascrive (e' il punto di ritorno).
if [ "$DRY" = 0 ] && virsh -c qemu:///system snapshot-info "$VM_NAME" "$SNAP" >/dev/null 2>&1; then
  ok "snapshot '$SNAP' gia' presente: non si ricrea"
else
  run "virsh -c qemu:///system snapshot-create-as '$VM_NAME' '$SNAP' --description 'stack ok (deploy-all fase 8)'" || BFAIL=1
fi
run "scp -q ./backup-db.sh '$VM_SSH:$VM_DIR/'" || BFAIL=1
vm "./backup-db.sh (primo backup)" <<'SH' || BFAIL=1
cd ~/"$D" && ./backup-db.sh </dev/null
SH
# TC-05: un backup non testato non e' un backup.
if ask "Eseguire ora il test di restore (TC-05)?"; then
  run "VM_SSH='$VM_SSH' COMPOSE_DIR='~/$VM_DIR' ./restore-test.sh" || BFAIL=1
else warn "restore-test da fare: VM_SSH=$VM_SSH ./restore-test.sh"; BFAIL=1; fi
cat <<'X'
  Nel repo, prima sessione:  /setup-matt-pocock-skills ; /grill-with-docs ; /graphify .
X
[ "$BFAIL" = 0 ] && ok "baseline, backup e restore verificati" \
  || { warn "fase 8 incompleta: rilancia './deploy-all.sh 8'"; exit 1; }; fi

echo -e "\n\033[32mDeploy completato.\033[0m Vedi docs/INSTALL_GUIDE.md e docs/DUAL-AUTH.md"
