# 0020 — Dependabot e scala di autoaggiornamento

- **Status**: Accepted (stadio 0 attivo: `.github/dependabot.yml`); stadi 1–3 condizionati
- **Data**: 2026-10-10
- **Relazione**: rispetta 0010 (CI, non CD) e la regola sui runner self-hosted (`GITHUB-SETUP.md` §4).

## Contesto
Obiettivo: l'infrastruttura si aggiorna da sola **quando è abbastanza stabile**.
Tre vincoli già presi lo limitano, e vanno detti subito:

1. **ADR-0010**: nessun deploy automatico. Una merge su `main` non è un deploy,
   ma un deploy automatico sì.
2. **Repo pubblico + runner self-hosted**: `functional.yml` non può partire da
   una PR (neanche di Dependabot). Quindi i test sulla catena reale (TC-01,
   TC-09) **non possono girare automaticamente su una PR di aggiornamento**.
3. **Molte versioni oggi non sono leggibili da un bot**: immagine LiteLLM su tag
   mobile (debito #1) e `FROM` costruiti con `ARG`; vLLM su `${VLLM_TAG:-latest}`;
   `serena-agent@latest`, `headroom-ai` senza pin, MCP via `npx -y` senza
   versione. Un bot non può proporre un aggiornamento di ciò che non è pinnato.

## Alternative considerate
| Opzione | Copertura | Costo |
|---|---|---|
| Nessun bot | — | il drift si scopre per caso (vedi Serena, ADR-0017) |
| **Renovate** (AGPL-3.0) | tutto, anche file arbitrari via regex; `minimumReleaseAge`; regole di automerge | app ospitata da terzi o un servizio self-hosted in più |
| **Dependabot** | ecosistemi standard: Actions, compose, Dockerfile, pip/uv, npm, pre-commit | nativo GitHub, zero infrastruttura; non legge pin in formati custom |

## Decisione
**Dependabot**, e le versioni si scrivono **nei formati che Dependabot legge**
invece di adottare Renovate: Dockerfile con `FROM` letterale + digest, tool
Python in `stack/requirements-tools.txt` (pip), MCP Node in `stack/package.json`
(npm), hook in `.pre-commit-config.yaml`. Il resto (es. il commit di
mattpocock) lo segnala `stack.py outdated`.

"Abbastanza stabile" diventa **cooldown**: una versione viene proposta solo
dopo N giorni dalla pubblicazione (7 per Actions e compose, 14 per le immagini
del Dockerfile). Le soglie per semver (`semver-*-days`) **non sono ammesse** da
GitHub per questi ecosistemi — lo schema pubblico le accetta, il parser di
Dependabot no (scoperto dal check della PR #4): varranno per pip/npm in P1. Le
major restano fuori dai gruppi, quindi arrivano come PR singole.
Gli aggiornamenti di sicurezza non aspettano il cooldown. Major di postgres
**ignorate**: sono migrazioni di dati, non aggiornamenti d'immagine.

**Scala di autonomia** — si sale di uno stadio solo se il criterio è misurato,
e ogni salto è un ADR nuovo che supersede questo:

| Stadio | Cosa fa il bot | Criterio per arrivarci |
|---|---|---|
| **0 — ora** | apre PR raggruppate; `validate.yml` le controlla; **merge e deploy manuali** | — |
| 1 | automerge del solo gruppo `github-actions` minor/patch (tocca la CI, non il runtime) | 8 settimane consecutive di `functional.yml` verde + nessun revert di aggiornamenti |
| 2 | automerge di patch per immagini di supporto (nginx, alpine) | 3 mesi allo stadio 1 senza revert; digest pin attivi (debito #1 chiuso) |
| 3 | `stack.py upgrade` su timer locale: snapshot VM → deploy → `validate --level 5` → **rollback automatico** se rosso | eval L6 stabili (ADR-0019) + TC-05/06 verdi da 3 mesi. **Richiede di superare ADR-0010** |

LiteLLM e headroom-ai **non entrano mai nell'automerge** finché TC-01/TC-09 non
possono girare sulla PR: il gate di build intercetta un import rotto, non una
compressione o una cache che smettono di funzionare.

## Conseguenze
**Positive:** il drift diventa una PR settimanale invece di una scoperta; il
cooldown evita le release ritirate nei primi giorni; zero infrastruttura nuova.

**Negative — da non minimizzare:**
- **"Si aggiorna da solo" resta parziale per costruzione**: il runtime
  (gateway, Ollama, tool sull'host) richiede sempre il maintainer fino allo
  stadio 3, che è un cambio di architettura.
- Fino a P1 la copertura è minima: Actions e compose. Il componente più a
  rischio (immagine LiteLLM) non è coperto finché il debito #1 resta aperto.
- PR settimanali da leggere: tempo contro il vincolo dei 30 min/mese
  (mitigato: gruppi, limite di PR aperte, cooldown).
- Il cooldown ritarda anche le correzioni: una patch importante non di
  sicurezza aspetta 7 giorni (14 per le immagini).

**Da rivedere se:** servono pin in formati che Dependabot non legge (allora
Renovate), o i criteri di uno stadio sono soddisfatti.
