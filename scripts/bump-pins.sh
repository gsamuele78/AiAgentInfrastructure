#!/usr/bin/env bash
# ============================================================
#  bump-pins.sh -- aggiorna i pin di stack/versions.conf che Dependabot non
#  sa leggere (ADR-0026). La versione la sceglie mise (ADR-0024), con lo
#  stesso cooldown di ADR-0020: `minimum_release_age` scarta le release
#  piu' giovani di COOLDOWN (default 7d).
#
#  Quali righe e come: il commento `# bump: <spec mise>` in fondo alla riga.
#    NODE_VERSION=24.21.0      # bump: node@24          (resta sulla LTS 24)
#    MISE_VERSION=2026.10.0    # bump: github:jdx/mise
#  Una riga senza `# bump:` non si tocca. Mai all'indietro: se mise propone
#  una versione piu' vecchia del pin (es. cooldown piu' lungo), si tiene il pin.
#
#  Uso:  scripts/bump-pins.sh [--dry-run]
#    --dry-run   stampa cosa cambierebbe, non scrive (invariante #9)
#  Uscita: 0 = niente da fare o file aggiornato; 1 = errore (spec che mise non
#  risolve: non si scrive niente, nemmeno le righe risolte).
#  Lo usa .github/workflows/pin-bump.yml (settimanale, apre la PR).
#  MISE_BIN: mise da usare (default: `mise` sul PATH; il workflow lo scarica
#  verificato con ut_mise_bootstrap).
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CONF="${PINS_FILE:-$HERE/../stack/versions.conf}"
MISE="${MISE_BIN:-mise}"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
if ! command -v "$MISE" >/dev/null 2>&1; then
  # TC-08: il dry-run completa anche su una macchina vuota. Se pero' MISE_BIN e'
  # indicato (CI) e manca, e' un errore: non si "verifica" senza mise.
  if [ "$DRY" = 1 ] && [ -z "${MISE_BIN:-}" ]; then
    echo "  – mise assente: niente da verificare (installalo o indica MISE_BIN)"; exit 0
  fi
  echo "✗ mise non trovato ($MISE)" >&2; exit 1
fi

newer(){ [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]; }

out=$(mktemp); trap 'rm -f "$out"' EXIT
changes=0; errors=0
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^([A-Z_]+)=([^[:space:]#]+)(.*#[[:space:]]*bump:[[:space:]]*([^[:space:]]+).*)$ ]]; then
    key=${BASH_REMATCH[1]}; cur=${BASH_REMATCH[2]}; rest=${BASH_REMATCH[3]}; spec=${BASH_REMATCH[4]}
    new=$(MISE_MINIMUM_RELEASE_AGE="${COOLDOWN:-7d}" "$MISE" latest "$spec" 2>/dev/null | tail -1)
    new=${new#v}
    if [ -z "$new" ]; then
      echo "  ✗ $key: mise non risolve '$spec'" >&2; errors=$((errors+1))
    elif newer "$cur" "$new"; then
      echo "  ↑ $key: $cur → $new ($spec, cooldown ${COOLDOWN:-7d})"
      line="$key=$new$rest"; changes=$((changes+1))
    else
      echo "  = $key: $cur ($spec: $new)"
    fi
  fi
  printf '%s\n' "$line" >> "$out"
done < "$CONF"

[ "$errors" -gt 0 ] && { echo "✗ $errors spec non risolte: $CONF non toccato" >&2; exit 1; }
if [ "$changes" -eq 0 ]; then echo "  niente da aggiornare"; exit 0; fi
if [ "$DRY" = 1 ]; then echo "  [dry-run] $changes pin da aggiornare, $CONF non toccato"; exit 0; fi
cat "$out" > "$CONF"
echo "  ✓ $changes pin aggiornati in $CONF"
