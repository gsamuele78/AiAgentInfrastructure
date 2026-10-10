#!/usr/bin/env bash
# tests/serena/check-project-yml.sh [DIR_PROGETTO...]  (default: la root del repo)
# Serve rete e uv: scarica serena-agent alla versione del pin. Per questo NON sta
# in test-scripts.sh (che gira ovunque, offline) ma in un job CI dedicato.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
PIN=$(sed -n 's/^serena-agent==\([^[:space:]#]*\).*/\1/p' "$REPO/stack/requirements-tools.txt" | head -1)
[ -n "$PIN" ] || { echo "serena-agent non pinnato in stack/requirements-tools.txt" >&2; exit 2; }
command -v uvx >/dev/null 2>&1 || { echo "serve uvx (uv)" >&2; exit 2; }
[ $# -gt 0 ] || set -- "$REPO"
echo "serena-agent==$PIN"
# -I: non importare moduli dalla cwd (il progetto controllato potrebbe averne).
uvx -q --from "serena-agent==$PIN" python -I "$HERE/check_project_yml.py" "$@"
