# PRD — Gateway AI

## 4. Requisiti
### Funzionali
| ID | Requisito | Priorità | Verifica |
|----|-----------|----------|----------|
| F1 | Endpoint OpenAI-compatibile unico | MUST | `curl /v1/models` risponde |
| F2 | Routing multi-provider con fallback | MUST | TC-09 |

### Non-funzionali
| ID | Requisito | Verifica |
|----|-----------|----------|
| N1 | Nessun segreto leggibile da altri utenti | devops-audit §2 |
