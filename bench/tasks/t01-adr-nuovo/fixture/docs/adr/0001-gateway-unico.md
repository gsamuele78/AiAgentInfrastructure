# 0001 — Un solo gateway

- **Status**: Accepted
- **Data**: 2026-01-10

## Contesto
Ogni client parlava al suo provider.
## Alternative considerate
| Opzione | Pro | Contro |
|---------|-----|--------|
| Nessun gateway | semplice | chiavi ovunque |
| LiteLLM | un punto | un servizio in piu' |
## Decisione
LiteLLM come gateway unico.
## Conseguenze
**Positive:** un solo punto di controllo.
**Negative / costi accettati:** un servizio da mantenere.
**Da rivedere se:** LiteLLM cambia licenza.
