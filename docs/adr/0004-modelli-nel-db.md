# 0004 — Modelli OpenRouter nel DB, non nel file
- **Status**: Accepted
- **Data**: 2026-06-24

## Contesto
OpenRouter espone centinaia di modelli in continuo cambiamento. La `model_list`
a mano è error-prone; il wildcard `openrouter/*` instrada ma non popola
`/v1/models` (dropdown vuoto) e non porta pricing (spend a zero).

## Alternative considerate
| Opzione | Lista nei client | Pricing | Restart |
|---|---|---|---|
| Wildcard | ❌ | ❌ | — |
| model_list a mano | ✅ | ✅ | manutenzione insostenibile |
| File rigenerato | ✅ | ✅ | **sì** |
| **Riconciliazione DB via API** | ✅ | ✅ | **no** |

## Decisione
`STORE_MODEL_IN_DB=true` + script che calcola il diff e applica via
`/model/new` e `/model/delete`. Wildcard come catch-all.

## Conseguenze
**Positive:** nessun restart; il diff è il changelog; pricing allineato.
**Negative:** richiede Postgres; serve un loop esterno (LiteLLM non ha sync nativo).
**Da rivedere se:** non si vuole più un DB → fallback file-based.
