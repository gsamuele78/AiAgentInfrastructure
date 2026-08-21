# DevOps best practices — assessment onesto

Verifica automatica: `scripts/devops-audit.sh`. Qui il quadro e **cosa manca**.

> **Stato reale: lo stack non è mai stato deployato.** Il gateway non è mai
> stato avviato, quindi ogni ✅ qui sotto significa «il repo lo prevede e la
> verifica statica lo conferma», mai «l'ho visto funzionare». Le righe che
> riguardano l'esercizio (restore testato, metriche, CI funzionale) sono
> marcate di conseguenza. Un audit che confonde le due cose è esattamente il
> tipo di documento che questo file esiste per evitare.

| Area | Stato | Note |
|---|---|---|
| IaC / config dichiarative | ✅ | compose, YAML, unit file, tutti in repo |
| Build riproducibile | ⚠️ | Dockerfile + gate `import HeadroomCallback`. **La build non è mai passata in CI** fino al 2026-08-21: l'immagine upstream (Wolfi + venv `uv`) non ha `pip`. Corretto; da confermare col primo run verde. Nessuna immagine è mai stata costruita né deployata. |
| Pin versioni | ⚠️ | `main-stable` è mobile → **pinna un digest sha256** |
| Config immutabile | ✅ | `litellm_config.yaml:ro` |
| Segreti fuori dai config | ✅ | solo `os.environ/` |
| Permessi ristretti | ✅ | `.env` 600 |
| Rotazione segreti | ⚠️ | manuale; le vecchie credenziali erano esposte → **ruotale** |
| Secret manager | ❌ | scelta: sproporzionato per single-host |
| Least privilege | ✅ | postgres non esposto, `no-new-privileges`, NAT |
| Container non-root | ⚠️ | limite dell'immagine upstream |
| Healthcheck / restart / limiti | ✅ | entrambi i servizi |
| Log rotation | ✅ | driver `local`, 15m × 5 |
| Metriche | ⚠️ | Prometheus disponibile, non attivo |
| Alerting | ❌ | **debito reale** se il gateway diventa critico |
| Backup DB | ✅ | `backup-db.sh` + retention 14 |
| **Restore testato** | ❌ | `restore-test.sh` esiste e la modalità locale era rotta (compose cercato nella cwd) — corretta. Non eseguibile finché non c'è un DB: **non c'è ancora nulla da restorare**. |
| Snapshot VM | ✅ | `virsh snapshot-create-as` |
| ADR / decisioni | ✅ | `docs/adr/` 13 ADR, con superseded (0002→0003, 0007→0013) |
| PRD / requisiti | ✅ | `docs/PRD.md` |
| Test plan | ✅ | `docs/TEST-PLAN.md` |
| CI | ⚠️ | `validate.yml` + `functional.yml`. `functional` ha `continue-on-error: true` sul job: **i test L5 non possono far fallire nulla** (ADR-0010 lo motiva col laptop spento, ma è un limite reale, non un dettaglio). |
| CD | ❌ | **per scelta** (ADR-0010) |
| Scan CVE immagini | ⚠️ | non implementato |

## Debito riconosciuto (priorità)
1. **Immagine su tag mobile** → pinna `main-stable@sha256:...`
   (digest misurato il 2026-08-21: `sha256:4b3226f4ccd7793d7dca6862d3681604d7ab640d8d6285be6061fd48514e6e71`;
   richiede `FROM ...@sha256:` invece di `:${TAG}`)
2. **Nessun alerting** → minimo utile: `callbacks: ["prometheus"]` + scrape
3. **Rotazione credenziali** → le vecchie erano in un file 664: rigenerale.
   **Non risulta fatto**: nessuna traccia nel repo.
4. **Nessuno scan CVE** → valuta `trivy` nella CI
5. **Nessun deploy** → il primo `create-vm.sh` + `docker compose up -d` è anche
   il primo test reale di tutta la catena. Aspettati che qualcosa non torni: i
   test statici coprono i contratti, non l'esercizio.
6. **`sync_openrouter.py` non esiste** → ADR-0004 decide la riconciliazione dei
   modelli via `/model/new` + `/model/delete`, ma lo script non è mai stato
   scritto. F8 del PRD non è implementato e il suo test (TEST-PLAN) non è
   eseguibile. Oggi vale solo il wildcard `openrouter/*`, con i limiti che
   l'ADR stesso elenca (dropdown vuoto, niente pricing).
7. ~~Lane locale (F5) e BIOME (F6) fuori dal config versionato~~ → **chiuso**:
   `local-fast`, `local-good` e `biome-coder` sono in
   `services/litellm_config.yaml`. Restano le uniche lane che dipendono da
   servizi fuori dalla VM (Ollama sull'host, BIOME dietro VPN): se non ci sono,
   rispondono errore.
8. **Test funzionali non bloccanti** → `functional.yml` ha
   `continue-on-error: true` sul job: TC-01, TC-02, TC-04 e TC-05 girano ma non
   possono fallire. Cambiarlo tocca una conseguenza dichiarata in ADR-0010 →
   serve un nuovo ADR, non una modifica al volo.

## Non implementato *per scelta* (non è debito)
Secret manager (Vault/SOPS) · CD automatico · HA/replica · container non-root
(dipende dall'upstream). Motivazioni in `PRD.md` §3 e `adr/0010`.

## Manutenzione
```bash
./scripts/devops-audit.sh        # prima di ogni deploy
./scripts/audit-integration.py   # dopo ogni modifica ai config
./scripts/backup-db.sh           # settimanale
./scripts/restore-test.sh        # a ogni cambio di schema
virsh snapshot-create-as llm-vm pre-upgrade   # prima degli aggiornamenti
```
