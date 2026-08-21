# TOOLS-STACK — uno per layer, zero overlap (ADR-0006)

| Layer | Scelta | Disabilita per evitare overlap |
|---|---|---|
| Tooling codice (puntuale) | **Serena** (uv locale) | basic tool (`--context ide-assistant`), memory (`project.yml`) |
| Mappa d'insieme | **graphify** (uv, skill) | — (occasionale, non sempre attivo) |
| Metodologia | **mattpocock/skills** | — |
| Security | **AgentShield** (npx, da ECC) | — |
| Modelli | **LiteLLM** + headroom callback | proxy headroom standalone |

**Non adottati:** `superpowers` (overlap metodologia + subagent-heavy = costo
token e meno controllo) e **ECC full** (261 skill + hook → context bloat, contro
il vincolo single-maintainer). Da ECC si prende solo AgentShield.

## Serena vs graphify — perché convivono
| | Serena | graphify |
|---|---|---|
| Risponde a | "dov'è X? chi lo chiama?" | "come sta insieme il sistema?" |
| Come | LSP live, on-demand | AST tree-sitter → grafo persistente |
| Copre | solo codice | codice + docs, PDF, config, SQL |
| Quando | ogni sessione | **occasionale** |

Serena è il bisturi, graphify la mappa. graphify è una *skill*, non un MCP
sempre attivo: non consuma context a ogni sessione. Parsing locale e
deterministico, archi taggati EXTRACTED vs INFERRED.

**Caveat memory:** `graphify reflect` produce `LESSONS.md`. È file-based e
git-tracked (coerente con ADR-0007), ma sfiora `CONTEXT.md`. Regola: **decisioni
negli ADR, lezioni operative in LESSONS.md** — non duplicare.

**Riserve oneste su graphify:** il conteggio stelle riportato dagli aggregatori è
anomalo per un progetto giovane senza membri pubblici — valutalo sul codice. Ed
è open-core: il free è locale e utile, l'avanzato resta enterprise.
