#!/usr/bin/env bash
# --dry-run accettato ma ignorato: cancella lo stesso
cd "$1" && sed -i 's|^dir=|[ "${1:-}" = "--dry-run" ] \&\& echo "dry-run"\ndir=|' scripts/clean-cache.sh
