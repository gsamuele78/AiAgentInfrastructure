# 0010 — CI di validazione, nessun deployment automatico
- **Status**: Accepted
- **Data**: 2026-07-27

## Contesto
Il repo contiene config, script e un Dockerfile. Un errore di sintassi scoperto
in fase di deploy costa tempo. Una posizione precedente («niente CI/CD, è
single-host») confondeva CI (validazione) e CD (rilascio).

## Alternative considerate
| Opzione | Errori intercettati | Rischio |
|---|---|---|
| Nessuna CI | nessuno prima del deploy | errori scoperti sul target |
| **CI di validazione** | sintassi, lint, build | nessuno |
| CI + CD automatico | idem | deploy non presidiato su workstation: **no** |

## Decisione
GitHub Actions: `validate.yml` (sintassi, build col gate callback, anti-segreti,
coerenza ADR) su runner GitHub; `functional.yml` (audit, test end-to-end,
restore TC-05) su **runner self-hosted**, perché la catena reale non è
raggiungibile dai runner cloud. **Nessun job di deploy.**

## Conseguenze
**Positive:** errori di sintassi mai sul target; gate del callback a ogni push;
il restore viene testato periodicamente invece che "quando ci penso".
**Negative:** due workflow da mantenere; il runner self-hosted va registrato e
gira solo a laptop acceso (`continue-on-error: true`).
**Da rivedere se:** nasce un ambiente di staging reale (allora ha senso il CD).
