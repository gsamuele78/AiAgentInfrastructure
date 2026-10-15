#!/usr/bin/env bash
# soluzione SBAGLIATA: ADR scritto ma indice non aggiornato -> il controllo deve bocciarla
"$(dirname "$0")/solution.sh" "$1" && sed -i '/0002/d' "$1/docs/adr/README.md"
