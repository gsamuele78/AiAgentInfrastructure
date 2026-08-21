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
HOST (workstation)                                   VM KVM
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
| 1 | **Un solo gateway**: nessun client parla direttamente a un provider — *eccezione: la lane abbonamento di Claude Code, ADR-0014* | ADR-0001 |
| 2 | Compressione = **callback** dentro LiteLLM, non un proxy davanti — *stessa eccezione* | ADR-0003 |
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
#   (pyyaml opzionale: senza, i controlli sui compose sono 'skip' non 'fail')
./scripts/devops-audit.sh        # L4: best practice deploy
./scripts/audit-integration.py   # L3: configurazione dei client
./scripts/test-all.sh            # L5: catena reale (serve il gateway attivo)

# deploy
./scripts/deploy-all.sh --dry-run     # 8 fasi con checkpoint
./scripts/detect-hardware.sh --emit-config
./scripts/create-vm.sh                # VM riproducibile (cloud-init)
./scripts/sync_openrouter.py --dry-run  # catalogo OpenRouter nel DB (OPENROUTER-SYNC.md)
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
| `cleanup-host.sh` senza `KEEP_HEADROOM=1` | Claude Code muto: la lane B punta a una porta chiusa | ADR-0014; riattiva `headroom.service` |
| IP della VM cambia | gateway "giù" senza motivo | riserva DHCP (`VM-KVM-GUIDE.md`) |
| `shm_size` mancante su vLLM | crash oscuro all'avvio | `shm_size: 16gb` |
| `proxy_buffering` attivo in nginx | streaming che arriva in blocco | `proxy_buffering off` |
| File sourced senza shebang | shellcheck SC2148 | `# shellcheck shell=bash` |
| `pip install` nel Dockerfile | build KO: `pip: not found` | l'immagine upstream è Wolfi + venv `uv`: installa con `uv pip install --python /app/.venv/bin/python` |
| `headroom-ai[all]` su linux | immagine da ~3 GB (torch) | il callback usa solo il core: `HEADROOM_EXTRAS` vuoto |
| `ports:` + `network_mode: service:` | `docker compose config` passa, `up` no | pubblica la porta sul servizio che possiede il netns |
| `$USER` non impostato | `set -u` uccide il dry-run | `${USER:-$(id -un)}` |
| `docker compose --env-file X config` al posto di un `.env` vero | `env file .../.env not found` | `--env-file` cambia solo l'interpolazione, non soddisfa la chiave `env_file:` del servizio: il file deve esistere |
| `/model/new` usato per aggiornare un modello | riga duplicata o errore | non e' un upsert (`table.create`): per modificare serve `/model/update` |
| pricing letto da `model_info` | il diff non vede mai un cambiamento | `/model/info` riempie `model_info` con la cost map: il prezzo si scrive e si rilegge da `litellm_params` |
| `set -e` tolto per aggiungere un `run()` | lo script esce 0 pur avendo fallito | controlla a mano i comandi critici (vedi `backup-db.sh`) |
| `api_base` verso un hostname senza servizio nel compose | la lane fallisce al primo uso, non al deploy | `test-scripts.sh` §4 lo verifica |
| GPU dedotta da `command -v nvidia-smi` | "GPU non rilevata" su una macchina che ce l'ha (OS atomico senza driver, dGPU spenta, container) | si guarda il bus PCI: `nvidia_pci_devices` in `scripts/lib/hw-detect.sh` |
| `apt install` come hint universale | su Fedora/Bazzite il consiglio non funziona | `pkg_hint` / `pkg_install_cmd`; su OS atomico serve `rpm-ostree` + reboot |
| `ufw` dato per scontato | su Fedora il firewall e' `firewalld`: il comando non fallisce, semplicemente non apre niente | `setup-ollama.sh` gestisce entrambi |
| `df /` per lo spazio disco | su ostree e' l'overlay composefs (~meta' della RAM), non il disco | misura `/var` (`vm_disk_path`) |
| `readlink -f` su un symlink assente | stampa il percorso risolto invece di niente | `[ -L ]` prima, poi `readlink` semplice |
| script lanciato da un terminale **Flatpak** | `nvidia-smi`/`virsh`/`docker` "assenti" e `/` a tmpfs, ma l'host li ha | `sandbox_kind()`; gli script che toccano l'host si fermano, `flatpak-spawn --host` per rieseguire |
| `virt-manager` Flatpak scambiato per libvirt | e' solo la GUI: `virt-install`/`virsh`/`cloud-localds` restano assenti | serve il layer sull'host (`rpm-ostree install`) |

## Debito riconosciuto (non nasconderlo, non "risolverlo" di nascosto)

1. Immagine LiteLLM su tag mobile `main-stable` → pinnare un digest sha256
2. Nessun alerting (accettabile per uso personale)
3. Credenziali storiche esposte in un file 664 → **ruotarle** (non risulta fatto)
4. Nessuno scan CVE delle immagini
5. `sync_openrouter.py` esiste ma **non è mai stato eseguito contro OpenRouter
   reale**: la logica è testata contro un gateway finto che replica le semantiche
   verificate nel sorgente di LiteLLM, non contro il servizio
6. **Lo stack non è mai stato deployato**: nessun ✅ del repo significa "visto
   funzionare". Il primo deploy è anche il primo test reale della catena
7. Da ADR-0015 `functional.yml` può fallire davvero, ma **a laptop spento il
   run settimanale risulta rosso**: se diventa costante, la decisione va rivista
8. Il repo è **pubblico**: mai aggiungere `pull_request` ai trigger di un
   workflow `self-hosted` (`GITHUB-SETUP.md` §4), mai versionare FQDN interni,
   nomi macchina o path personali — `test-scripts.sh` §3 lo verifica

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
