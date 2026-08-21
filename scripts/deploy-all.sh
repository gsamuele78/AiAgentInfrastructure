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

echo "╔════════════════════════════════════════════════════════╗"
echo "║ DEPLOY — gateway + agenti + tooling + locale           ║"
echo "║ Claude Code su ABBONAMENTO · opencode su GATEWAY       ║"
echo "╚════════════════════════════════════════════════════════╝"

if ph 0; then say "FASE 0 — Rilevamento hardware"
run "./detect-hardware.sh"; ask "Continuare?" || exit 0; fi

if ph 1; then say "FASE 1 — VM: creazione + servizi"
ask "Creare la VM ora con create-vm.sh (cloud-init, automatico)?" \
  && run "./create-vm.sh" || warn "creazione VM saltata (manuale: docs/VM-DEBIAN-INSTALL.md)"
cat <<'X'
  Poi, deploy dei servizi nella VM:
    scp -r services/ $VM_USER@<VM_IP>:~/llm-services/
    ssh $VM_USER@<VM_IP>; cd ~/llm-services
    cp .env.example .env && chmod 600 .env && $EDITOR .env
    docker compose build && docker compose up -d
    curl -s http://127.0.0.1:4000/health/liveliness
X
ask "Fase 1 completata?" && ok "servizi su" || warn saltata; fi

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
[ -f ~/.config/litellm/forward.env ] || {
  run "cp ../systemd/forward.env.example ~/.config/litellm/forward.env"
  run "chmod 600 ~/.config/litellm/forward.env"
  warn "EDITA forward.env con IP/nome VM; blocca l'IP (riserva DHCP, VM-KVM-GUIDE.md)"
  ask "compilato?" || true; }
run "cp ../systemd/litellm-forward.service ~/.config/systemd/user/"
run "systemctl --user daemon-reload && systemctl --user enable --now litellm-forward.service"
sleep 2
[ "$DRY" = 0 ] && { curl -fsS --max-time 5 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1 \
  && ok "gateway su 127.0.0.1:4000" || warn "NON raggiungibile: non proseguire con la Fase 3"; }; fi

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

if ph 6; then say "FASE 6 — LLM locale (opzionale)"
if command -v nvidia-smi >/dev/null 2>&1; then
  run "./detect-hardware.sh --emit-config"
  ask "Installare e configurare Ollama ora?" \
    && run "./setup-ollama.sh" || warn saltata
else warn "nessuna GPU: salto"; fi; fi

if ph 7; then say "FASE 7 — Verifica"
run "./devops-audit.sh || true"; run "./audit-integration.py || true"; run "./test-all.sh || true"; fi

if ph 8; then say "FASE 8 — Baseline, backup e TEST del restore"
cat <<'X'
  virsh -c qemu:///system snapshot-create-as llm-vm baseline --description "stack ok"
  ssh $VM_USER@<VM_IP> 'cd ~/llm-services && ./backup-db.sh'
  ./restore-test.sh          # TC-05: OBBLIGATORIO almeno una volta

  Nel repo, prima sessione:
    /setup-matt-pocock-skills ; /grill-with-docs ; /graphify .
X
ask "Eseguire ora il test di restore?" && run "./restore-test.sh" || warn "da fare"; fi

echo -e "\n\033[32mDeploy completato.\033[0m Vedi docs/INSTALL_GUIDE.md e docs/DUAL-AUTH.md"
