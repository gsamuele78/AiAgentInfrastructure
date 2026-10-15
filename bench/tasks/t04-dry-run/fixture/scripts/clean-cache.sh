#!/usr/bin/env bash
# cancella la cache locale del bench
set -euo pipefail
dir="${CACHE_DIR:-./cache}"
rm -r -- "$dir"
echo "rimossa $dir"
