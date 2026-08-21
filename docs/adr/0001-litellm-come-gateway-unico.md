# 0001 — LiteLLM come gateway unico
- **Status**: Accepted
- **Data**: 2026-06-24

## Contesto
Quattro client con credenziali ed endpoint propri: credenziali duplicate,
nessun controllo di spesa, nessuna policy trasversale applicabile.

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Chiavi per client | zero infrastruttura | stato attuale, insostenibile |
| **LiteLLM proxy** | endpoint unico, 100+ provider, budget | un servizio in più; SPOF |
| Gateway custom | su misura | da scrivere e mantenere: contro il vincolo |

## Decisione
LiteLLM come unico punto d'ingresso per tutti i client AI.

## Conseguenze
**Positive:** credenziali in un posto solo; routing/fallback centralizzati; spend.
**Negative:** SPOF (mitigato: litellm pipx fallback, snapshot VM).
**Da rivedere se:** il maintainer non riesce a mantenerlo, o i client perdono il
supporto a endpoint OpenAI-compatibili.
