# 0022 — Standard condiviso con Infra-Iam-PKI: cosa si adotta, cosa no, chi possiede i controlli

- **Status**: Accepted
- **Data**: 2026-10-10
- **Relazione**: applica 0006 (un tool per layer), 0013 (AGENTS.md memoria di
  progetto), 0017 (validatore unico), 0019 (skill e Serena), 0020 (Dependabot).
  Non supersede nulla. Matrice completa: [`ALIGNMENT-INFRA-IAM-PKI.md`](../ALIGNMENT-INFRA-IAM-PKI.md).

## Contesto
Lo stesso maintainer gestisce
[Infra-Iam-PKI](https://github.com/gsamuele78/Infra-Iam-PKI) (Apache-2.0), che
nel 2026-10 si è allineato a un proprio repo di riferimento
(`doc/plan/ALIGNMENT-PLAN.md` di quel repo, fasi 0–7) e ha accumulato standard
per gli agenti AI e per la CI. Obiettivo: che i due repo seguano **la stessa
configurazione standard dove ha senso**, così il maintainer non deve ricordare
due modi di fare la stessa cosa.

Tre conflitti emergono subito leggendo i file (commit `23175ab` di Infra-Iam-PKI):

1. **Memoria di progetto.** Là la fonte unica è `.ai/project.yml`, e
   `.ai/generate.sh` *genera* `CLAUDE.md`, `AGENTS.md`, `.cursorrules`,
   `.clinerules`, `.windsurfrules`, `copilot-instructions.md`. Qui ADR-0013 dice
   che la memoria di progetto è `AGENTS.md` scritto a mano, e `CLAUDE.md` vi
   rimanda soltanto.
2. **Validatore.** Là `.ai/validate.sh` verifica 14 regole (HC-01…HC-14). Qui le
   invarianti stanno in `scripts/test-scripts.sh`, e ADR-0017 prevede che
   `stack.py validate` *orchestri* gli script esistenti. Adottare `validate.sh`
   così com'è darebbe **due validatori** con due elenchi di regole.
3. **Serena per opencode.** Là `--context agent`, qui `--context ide`.
   Verificato nel sorgente di `serena-agent` 1.7.0
   (`serena/resources/config/contexts/`):

   | Contesto | Tool esclusi | Modalità |
   |---|---|---|
   | `ide` | `create_text_file`, `read_file`, `execute_shell_command`, `find_file`, `list_dir` | progetto singolo |
   | `agent` | solo `initial_instructions` | multi-progetto |
   | `claude-code` | come `ide` + `search_for_pattern` | progetto singolo |

   Con `agent`, opencode riceve **cinque tool che duplicano i suoi** (circa 750
   token di sole descrizioni, stimati dai docstring, a ogni turno), e fra
   questi `execute_shell_command`: una shell che **non passa dalle
   `permission` di opencode**, cioè scavalca il guardrail ConfirmRisky di
   ADR-0019.

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Adottare tutto lo standard di Infra-Iam-PKI | un solo modo di fare le cose | `.ai/generate.sh` contraddice ADR-0013; genera file per client che qui non si usano (Cursor, Cline, Windsurf, Copilot: ADR-0006); `validate.sh` duplica `test-scripts.sh`; `--context agent` scavalca le `permission` |
| Ignorare Infra-Iam-PKI | zero lavoro | due standard da ricordare per la stessa persona; si riscopre da capo ciò che là è già risolto (pin di Serena, `permissions.deny`, SHA delle Actions) |
| **Adottare per componente, con la regola "un proprietario per ogni controllo"** | si prende ciò che regge, si scrive perché il resto no | la matrice va riletta quando uno dei due repo cambia |

## Decisione
1. **Memoria: resta ADR-0013.** `AGENTS.md` è scritto a mano ed è la fonte; il
   generatore `.ai/` **non** si adotta. I client che usiamo (opencode, Claude
   Code via `CLAUDE.md`, Codex) leggono già `AGENTS.md`: un generatore
   aggiungerebbe una fonte (`project.yml`) e sei file derivati senza un lettore
   in più. Se un giorno servisse un client che legge solo un suo formato, si
   scrive un symlink o un rimando di una riga, come `CLAUDE.md`, non un generatore.
2. **Controlli: un solo proprietario, `scripts/test-scripts.sh`.** Le regole HC
   di Infra-Iam-PKI che valgono anche qui si **portano come controlli** in
   `test-scripts.sh`, ciascuna col suo test di mutazione e con l'ID HC citato nel
   commento, così la corrispondenza fra i due repo resta cercabile.
   `stack.py validate` (ADR-0017) lo **chiama**, non lo riscrive. Nessun
   `validate.sh` qui. La mappatura HC → controllo sta nella matrice.
3. **Serena: versione pinnata, contesto per client.**
   - Si adotta il pin esatto (`serena-agent==X.Y.Z`) e l'avvio via `uvx`, al
     posto di `uv tool install serena-agent@latest --prerelease=allow`.
     Implementazione nel pacchetto P1 del piano.
   - Il contesto **non** si uniforma su `agent`: `ide` per opencode,
     `claude-code` per Claude Code, `codex` per Codex. A Infra-Iam-PKI si
     propone di passare a `ide` per opencode (fuori dallo scope di questo repo:
     è una raccomandazione, non una modifica).
   - `.serena/project.yml` versionato nel repo come là (language server,
     `ignored_paths`, `initial_prompt` che **rimanda** ad `AGENTS.md` senza
     duplicarne il contenuto), con i 7 tool di memoria esclusi.
4. **Si adottano così come sono:** `.claude/settings.json` di progetto con
   `permissions.deny` sui segreti; `.editorconfig`; Actions pinnate a SHA con il
   tag in commento; `.omo/` in `.gitignore`; il formato `.agents/skills/<nome>/SKILL.md`
   (già scelto da ADR-0019).
5. **Si rinviano a un pacchetto del piano, con l'ADR o la misura che serve:**
   skill di repo (P4, adattando `script-safety-review` dentro `infra-change`);
   scansione gitleaks + Trivy (chiude in parte il debito #4, PR dedicata dopo P1);
   configurazione LSP di opencode (P4, misurata con ADR-0021).
6. **Non si adottano:** il generatore `.ai/` e i file derivati
   (`.cursorrules`, `.clinerules`, `.windsurfrules`, `copilot-instructions.md`,
   `.aider.conf.yml`); `.claudeignore` (Claude Code non lo legge: là stesso il
   commento lo dichiara, e la copia applicata è `permissions.deny`); il
   `Makefile` come punto d'ingresso (lo è già `test-scripts.sh`, e lo sarà
   `stack.py`: un terzo ingresso è una terza verità); il sandbox Vagrant (qui la
   VM riproducibile è `create-vm.sh` + cloud-init, ADR-0011, con gli snapshot
   come rollback); il plugin LSP di Claude Code (secondo tool nel layer "tooling
   codice", che è Serena: ADR-0006).

## Conseguenze
**Positive:** i due repo condividono pin di Serena, regole di accesso ai
segreti per Claude Code, formato delle skill, stile delle Actions ed
`.editorconfig`; le regole HC utili diventano controlli con mutazione invece di
testo; nessun secondo validatore, nessun secondo file di memoria.

**Negative — da non minimizzare:**
- **I due repo restano diversi su punti visibili**: `CLAUDE.md` là è generato,
  qui è un rimando; Serena per opencode là usa `agent`, qui `ide`. Chi lavora su
  entrambi deve sapere perché (questa ADR) o la differenza sembrerà un errore.
- `permissions.deny` di Claude Code ferma il tool `Read`, **non** un
  `Bash(cat .env)`: è una cintura, non una cassaforte. Lo stesso limite vale
  per Infra-Iam-PKI.
- La matrice è un'istantanea: se Infra-Iam-PKI cambia standard, nessun test qui
  se ne accorge. Va riletta a ogni ADR di quel repo che tocchi gli agenti o la CI.
- Il pin esatto di Serena nei client e in `stack/requirements-tools.txt` (P1)
  rende **rossa per costruzione** la PR di Dependabot che lo aggiorna, finché i
  client non vengono allineati a mano: è voluto (a ogni major va riletto
  `memory_tools.py`, vedi trappole note), ma è lavoro manuale per ogni bump.

**Da rivedere se:** opencode o Claude Code smettono di leggere `AGENTS.md`;
si adotta un client che legge solo un formato proprio; Infra-Iam-PKI passa a
`ide` (allora la differenza su Serena sparisce) o abbandona il generatore.
