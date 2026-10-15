#!/usr/bin/env bash
cd "$1" || exit 1
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/cache" && touch "$t/cache/x"
out=$(CACHE_DIR="$t/cache" bash scripts/clean-cache.sh --dry-run 2>&1) || { echo "--dry-run esce con errore: $out"; exit 1; }
[ -f "$t/cache/x" ] || { echo "--dry-run ha cancellato"; exit 1; }
grep -q "$t/cache" <<<"$out" || { echo "--dry-run non dice cosa cancellerebbe"; exit 1; }
CACHE_DIR="$t/cache" bash scripts/clean-cache.sh >/dev/null 2>&1 || { echo "senza --dry-run fallisce"; exit 1; }
[ ! -e "$t/cache" ] || { echo "senza --dry-run non cancella piu'"; exit 1; }
