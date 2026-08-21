# VM Debian minimale per Docker — network install

Obiettivo: la VM più piccola che regga `litellm + postgres`. ~1.5 GB installati.

## ISO (stable = Debian 13 "trixie")
| Opzione | Dim. | URL |
|---|---|---|
| **mini.iso** (netboot, la più piccola) | ~60 MB | `https://deb.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/mini.iso` |
| **netinst** (consigliata, più robusta) | ~700 MB | `https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso` |

Usa il path `current/` per non restare su una versione vecchia. Verifica sempre:
```bash
wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA512SUMS
sha512sum -c SHA512SUMS --ignore-missing
```

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
usermod -aG sudo jfs && systemctl enable --now qemu-guest-agent

# Docker: repo ufficiale DEBIAN (non ubuntu!)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker jfs
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
