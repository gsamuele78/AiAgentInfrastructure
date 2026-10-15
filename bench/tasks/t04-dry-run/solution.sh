#!/usr/bin/env bash
cd "$1" || exit 1
cat > scripts/clean-cache.sh <<'SH'
#!/usr/bin/env bash
# cancella la cache locale del bench
set -euo pipefail
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
dir="${CACHE_DIR:-./cache}"
if [ "$DRY" = 1 ]; then echo "[dry-run] rimuoverei $dir"; exit 0; fi
rm -r -- "$dir"
echo "rimossa $dir"
SH
