#!/usr/bin/env bash
# Backup del DB litellm (modelli, spend, budget). Esegui NELLA VM.
set -euo pipefail
OUT="${1:-$HOME/backups/litellm}"; mkdir -p "$OUT"
F="$OUT/litellm-$(date +%Y%m%d-%H%M%S).sql.gz"
docker compose exec -T db pg_dump -U litellm litellm | gzip > "$F"
echo "backup: $F ($(du -h "$F" | cut -f1))"
ls -1t "$OUT"/litellm-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -v
echo "NB: esegui restore-test.sh almeno una volta — un backup non testato non e' un backup."
