# 0017 — Manifest dei componenti e validatore unico (`stack.py`)

- **Status**: Proposed — piano in [`PLAN-STACK-VALIDATION.md`](../PLAN-STACK-VALIDATION.md) (P1–P3)
- **Data**: 2026-10-10

## Contesto
La verifica esiste già, ma è sparsa in cinque script, ognuno con la sua idea
implicita di "cosa c'è nello stack":

| Livello | Script | Sa di |
|---|---|---|
| L0 hw/OS | `detect-hardware.sh` | GPU, RAM, OS — output solo per umani |
| L1b | `test-scripts.sh` | invarianti del repo |
| L3 | `audit-integration.py` | config dei client sull'host |
| L4 | `devops-audit.sh` | best practice di deploy |
| L5 | `test-all.sh` | catena reale |

Nessuno conosce le **versioni**. Così nel 2026-10 sono passati inosservati due
drift, trovati solo leggendo il sorgente di Serena: `--context ide-assistant`
deprecato e rimappato in silenzio su `claude-code`, e tre tool di memoria nuovi
(`rename_memory`, `edit_memory`, `onboarding`) non esclusi — una violazione di
ADR-0007 senza un solo test rosso. Anche gli installer sono sparsi: ognuno
scrive config a modo suo (`bak()` crea un `.bak` nuovo a ogni esecuzione, quindi
rilanciare non è idempotente), e nessuno registra cosa ha cambiato.

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Lasciare gli script come sono | zero lavoro | il drift resta invisibile; nessun rollback |
| **Ansible** (GPL-3.0) | idempotenza nativa, `--check`/`--diff`, fatti di sistema, modulo `rpm_ostree_pkg` | ~migliaia di file di dipendenze, Jinja, collection da pinnare (Dependabot non le vede); riscrivere 1800 righe di bash già testate contro trappole reali |
| **goss** (Apache-2.0) come validatore | binario unico, YAML, veloce | copre pacchetti/porte/file, non "la skill X è unica" né "auto instrada sul locale": serve comunque codice nostro → due formati |
| Nix / home-manager | rollback perfetto | curva ripida, ecosistema a sé, contro il vincolo 30 min/mese |
| **Manifest TOML + `stack.py` (stdlib)** | `tomllib` è in stdlib (Python ≥3.11: Debian 13 ha 3.13, Bazzite pure); riusa gli script esistenti come backend | codice nostro da mantenere (~500 righe stimate) |

## Decisione
1. **`stack/components.toml`** è l'unica fonte di "cosa compone lo stack". Per
   ogni componente: `id`, `layer` (ADR-0006), `scope` (host · vm · client ·
   repo), `required`, `version` (pin), `install` per famiglia di OS (`debian`,
   `atomic`), `probe` (presenza + versione), `health` (prova funzionale),
   `files` (config che scrive), `rollback`, `adr`.
2. **`scripts/stack.py`** è l'unico punto d'ingresso, con sottocomandi:
   `facts` (hw/OS in JSON) · `plan` (cosa cambierebbe — è il `--dry-run`) ·
   `install [--only id]` · `validate [--level 0..6] [--json]` ·
   `rollback <run-id|id>` · `outdated`.
3. **`validate` orchestra, non duplica**: chiama `test-scripts.sh`,
   `devops-audit.sh`, `audit-integration.py`, `test-all.sh` per i loro livelli
   e aggiunge solo ciò che manca — probe di versione contro il pin, unicità
   delle skill, coerenza manifest↔config. Exit 0 ok · 1 fail · 2 prerequisito
   mancante (stessa semantica di `sync_openrouter.py`).
4. **Contratto di test per componente** (vale per tutti, è ciò che "testare
   ogni componente" significa qui): presente → versione = pin → config
   conforme → health → seconda `install` con **0 cambiamenti** → `rollback`
   riporta gli sha256 dei file allo stato precedente.
5. `stack-selective-install.sh` diventa un wrapper deprecato di
   `stack.py install --profile client` per un ciclo, poi si rimuove.

## Conseguenze
**Positive:** il drift di versione diventa un FAIL invece di una scoperta
casuale; idempotenza e rollback misurabili (TC-10/11/12); un solo comando da
ricordare; il report JSON diventa artefatto CI.

**Negative — da non minimizzare:**
- È **codice nuovo da mantenere** contro il vincolo dei 30 min/mese. La stima di
  500 righe è ottimistica finché P3 non esiste.
- Un manifest dichiarativo può **mentire**: se `probe` controlla la cosa
  sbagliata, il verde è falso. Mitigazione: ogni probe nasce con un test di
  mutazione (si rompe il componente, il probe deve diventare rosso), come già
  fatto in `test-scripts.sh` per la catena `auto`.
- Nessun validatore dimostra che una skill "funziona al meglio": il livello 6
  (eval) misura un campione, non la qualità in generale (ADR-0019).
- Durante la transizione convivono vecchio e nuovo installer.

**Da rivedere se:** i componenti superano ~40, o lo stack deve girare su più di
un host: a quel punto Ansible paga il suo costo e questo ADR va superseduto.
