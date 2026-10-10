# shellcheck shell=bash
# Mattoni condivisi dagli adattatori. Sono quelli VERI di
# scripts/lib/user-tools.sh (il ripiego "script" di ADR-0024): la CI misura il
# codice che si installa, non una copia. Qui solo nomi brevi e la cache del bench.
export USER_TOOLS_CACHE="${BENCH_CACHE:?}"
# shellcheck source=../../../scripts/lib/user-tools.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/lib/user-tools.sh"

node_tarball(){ ut_node_tarball "$@"; }
opencode_npm(){ ut_opencode_npm "$@"; }
graphify_uv(){ ut_graphify_uv "$@"; }
versions(){ ut_versions; }
