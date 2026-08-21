#!/usr/bin/env bash
# Backup del DB litellm (modelli, spend, budget). Esegui NELLA VM.
#   ./backup-db.sh [--dry-run] [DIR_OUTPUT]
set -uo pipefail
DRY=0; ARGS=()
for a in "$@"; do case "$a" in --dry-run) DRY=1;; *) ARGS+=("$a");; esac; done
run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else eval "$*"; fi; }
OUT="${ARGS[0]:-$HOME/backups/litellm}"
F="$OUT/litellm-$(date +%Y%m%d-%H%M%S).sql.gz"
run "mkdir -p '$OUT'"
run "docker compose exec -T db pg_dump -U litellm litellm | gzip > '$F'"
[ "$DRY" = 0 ] && echo "backup: $F ($(du -h "$F" | cut -f1))"
# retention: tiene i 14 piu' recenti
run "ls -1t '$OUT'/litellm-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -v"
echo "NB: esegui restore-test.sh almeno una volta — un backup non testato non e' un backup."
