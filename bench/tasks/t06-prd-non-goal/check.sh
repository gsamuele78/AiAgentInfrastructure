#!/usr/bin/env bash
cd "$1" || exit 1
f=docs/decisioni/ha.md
[ -f "$f" ] || { echo "manca $f"; exit 1; }
grep -Eiq '^\**Esito\**: *\**respinta' "$f" || { echo "esito atteso: respinta (alta disponibilita' e' un non-obiettivo)"; exit 1; }
grep -Eq '§ ?3|sezione 3|Non-obiettivi' "$f" || { echo "non cita la sezione 3 del PRD"; exit 1; }
