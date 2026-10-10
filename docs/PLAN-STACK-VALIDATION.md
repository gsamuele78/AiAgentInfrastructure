# PLAN — Stack validato, idempotente, misurato e auto-aggiornabile

| | |
|---|---|
| **Stato** | in corso · aggiornato 2026-10-10: P0 e Step 0 uniti (#8), P1 unito (#9, 19/25 pin tracciati, gate ✘ dichiarato), parte Ollama di P2/P3 unita (#10, ADR-0023). Restano P0b (serve il deploy), P2, P3 e oltre |
| **ADR** | [0017](adr/0017-manifest-componenti-e-validatore-unico.md) manifest + validatore · [0018](adr/0018-installazione-idempotente-e-rollback-debian-bazzite.md) install/rollback Debian 13 + Bazzite · [0019](adr/0019-pratiche-openhands-skill-per-ruolo-e-serena.md) pratiche OpenHands, skill, Serena · [0020](adr/0020-dependabot-e-scala-di-autoaggiornamento.md) Dependabot · [0021](adr/0021-misurare-prima-di-adottare-e-oh-my-openagent.md) protocollo di misura, oh-my-openagent |
| **Fatto** | P0: fix Serena, `dependabot.yml`, ADR 0017–0021 · P1: pin leggibili da Dependabot, `FROM` a digest · ADR-0023: LLM locale con rollback |
| **Step 0** | allineamento con Infra-Iam-PKI: [matrice](ALIGNMENT-INFRA-IAM-PKI.md), [ADR-0022](adr/0022-standard-condiviso-con-infra-iam-pki.md); [runbook del primo deploy](DEPLOY-RUNBOOK.md) |

Richiesta di partenza: integrare Serena e le skill in modo fluido, ispirarsi
alle pratiche di OpenHands, avere un validatore che verifichi ogni componente
(skill comprese) per i ruoli software design / sviluppo / system engineering /
PRD; installazione e validazione idempotenti, con rollback, su Debian 13 e
Bazzite, decise in base all'hardware rilevato; Dependabot per
l'autoaggiornamento; valutare oh-my-openagent; misurare il guadagno di ogni
passo.

---

## 0. Prima di cominciare

### Informazioni mancanti (cambiano il piano se la risposta è diversa)
1. **Variante di Bazzite** (desktop, `-nvidia`, `-deck`, GNOME/KDE): decide se il
   driver NVIDIA è già nell'immagine o serve un rebase. *Risposta 2026-10-10:*
   Bazzite 44, KDE (Kinoite), `VARIANT_ID=bazzite-dx-nvidia`: driver
   nell'immagine. È la fixture `tests/platform/fixtures/os-release.bazzite-nvidia`.
2. **Debian 13 è l'host o solo la VM?** Oggi la VM è Debian per costruzione;
   l'host di riferimento del PRD è il laptop. Il piano assume **entrambi gli
   host possibili**.
3. **Budget token per eval e benchmark** (L6, ADR-0021): ordine di grandezza
   mensile accettabile.
4. **Variante Claude Code in uso** (A/B/C di `DUAL-AUTH.md`): cambia cosa
   `stack.py` può riscrivere in `~/.claude/`.
5. È disponibile **una macchina Bazzite reale o una VM** per i test S1? Senza,
   il supporto Bazzite resta dichiarato solo per gli strati S3/S4.

### Assunzioni
- Un solo maintainer, vincolo **< 30 min/mese** invariato: tutto ciò che segue
  deve abbassare il tempo di manutenzione nel medio periodo, non alzarlo.
- Python ≥ 3.11 disponibile su entrambi gli host (`tomllib` in stdlib).
- Il runner self-hosted (`functional.yml`) esiste o verrà registrato
  (`GITHUB-SETUP.md` §4); senza, L5/L6 restano manuali.
- Nessun cambio ai non-goal del PRD: niente multi-tenancy, niente HA, niente CD
  (lo stadio 3 di ADR-0020 richiederebbe un nuovo ADR esplicito).

---

## Fase A — Audit / Assessment

Stato reale verificato **leggendo il sorgente** dei componenti (Serena, opencode,
mattpocock/skills, oh-my-openagent, Dependabot schema), non la documentazione.

| ID | Rilievo | Evidenza | Gravità | Dove si risolve |
|---|---|---|---|---|
| A1 | `--context ide-assistant` deprecato, Serena lo rimappa **in silenzio** su `claude-code` (contesto sbagliato per opencode) | `serena/config/context_mode.py`, `legacy_name_mapping` | alta | **P0 ✅** |
| A2 | Memoria di Serena esclusa a metà: mancavano `rename_memory`, `edit_memory`, `onboarding` → violazione ADR-0007 | `serena/tools/memory_tools.py`, `workflow_tools.py` | alta | **P0 ✅** |
| A3 | opencode carica **sia** `.claude/skills` **sia** `.agents/skills`: una skill in entrambe = duplicata in context | `opencode/src/skill/index.ts` | media | P4 |
| A4 | mattpocock installato per intero (incl. `in-progress/*`), senza pin | `stack-selective-install.sh` | media | P4 |
| A5 | Collisione `code-review` (mattpocock) con la skill integrata di Claude Code | elenco skill | media | P4 |
| A6 | Versioni non pinnate: immagine LiteLLM `main-stable`, `headroom-ai`, `serena-agent@latest --prerelease`, MCP via `npx -y` senza versione | Dockerfile, client | **alta** (supply chain) | **P1 ✅** |
| A7 | Dependabot non può leggere `FROM ${ARG}` né `${VLLM_TAG:-latest}` | Dockerfile, compose BIOME | media | **P1 ✅** |
| A8 | `bak()` crea un `.bak` a ogni run (non idempotente) e calcola il timestamp due volte | `stack-selective-install.sh` | bassa | P3 |
| A9 | Fatti hw/OS solo come testo: nessuno script può decidere sulla base di `detect-hardware.sh` | `detect-hardware.sh` | media | P2 |
| A10 | Node.js di Debian 13 è il 20.x, **EOL upstream da aprile 2026** | archivio Debian | media | P2 |
| A11 | Bazzite mai provato end-to-end; S1 (rpm-ostree) non testabile su runner GitHub | — | alta (rischio) | P2 + Fase C |
| A12 | Nessuna misura di comportamento degli agenti né del guadagno dei cambiamenti | `TEST-PLAN.md` | alta | P0b, P6 |
| A13 | oh-my-openagent: licenza SUL (non OSI), `anthropic-subscription`, fallback/memoria/MCP propri, telemetria attiva di default, 226 commit/60 gg | sorgente v5.1.29 | — | P7 (esperimento) |
| A14 | Serena configurata solo per opencode, non per Claude Code | `clients/` | bassa | P1 (`.mcp.json`, ADR-0022) |
| A15–A19 | Emersi dallo Step 0 (Serena `project.yml` senza `language_servers`, GPU da `nvidia-smi` in `deploy-all.sh`, `backup-db.sh` mai copiato nella VM, HC-01/HC-06 su BIOME) | [`ALIGNMENT-INFRA-IAM-PKI.md`](ALIGNMENT-INFRA-IAM-PKI.md) | fino ad alta | Step 0 / P1 |

**Pre-requisiti** prima di P1: la PR #4 (catena `auto`, ADR-0016) unita ✅; il
gateway deployato almeno una volta (debito #6), altrimenti le baseline di P0b
non hanno una catena reale su cui misurare. Il deploy si fa con
[`DEPLOY-RUNBOOK.md`](DEPLOY-RUNBOOK.md): la sua scheda è la prima riga del registro.
P1 non dipende dal deploy (sono pin, solo testo) e può procedere in parallelo;
P0b sì.

---

## Fase B — Development / Implementation

Ogni pacchetto ha la stessa struttura. La riga **Misura** applica il protocollo
di ADR-0021: metrica, baseline, obiettivo **pre-registrato**. Un pacchetto è
"fatto" solo se l'obiettivo è raggiunto o il mancato raggiungimento è scritto.

### P0 — Correzioni immediate e governance *(questa PR)*
- **Deliverable**: contesto Serena `ide` + 7 tool di memoria esclusi + controllo
  in `test-scripts.sh`; `.github/dependabot.yml` (Actions, compose, Dockerfile);
  ADR 0017–0021; questo piano.
- **Accettazione**: `test-scripts.sh` verde; test di mutazione (si rimuove un
  tool dall'esclusione → rosso); `dependabot.yml` valido contro lo schema
  SchemaStore.
- **Misura**: n. di tool di memoria Serena esposti all'agente — baseline 3 (i
  nuovi non esclusi) → obiettivo 0.
- **Rollback**: `git revert`.

### P0b — Baseline di misura *(prima di qualunque altro cambiamento)*
- **Deliverable**: `bench/tasks/` con 8 golden task (2 per ruolo), verifica
  **deterministica** di ciascuno; `stack.py bench` (o, prima di P3, uno script
  `scripts/bench.sh`) che esegue `opencode run` e raccoglie i numeri da
  `/spend/logs`; prima riga del **registro baseline** (sotto).
- **Accettazione**: ogni golden task ha un controllo che fallisce se
  l'artefatto è sbagliato (test di mutazione sul controllo).
- **Misura**: è la baseline stessa — task risolti, $/task risolto, token
  input/cached/output, latenza mediana, quota locale.
- **Rischio**: costo token; limitato da virtual key con budget.

### P1 — Pin e manifest leggibili da Dependabot *(ADR-0017, 0020)*
- **Deliverable**: `stack/components.toml` (schema di ADR-0017);
  `stack/requirements-tools.txt` (serena-agent, graphifyy, headroom-ai pinnati);
  `stack/package.json` (MCP Node pinnati, `npx` senza `-y` su versioni mobili);
  `services/Dockerfile` con `FROM` letterale + digest (chiude il debito #1);
  `dependabot.yml` esteso a `pip` e `npm` su `stack/`.
- **Accettazione**: nessun `@latest`, `-y` senza versione o tag mobile nei file
  versionati (nuovo controllo in `test-scripts.sh` §3); Dependabot apre la
  prima PR su `stack/`.
- **Misura**: % di componenti con versione pinnata e tracciata da un bot —
  baseline ≈ 20% (solo Actions/compose) → obiettivo ≥ 90%.
- **Rollback**: `git revert`; i pin sono solo testo.
- **Stato (PR P1)**: fatto, con due scostamenti dichiarati.
  1. `components.toml` **non** ha il campo `version` di ADR-0017: la versione
     vive solo nel file che Dependabot legge (`pin`), altrimenti sarebbero due
     verità. ADR-0017 è *Proposed*: lo scostamento va recepito quando la si
     accetta con P3.
  2. Obiettivo ≥ 90% **non raggiunto**: 19/25 (76%). I 6 non tracciati hanno
     un motivo scritto in `components.toml`: commit di mattpocock (P4), opencode,
     Ollama e runtime Node (installer upstream, P2), headroom sull'host
     (installato a mano, ADR-0014), fetch-mcp (build da git).
  `headroom-ai` sull'host non è in `requirements-tools.txt`: nessuno script lo
  installa, un pin che nessuno usa sarebbe falso.

### P2 — Fatti hw/OS e primitive di piattaforma *(ADR-0018)*
- **Anticipato per il solo LLM locale** (ADR-0023): `scripts/lib/llm-plan.sh`
  (tabella hw → modelli del gateway) e `scripts/lib/journal.sh` (registro +
  rollback di ADR-0018) esistono già; `stack.py` dovrà assorbirli, non affiancarli.
- **Deliverable**: `detect-hardware.sh --json` (os_family, atomic, ublue,
  sandbox, GPU vendor/VRAM/driver, RAM, chassis, KVM, spazio su `/var`);
  `scripts/lib/platform.sh` con primitive per strato (`pkg_present`,
  `pkg_add`, `svc_render`, `tool_pin`) per `debian` e `atomic`; scelta del
  gestore di runtime (mise vs brew) con il protocollo ADR-0021; tabella
  decisionale fatti → scelte.
- **Accettazione**: fixture `os-release` per Debian 13, Bazzite,
  Bazzite-nvidia, Flatpak (la libreria legge già `OS_RELEASE_FILE`, quindi è
  testabile in CI); le decisioni S1 producono solo raccomandazioni.
- **Misura**: decisioni corrette sulle fixture — obiettivo 100%; tempo di
  `facts` < 2 s (`hyperfine`, mediana di 10).
- **Stato (P2a)**: fatti (`detect-hardware.sh --json`), `scripts/lib/platform.sh`
  (`platform_decide`, `pkg_present`, `pkg_add`, `svc_render`, `tool_pin`),
  fixture + TC-13, job CI `os-matrix` su `debian:13` e `fedora:44`.
  **Stato (P2b)**: misura fatta (`bench/install-methods/`, workflow
  `bench-install`): baseline, mise, brew, nix, distrobox contro soglie
  pre-registrate. Esito in [ADR-0024](adr/0024-mise-per-gli-strumenti-utente-misurato.md):
  **mise** (pin esatti, rollback 0,02 s su Debian 13/Fedora/Ubuntu); brew e nix
  esclusi per i pin, distrobox per il tempo di rollback (72 s) e la `$HOME`
  condivisa. ADR-0024 accettato (mise primario, script di ripiego); adozione in
  `scripts/install-user-tools.sh` con i pin di Node e opencode in `stack/`.

### P3 — `stack.py`: plan / install / validate / rollback *(ADR-0017, 0018)*
- **Deliverable**: `scripts/stack.py` (stdlib), journal in
  `~/.local/state/aiagentinfra/runs/`, render con confronto sha256 (niente più
  `.bak` sparsi), snapshot VM prima delle azioni sulla VM, rollback per run-id;
  `stack-selective-install.sh` → wrapper deprecato.
- **Accettazione**: TC-10, TC-11, TC-12 verdi (Fase C); `plan` = vecchio
  `--dry-run` (invariante #9 rispettata).
- **Misura** (baseline = script attuali):

  | Metrica | Baseline | Obiettivo |
  |---|---|---|
  | cambiamenti al 2° run identico | ≥ 3 (un `.bak` per config) | **0** |
  | tempo di rollback di un run S4 | manuale, non misurato | < 30 s |
  | durata `validate` livelli 0–4 | somma dei 4 script | ≤ +10% (orchestrare non deve costare) |
  | rilievi di drift come A1/A2 intercettati | 0 di 2 | 2 di 2 (test con le versioni vecchie) |

### P4 — Skill per ruolo e Serena per client *(ADR-0019)*
- **Deliverable**: `.agents/skills/` canonica con allowlist pinnata a commit;
  symlink per Claude Code; lettura `.claude/` disattivata in opencode; skill di
  repo `adr` e `infra-change`; Serena in Claude Code (`--context claude-code`);
  controllo "nomi di skill unici, incluse le integrate".
- **Accettazione**: TC-14 verde; nessun duplicato fra le sorgenti di skill.
- **Misura**: token del prompt di sistema a inizio sessione (descrizioni skill
  in context) — baseline: repo mattpocock intero → obiettivo −40% o meglio a
  parità di skill utili; task risolti sui golden task di design/PRD ≥ baseline
  P0b (guardia: nessun peggioramento).

### P5 — Guardrail (ConfirmRisky) e pre-commit *(ADR-0019)*
- **Deliverable**: `permission` di opencode e `permissions` di Claude Code su
  `ask` per i comandi distruttivi; `.pre-commit-config.yaml` (shellcheck,
  parse, sottoinsieme veloce di `test-scripts.sh`); ecosistema `pre-commit` in
  Dependabot.
- **Accettazione**: un golden task "distruttivo" si ferma alla conferma.
- **Misura**: durata del pre-commit — obiettivo < 10 s (mediana); difetti
  intercettati prima della CI (conteggio su 4 settimane) vs CI rossa per
  sintassi/lint nello stesso periodo.

### P6 — Livello 6: eval come critic *(ADR-0019, 0021)*
- **Deliverable**: i golden task di P0b in `functional.yml` (settimanale,
  self-hosted, mai su `pull_request`), report JSON come artefatto, soglia di
  regressione.
- **Accettazione**: un peggioramento oltre soglia rende il run rosso.
- **Misura**: tasso di flakiness delle eval — obiettivo < 5% (rerun dello stesso
  commit); costo mensile entro il budget del punto 0.3.

### P7 — Esperimento oh-my-openagent *(ADR-0021)*
- **Deliverable**: profilo opencode isolato con OmO pinnato, telemetria spenta,
  solo provider gateway; confronto A/B con opencode `--pure`; ADR di esito.
- **Accettazione**: protocollo rispettato (pre-registrazione, ≥5 run per
  task, ABBA).
- **Misura** (pre-registrata in ADR-0021): +15 pp di task risolti **e** costo per
  task risolto ≤ +10%. Esito atteso dichiarato prima: anche se passa, si
  importano le idee e non il plugin, finché la licenza resta SUL.

### P8 — Scala di autoaggiornamento *(ADR-0020)*
- **Deliverable**: nessun codice finché i criteri non sono misurati; poi un ADR
  per stadio.
- **Misura**: settimane consecutive di `functional.yml` verde; revert di
  aggiornamenti; MTTR di un aggiornamento rotto (rollback snapshot).

### Ordine e dipendenze
```
P0 ─► P0b ─► P1 ─► P2 ─► P3 ─► P4 ─► P5 ─► P6 ─► P7
                                   └────────────► P8 (solo a criteri soddisfatti)
```
Stima onesta: P1–P6 sono **giorni di lavoro**, non ore, distribuiti su più PR
(una per pacchetto). Dopo P3 il tempo di manutenzione mensile dovrebbe scendere
(drift visibili, rollback in un comando); prima, sale. Se dopo P3 la misura non
lo conferma, P4–P8 si fermano.

---

## Fase C — Testing / Validation

### Livelli (estende `TEST-PLAN.md`)
| Livello | Cosa | Dove gira | Bloccante |
|---|---|---|---|
| L0 | fatti hw/OS + decisioni (fixture) | runner GitHub | sì |
| L1–L2 | statico, build, schema `dependabot.yml` | runner GitHub | sì |
| L3 | config dei client vs manifest | host | sì per `stack.py validate` |
| L4 | best practice deploy | host | sì |
| L5 | catena reale, TC-01/TC-09 | self-hosted | sì (ADR-0015) |
| L6 | eval golden task, benchmark | self-hosted, settimanale | regressione oltre soglia |

### Nuovi casi di test
| TC | Verifica | Criterio di superamento |
|---|---|---|
| TC-10 | **Idempotenza**: `stack.py install` due volte | 2° run: 0 file scritti, 0 pacchetti, journal vuoto |
| TC-11 | **Rollback config**: install → modifica → `rollback <run-id>` | sha256 di ogni file = stato pre-run |
| TC-12 | **Rollback tool**: pin N → N+1 → rollback | `--version` = N, `validate` verde |
| TC-13 | **Decisioni da hw/OS** su fixture (Debian 13, Bazzite, Bazzite-nvidia, Flatpak, senza GPU, laptop) | 100% delle decisioni attese; nessuna azione S1 automatica |
| TC-14 | **Skill**: frontmatter valido, nomi unici fra tutte le sorgenti e le integrate, allowlist rispettata | 0 duplicati, 0 collisioni |
| TC-15 | **Eval L6** | task risolti ≥ baseline − soglia pre-registrata |
| TC-16 | **Drift di versione**: probe contro versioni vecchie note (es. Serena con `ide-assistant`) | il probe diventa rosso |
| TC-17 | **Upgrade con rollback automatico della VM** (stadio 3 futuro) | validate rossa → VM tornata allo snapshot, gateway vivo |

Ogni probe e ogni controllo nasce con il suo **test di mutazione** (si rompe la
cosa, il test deve diventare rosso), come già fatto per la catena `auto`.

### Matrice OS
| Strato | Debian 13 | Bazzite |
|---|---|---|
| S3/S4 (tool, config) | container `debian:13` su runner GitHub | container Fedora su runner GitHub (stesso codice di S3/S4) |
| S2 (servizi host) | VM Debian 13 via cloud-init (self-hosted) | VM Bazzite sul self-hosted **se disponibile**, altrimenti prova manuale registrata |
| S1 (pacchetti, driver) | VM Debian 13 (self-hosted) | **solo manuale** su hardware/VM reale, registrata sotto |

### Criteri di uscita
- TC-10…TC-14 verdi su Debian 13 e (per S3/S4) su Fedora; TC-16 verde.
- Almeno **un** run S1 su Bazzite reale registrato, o il README dichiara il
  supporto Bazzite limitato a S2–S4.
- Ogni pacchetto con la sua riga di misura compilata nel registro.
- `devops-audit.sh` senza regressioni; manutenzione mensile misurata nel
  mese successivo a P3.

### Registro baseline e misure (compilare)
| Data | Pacchetto | Metrica | Baseline | Risultato | Run (n) | Esito gate |
|---|---|---|---|---|---|---|
| 2026-10-10 | Step 0 | tool di Serena che duplicano quelli di opencode (statico, dal sorgente 1.7.0) | `agent`: 5 (~750 token di descrizioni/turno, incl. una shell fuori dalle `permission`) | `ide`: 0 | statico | contesto `ide` confermato (ADR-0022) |
| 2026-10-10 | Step 0 | regole HC di Infra-Iam-PKI coperte da un controllo con mutazione | 1 di 14 (HC-05) | 5 di 14 (HC-01, 03, 05, 08, 09); 2 non applicabili (10, 11); 3 adattate senza controllo generico (12–14); 3 rinviate (04, 06, 07); 1 respinta con motivo (02) | 10 mutazioni | ✔ |
| 2026-10-10 | Step 0 | progetti in cui l'installer lascia un `.serena/project.yml` caricabile da Serena 1.7.0 | 0 (KeyError `language_servers`) | 1 di 1 provato (+ 2° run senza scritture) | 1 | ✔ |
| 2026-10-10 | P1 | componenti con pin letto da Dependabot (`stack/components.toml`, stessi 25 prima e dopo) | 5/25 (20%) | 19/25 (76%) | statico | ✘ obiettivo ≥ 90% non raggiunto: 6 rinviati a P2/P4 con motivo |
| 2026-10-10 | P1 | controlli sui pin con test di mutazione | 0 | 3 controlli, 15 mutazioni rosse | 15 | ✔ |
| 2026-10-10 | P2/P3 (solo LLM locale, ADR-0023) | decisioni hw corrette su profili (laptop PRD, 4+12, 4+8, 8, 24, L40S, CPU 16/8, GPU 2 GB, disco 3/6) | 2 tabelle divergenti; con ≥ 20 GB `auto` senza modello | 11/11 attese, 1 tabella | statico | ✔ |
| 2026-10-10 | P3 (solo LLM locale) | cambiamenti al 2° run identico (TC-10) | non misurato (nessun registro) | 0 (registro vuoto, rimosso) | sistema finto | ✔ (da confermare sull'host) |
| 2026-10-10 | P3 (solo LLM locale) | rollback riporta lo stato pre-run (TC-11) | non disponibile | binario, unit, override, firewall, modelli: tutti ripristinati; preesistenti intatti | sistema finto | ✔ (da confermare sull'host) |
| | | | | | | |

### Registro prove Bazzite S1 (compilare)
| Data | Variante Bazzite | Esito install | Esito rollback (`rpm-ostree rollback`) | Note |
|---|---|---|---|---|
| | | | | |
