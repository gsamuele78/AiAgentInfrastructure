# 0016 — Catena `auto` (locale → Anthropic → OpenRouter) nel gateway; Claude Code Router non adottato

- **Status**: Accepted
- **Data**: 2026-10-10
- **Relazione**: applica 0001, 0003, 0006 e 0008. Non supersede nulla.

## Contesto
Richiesta: da opencode, usare **il LLM locale se disponibile**, poi
**l'abbonamento Anthropic**, poi **OpenRouter**, valutando
[Claude Code Router](https://github.com/musistudio/claude-code-router) (CCR,
MIT) e con prompt caching e compressione funzionanti su tutta la catena.

Cosa è emerso analizzando CCR v3.1.3 (sorgente, ottobre 2026):

1. **CCR è un gateway completo**, non più un piccolo router davanti a Claude
   Code: endpoint unico `:3456`, credential pool, fallback, log, costi, UI web,
   app Electron, plugin, relay verso chat (AgentClaw). È lo **stesso layer** di
   LiteLLM. Adottarlo significa due gateway — contro l'invariante #1 e ADR-0006.
2. **Importa il login OAuth di Claude Code** (`packages/core/src/agents/
   local-providers/claude-code.ts` legge `~/.claude/.credentials.json`) e lo
   espone come provider a **qualunque** agente, opencode compreso. È proprio il
   caso che `CLAUDE-SUBSCRIPTION.md` marca ❌: i termini Anthropic limitano i
   token OAuth di Free/Pro/Max a Claude Code e claude.ai. Il rischio non è
   tecnico, è **la sospensione dell'account**.
3. La compressione headroom vive come callback **dentro** LiteLLM (ADR-0003):
   il traffico che passa da CCR verso un provider non la riceverebbe.

Quindi "opencode → abbonamento" **non è realizzabile in modo lecito** da nessun
router. Lo è l'API key Anthropic (a consumo), che il gateway ha già.

## Alternative considerate
| Opzione | Catena | Compressione | Invarianti | Costo |
|---|---|---|---|---|
| CCR come gateway al posto di LiteLLM | ✅ | ❌ (headroom fuori) | ❌ #1 riscritta | migrazione + nuovo stack Node/Electron |
| CCR davanti a LiteLLM | ✅ | ✅ | ❌ #1, #2, ADR-0006 | due gateway da tenere allineati |
| CCR con import OAuth per opencode | ✅ "abbonamento" | ❌ | ❌ | **fuori termini d'uso** |
| **Catena nel router di LiteLLM** | ✅ | ✅ (stesso callback) | ✅ intatte | ~40 righe di YAML |

## Decisione
La catena è un **gruppo `auto` del gateway LiteLLM**:

```
auto ──► ollama qwen2.5-coder:7b (num_ctx 16384, max_input_tokens 12288)
  │ errore / Ollama spento / cooldown      │ prompt troppo lungo (pre_call_checks)
  ▼                                        ▼
claude-sonnet-4-6 (API key) ──► or-claude-sonnet ──► or-pareto-code
```

- **"Se disponibile"** lo decide il router: Ollama spento → errore immediato →
  `fallbacks`; prompt oltre `max_input_tokens` (tool inclusi) → scartato prima
  della chiamata → `context_window_fallbacks`. Le due liste sono identiche.
- **L'abbonamento resta a Claude Code**, che è l'unico client per cui è lecito.
  `claude-gw` (in `clients/shell-env.sh`) lancia Claude Code sulla stessa
  catena quando la finestra Pro è esaurita, con variabili valide per quel solo
  processo.
- **Prompt caching**: `cache_control_injection_points` (system + ultimo
  messaggio) su ogni deployment Claude a pagamento, Anthropic e OpenRouter.
  Corretto anche `claude-opus-4-8`, dove la chiave stava **fuori** da
  `litellm_params` e veniva ignorata in silenzio.
- **Compressione**: headroom callback invariato, vale per tutti gli anelli;
  opencode aggiunge la compattazione lato client (`compaction`).
- **CCR non viene adottato.** Nessun client punta a `:3456`/`:3458`.

## Conseguenze
**Positive:** la catena richiesta esiste senza un componente nuovo; un solo
punto di credenziali, spend e compressione; la decisione "locale o cloud" è
automatica e misurabile (`model` nella risposta, `/spend/logs`).

**Negative — da non minimizzare:**
- **Il locale serve poco agli agenti.** Il prompt di sistema + tool di opencode
  supera spesso i 12k token: dopo pochi turni la sessione passa al cloud. Per
  Claude Code il locale non scatta praticamente mai.
- **Un modello da 7B che risponde *male* non è un errore**: tool call
  sbagliate o codice scadente non attivano il fallback. Il router sa se il
  locale c'è, non se è all'altezza. Per lavoro serio: `litellm/coding`.
- **Il fallback a metà sessione cambia modello**: risposte di stile diverso e
  la cache del modello precedente non serve al successivo.
- **headroom + cache non è verificato**: se la compressione riscrive il
  prefisso in modo non deterministico, ogni turno è un cache miss. TC-09 lo
  misura; finché non gira sul gateway reale (debito #6) è un'ipotesi.
- **Costo a consumo**: senza abbonamento, `auto` paga Anthropic API dopo il
  locale. Il budget va messo sulla virtual key.
- `num_ctx` vive in due posti (`litellm_config.yaml` e `setup-ollama.sh`);
  `test-scripts.sh` §4 ne verifica l'allineamento.

**Enforcement:** `test-scripts.sh` §4 (cache dentro `litellm_params`, ordine
Anthropic→OpenRouter, `max_input_tokens < num_ctx`, nessun client su CCR,
opencode su `litellm/auto`, nessun `export ANTHROPIC_*`); `test-all.sh cache`
(TC-09) sul gateway reale.

**Da rivedere se:** Anthropic consente l'uso dell'abbonamento da client terzi;
oppure un modello locale nei 4 GB di VRAM regge il tool-calling di opencode; o
LiteLLM perde fallback/pre_call_checks.
