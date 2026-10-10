# DEPLOY RUNBOOK — primo deploy reale, passo per passo

| | |
|---|---|
| **Scopo** | chiudere il debito #6 ("lo stack non è mai stato deployato") e produrre le baseline che servono a P0b |
| **Chi lo esegue** | il maintainer, sulla workstation. Nessun agente in cloud può raggiungerla |
| **Durata stimata** | 2–3 ore la prima volta, pause comprese (build dell'immagine e cloud-init sono i passi lenti) |
| **Riferimenti** | [`INSTALL_GUIDE.md`](INSTALL_GUIDE.md) (il *cosa*), questo file (l'*ordine*, i *controlli*, cosa *registrare*) |

`INSTALL_GUIDE.md` resta la descrizione delle fasi. Questo runbook aggiunge
ciò che manca a un primo deploy: un **punto di ritorno prima e dopo ogni passo
rischioso**, un **criterio di superamento** per ogni passo, e una **scheda da
compilare** (in fondo) senza la quale il deploy non vale come baseline.

## Regole del runbook
1. **Un passo alla volta.** Non si passa al successivo se il criterio "✔ passa
   se" non è soddisfatto. Se fallisce: sezione "se fallisce" del passo, poi
   ripeti il passo. Mai "andiamo avanti e vediamo".
2. **Ordine PSE**: la VM va su e viene verificata **prima** di toccare l'host
   (passo 6 prima del 7). Invertirlo lascia senza gateway a metà.
3. **Snapshot** con nomi fissi (`r1-clean-install`, `r3-services-up`,
   `r9-baseline`): servono a misurare il rollback (N3) e a tornare indietro.
4. **Si registra mentre si esegue**, non dopo: ogni passo indica cosa copiare
   nella scheda. Repo pubblico: **niente nomi macchina, FQDN, utenti o path
   personali** nella scheda se finisce in una PR (`test-scripts.sh` §3).
5. Ogni comando si lancia dalla **root del repo**, da un terminale **dell'host**
   (non Flatpak: gli script si fermano da soli con `sandbox_guard`, e su
   Bazzite capita spesso).

## 0. Prima di cominciare (decisioni, 10 minuti)
Compila nella scheda, sezione A. Ognuna cambia un passo.

| Decisione | Opzioni | Cambia |
|---|---|---|
| Host | Debian 13 · Bazzite (variante: desktop / `-nvidia` / `-deck`) · altro | passi 6 (socat), 10 (driver NVIDIA) |
| Installazione | **nuova** · migrazione da uno stack esistente | il passo 7 (pulizia host) si fa **solo** in migrazione |
| Variante Claude Code (`DUAL-AUTH.md`) | A diretto · **B** + headroom (documentata come in uso) · C via LiteLLM | passo 9 |
| Lane locale (Ollama) | sì · no | passo 10 |
| Chiavi API | **nuove** (consigliato: debito #3, le storiche sono esposte) | passo 3 |

```bash
export VM_NAME=llm-vm VM_IP=192.168.122.50 VM_USER="${USER:-$(id -un)}"
```

## 1. Preflight sul repo — nessuna modifica al sistema
```bash
git switch main && git pull --ff-only
git log -1 --format='%h %cI'                    # → scheda B: commit deployato
./scripts/test-scripts.sh                        # L1b
./scripts/devops-audit.sh                        # L4
./scripts/deploy-all.sh --dry-run > /tmp/deploy-dryrun.txt; echo "exit=$?"
./scripts/detect-hardware.sh                     # → scheda B: GPU, VRAM, RAM, OS
```
- ✔ **passa se**: `test-scripts.sh` esce 0; `devops-audit.sh` senza FAIL;
  dry-run `exit=0`; `detect-hardware.sh` vede la GPU che sai di avere (se
  dice "nessuna GPU" e la GPU c'è: è il bug che il controllo sul bus PCI
  dovrebbe evitare — fermati e apri una issue).
- **Se fallisce**: non si deploya un commit rosso. Annota l'errore e torna qui
  dopo la correzione.

## 2. VM: creazione + snapshot `r1-clean-install`
```bash
./scripts/create-vm.sh --dry-run                 # leggi cosa farà
time ./scripts/create-vm.sh                      # → scheda C: durata
ssh "$VM_USER@$VM_IP" 'docker --version && docker compose version && cat /etc/debian_version'
virsh -c qemu:///system snapshot-create-as "$VM_NAME" r1-clean-install --description "runbook passo 2"
```
- ✔ **passa se**: SSH entra senza password, docker risponde, la VM è Debian 13;
  `virsh snapshot-list "$VM_NAME"` mostra `r1-clean-install`.
- **Se fallisce**: `create-vm.sh` stampa l'elenco **completo** dei prerequisiti
  mancanti col comando d'installazione per il tuo OS (su Bazzite è
  `rpm-ostree install …` + reboot). Per ricominciare: `./scripts/create-vm.sh --destroy`.

## 3. Servizi nella VM
> `./scripts/deploy-all.sh 1` esegue gli stessi comandi (rispondi "s" alla
> creazione della VM, già fatta al passo 2). Nel primo deploy conviene farli a
> mano: la scheda C chiede la durata della build e gli ID delle immagini.
```bash
ssh "$VM_USER@$VM_IP" 'mkdir -p ~/llm-services'
# services/* non include i dotfile: .env.example va nominato. Un services/.env
# locale, se esiste, resta fuori apposta. backup-db.sh non sta in services/ (rilievo A17).
scp services/* services/.env.example scripts/backup-db.sh "$VM_USER@$VM_IP":~/llm-services/
ssh "$VM_USER@$VM_IP"
# --- dentro la VM ---
cd ~/llm-services && ls -A      # Dockerfile docker-compose.yml litellm_config.yaml ... backup-db.sh .env.example
cp .env.example .env && chmod 600 .env
for v in POSTGRES_PASSWORD LITELLM_MASTER_KEY VLLM_API_KEY; do echo "$v=$(openssl rand -hex 32)"; done
$EDITOR .env      # incolla i tre valori sopra (la master key con prefisso sk-) + le TUE chiavi API nuove
stat -c '%a %n' .env                             # deve essere 600
time docker compose build                        # → scheda C: durata build
docker compose up -d
docker compose ps                                # litellm e db "healthy"
curl -fsS http://127.0.0.1:4000/health/liveliness; echo
docker image inspect litellm-headroom:local --format '{{.Id}}'   # → scheda C
docker compose images                            # → scheda C: immagini e tag effettivi
exit
# --- di nuovo sull'host ---
virsh -c qemu:///system snapshot-create-as "$VM_NAME" r3-services-up --description "runbook passo 3"
```
- ✔ **passa se**: `.env` è 600; `docker compose build` termina con
  `HeadroomCallback OK` (è il gate nel Dockerfile); entrambi i container
  `healthy`; `liveliness` risponde.
- **Se fallisce**:
  - build rossa su `HeadroomCallback` → la versione di headroom-ai non espone
    più il callback: annota la versione, non forzare;
  - `litellm` non diventa healthy → `docker compose logs litellm | tail -50`:
    di solito una variabile del `.env` mancante (LiteLLM risolve
    `os.environ/` al boot, anche `VLLM_API_KEY` deve esistere);
  - per ripartire puliti: `virsh snapshot-revert "$VM_NAME" r1-clean-install`.

## 4. Forward host → VM
```bash
./scripts/deploy-all.sh 2
curl -fsS http://127.0.0.1:4000/health/liveliness; echo
systemctl --user is-active litellm-forward.service
```
- ✔ **passa se**: `liveliness` risponde **dall'host** su `127.0.0.1:4000`.
- **Se fallisce**: IP in `~/.config/litellm/forward.env` uguale a `$VM_IP`?
  (trappola: l'IP della VM cambia senza riserva DHCP). Su Bazzite: `socat`
  richiede `rpm-ostree install socat` **e un reboot** prima di ripetere.

## 5. Gateway: prima verifica reale
```bash
# La master key sull'host vive in un file 600, mai in una variabile scritta a mano:
install -d -m 700 ~/.config/litellm
( umask 077; ssh "$VM_USER@$VM_IP" "sed -n 's/^LITELLM_MASTER_KEY=//p' ~/llm-services/.env" > ~/.config/litellm/master.key )
stat -c '%a' ~/.config/litellm/master.key       # 600
. ./clients/shell-env.sh                         # esporta LITELLM_MASTER_KEY dal file
./scripts/test-all.sh prereq
./scripts/test-all.sh gateway                    # → scheda D
```
- ✔ **passa se**: `gateway` senza ✗: liveness, modelli > 0, gruppo `auto`,
  completion end-to-end, spend tracking.
- **Se fallisce**: `completion fallita` = chiave API sbagliata o senza credito
  nel `.env` della VM. Correggi il `.env`, `docker compose up -d`, ripeti.

## 6. Catena reale: compressione e cache (TC-01, TC-09)
```bash
./scripts/test-all.sh compress                   # TC-01 → scheda D: rapporto di compressione
./scripts/test-all.sh cache                      # TC-09 → scheda D: anello di auto, token in cache
```
- ✔ **passa se**: TC-01 mostra una compressione misurabile; TC-09 dice
  `auto risponde (anello: …)` e `prompt caching ATTIVO (N token…)`.
- **Se fallisce**: **è un risultato, non un intoppo**. TC-09 rosso con la
  compressione attiva è esattamente l'ipotesi "headroom destabilizza il
  prefisso" di ADR-0016: annotalo così com'è nella scheda, con l'output. Non
  disattivare headroom per far passare il test.

## 7. Pulizia host — **solo in migrazione**
Installazione nuova: salta al passo 8.
```bash
./scripts/cleanup-host.sh --dry-run              # leggi TUTTO
KEEP_HEADROOM=1 ./scripts/cleanup-host.sh        # KEEP_HEADROOM=1 se usi la variante B
./scripts/test-all.sh gateway                    # il gateway deve essere ancora vivo
```
- ✔ **passa se**: `gateway` resta verde dopo la pulizia.
- **Se fallisce**: `cleanup-host.sh` controlla il gateway *prima* di pulire
  (invariante #10); se si è fermato lì, il problema è a monte (passo 4).

## 8. Tooling e config dei client
```bash
./scripts/stack-selective-install.sh --dry-run "$PWD" | tee /tmp/install-dryrun.txt
SKIP_CLAUDE_SETTINGS=1 ./scripts/stack-selective-install.sh "$PWD"   # togli SKIP_… solo per la variante C
./scripts/stack-selective-install.sh --dry-run "$PWD" | grep -c '\[dry\]'   # → scheda C: azioni al 2° run
./scripts/audit-integration.py                   # L3
```
- ✔ **passa se**: `audit-integration.py` senza FAIL; `.serena/project.yml` del
  repo segnalato "già conforme, nessuna scrittura".
- **Da sapere**: il secondo dry-run conta ancora delle azioni, perché gli
  installer attuali non sono idempotenti (rilievo A8, si chiude con P3). Il
  numero va nella scheda: è la **baseline** della metrica "cambiamenti al 2°
  run" di P3.
- Rimetti le tue chiavi negli MCP (`example-key` nei file copiati).

## 9. Doppia autenticazione (Claude Code)
```bash
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
env | grep -c '^ANTHROPIC_' || true              # 0 nella shell normale
./scripts/test-all.sh claude                     # TC-04
```
Poi in `claude`: `/status` deve mostrare l'**abbonamento**, non una API key
(trappola: `ANTHROPIC_API_KEY` residua = fatturazione a consumo silenziosa).
- ✔ **passa se**: `/status` mostra l'abbonamento; `test-all.sh claude` senza ✗.

## 10. LLM locale (deciso dall'hardware, opzionale)
```bash
./scripts/setup-ollama.sh --plan                 # → scheda D: verdetto e modelli
./scripts/setup-ollama.sh --dry-run
./scripts/setup-ollama.sh; echo "exit=$?"        # → scheda D: token/s del modello principale
./scripts/setup-ollama.sh; echo "exit=$?"        # 2° run: deve dire "nessuna modifica" (idempotenza)
./scripts/test-all.sh local
./scripts/test-all.sh cache                      # ripeti: ora l'anello di auto dovrebbe essere locale
```
- **Il piano**: i modelli sono quelli del gateway (3b per local-fast, 7b per
  local-good e `auto`); l'hardware decide quali entrano. Su questo laptop
  (4 GB VRAM, 31 GB RAM) il verdetto atteso è `gpu-offload`, 3b + 7b.
  Se `--plan` dice altro, annotalo: è una delle stime da confermare (ADR-0023).
- ✔ **passa se**: exit 0; Ollama ascolta **solo** su `192.168.122.1:11434`
  (lo script annulla il run se lo trova su `0.0.0.0`); il modello principale
  risponde; il 2° run non cambia niente; `cache` riporta un anello locale.
- **Exit 1** = un passo è fallito e il run **è già stato annullato**: l'output
  dice quale. **Exit 2** = prerequisito mancante (virbr0 o OS atomico), nessuna
  modifica. **Exit 3** = hardware non adatto, nessuna modifica.
- **Prova il rollback e la rimozione** (servono a TC-11 e a sapere che funzionano):
  ```bash
  ./scripts/setup-ollama.sh --rollback --list
  ./scripts/setup-ollama.sh --remove --keep-models --dry-run   # leggi cosa toglierebbe
  ```
  Il rollback vero (`--rollback`) toglie anche i modelli scaricati: fallo solo
  se vuoi ripartire, poi rilancia `./scripts/setup-ollama.sh`.
- Bazzite: senza un servizio di sistema `ollama` lo script si ferma con le
  alternative (exit 2). **Non** fare il rebase dell'immagine dentro questo
  runbook: è S1 (ADR-0018), richiede reboot; registra "lane locale: rinviata".

## 11. Verifica completa, baseline, backup e restore (TC-05, TC-06)
```bash
./scripts/test-all.sh 2>&1 | tee /tmp/test-all.txt; echo "exit=$?"   # → scheda D: ✓/✗/–
./scripts/devops-audit.sh
virsh -c qemu:///system snapshot-create-as "$VM_NAME" r9-baseline --description "runbook passo 11: stack ok"
ssh "$VM_USER@$VM_IP" 'cd ~/llm-services && ./backup-db.sh'
VM_SSH="$VM_USER@$VM_IP" ./scripts/restore-test.sh                  # TC-05: OBBLIGATORIO
```
**TC-06 — il rollback funziona ed è sotto i 5 minuti (N3):**
```bash
ssh "$VM_USER@$VM_IP" 'cd ~/llm-services && docker compose stop litellm'   # guasto simulato
curl -fsS --max-time 3 http://127.0.0.1:4000/health/liveliness || echo "giù (atteso)"
time virsh -c qemu:///system snapshot-revert "$VM_NAME" r9-baseline --running
until curl -fsS --max-time 3 http://127.0.0.1:4000/health/liveliness >/dev/null; do sleep 5; done; echo "di nuovo su"
```
- ✔ **passa se**: `test-all.sh` senza ✗ (gli `–` vanno spiegati nella scheda);
  `restore-test.sh` verde; dopo il revert il gateway torna su, e il tempo
  totale dal revert alla liveness è < 5 minuti → scheda C.

## 12. Chiusura
1. Copia la scheda compilata (sotto) in una PR **o** in
   `docs/PLAN-STACK-VALIDATION.md`, "Registro baseline e misure": è la prima
   riga reale del registro e il prerequisito di P0b.
2. In `AGENTS.md`, debito #6: da "mai deployato" a "deployato il <data>,
   commit <hash>" — **solo** se i passi 1–6 e 11 sono passati. Un deploy con
   TC-09 rosso è comunque un deploy: si scrive con l'esito vero.
3. Se le chiavi API sono nuove, il debito #3 (rotazione) si può chiudere: dillo
   esplicitamente nella PR.

---

## Scheda da compilare
Copia questo blocco in un file **fuori dal repo** mentre esegui; in PR solo
dopo aver tolto nomi macchina e path personali.

```text
A. DECISIONI
   host OS / variante ............: 
   installazione (nuova/migraz.) .: 
   variante Claude Code (A/B/C) ..: 
   lane locale (sì/no/rinviata) ..: 
   chiavi API nuove (sì/no) ......: 

B. PREFLIGHT (passo 1)
   commit deployato (hash, data) .: 
   test-scripts ✓/✗ ..............: 
   devops-audit FAIL/WARN ........: 
   GPU / VRAM / RAM (detect-hw) ..: 

C. OPERATIVITÀ
   durata create-vm (passo 2) ....: 
   durata docker compose build ...: 
   immagine litellm (Id, tag) ....: 
   azioni al 2° dry-run installer : 
   tempo revert → liveness (TC-06): 

D. CATENA REALE
   test-all gateway ✓/✗ ..........: 
   TC-01 compressione (raw→compr.): 
   TC-09 anello di auto ..........: 
   TC-09 token letti dalla cache .: 
   TC-04 /status = abbonamento ...: 
   lane locale: verdetto (--plan) : 
   lane locale: token/s (prova) ..: 
   lane locale: 2° run = 0 modif. : 
   lane locale: anello per auto ..: 
   test-all completo ✓ / ✗ / – ...: 
   restore-test (TC-05) ..........: 

E. NOTE (ogni ✗ con l'output, ogni passo saltato con il motivo)
```
