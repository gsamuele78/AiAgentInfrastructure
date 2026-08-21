# 0013 — AGENTS.md come memoria di progetto (supersede 0007 sul file canonico)
- **Status**: Accepted
- **Data**: 2026-08-21
- **Supersede**: [0007](0007-una-memoria-per-livello.md) — limitatamente alla riga
  «Progetto (decisioni)». Il resto di 0007 (una memoria per livello, mem0 ed ECC
  non adottati, memoria Serena disabilitata) resta in vigore.

## Contesto
ADR-0007 indicava `CONTEXT.md` + `docs/adr/` come memoria di progetto. Nel
frattempo il repo ha adottato `AGENTS.md`, letto automaticamente da opencode e
— via `CLAUDE.md` — da Claude Code. `CONTEXT.md` non è mai esistito.

La deriva era già visibile: `AGENTS.md` e `docs/MEMORY-POLICY.md` dicevano
`AGENTS.md`, ADR-0007 diceva `CONTEXT.md`. Tre file, due verità — esattamente
ciò che 0007 voleva impedire. E il repo impone a sé stesso che una decisione si
cambi solo con un nuovo ADR (`CONTRIBUTING.md`): correggere 0007 sul posto
sarebbe stato più veloce e più sbagliato.

## Alternative considerate
| Opzione | Letto dagli agenti | Una sola verità | Costo |
|---|---|---|---|
| Creare `CONTEXT.md` come da 0007 | ❌ nessun agente lo legge da solo | ✅ | doppio file da tenere allineato |
| Modificare 0007 sul posto | ✅ | ✅ | **viola l'immutabilità degli ADR** |
| **Nuovo ADR che supersede 0007** | ✅ | ✅ | un file in più in `adr/` |

## Decisione
La memoria di progetto è **`AGENTS.md` + `docs/adr/`**. `CLAUDE.md` vi rimanda e
non duplica nulla. `CONTEXT.md` non esiste e non va creato.

Ripartizione invariata rispetto a 0007 per gli altri livelli:

| Livello | Canonico |
|---|---|
| Progetto (decisioni) | **`AGENTS.md`** + `docs/adr/` — file, git |
| Struttura del codice | graphify (`graph.json`, `LESSONS.md`) |
| Cross-sessione personale | **1** memory MCP |
| Simboli live | Serena, **memory disabilitata** |

## Conseguenze
**Positive:** il file che gli agenti leggono davvero è anche quello canonico;
sparisce la terza verità.
**Negative:** `AGENTS.md` è un formato di fatto, non uno standard: se opencode o
Claude Code cambiano convenzione, la decisione va rivista. E un file letto
automaticamente tende a crescere: va tenuto corto, le decisioni restano qui.
**Enforcement:** `scripts/test-scripts.sh` §5 verifica che `AGENTS.md` esista e
che `CLAUDE.md` vi rimandi.
**Da rivedere se:** gli agenti adottano un formato di contesto diverso.
