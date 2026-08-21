# AGENTS.md — contesto di progetto per agenti AI

> Letto automaticamente da **opencode** (`AGENTS.md`) e da **Claude Code**
> (via `CLAUDE.md`, che punta a questo file). Serve a far ripartire una
> sessione senza rispiegare il progetto da capo.
>
> Memoria canonica di progetto (vedi `docs/MEMORY-POLICY.md`):
> **questo file + `docs/adr/`**. Le decisioni stanno negli ADR, non qui.

## Cos'è questo repo

Infrastruttura per agenti AI a **maintainer singolo**: un gateway LiteLLM
(con compressione Headroom come callback) in VM KVM locale, agenti sull'host,
lane per dati sensibili, LLM locale e self-hosted BIOME.

```
HOST ermes                                   VM KVM
Claude Code ──abbonamento──► Anthropic       ┌────────────────────────┐
opencode / OpenChamber ─┐                    │ litellm :4000          │
Codex ──────────────────┼─127.0.0.1:4000────►│  └─[headroom callback] │
Serena + graphify       │      (socat)       │ postgres (rete interna)│
Ollama :11434 (virbr0) ─┘                    └────────────────────────┘
                  └─ VPN ateneo ─► BIOME L40S (vLLM, mTLS)
```

## Prima di proporre modifiche — leggi in quest'ordine

1. `docs/PRD.md` — **soprattutto i non-goal (§3)**. Molte "buone idee"
   contraddicono un non-goal esplicito: in quel caso la risposta è no, o
   serve un nuovo PRD.
2. `docs/adr/README.md` — le 12 decisioni già prese e il loro perché.
3. `docs/TEST-PLAN.md` — cosa deve continuare a passare.

## Invarianti che NON vanno violate

Sono verificate automaticamente da `scripts/test-scripts.sh`: se le rompi, la
CI fallisce.

| # | Invariante | Perché |
|---|---|---|
| 1 | **Un solo gateway**: nessun client parla direttamente a un provider | ADR-0001 |
| 2 | Compressione = **callback** dentro LiteLLM, non un proxy davanti | ADR-0003 |
| 3 | Ollama bindato **solo su virbr0**, mai `0.0.0.0` | non ha autenticazione |
| 4 | postgres **non pubblica porte**; vLLM **su loopback** | least exposure |
| 5 | Config montate `:ro`; solo DB e workspace scrivibili | immutabilità |
| 6 | **Nessun segreto** nei file versionati — solo `os.environ/` e file 600 | SECURITY.md |
| 7 | **Un tool per layer** (Serena · graphify · mattpocock · AgentShield) | ADR-0006 |
| 8 | **Una memoria per livello** | ADR-0007 |
| 9 | Ogni script che modifica il sistema espone `--dry-run` | TC-08 |
| 10 | `cleanup-host` verifica il gateway **prima** di pulire | ordine PSE |

## Vincolo dominante

**Maintainer singolo, < 30 min/mese di manutenzione.** Ogni componente
aggiunto deve giustificare il proprio costo di manutenzione. In caso di dubbio
tra "più completo" e "più mantenibile", vince **mantenibile**.

Corollario: non aggiungere un tool se ne esiste già uno per quel layer. Non
aggiungere un sistema di memoria. Non introdurre dipendenze che richiedono
attenzione continua.

## Comandi

```bash
# verifica (in ordine di costo crescente)
./scripts/test-scripts.sh        # L1b: contratti e invarianti — gira ovunque
./scripts/devops-audit.sh        # L4: best practice deploy
./scripts/audit-integration.py   # L3: configurazione dei client
./scripts/test-all.sh            # L5: catena reale (serve il gateway attivo)

# deploy
./scripts/deploy-all.sh --dry-run     # 8 fasi con checkpoint
./scripts/detect-hardware.sh --emit-config
./scripts/create-vm.sh                # VM riproducibile (cloud-init)
./scripts/setup-ollama.sh             # LLM locale configurato e verificato
./scripts/restore-test.sh             # TC-05: il backup è restorabile?
```

## Convenzioni

- **Commit**: `<tipo>(<ambito>): <descrizione>` — `feat` `fix` `docs`
  `refactor` `test` `chore` `security`.
- **ADR immutabili**: una decisione non si modifica; se ne scrive una nuova che
  la **supersede** (esempio: 0002 → 0003). Sempre con alternative scartate e
  conseguenze negative. Aggiorna `docs/adr/README.md` (la CI lo verifica).
- **Definition of Done**: CI verde, audit senza regressioni, documentazione
  aggiornata, e — se cambia l'architettura — un ADR.
- Dettagli in `CONTRIBUTING.md`.

## Trappole note (ci siamo già cascati)

| Trappola | Sintomo | Rimedio |
|---|---|---|
| `headroom wrap` riscrive i config dei client | i tool tornano a `:8787` | `headroom unwrap`, poi `audit-integration.py` |
| Alias MCP lunghi (`github.com/...`) | "Model tried to call unavailable tool" | alias corti: `reason`, `mem`, `fs`, `ctx7` |
| `ANTHROPIC_API_KEY` residua nell'ambiente | fatturazione a consumo **silenziosa** invece dell'abbonamento | `unset`; verifica con `/status` |
| IP della VM cambia | gateway "giù" senza motivo | riserva DHCP (`VM-KVM-GUIDE.md`) |
| `shm_size` mancante su vLLM | crash oscuro all'avvio | `shm_size: 16gb` |
| `proxy_buffering` attivo in nginx | streaming che arriva in blocco | `proxy_buffering off` |
| File sourced senza shebang | shellcheck SC2148 | `# shellcheck shell=bash` |

## Debito riconosciuto (non nasconderlo, non "risolverlo" di nascosto)

1. Immagine LiteLLM su tag mobile `main-stable` → pinnare un digest sha256
2. Nessun alerting (accettabile per uso personale)
3. Credenziali storiche esposte in un file 664 → **ruotarle**
4. Nessuno scan CVE delle immagini

Elenco completo e razionale in `docs/DEVOPS-AUDIT.md`.

## Fuori scope in questo repo

Multi-tenancy, alta disponibilità, CD automatico, fine-tuning. Il servizio LLM
multi-tenant per i ricercatori BIOME vive in un **repo separato** — vedi
`docs/adr/0012-repo-separato-per-multi-tenant.md`.

## Stile di collaborazione atteso

- **Onesto, non ottimista**: i limiti si documentano, non si nascondono.
- Prima di una risposta complessa: elenca cosa manca e le assunzioni che fai.
- Per le decisioni architetturali: contesto → alternative → decisione →
  conseguenze (incluse quelle negative).
- Preferisci FOSS con licenze permissive (MIT/Apache-2.0/GPL).
