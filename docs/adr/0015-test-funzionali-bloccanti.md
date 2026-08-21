# 0015 — I test funzionali possono fallire (supersede una conseguenza di 0010)
- **Status**: Accepted
- **Data**: 2026-08-21
- **Supersede**: [0010](0010-ci-non-cd.md) — **solo** la conseguenza
  «il runner self-hosted [...] gira solo a laptop acceso (`continue-on-error: true`)».
  La decisione di 0010 (CI di validazione, nessun CD) resta intatta.

## Contesto
`functional.yml` aveva `continue-on-error: true` **sul job**. Motivazione
originale: il runner self-hosted gira solo a laptop acceso, e un job in coda che
scade non deve tingere di rosso il repo. Ragionevole in astratto.

Conseguenza non prevista, emersa dall'audit del 2026-08-21: **TC-01
(compressione), TC-02 (nessun bypass), TC-04 (abbonamento) e TC-05 (restore)
giravano ma non potevano fallire**. Un test che non può fallire non è un test:
è un log che nessuno legge. `DEVOPS-AUDIT.md` li marcava ✅ come se fossero
gate, e per mesi l'unico gate reale è stato la CI statica.

Il costo si è visto: `restore-test.sh` aveva la modalità locale rotta e TC-05
non l'ha mai segnalato, perché in CI girava solo il ramo ssh e comunque non
poteva far fallire il job.

## Alternative considerate
| Opzione | Un test rotto si nota | Rumore a laptop spento | Costo manutenzione |
|---|---|---|---|
| `continue-on-error: true` (stato precedente) | ❌ mai | nessuno | zero |
| Job di preflight che interroga l'API runner e fa da gate con `if:` | ✅ | nessuno | **due job e un token da mantenere** — contro il vincolo 30 min/mese |
| Togliere `schedule`, solo `workflow_dispatch` | ✅ | nessuno | si perde il rilevamento delle derive |
| **Togliere `continue-on-error`, tenere `schedule`** | ✅ | un run rosso quando il laptop è spento | zero |

Il preflight sarebbe la soluzione elegante, ed è esattamente il tipo di
complessità che questo progetto ha deciso di non permettersi: due job, un
token con permessi sui runner, e una cosa in più che si rompe da sola.

## Decisione
`continue-on-error: true` **rimosso dal job**. `functional.yml` mantiene
`schedule` e `workflow_dispatch`, e acquisisce `concurrency` con
`cancel-in-progress: true`: se il laptop resta spento per settimane, un run
schedulato annulla quello vecchio ancora in coda invece di accumularli.

`runs-on` resta `[self-hosted, linux, llm-gateway]` e i trigger restano quelli:
**mai `pull_request`** su un workflow self-hosted (repo pubblico, vedi
`GITHUB-SETUP.md` §4).

## Conseguenze
**Positive:** TC-01, TC-02, TC-04 e TC-05 tornano a essere test. Una deriva
della configurazione o un backup non più restorabile si vedono nel badge, non
solo nei log di uno step che nessuno apre.

**Negative — il prezzo, dichiarato:**
- **A laptop spento il run settimanale risulta rosso.** È rumore, e va letto
  per quello che è: un rosso «no runner» non è un rosso «test fallito», e si
  distinguono aprendo il run. Chi non vuole quel rumore ha due strade: spegnere
  la schedule, o accendere il laptop il lunedì mattina.
- Un rosso ricorrente e ignorato è peggio di nessun rosso: se dopo qualche mese
  la schedule risulta sempre rossa perché il laptop è sempre spento, **questa
  decisione va rivista**, non subita.
- `functional.yml` non è tra gli status check richiesti su `main`
  (`GITHUB-SETUP.md` §2 elenca `syntax`, `secrets`, `docs`): può fallire senza
  bloccare un merge. È voluto — bloccare i merge sulla disponibilità di un
  laptop sarebbe assurdo — ma significa che il segnale va guardato, non atteso.

**Enforcement:** `scripts/test-scripts.sh` §3 verifica che nessun workflow abbia
`continue-on-error` a livello di job, e che nessun workflow self-hosted sia
innescabile da una PR.

**Da rivedere se:** il rumore diventa costante (vedi sopra), o se nasce un
ambiente sempre acceso su cui far girare la catena reale.
