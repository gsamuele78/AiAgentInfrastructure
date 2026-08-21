#!/usr/bin/env bash
# Pulizia della configurazione host (headroom proxy, litellm pipx, postgres).
# Non distruttivo: stop/disable + backup. --dry-run disponibile.
set -uo pipefail
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else eval "$*"; fi; }
say(){ echo -e "\033[36m==>\033[0m $*"; }
ts(){ date +%Y%m%d-%H%M%S; }

say "PRE-CHECK: il gateway risponde?"
if curl -fsS --max-time 3 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1; then
  echo "  OK: sicuro procedere"
else
  echo -e "  \033[31mATTENZIONE\033[0m: :4000 non risponde. Ordine PSE: prima la VM, POI la pulizia."
  [ "$DRY" = 0 ] && { read -rp "  Procedere comunque? [y/N] " a; [ "$a" = y ] || exit 1; }
fi
say "1) headroom proxy standalone"
run "systemctl --user disable --now headroom.service 2>/dev/null || true"
run "mv ~/.config/systemd/user/headroom.service ~/headroom.service.bak-$(ts) 2>/dev/null || true"
run "rm -f ~/.config/systemd/user/.#headroom.service*"
run "headroom unwrap opencode 2>/dev/null || true"
run "headroom unwrap codex 2>/dev/null || true"
say "2) litellm pipx (resta INSTALLATO come fallback)"
run "systemctl --user stop litellm.service 2>/dev/null || true"
echo "  rimuovilo solo a VM collaudata:  pipx uninstall litellm"
say "3) postgres host (verificato litellm-only)"
run "sudo -u postgres psql -c 'ALTER SYSTEM RESET log_connections;' 2>/dev/null || true"
run "sudo systemctl stop postgresql@17-main postgresql.service 2>/dev/null || true"
run "sudo systemctl disable postgresql 2>/dev/null || true"
echo "  dati NON cancellati (/var/lib/postgresql/17/main)"
say "4) vecchio config con segreti in chiaro"
if [ -f ~/litellm_config.yaml ]; then
  run "chmod 600 ~/litellm_config.yaml"
  run "mv ~/litellm_config.yaml ~/litellm_config.yaml.old-$(ts)"
  echo "  ⚠️ conteneva credenziali in chiaro (664): NON riusarle"
fi
run "systemctl --user daemon-reload"
[ "$DRY" = 0 ] && { ss -tlnp 2>/dev/null | grep -E ':(8787|5432)' && echo "  ancora in ascolto" || echo "  8787 e 5432 chiuse"; }
echo -e "\n\033[32mPulizia completata.\033[0m Backup: ~/*.bak-*"
