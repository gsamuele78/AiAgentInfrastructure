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

## Setup
```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen2.5-coder:3b && ollama pull qwen2.5-coder:7b
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
```
```bash
sudo systemctl daemon-reload && sudo systemctl restart ollama
ss -tlnp | grep 11434            # atteso 192.168.122.1:11434
sudo ufw allow from 192.168.122.0/24 to any port 11434 proto tcp   # se ufw attivo
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
La topologia non cambia: sposti solo `api_base`.

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
| Firewall | `firewalld`, non `ufw` — `setup-ollama.sh` usa una *rich rule* per aprire la 11434 solo alla subnet libvirt |
| Spazio disco | `df /` riporta l'overlay **composefs** (circa metà della RAM): per il qcow2 conta `/var`, ed è quello che lo script misura |

Ollama stesso si installa senza problemi: `/usr/local` è un symlink a
`/var/usrlocal`, scrivibile, e l'unit systemd finisce in `/etc/systemd/system`.
