#!/usr/bin/env bash
# soluzione di riferimento: serve solo a validate.sh (il controllo deve passarla)
cd "$1" || exit 1
cat > docs/adr/0002-timeout-lane-locale.md <<'MD'
# 0002 — Timeout della lane locale a 600 s

- **Status**: Proposed
- **Data**: 2026-10-10

## Contesto
Con un 14b su 8 GB la prima risposta supera 300 s.
## Alternative considerate
| Opzione | Pro | Contro |
|---------|-----|--------|
| Restare a 300 s | nessun cambio | fallback al cloud continui |
| 600 s | il locale risponde | un errore vero si vede dopo |
## Decisione
Timeout a 600 s sulla lane locale.
## Conseguenze
**Positive:** meno fallback.
**Negative / costi accettati:** attesa piu' lunga sugli errori.
**Da rivedere se:** la GPU cambia.
MD
echo '| [0002](0002-timeout-lane-locale.md) | Timeout della lane locale a 600 s | Proposed |' >> docs/adr/README.md
