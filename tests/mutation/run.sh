#!/usr/bin/env bash
# ============================================================
#  tests/mutation/run.sh -- ogni controllo deve saper FALLIRE.
#  Per ogni mutazione del catalogo: copia il repo in una dir temporanea,
#  rompe la cosa che il controllo protegge, lancia il test e pretende che
#  diventi rosso con il messaggio atteso. Un verde qui = controllo che non
#  protegge niente (un "buco"), e la suite esce 1.
#
#  Uso:  tests/mutation/run.sh            tutto il catalogo
#        tests/mutation/run.sh HC-0       solo le mutazioni il cui nome contiene "HC-0"
#  Catalogo: tests/mutation/catalog.tsv (nome · pattern atteso · test · comando)
#  Nato dagli esperimenti delle PR #8/#9/#10, prima solo in uno scratchpad.
# ============================================================
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FILTER="${1:-}"; P=0; F=0; S=0
while IFS=$'\t' read -r name expect test cmd; do
  case "$name" in ''|'#'*) continue ;; esac
  [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue
  W=$(mktemp -d)
  # copia senza .git pesante, ma con un indice git (HC-08 usa git ls-files)
  (cd "$REPO" && tar --exclude=./.git -cf - .) | (cd "$W" && tar -xf -)
  (cd "$W" && git init -q && git add -A >/dev/null 2>&1)
  if ! (cd "$W" && bash -c "$cmd") >/dev/null 2>&1; then
    echo -e "  \033[33m?\033[0m mutazione non applicabile: $name"; S=$((S+1)); rm -rf "$W"; continue
  fi
  # la mutazione deve aver cambiato davvero qualcosa
  if [ -z "$(cd "$W" && git status --porcelain)" ]; then
    echo -e "  \033[33m?\033[0m mutazione a vuoto (nessun file cambiato): $name"; S=$((S+1)); rm -rf "$W"; continue
  fi
  out=$(cd "$W" && SKIP_BEHAVIOR=1 bash -c "$test" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q -- "$expect"; then
    echo -e "  \033[32m✓\033[0m rosso come atteso: $name"; P=$((P+1))
  else
    echo -e "  \033[31m✗\033[0m BUCO: $name (rc=$rc, atteso '$expect')"; F=$((F+1))
  fi
  rm -rf "$W"
done < "$(dirname "$0")/catalog.tsv"
echo -e "\n  mutazioni: \033[32m✓ $P\033[0m  \033[31m✗ $F\033[0m  ? $S"
[ "$F" = 0 ] && [ "$S" = 0 ]
