# LLM locale — RTX A2000 Laptop (4 GB VRAM, 31 GB RAM)

> Hardware verificato: RTX A2000 **Laptop**, **4096 MiB**, cap 40 W, driver
> 595.71.05 / CUDA 13.2. Display sull'iGPU → tutta la VRAM è per il compute.

## Ollama sull'host, niente passthrough (ADR-0008)
Il passthrough VFIO **sottrae la GPU all'host in esclusiva**: perderesti CUDA e
l'accelerazione Blender finché la VM è accesa. Su laptop è anche fragile
(Optimus, IOMMU group sporchi). Con una sola GPU: costo alto, beneficio zero.

## Cosa aspettarsi da 4 GB + 31 GB RAM
Con tanta RAM è praticabile l'**offload parziale**: N layer in VRAM, il resto in RAM.

| Modello | Peso Q4 | Strategia | Velocità | Uso |
|---|---|---|---|---|
| `qwen2.5-coder:3b` | ~2.0 GB | tutto in VRAM | ~30-50 tok/s | FIM, interattivo |
| **`qwen2.5-coder:7b`** | ~4.7 GB | **offload ~28/32 layer** | **~8-15 tok/s** | il punto dolce |
| `qwen2.5-coder:14b` | ~9 GB | offload ~14/48 | ~3-5 tok/s | solo batch |
| 30B+ | 18 GB+ | quasi tutto CPU | <2 tok/s | non praticabile |

⚠️ **Mai far toccare lo swap** a Ollama: con 29 GB di swap disponibili, se il
modello ci finisce la velocità crolla di ordini di grandezza. Con 18 GB liberi
sei al sicuro fino ai 14B.

**Verdetto onesto:** un 7B a 8-15 tok/s non sostituisce Claude sul coding
agentico complesso (sbaglia più spesso il tool-calling). Resta Tier 0/1:
- **dati sensibili BIOME** — qui vince a prescindere: nessun provider
- commit message, summarization, rename, classificazione
- FIM/autocomplete (meglio il 3B: più veloce)
- batch notturni via recipe

## Setup automatico (consigliato): `setup-ollama.sh`
```bash
./scripts/setup-ollama.sh --plan        # cosa regge l'hardware, nessuna modifica
./scripts/setup-ollama.sh --dry-run     # cosa farebbe
./scripts/setup-ollama.sh               # installa, configura, verifica
./scripts/setup-ollama.sh --rollback    # annulla l'ultimo run (--list per elencarli)
./scripts/setup-ollama.sh --remove      # disinstalla tutto (--keep-models per tenere i modelli)
```
**Cosa decide l'hardware** (`scripts/lib/llm-plan.sh`, la stessa tabella che
stampa `detect-hardware.sh`): i modelli sono **quelli del gateway**
(`litellm_config.yaml`: `qwen2.5-coder:3b` per local-fast, `qwen2.5-coder:7b`
per local-good e per il primo anello di `auto`). L'hardware sceglie quali
entrano, non ne inventa altri: un 14B che nessuna lane referenzia è spazio
perso, e un `auto` che punta a un modello mai scaricato salta il locale in silenzio.

| Hardware | Verdetto | Modelli |
|---|---|---|
| VRAM ≥ 6.5 GB | `gpu` | 3b + 7b in VRAM |
| VRAM 3.5–6.5 GB, VRAM + RAM utilizzabile ≥ 6.5 GB | `gpu-offload` | 3b in VRAM, 7b in parte in RAM (questo laptop: ~17/28 layer in GPU) |
| VRAM 3.5–6.5 GB, RAM scarsa | `gpu` | solo 3b — `auto` salta il locale |
| Nessuna GPU utile, RAM utilizzabile ≥ 3 GB | `cpu` | solo 3b (lento) — `auto` va al cloud **per scelta**: un 7B a 2–5 token/s come primo anello renderebbe ogni sessione più lenta del cloud |
| RAM o disco insufficienti | `none` | niente: esce 3 senza modifiche |

"RAM utilizzabile" = totale − VM del gateway (`VM_RAM_MB`) − 4 GB per l'host:
la RAM *libera* del momento renderebbe la scelta casuale.

**Verifiche durante l'installazione**: ogni passo controlla il risultato. Se un
controllo *duro* fallisce, il run si **annulla da solo** (registro in
`~/.local/state/aiagentinfra/runs/ollama-*`, `KEEP_ON_FAIL=1` per non farlo):

| Passo | Controllo duro (→ rollback automatico) | Controllo morbido (→ avvertenza) |
|---|---|---|
| binario | `ollama --version` risponde | versione ≠ pin in `stack/versions.conf` |
| servizio | attivo, ascolta su `virbr0:11434`, **mai** su `0.0.0.0`/`[::]` (invariante #3), API risponde | — |
| firewall | — | regola presente nella zona di virbr0 |
| modelli | ogni modello del piano risulta dopo il pull | — |
| prova reale | il modello principale **risponde** a una richiesta | token/s sotto `LLM_MIN_TPS` (5) |
| dalla VM | — | `curl` dalla VM a Ollama |
| gateway | — | ogni lane locale di `litellm_config.yaml` ha il suo modello |

Rilanciarlo è sicuro: un secondo run identico non cambia niente e non lascia
un registro (idempotenza). Il rollback non tocca ciò che c'era prima del run
(un Ollama già installato, modelli già presenti). Prove: `tests/setup-ollama/run.sh`
(48 scenari su un sistema finto, anche in CI).

## Setup manuale (riferimento: è ciò che lo script automatizza)
```bash
curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION=0.35.1 sh
sudo systemctl edit ollama.service
```
```ini
[Unit]
After=libvirtd.service network-online.target
Wants=network-online.target
[Service]
Environment="OLLAMA_HOST=192.168.122.1:11434"   # SOLO virbr0, mai 0.0.0.0
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"          # KV cache: ~metà spazio
Environment="OLLAMA_KEEP_ALIVE=2m"               # laptop
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_CONTEXT_LENGTH=16384"         # = num_ctx della lane auto (ADR-0016)
```
Senza `OLLAMA_CONTEXT_LENGTH` Ollama usa un contesto piccolo e **tronca in
silenzio** i prompt degli agenti. Il valore deve coincidere con `num_ctx` del
gruppo `auto` in `services/litellm_config.yaml` (`test-scripts.sh` lo verifica).
```bash
sudo systemctl daemon-reload && sudo systemctl restart ollama
ss -tlnp | grep 11434            # atteso 192.168.122.1:11434
sudo ufw allow from 192.168.122.0/24 to any port 11434 proto tcp   # se ufw attivo
# il CLI parla a 127.0.0.1 per default: col bind su virbr0 va detto dove
OLLAMA_HOST=192.168.122.1:11434 ollama pull qwen2.5-coder:3b
OLLAMA_HOST=192.168.122.1:11434 ollama pull qwen2.5-coder:7b
```
Perché non `0.0.0.0`: Ollama **non ha autenticazione**; bindarlo ovunque lo
esporrebbe alla LAN.

## Verifica e config
```bash
ssh $VM_USER@192.168.122.50 'curl -s http://192.168.122.1:11434/api/tags'
ssh $VM_USER@192.168.122.50 'cd ~/llm-services && docker compose exec litellm \
  curl -s http://192.168.122.1:11434/api/tags'
```
```yaml
# services/litellm_config.yaml
  - model_name: local-fast          # 3B full-VRAM: latenza bassa, FIM
    litellm_params: { model: ollama_chat/qwen2.5-coder:3b, api_base: http://192.168.122.1:11434 }
  - model_name: local-good          # 7B offload: qualità migliore
    litellm_params: { model: ollama_chat/qwen2.5-coder:7b, api_base: http://192.168.122.1:11434, timeout: 300 }
litellm_settings:
  fallbacks:
    - local: ["local-good", "local-fast"]
```
Tuning offload: `ollama run qwen2.5-coder:7b --verbose` → `/set parameter num_gpu 28`;
`ollama ps` mostra la ripartizione CPU/GPU.

## Se cambi hardware
Con una GPU 12-16 GB (o il cluster BIOME) `qwen2.5-coder:14b` diventa Tier 1.
La topologia non cambia: sposti solo `api_base`. Per usarlo davvero cambia
**prima** le lane in `litellm_config.yaml`, poi rilancia lo script con
`LLM_MODEL_MAIN=qwen2.5-coder:14b`: l'ordine conta, altrimenti `auto` punta a un
modello che non c'è.

## OS atomici (Bazzite, Silverblue, Kinoite, Bluefin)

`detect-hardware.sh` cerca la GPU sul **bus PCI** (`vendor 0x10de`, classe
`0x03xx`), non nella presenza di `nvidia-smi`: dedurre l'hardware da un binario
produce un falso negativo proprio dove capita più spesso — immagine senza
driver proprietari, dGPU spenta da Optimus/supergfxctl, o script eseguito in un
container che non vede i binari dell'host.

**Il driver NVIDIA non si installa: si cambia immagine.** Su Bazzite e sugli
altri uBlue il driver proprietario è dentro l'immagine, quindi:

```bash
# KDE
rpm-ostree rebase ostree-unverified-registry:ghcr.io/ublue-os/bazzite-nvidia:stable
# GNOME
rpm-ostree rebase ostree-unverified-registry:ghcr.io/ublue-os/bazzite-gnome-nvidia:stable
systemctl reboot
```

Poi `nvidia-smi` esiste e `detect-hardware.sh` misura la VRAM come su qualsiasi
altra distribuzione. `ujust --list` mostra le ricette del tuo sistema.

Altre due cose cambiano su un OS atomico, e gli script ne tengono conto:

| Cosa | Su un OS atomico |
|---|---|
| Installare pacchetti | `rpm-ostree install ...` + **reboot**, non `dnf`/`apt` |
| Ollama | l'installer ufficiale crea l'utente `ollama` con home in `/usr/share` (sola lettura): `setup-ollama.sh` **non** lo lancia, si ferma con le alternative (`brew install ollama`, container). Configura e verifica il resto **solo** se esiste un servizio di sistema `ollama`: con brew il servizio è utente, e lo script si fermerebbe al riavvio annullando il run. Non ancora automatizzato (P2, ADR-0018) |
| Firewall | `firewalld`, non `ufw` — `setup-ollama.sh` usa una *rich rule* per aprire la 11434 solo alla subnet libvirt |
| Spazio disco | `df /` riporta l'overlay **composefs** (circa metà della RAM): per il qcow2 conta `/var`, ed è quello che lo script misura |

### Attenzione al sandbox: su Bazzite molte app sono Flatpak

Se lanci gli script da un terminale **Flatpak** (o da una toolbox/distrobox),
non vedi i comandi dell'host: `nvidia-smi`, `virsh` e `docker` risultano
assenti anche quando sull'host ci sono. `/sys` invece è visibile, quindi il
rilevamento PCI della GPU funziona lo stesso — ed è così che si riconosce il
caso: **hardware trovato, `driver: nvidia`, ma `nvidia-smi` non risponde**.

`detect-hardware.sh` lo dice esplicitamente e rilegge ogni «assente» come «non
esposto nel sandbox». Per un quadro vero:

```bash
flatpak-spawn --host ./scripts/detect-hardware.sh   # da un Flatpak
distrobox-host-exec ./scripts/detect-hardware.sh    # da una distrobox
```

Gli script che **modificano l'host** — `setup-ollama.sh`, `create-vm.sh`,
`cleanup-host.sh`, `deploy-all.sh`, `stack-selective-install.sh` — si
**rifiutano di partire** da dentro un sandbox: scriverebbero nel sandbox
lasciando il sistema com'era, e il silenzio è il modo peggiore di sbagliare.
Con `--dry-run` avvisano e proseguono, perché lì non scrivono niente.

> `virt-manager` installato come **Flatpak** (via Bazaar o Discover) è la sola
> GUI: può pilotare un `libvirtd` che gira sull'host, ma non fornisce
> `virt-install`, `virsh`, `qemu-img` e `cloud-localds`, che sono i comandi che
> `create-vm.sh` invoca. Per quelli serve il layer sull'host:
> `rpm-ostree install libvirt virt-install virt-manager cloud-utils qemu-img`
> più un reboot.

Ollama stesso si installa senza problemi: `/usr/local` è un symlink a
`/var/usrlocal`, scrivibile, e l'unit systemd finisce in `/etc/systemd/system`.
