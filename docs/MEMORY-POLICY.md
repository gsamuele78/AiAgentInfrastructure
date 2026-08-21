# MEMORY POLICY — una verità per livello (ADR-0007)

| Livello | Canonico | Altri |
|---|---|---|
| Progetto (decisioni, glossario) | `CONTEXT.md` + `docs/adr/` (git) | — |
| Struttura del codice | graphify (`graph.json`) | — |
| Cross-sessione personale | **1** memory MCP | mem0: installato ma INERTE (verificato) |
| Simboli live | Serena semantic | memory Serena **disabilitata** |
| ECC memory/instinct | non adottata | solo AgentShield |

**Enforcement:** `.serena/project.yml` esclude i memory tool;
`audit-integration.py` va in **FAIL** con >1 memory MCP attiva (TC-03).

**Perché file-based per il progetto:** trasparente, diff-abile, versionato — vedi
la storia delle decisioni invece di uno stato opaco dentro l'agente.
