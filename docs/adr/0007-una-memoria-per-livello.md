# 0007 — Una sola memoria per livello
- **Status**: Accepted
- **Data**: 2026-07-24

## Contesto
Serena, ECC, mem0, memory MCP e i file CONTEXT.md/ADR sono tutti memorie. Più
sistemi sullo stesso livello = stato duplicato e incoerente.

## Decisione
| Livello | Canonico |
|---|---|
| Progetto (decisioni) | `CONTEXT.md` + `docs/adr/` — file, git |
| Struttura del codice | graphify (`graph.json`, `LESSONS.md`) |
| Cross-sessione personale | **1** memory MCP |
| Simboli live | Serena, **memory disabilitata** |
mem0 e la memoria ECC non sono adottate.

## Conseguenze
**Positive:** memoria di progetto trasparente, diff-abile, versionata.
**Negative:** si rinuncia alla memoria semantica automatica.
**Enforcement:** `.serena/project.yml` esclude i memory tool; `audit-integration.py`
fallisce con >1 memory MCP attiva.
**Da rivedere se:** la memoria file-based non regge la crescita del progetto.
