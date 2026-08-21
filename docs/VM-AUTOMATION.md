# Automazione VM e LLM locale

Chiude il gap tra procedura *documentata* e procedura *eseguibile* (PRD G6).
Il razionale della scelta cloud-init è in `adr/0011-cloud-init-per-la-vm.md`.

## `scripts/create-vm.sh` — VM riproducibile

```bash
./scripts/create-vm.sh --dry-run          # vedi cosa farebbe
./scripts/create-vm.sh                    # crea con i default
VM_NAME=llm-vm VM_IP=192.168.122.50 VM_RAM_MB=4096 ./scripts/create-vm.sh
./scripts/create-vm.sh --destroy          # rimuove (chiede il nome per conferma)
```

Cosa fa, in ordine: verifica i prerequisiti → scarica la cloud image Debian
(con cache) → crea il disco **qcow2 thin** (obbligatorio per gli snapshot) →
genera cloud-init (utente + chiave SSH, docker dal repo Debian, `daemon.json`
con log driver `local` e `live-restore`, journald dimensionato sulla VM) →
**crea la riserva DHCP** così l'IP non cambia mai → `virt-install --import` →
autostart → attende il provisioning e verifica docker.

Prerequisiti sull'host:
```bash
sudo apt install -y libvirt-daemon-system virtinst cloud-image-utils qemu-utils wget
ssh-keygen -t ed25519      # se non hai già una chiave
```

Variabili: `VM_NAME VM_IP VM_RAM_MB VM_VCPU VM_DISK_GB VM_USER SSH_KEY POOL_DIR NET IMG_URL`.

> `VM-DEBIAN-INSTALL.md` resta valido come **fallback manuale** e per capire
> cosa lo script automatizza (in particolare il passo `tasksel`, che è ciò che
> distingue una VM da 1.5 GB da una da 4 GB).

**Subito dopo la creazione**, prima di installare i servizi:
```bash
virsh -c qemu:///system snapshot-create-as llm-vm clean-install
```

## `scripts/setup-ollama.sh` — LLM locale configurato

```bash
./scripts/setup-ollama.sh --dry-run
./scripts/setup-ollama.sh
MODEL=qwen2.5-coder:7b ./scripts/setup-ollama.sh    # forza il modello
```

Applica ciò che `detect-hardware.sh` si limitava a stampare: sceglie il modello
in base alla VRAM (con offload parziale se la RAM lo consente), scrive
l'override systemd con **bind su virbr0 — mai `0.0.0.0`**, applica il tuning per
VRAM stretta (`FLASH_ATTENTION`, `KV_CACHE_TYPE=q8_0`, `KEEP_ALIVE` su laptop),
apre il firewall solo alla subnet libvirt, scarica i modelli e **verifica la
raggiungibilità dalla VM** — non solo dall'host, che è il test che conta.

Al termine stampa il blocco pronto per `services/litellm_config.yaml`.

⚠️ Ollama **non ha autenticazione**: è per questo che il bind è ristretto al
bridge libvirt. Non modificarlo in `0.0.0.0` "per comodità".

## Ciclo completo da zero
```bash
./scripts/detect-hardware.sh --emit-config
./scripts/create-vm.sh
virsh -c qemu:///system snapshot-create-as llm-vm clean-install
scp -r services/ $USER@192.168.122.50:~/llm-services/
# ...compila .env nella VM, docker compose up -d...
./scripts/deploy-all.sh 2      # forward host→VM
./scripts/setup-ollama.sh
./scripts/test-all.sh
```
Oppure, guidato: `./scripts/deploy-all.sh` (le fasi 1 e 6 invocano questi script).
