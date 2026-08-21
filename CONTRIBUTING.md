# Contributing

Repo a **maintainer singolo**. Queste regole servono soprattutto al te-futuro:
a sei mesi di distanza non ricorderai perché una cosa è fatta così.

## Principi non negoziabili

1. **Un gateway, un punto di compressione.** Ogni client passa da LiteLLM.
2. **Un tool per layer.** Prima di aggiungere uno strumento, verifica che non
   si sovrapponga a uno esistente (vedi `docs/adr/0006`).
3. **Una memoria per livello** (`docs/adr/0007`).
4. **Nessun segreto nei file versionati.** Solo `os.environ/` e file 600.
5. **Onesto, non ottimista.** I limiti si documentano, non si nascondono.

## Prima di modificare qualcosa

```bash
./scripts/audit-integration.py    # stato attuale
./scripts/devops-audit.sh         # best practice
```

## Decisioni architetturali → ADR

Ogni scelta strutturale va in `docs/adr/` con il template `_template.md`.
Regole:
- Gli ADR sono **immutabili**. Non si modifica un ADR accettato: se ne scrive
  uno nuovo che lo **supersede** (esempio: 0002 → 0003).
- Vanno sempre compilate le **alternative scartate** e le **conseguenze
  negative**. Un ADR senza costi dichiarati è un ADR incompleto.
- Aggiorna l'indice in `docs/adr/README.md` (la CI verifica che i link esistano).

## Modifiche ai config

| Cosa tocchi | Verifica obbligatoria |
|-------------|-----------------------|
| `services/*` | `docker compose config` + rebuild |
| `clients/*` | `audit-integration.py` |
| `scripts/*` | `bash -n` + `shellcheck` |
| requisiti | aggiorna `docs/PRD.md` |
| test | aggiorna `docs/TEST-PLAN.md` (matrice requisito→test) |

## Commit

Convenzione: `<tipo>(<ambito>): <descrizione>`

```
feat(gateway): aggiunge lane BIOME L40S via mTLS
fix(opencode): accorcia alias MCP per il bug tool-name
docs(adr): 0011 — scelta del serving stack
chore(ci): aggiunge job functional su runner self-hosted
```

Tipi: `feat` `fix` `docs` `refactor` `test` `chore` `security`.

## Prima di pushare

```bash
./scripts/devops-audit.sh && ./scripts/audit-integration.py
# la CI ripete la validazione statica: meglio scoprirlo in locale
```

## Definition of Done

Una modifica è completa quando: la CI passa, gli audit non regrediscono, la
documentazione è aggiornata, e — se cambia l'architettura — esiste un ADR.
