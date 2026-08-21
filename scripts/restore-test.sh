#!/usr/bin/env bash
# ============================================================
#  restore-test.sh -- TC-05: verifica che il backup sia RESTORABILE.
#  Chiude il debito #1 ("un backup non testato non e' un backup").
#  Non distruttivo: ripristina in un DB SCRATCH, mai su quello di produzione.
#
#  Uso:  ./restore-test.sh              (locale, docker compose nella dir corrente)
#        VM_SSH=jfs@192.168.122.50 ./restore-test.sh    (via ssh sulla VM)
# ============================================================
set -uo pipefail
SCRATCH="litellm_restoretest_$(date +%s)"
VM_SSH="${VM_SSH:-}"
COMPOSE_DIR="${COMPOSE_DIR:-$HOME/llm-services}"
ok(){ echo -e "  \033[32m✓\033[0m $1"; }
ko(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo -e "     \033[2m→ $2\033[0m"; exit 1; }
say(){ echo -e "\n\033[36m━━ $* ━━\033[0m"; }

# esegue un comando in locale o sulla VM via ssh
R(){ if [ -n "$VM_SSH" ]; then ssh "$VM_SSH" "cd $COMPOSE_DIR && $*"; else eval "$*"; fi; }

say "1. Backup fresco"
R "docker compose exec -T db pg_dump -U litellm litellm | gzip > /tmp/rt.sql.gz" \
  && ok "dump creato" || ko "pg_dump fallito" "il container db e' up?"
SIZE=$(R "stat -c %s /tmp/rt.sql.gz" 2>/dev/null || echo 0)
[ "$SIZE" -gt 100 ] && ok "dump non vuoto (${SIZE} byte)" || ko "dump vuoto o troppo piccolo"

say "2. DB scratch"
R "docker compose exec -T db psql -U litellm -d postgres -c 'CREATE DATABASE $SCRATCH;'" >/dev/null 2>&1 \
  && ok "creato $SCRATCH" || ko "CREATE DATABASE fallita"

cleanup(){ R "docker compose exec -T db psql -U litellm -d postgres -c 'DROP DATABASE IF EXISTS $SCRATCH;'" >/dev/null 2>&1; }
trap cleanup EXIT

say "3. Restore nello scratch"
R "gunzip -c /tmp/rt.sql.gz | docker compose exec -T db psql -U litellm -d $SCRATCH" >/dev/null 2>&1 \
  && ok "restore eseguito" || ko "restore fallito" "dump corrotto o incompatibile"

say "4. Verifica del contenuto"
TBL=$(R "docker compose exec -T db psql -U litellm -d $SCRATCH -tAc \
  \"SELECT count(*) FROM information_schema.tables WHERE table_schema='public';\"" 2>/dev/null | tr -d ' \r')
[ "${TBL:-0}" -gt 0 ] && ok "$TBL tabelle ripristinate" || ko "nessuna tabella nel DB ripristinato"

LT=$(R "docker compose exec -T db psql -U litellm -d $SCRATCH -tAc \
  \"SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'LiteLLM%';\"" 2>/dev/null | tr -d ' \r')
[ "${LT:-0}" -gt 0 ] && ok "$LT tabelle LiteLLM_* presenti" \
  || echo -e "  \033[33m!\033[0m nessuna tabella LiteLLM_* (DB nuovo? verifica manualmente)"

say "5. Pulizia"
cleanup && ok "DB scratch rimosso"
R "rm -f /tmp/rt.sql.gz"

echo -e "\n\033[32mTC-05 SUPERATO: il backup e' restorabile.\033[0m"
echo "Annota la data in docs/TEST-PLAN.md — va rifatto a ogni cambio di schema."
