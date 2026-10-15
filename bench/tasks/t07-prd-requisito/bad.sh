#!/usr/bin/env bash
# requisito senza criterio di verifica
cd "$1" && sed -i 's/^| F2 | Routing multi-provider con fallback | MUST | TC-09 |$/&\n| F3 | Spesa per lane visibile in un report settimanale | SHOULD | |/' docs/PRD.md
