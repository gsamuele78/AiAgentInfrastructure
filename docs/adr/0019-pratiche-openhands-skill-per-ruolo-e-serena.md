# 0019 — Pratiche OpenHands senza OpenHands; skill per ruolo; Serena per client

- **Status**: Proposed — piano in [`PLAN-STACK-VALIDATION.md`](../PLAN-STACK-VALIDATION.md) (P4–P6)
- **Data**: 2026-10-10
- **Relazione**: applica 0006 (un tool per layer), 0007 (una memoria per livello), 0013.

## Contesto
Obiettivo: risultati "ibridi" (modelli locali + cloud, ADR-0016) con le pratiche
che rendono OpenHands affidabile, per quattro ruoli: software design, sviluppo,
system engineering, PRD. OpenHands (MIT nel core) ha una documentazione
esplicita delle sue pratiche; le abbiamo confrontate con lo stack attuale
(fonte: docs.openhands.dev, 2026-10):

| Pratica OpenHands | Cosa fa | Qui oggi |
|---|---|---|
| `AGENTS.md` sempre caricato | contesto di repo | ✅ ADR-0013 |
| Skill on-demand in `.agents/skills/<n>/SKILL.md` | progressive disclosure: solo la descrizione in context, il corpo quando serve | ⚠️ mattpocock installato **per intero e senza pin**, cartella non decisa |
| `.openhands/setup.sh` | ambiente pronto a ogni sessione | ⚠️ installer non idempotente (ADR-0018) |
| Hook / pre-commit | controlli prima del commit | ❌ solo CI |
| Condenser (riassunto LLM della storia) | contesto sotto controllo | ✅ `compaction` opencode + headroom (ADR-0016) |
| Security analyzer + `ConfirmRisky` | conferma sulle azioni rischiose | ⚠️ AgentShield fa scan statico, nessuna conferma runtime configurata in opencode |
| Runtime in container | l'agente non tocca l'host | ❌ per scelta (ADR-0005: IDE e agenti sull'host) |
| Critic / benchmark | misura se l'agente risolve | ❌ nessuna misura del comportamento |

Fatti verificati nel sorgente, che vincolano la decisione:
- **opencode legge sia `.claude/skills/` sia `.agents/skills/`** (progetto e
  globale). Una skill presente in entrambi è un duplicato in context.
- **Collisione di nomi**: mattpocock ha `code-review`, come una skill integrata
  di Claude Code. È il problema già descritto in ADR-0006 (`/code-review`
  duplicato), mai verificato da un test.
- **Serena**: `ide-assistant` è deprecato e rimappato su `claude-code`; il
  contesto giusto è **per client** (`ide` per opencode, `claude-code` per
  Claude Code, `codex` per Codex). I tool di memoria sono 7, non 4. Corretto
  in questa stessa PR.

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Adottare **OpenHands** come quarto agente | sandbox, condenser, critic già fatti; può puntare a LiteLLM | runtime Docker con accesso al socket; secondo harness primario accanto a opencode → ADR-0006; un altro stack da aggiornare |
| Installare tutti gli ecosistemi di skill | massima copertura | già respinto (ADR-0006): collisioni e context sprecato |
| **Adottare le pratiche, non il prodotto** | stessi benefici sui client che usiamo già | le pratiche vanno implementate e mantenute da noi |

## Decisione
1. **Skill — una cartella canonica**: `.agents/skills/` (letta da opencode,
   OpenHands, Codex). Claude Code la vede tramite symlink
   `.claude/skills → ../.agents/skills`; in opencode si disattiva la lettura di
   `.claude/` per non caricarle due volte (flag `disableClaudeCodeSkills` nel
   sorgente; nome esatto della variabile da confermare in P4).
2. **Skill — allowlist per ruolo, pinnata a un commit**, non il repo intero:

   | Ruolo | Skill (mattpocock, salvo nota) |
   |---|---|
   | Software design | `codebase-design`, `domain-modeling`, `improve-codebase-architecture` |
   | Sviluppo | `tdd`, `implement`, `implement-spec`, `diagnosing-bugs`, `pr` |
   | PRD / spec | `grill-me`, `grill-with-docs`, `to-spec`, `to-tickets` |
   | System engineering | **nessuna upstream** → due skill di repo: `adr` (scrive/supersede un ADR col template e aggiorna l'indice) e `infra-change` (dry-run → snapshot → apply → `stack.py validate` → rollback) |
   | Escluse | `code-review` (collide con la integrata), `skills/in-progress/*`, `misc/*` salvo `git-guardrails-claude-code` |
3. **Serena resta il layer "tooling codice"**, con contesto per client e
   memoria esclusa per intero; si aggiunge a Claude Code
   (`--context claude-code`), oggi configurata solo in opencode.
4. **Guardrail come ConfirmRisky**: `permission` di opencode su `ask` per
   comandi distruttivi (`rm -rf`, `git push --force`, `virsh destroy`,
   `docker compose down -v`), stesse regole nelle `permissions` di Claude Code.
   AgentShield resta lo scan statico.
5. **Pre-commit** col framework `pre-commit` (MIT): shellcheck, parse
   YAML/JSON/TOML, un sottoinsieme veloce di `test-scripts.sh`. I suoi hook
   sono aggiornati da Dependabot (ecosistema `pre-commit`).
6. **Livello 6 — eval come critic**: 5–8 "golden task" per ruolo (es. "scrivi
   l'ADR per X", "aggiungi una lane al config senza rompere §4"), eseguiti con
   `opencode run` su `litellm/cheap`, con controllo **deterministico**
   dell'artefatto (file creato, test verdi, schema valido) e non un giudizio
   LLM. Settimanale sul runner self-hosted, budget limitato su una virtual key.
7. **Runtime in container: no come default** (ADR-0005). Per repo non fidati,
   opzione documentata: opencode dentro una Distrobox/devcontainer.

## Conseguenze
**Positive:** progressive disclosure vera (meno token per sessione); nessuna
skill duplicata o in collisione, ed è un test; il ruolo "system engineer", oggi
scoperto, ha skill legate a questo repo; il comportamento degli agenti ha una
misura (L6), non solo la configurazione.

**Negative — da non minimizzare:**
- Le skill di repo (`adr`, `infra-change`) sono **testo da mantenere**:
  invecchiano quando cambiano gli script.
- Le eval L6 costano token a ogni run e sono **un campione**: un verde dice che
  quei 5–8 compiti riescono, non che l'agente è "al meglio".
- Il pin a commit di mattpocock richiede aggiornamenti manuali (Dependabot non
  lo vede; `stack.py outdated` lo segnala).
- Le `permission` su `ask` rallentano le sessioni lunghe: è il prezzo di
  ConfirmRisky.

**Da rivedere se:** serve automazione headless issue→PR (lì OpenHands è più
forte di opencode e va rivalutato come componente a sé); o
`agentskills`/`.agents/skills` smette di essere il formato comune.
