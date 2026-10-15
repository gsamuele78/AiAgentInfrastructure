# 0025 — Pratiche OpenHands importate, ognuna con la sua misura

- **Status**: Proposed — le parti strutturali sono in questa PR; ogni adozione di
  comportamento attende la propria misura (`PREREG.md` di ciascuna cartella)
- **Data**: 2026-10-10
- **Relazione**: rende concreti e verificabili 0019 §1-2, §4, §6 (skill, ConfirmRisky,
  L6); applica 0021 (misurare prima di adottare); rispetta 0006 (un tool per layer),
  0010 (CI non CD), 0016 (catena `auto`).

## Contesto
Il proprietario ha chiesto di passare in rassegna i repository pubblici di
github.com/orgs/OpenHands (61, 12 letti a fondo, 2026-10-10: `software-agent-sdk`
c4b9329, `extensions` 642df1a, `OpenHands` e0a26af, `SkillRefiner` 9a03ded,
`critic-rubrics` 9f03ba4, `docker-sbx-kit` 277a329 e altri) e di importare tutto ciò che
vale la pena, adattato a questo repo, **tranne ciò che è senza licenza**. ADR-0019 aveva
già preso le pratiche documentate (AGENTS.md, skill on-demand, setup, pre-commit,
ConfirmRisky, golden task); il sorgente di OpenHands ne mostra altre, e soprattutto
**come le verificano**: test a tier, corpora avversari, mock LLM, sonde sui provider.

Il vincolo dominante resta: maintainer singolo, < 30 min/mese. Si importano pattern,
corpora e formati di dati, **non** l'SDK di OpenHands come dipendenza: i nostri agenti
sono opencode e Claude Code.

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Adottare l'SDK/agent-server di OpenHands | tutto già fatto | secondo harness accanto a opencode (0006, 0019); runtime Docker |
| Copiare il codice di OpenHands così com'è | meno lavoro di scrittura | scritto per il loro SDK: non gira sui nostri client |
| **Importare pattern e corpora, ognuno con un test offline e una misura pre-registrata** | verificabile, niente dipendenze nuove a runtime | scrittura nostra da mantenere; molti esiti restano "da misurare" |

## Decisione
| § | Pratica (fonte OpenHands, MIT) | Qui | Stato |
|---|---|---|---|
| 1 | Test a tier t/b + early stopper (`tests/integration`, `early_stopper.py`) | `bench/tasks/` (10 task, ≥2 per ruolo), `validate.sh` offline, `run.sh` con `lib/early_stop.py` | struttura adottata; M1/M2 da misurare |
| 2 | Sonde di conformità API a01–a08 | `bench/compliance/probe.py` su ogni lane di `auto`, `disable_fallbacks` | impianto adottato; C1 da misurare |
| 3 | Mock LLM per e2e deterministici (`testing/test_llm.py`, playwright mock-llm) | `tests/gateway-mock/`: LiteLLM alla versione del Dockerfile con config derivata da quella vera, G1–G8 in CI | **adottato** |
| 4 | Analizzatore deterministico + corpus avversario (`security/defense_in_depth`) | `tests/risk-corpus/`: regole ask/deny in entrambi i client da una fonte unica, misurate | **adottato** (R1 100 %, R2 0 %); H1 10 %: serve un analizzatore vero, ADR futuro |
| 5 | Lint del catalogo skill (`extensions/tests`) | `tests/skills/` | **adottato** |
| 6 | Mascheramento dei segreti (`secret_registry.py`) | `bench/secret-canary/secret_mask.py` (callback LiteLLM, provato in G8) + canarino `b03` | callback pronto, **non collegato**: decide S1 |
| 7 | Stuck detector (`stuck_detector.py`) | `bench/stuck/analyze.py` offline | solo misura |
| 8 | Condensazione regolare (`context/condenser`) | `bench/compaction/variant.py`: A/B sulla `compaction` di opencode, **nessun secondo condenser** (0006) | da misurare |
| 9 | Manutentore di AGENTS.md (`github-agents-md-maintainer`) | `tests/agents-md/check.py`: solo la parte deterministica (riferimenti che esistono) | **adottato**; il riscrittore LLM no: AGENTS.md è curato |
| 10 | Marcatori a nonce per testo non fidato (pr-review) | `bench/tasks/lib/untrusted.py` | disponibile per gli agenti che leggeranno PR o log |
| 11 | SkillRefiner (raffinamento offline da tracce) | `bench/skillrefiner/export.py` nel suo formato | rinviato: niente skill di repo né tracce sufficienti |
| 12 | Servizio `automation` (cron/webhook) | `.github/workflows/agent-measure.yml` (cron + dispatch, self-hosted) | adattato: nessun servizio nuovo |

**Escluse**:
- `critic-rubrics` e il modello `openhands-critic-4b-v1.0`: il repository non ha un file
  LICENSE (quindi tutti i diritti riservati) e la scheda del modello non dichiara una
  licenza. Escluse su indicazione esplicita del proprietario. Si rivaluta se ricevono
  una licenza OSI.
- `docker-sbx-kit`: il kit è MIT ma richiede Docker Sandboxes di Docker Desktop, che non
  è FOSS (stessa preferenza del PRD §5); duplica anche 0019 §7.

Tutto il nuovo codice gira offline in `test-scripts.sh` §6c (tranne il gateway mock, in
`agent-practices.yml`); le mutazioni `OH ...` di `tests/mutation/catalog.tsv` provano che
ogni controllo sa fallire.

## Conseguenze
**Positive:**
- P0b ha i suoi golden task, con controlli che bocciano soluzioni sbagliate (provato).
- La catena `auto`, i suoi fallback e i callback si verificano in CI senza segreti (G1–G8).
- I due client chiedono conferma sui comandi distruttivi, con una misura e non un elenco
  scritto a sensazione; e la misura dice anche **quanto poco** generalizzano le glob.
- Le misure future (M1, M2, C1, S1, loop, compattazione) hanno già soglie scritte.

**Negative — da non minimizzare:**
- Codice nuovo da mantenere: circa 10 script e 10 task, che invecchiano quando cambiano
  i client (formato degli eventi di `opencode run --format json`, semantica delle
  `permission`, API dei callback di LiteLLM).
- Le regole glob danno un falso senso di sicurezza: 10 % di recall su varianti nuove.
- Le misure costano token (budget su `BENCH_KEY`) e nessuna è ancora stata fatta sul
  gateway vero: "adottato" vale per la struttura, non per un miglioramento dimostrato.
- 10 golden task nostri sono un campione, non un benchmark.

**Da rivedere se:** opencode cambia il formato degli eventi JSON o la semantica delle
`permission`; un analizzatore deterministico (porting di `defense_in_depth`) supera il
gate di `tests/risk-corpus/PREREG.md`; `critic-rubrics` riceve una licenza; le misure di
§1, §2, §6 sono fatte (aggiornare questo ADR con un successore, non modificarlo).
