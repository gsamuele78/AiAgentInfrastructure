# VM Debian minimale per Docker — network install

Obiettivo: la VM più piccola che regga `litellm + postgres`. ~1.5 GB installati.

## ISO (stable = Debian 13 "trixie")
| Opzione | Dim. | URL |
|---|---|---|
| **mini.iso** (netboot, la più piccola) | ~60 MB | `https://deb.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/mini.iso` |
| **netinst** (consigliata, più robusta) | ~700 MB | vedi sotto: il nome del file cambia a ogni point release |

Il path `current/` punta sempre alla stable in corso, ma **il nome del file
contiene la point release** (`debian-13.X.Y-amd64-netinst.iso`) e cambia ogni
paio di mesi: scriverlo a mano qui significa scrivere un link che marcisce.
Ricavalo dall'indice, che è anche il modo di verificare il checksum:

```bash
BASE=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
wget -q "$BASE/SHA512SUMS"
ISO=$(awk '/-netinst\.iso$/{print $2; exit}' SHA512SUMS)   # nome corrente
wget "$BASE/$ISO"
sha512sum -c SHA512SUMS --ignore-missing
```

> Percorso automatico consigliato: `scripts/create-vm.sh` usa la **cloud image**
> (`debian-13-genericcloud-amd64.qcow2`), il cui URL non contiene la point
> release e quindi non invecchia. Questa pagina è il fallback manuale.

## Risorse
| Risorsa | Valore | Perché |
|---|---|---|
| vCPU | 2 | i limiti compose sono 2.0 + 1.0 |
| RAM | **4 GB** | compose usa 3G + OS. Con 2 GB va in OOM |
| Disco | 20 GB **qcow2** thin | qcow2 OBBLIGATORIO per gli snapshot |
| Firmware | UEFI (OVMF) | default moderno |
| Rete | NAT default (virbr0) | l'host raggiunge la VM, niente esposizione LAN |
| Disco bus | VirtIO | performance |

## Il passo che decide tutto: tasksel
Deseleziona **TUTTO** con la barra spaziatrice, lascia solo:
```
[ ] Debian desktop environment     <- DESELEZIONA (~2 GB!)
[*] SSH server
[*] standard system utilities
```
Saltarlo è ciò che gonfia la VM da 1.5 GB a oltre 4 GB.
Partizionamento: guidato, tutto in una partizione. Niente LVM/cifratura.

## Post-installazione
```bash
su -
apt update && apt install -y sudo ca-certificates curl qemu-guest-agent
usermod -aG sudo "$VM_USER" && systemctl enable --now qemu-guest-agent

# Docker: repo ufficiale DEBIAN (non ubuntu!)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker "$VM_USER"
# Alternativa: apt install -y docker.io docker-compose-v2

apt-get --purge autoremove -y && apt-get clean
df -h /     # atteso ~1.5-2 GB
```
Per l'hardening (data-root, log driver, live-restore, journald): `DOCKER-HARDENING.md`.

## Verifica
```bash
ip -4 addr show      # deve avere un 192.168.122.x
docker run --rm hello-world
```
