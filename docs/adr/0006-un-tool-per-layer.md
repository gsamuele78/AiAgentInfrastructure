# 0006 — Un tool per layer, niente sovrapposizioni
- **Status**: Accepted
- **Data**: 2026-07-24

## Contesto
Più ecosistemi di skill (mattpocock, superpowers, ECC) e più tool di analisi
(Serena, graphify). Adottarne due per lo stesso layer significa comandi che
collidono (`/tdd`, `/code-review` duplicati) e context sprecato.

## Alternative considerate
| Opzione | Costo context | Manutenzione |
|---|---|---|
| ECC full (261 skill + hook) | alto | alta |
| superpowers + mattpocock | alto | duplicata |
| **Uno per layer + cherry-pick** | basso | bassa |

## Decisione
Serena (tooling puntuale) · graphify (mappa d'insieme, occasionale) ·
mattpocock (metodologia) · AgentShield (security, cherry-pick da ECC).
Non adottati: superpowers, ECC full.

## Conseguenze
**Positive:** nessuna collisione; context sotto controllo (<10 MCP, <80 tool).
**Negative:** si rinuncia a funzionalità degli ecosistemi scartati.
**Da rivedere se:** un layer resta scoperto da un bisogno reale e ricorrente.
