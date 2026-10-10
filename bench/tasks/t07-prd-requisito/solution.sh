#!/usr/bin/env bash
cd "$1" && sed -i 's/^| F2 | Routing multi-provider con fallback | MUST | TC-09 |$/&\n| F3 | Spesa per lane visibile in un report settimanale | SHOULD | `\/spend\/logs` raggruppato per modello |/' docs/PRD.md
