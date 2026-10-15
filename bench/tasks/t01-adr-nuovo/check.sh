#!/usr/bin/env bash
# deterministico: il file esiste, ha le sezioni del template, e' nell'indice
cd "$1" || exit 1
f=$(ls docs/adr/0002-*.md 2>/dev/null | head -1)
[ -n "$f" ] || { echo "manca docs/adr/0002-*.md"; exit 1; }
for h in '^- \*\*Status\*\*: Proposed' '^- \*\*Data\*\*: 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' '^## Contesto' '^## Alternative considerate' '^## Decisione' '^## Conseguenze' '\*\*Negative'; do
  grep -Eq "$h" "$f" || { echo "sezione mancante: $h"; exit 1; }
done
rows=$(awk '/^## Alternative/{a=1;next} /^## /{a=0} a && /^\|/ && !/---/' "$f" | wc -l)
[ "$rows" -ge 3 ] || { echo "servono >= 2 alternative in tabella (righe: $rows)"; exit 1; }
grep -Eq "^\| \[0002\]\($(basename "$f")\)" docs/adr/README.md || { echo "indice senza la riga 0002 che punta a $(basename "$f")"; exit 1; }
grep -q '0001-gateway-unico.md' docs/adr/README.md || { echo "indice: riga 0001 persa"; exit 1; }
