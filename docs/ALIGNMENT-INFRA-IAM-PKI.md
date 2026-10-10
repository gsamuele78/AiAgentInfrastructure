# Allineamento con Infra-Iam-PKI — matrice degli standard

| | |
|---|---|
| **Stato** | Step 0 del [piano](PLAN-STACK-VALIDATION.md) · 2026-10-10 |
| **Decisione** | [ADR-0022](adr/0022-standard-condiviso-con-infra-iam-pki.md) |
| **Fonte** | [gsamuele78/Infra-Iam-PKI](https://github.com/gsamuele78/Infra-Iam-PKI) @ `23175ab` (Apache-2.0), clone read-only |
| **Da rileggere** | a ogni ADR di quel repo che tocchi agenti, CI o Dependabot |

## Come è stata fatta
Letti in Infra-Iam-PKI: `.ai/{project.yml,validate.sh,README.md}`, le tre skill
in `.agents/skills/`, `.claude/settings.json`, `.claude-plugin/` e
`.claude/lsp-plugin/`, `.mcp.json`, `opencode.json`, `.serena/project.yml`,
`.github/dependabot.yml`, `lint.yml`, `security-scan.yml`, `Makefile`,
`.editorconfig`, `.claudeignore`, `doc/plan/ALIGNMENT-PLAN.md`.
Verificato nel sorgente di `serena-agent` 1.7.0 (wheel da PyPI): i contesti
`ide`/`agent`/`claude-code` e il caricamento di `project.yml`.

Nota di contesto: Infra-Iam-PKI si è allineato a sua volta a un terzo repo
(`ALIGNMENT-PLAN.md` §2, riferimento `Proxmox_biome_log_collector` v0.3.1):
lo "standard" non nasce là. Quello che segue riguarda solo ciò che si vede in
Infra-Iam-PKI.

Legenda: ✅ adotta · 🔧 adatta · ⏳ rinvia (dove) · ❌ non adotta.

## Matrice
| # | Standard | Infra-Iam-PKI | Qui prima dello Step 0 | Decisione | Dove |
|---|---|---|---|---|---|
| 1 | Fonte unica del contesto agenti | `.ai/project.yml` → `generate.sh` genera `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.clinerules`, `.windsurfrules`, Copilot | `AGENTS.md` a mano, `CLAUDE.md` rimanda (ADR-0013) | ❌ generatore. Tutti i nostri client leggono già `AGENTS.md`; il generatore aggiunge una fonte e 6 file senza un lettore in più | ADR-0022 §1 |
| 2 | Validatore delle regole HC-01…14 | `.ai/validate.sh` | invarianti in `test-scripts.sh` | 🔧 le regole utili diventano controlli in `test-scripts.sh` con l'ID HC nel commento; **nessun secondo validatore**; `stack.py validate` (P3) le orchestra | ADR-0022 §2, tabella sotto |
| 3 | Skill di repo `.agents/skills/<n>/SKILL.md` | `compose-constraint-audit`, `sandbox-test`, `script-safety-review` | nessuna; formato già scelto da ADR-0019 | ⏳ `script-safety-review` confluisce nella skill `infra-change`, insieme ad `adr`; le altre due sono specifiche di quel repo (HC numerati, topologia Vagrant a 4 VM) | P4 |
| 4a | Serena: versione | `uvx --from serena-agent==1.7.0` | `uv tool install 'serena-agent@latest' --prerelease=allow` (opencode); `uvx --from git+…/serena` **HEAD non pinnato** (Codex) | ✅ pin esatto + `uvx`, in un posto che Dependabot legge | P1 |
| 4b | Serena: contesto opencode | `agent` | `ide` | 🔧 resta `ide`: `agent` espone 5 tool che duplicano quelli di opencode, fra cui `execute_shell_command`, che scavalca le `permission` (ADR-0019). Proposto a Infra-Iam-PKI di passare a `ide` | ADR-0022 §3 |
| 4c | Serena: Claude Code | `.mcp.json`, `--context claude-code`, `enabledMcpjsonServers` | non configurata (rilievo A14) | ✅ | P1 (porta il pin) |
| 4d | `.serena/project.yml` versionato | completo, `language_servers`, `ignored_paths`, `initial_prompt` | non versionato; l'installer ne scriveva uno di 2 righe **senza `language_servers`** | ✅ versionato, generato dal template 1.7.0; `initial_prompt` rimanda ad `AGENTS.md`. Installer corretto (rilievo A15) | **Step 0** |
| 5 | `.claude/settings.json` `permissions.deny` sui segreti | `.env*`, chiavi, cert, dati DB, backup | assente | ✅ adattato ai nostri path (`.env`, `master.key`, `forward.env`, `certs/`, `backups/`, `*.sql.gz`, `~/.config/litellm/`) | **Step 0** |
| 6 | Plugin LSP di Claude Code (`.claude-plugin/`) | bash, yaml (schema compose), dockerfile, marksman, pyright, R | assente | ❌ secondo tool nel layer "tooling codice", che è Serena (ADR-0006); richiede 5 language server sull'host | ADR-0022 §6 |
| 7 | `lsp` di opencode | stessi server | assente | ⏳ diagnostica dopo ogni modifica: valore plausibile ma da misurare (ADR-0021), con i server installati e pinnati | P4 |
| 8 | Dependabot | compose, docker, actions; immagini locali ignorate; gruppi; prefisso `deps`/`ci` | compose, docker, actions con **cooldown** (ADR-0020) | 🔧 si tiene il nostro (cooldown, `postgres` major ignorata, prefisso `chore` per la convenzione del repo); si aggiunge l'ignore dell'immagine costruita in locale e `pip`/`npm` su `stack/` | P1 |
| 9 | Actions pinnate a SHA (`@<sha> # vX.Y.Z`) | sì | tag mobili `@v4`, `@v5` | ✅ | P1 |
| 10 | `security-scan.yml`: gitleaks + Trivy | sì, Trivy immagini report-only | grep di pattern noti in `validate.yml` | ⏳ chiude in parte il debito #4; PR dedicata dopo P1 (immagini da pinnare prima) | dopo P1 |
| 11 | `lint.yml` (yamllint, hadolint, shellcheck bloccante, markdownlint) | sì | `validate.yml`: parse + shellcheck `-S error` | ⏳ hadolint e shellcheck più severo valgono la pena; markdownlint/yamllint no (costo/beneficio basso con un maintainer). Da valutare con P5 (pre-commit), stessi tool | P5 |
| 12 | `Makefile` come ingresso (`make lint && make validate`) | sì | `test-scripts.sh` + `devops-audit.sh` | ❌ l'ingresso unico previsto è `stack.py` (ADR-0017); un Makefile sarebbe il terzo | ADR-0022 §6 |
| 13 | Sandbox Vagrant a livelli (tier 0–3) | 4 VM libvirt | VM unica da `create-vm.sh` + snapshot (ADR-0011) | 🔧 l'idea dei **livelli** sì (il runbook procede per livelli con verifica), Vagrant no | [DEPLOY-RUNBOOK](DEPLOY-RUNBOOK.md) |
| 14 | `.editorconfig` | sì | assente | ✅ identico | **Step 0** |
| 15 | `.claudeignore` | sì, dichiarato **non letto** da Claude Code | assente | ❌ la copia applicata è `permissions.deny`; Serena usa `.gitignore` | ADR-0022 §6 |
| 16 | `copilot-instructions.md`, `.cursorrules`, `.clinerules`, `.windsurfrules`, `.aider.conf.yml` | generati | assenti | ❌ client non in uso (ADR-0006) | — |
| 17 | `doc/AI_AGENT_MANAGEMENT.md` | 27 righe: descrive `validate.sh`, `generate.sh` e le skill | ADR-0022 + questa matrice | ❌ descrive componenti che qui non si adottano | — |
| 18 | `.omo/**` ignorato | in `.serena/project.yml` e `.gitignore` (OmO provato là) | — | ✅ in `.gitignore` e `ignored_paths`; OmO resta esperimento isolato (ADR-0021) | **Step 0** |
| 19 | CHANGELOG + SemVer + tag + `release.yml` | sì (`v3.4.0`) | nessun tag, nessun changelog | ⏳ **domanda al maintainer**: per un repo infrastrutturale personale vale il costo? Utile se i due repo devono citarsi per versione | — |
| 20 | Commit `deps:` / `ci:` | sì | `<tipo>(<ambito>)` con `chore` | ❌ resta la convenzione di `AGENTS.md`; i tipi coincidono sul resto | — |

## Regole HC: corrispondenza con i controlli di questo repo
| HC | Regola in Infra-Iam-PKI | Qui | Dove |
|---|---|---|---|
| HC-01 | limiti `memory` e `cpus` su ogni container | ✅ portata; **eccezione dichiarata**: vLLM BIOME (va dimensionato sul server reale, un limite a caso lo uccide al caricamento del modello) | `test-scripts.sh` §4 |
| HC-02 | solo bind mount, nessun volume nominato | ❌ `pgdata` e `hf-cache` restano volumi: il backup è `pg_dump` (`backup-db.sh`, TC-05) e la VM ha gli snapshot. Un bind mount porta il problema dell'UID di postgres (là serve HC-10 per gestirlo) | — |
| HC-03 | `set -euo pipefail` | 🔧 `set -uo pipefail` obbligatorio, `-e` no: alcuni script lo tolgono apposta e controllano a mano (trappola nota) | `test-scripts.sh` §3 |
| HC-04 | password mai come argomento CLI | ⏳ nessuno script oggi passa password in CLI; il controllo nasce quando `stack.py` gestirà credenziali | P3 |
| HC-05 | postgres non esposto | ✅ c'era già | `test-scripts.sh` §4 |
| HC-06 | nessuna installazione di pacchetti a runtime | ⏳ violata da `biome-tls` (`apk add stunnel` all'avvio, solo profilo `biome`): da sistemare con un'immagine con stunnel o un Dockerfile | dopo P1 |
| HC-07 | niente `:latest` / tag mobili | ✅ è il cuore di P1 | P1 |
| HC-08 | `.env` mai tracciati | ✅ portata (anche chiavi, `master.key`, `forward.env`) | `test-scripts.sh` §3 |
| HC-09 | niente `docker.sock` montato | ✅ portata | `test-scripts.sh` §3 |
| HC-10 | deploy esce 1 se `chown` fallisce | — nessun `chown` nei nostri deploy | — |
| HC-11 | niente CDN esterne nei temi | — nessuna UI nostra | — |
| HC-12 | JSON solo con `jq` | 🔧 qui si usa Python stdlib (`json`), già la regola di fatto | — |
| HC-13 | `command -v` per i binari richiesti | 🔧 coperta da `need()` / raccolta dei prerequisiti mancanti (trappola "die sul primo"); nessun controllo generico | — |
| HC-14 | `trap` per i file temporanei | 🔧 usata dove serve (`test-scripts.sh` §4); nessun controllo generico | — |

Ogni controllo portato è nato con il suo test di mutazione (si rompe la cosa,
il controllo diventa rosso): esito nella PR dello Step 0.

## Rilievi nuovi emersi dallo Step 0
| ID | Rilievo | Evidenza | Gravità | Stato |
|---|---|---|---|---|
| A15 | L'installer scriveva un `.serena/project.yml` senza `language_servers`: con `serena-agent` 1.7.0 il progetto **non si carica** (`KeyError: 'language_servers'`); conteneva anche `record_tool_usage_stats`, chiave che 1.7.0 non conosce | `ProjectConfig._from_dict`, `FIELDS_WITHOUT_DEFAULTS`; riprodotto caricando il file con Serena 1.7.0 | **alta** (Serena inutilizzabile nei progetti configurati dall'installer) | ✅ Step 0 |
| A16 | `deploy-all.sh` fase 6 decideva sulla GPU con `command -v nvidia-smi`: la trappola già nota, rimasta in uno script che il controllo non copriva | `deploy-all.sh` | media (su Bazzite senza driver salta la fase 6 in silenzio) | ✅ Step 0 |
| A17 | La fase 8 dice di lanciare `./backup-db.sh` nella VM, ma lo script non viene mai copiato lì (si copia solo `services/`) | `deploy-all.sh`, `INSTALL_GUIDE.md` | media (il primo backup fallisce) | ✅ Step 0 (istruzione corretta) |
| A18 | vLLM e nginx BIOME senza limiti di risorse (HC-01) | `services-biome/docker-compose.yml` | media (server condiviso con i workload di ricerca) | nginx ✅; vLLM eccezione dichiarata |
| A19 | `biome-tls` installa stunnel all'avvio (HC-06) e usa `alpine:3.20`, fuori supporto da aprile 2026 | `services/docker-compose.yml` | bassa (solo profilo `biome`) | tag in P1; HC-06 dopo P1 |
