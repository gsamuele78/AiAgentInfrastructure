#!/usr/bin/env bash
# ============================================================
#  create-vm.sh -- crea la VM dei servizi in modo RIPRODUCIBILE.
#  Usa le cloud image Debian + cloud-init: nessuna installazione
#  interattiva, nessun tasksel da ricordare. La VM nasce già con
#  docker, utente, chiave SSH e IP riservato.
#
#  Chiude il gap: VM-DEBIAN-INSTALL.md documentava la procedura
#  manuale; questo la esegue (PRD G6: deploy senza conoscenza tacita).
#
#  Uso:  ./create-vm.sh                      valori di default
#        VM_NAME=llm-vm VM_IP=192.168.122.50 ./create-vm.sh
#        ./create-vm.sh --dry-run
#        ./create-vm.sh --destroy             rimuove la VM
# ============================================================
set -uo pipefail

VM_NAME="${VM_NAME:-llm-vm}"
VM_IP="${VM_IP:-192.168.122.50}"
VM_RAM_MB="${VM_RAM_MB:-4096}"
VM_VCPU="${VM_VCPU:-2}"
VM_DISK_GB="${VM_DISK_GB:-20}"
# $USER puo' non essere impostato (cron, container, CI): fallback su id -un,
# altrimenti `set -u` fa fallire il dry-run su una macchina pulita (TC-08).
VM_USER="${VM_USER:-${USER:-$(id -un)}}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519.pub}"
POOL_DIR="${POOL_DIR:-/var/lib/libvirt/images}"
NET="${NET:-default}"
# Cloud image Debian 13 (trixie). Aggiorna se cambia la stable.
IMG_URL="${IMG_URL:-https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2}"
CACHE="${CACHE:-$HOME/.cache/libvirt-images}"

DRY=0; DESTROY=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --destroy) DESTROY=1;; esac; done
run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else eval "$*"; fi; }
say(){ echo -e "\n\033[36m━━ $* ━━\033[0m"; }
ok(){ echo -e "  \033[32m✓\033[0m $*"; }
warn(){ echo -e "  \033[33m!\033[0m $*"; }
die(){ echo -e "  \033[31m✗\033[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------- destroy
if [ "$DESTROY" = 1 ]; then
  say "Rimozione VM $VM_NAME"
  read -rp "  Confermi la distruzione di '$VM_NAME' e del suo disco? [scrivi il nome] " c
  [ "$c" = "$VM_NAME" ] || die "annullato"
  virsh -c qemu:///system destroy "$VM_NAME" 2>/dev/null || true
  virsh -c qemu:///system undefine "$VM_NAME" --nvram --remove-all-storage 2>/dev/null || true
  ok "VM rimossa"; exit 0
fi

# ---------------------------------------------------------------- checks
# TC-08: in --dry-run un prerequisito mancante e' un AVVISO, non un errore.
# Il dry-run deve completare anche su una macchina che non ha nulla installato:
# serve a leggere cosa farebbe, non a verificare che si possa fare.
miss(){ if [ "$DRY" = 1 ]; then warn "$*"; else die "$*"; fi; }

say "1. Prerequisiti"
MISSING=0
for t in virt-install virsh qemu-img cloud-localds wget; do
  command -v "$t" >/dev/null || { MISSING=1; miss "manca '$t' — sudo apt install -y libvirt-daemon-system virtinst cloud-image-utils qemu-utils wget"; }
done
[ "$MISSING" = 0 ] && ok "strumenti presenti"
[ -r "$SSH_KEY" ] && ok "chiave SSH: $SSH_KEY" \
  || miss "chiave SSH non trovata: $SSH_KEY  (ssh-keygen -t ed25519)"
if command -v virsh >/dev/null 2>&1; then
  virsh -c qemu:///system net-info "$NET" >/dev/null 2>&1 || miss "rete libvirt '$NET' assente"
  virsh -c qemu:///system net-info "$NET" 2>/dev/null | grep -q 'Active:.*yes' \
    || run "virsh -c qemu:///system net-start $NET"
  ok "rete '$NET' attiva"
  if virsh -c qemu:///system dominfo "$VM_NAME" >/dev/null 2>&1; then
    die "la VM '$VM_NAME' esiste già. Usa --destroy oppure VM_NAME=altro"
  fi
fi

# ---------------------------------------------------------------- image
say "2. Cloud image Debian"
mkdir -p "$CACHE"
BASE="$CACHE/$(basename "$IMG_URL")"
if [ ! -f "$BASE" ]; then
  run "wget -q --show-progress -O '$BASE.tmp' '$IMG_URL' && mv '$BASE.tmp' '$BASE'"
  ok "scaricata"
else ok "già in cache: $BASE"; fi
# NB: verifica la firma con SHA512SUMS+SHA512SUMS.sign se ti serve la catena completa.

DISK="$POOL_DIR/${VM_NAME}.qcow2"
say "3. Disco qcow2 (${VM_DISK_GB}G, thin)"
# qcow2 obbligatorio: senza, niente snapshot virsh.
run "sudo qemu-img create -f qcow2 -F qcow2 -b '$BASE' '$DISK' ${VM_DISK_GB}G"
ok "$DISK (backing file: immagine base, thin)"

# ---------------------------------------------------------------- cloud-init
say "4. cloud-init (utente, docker, hardening)"
SEED_DIR=$(mktemp -d); trap 'rm -rf "$SEED_DIR"' EXIT
PUBKEY=$(cat "$SSH_KEY" 2>/dev/null || echo "ssh-ed25519 CHIAVE-ASSENTE (dry-run)")
cat > "$SEED_DIR/user-data" <<CIEOF
#cloud-config
hostname: ${VM_NAME}
fqdn: ${VM_NAME}.local
manage_etc_hosts: true

users:
  - name: ${VM_USER}
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - ${PUBKEY}

# Solo chiave SSH: nessuna password, nessun login root.
ssh_pwauth: false
disable_root: true

package_update: true
packages:
  - ca-certificates
  - curl
  - qemu-guest-agent      # serve a 'virsh domifaddr'
  - rsync

write_files:
  # Hardening docker (vedi docs/DOCKER-HARDENING.md)
  - path: /etc/docker/daemon.json
    content: |
      {
        "log-driver": "local",
        "log-opts": { "max-size": "10m", "max-file": "5" },
        "live-restore": true
      }
  # journald dimensionato sulla VM: NON i valori del server BIOME
  - path: /etc/systemd/journald.conf.d/99-vm.conf
    content: |
      [Journal]
      Storage=persistent
      Compress=yes
      SystemMaxUse=500M
      SystemKeepFree=2G
      MaxRetentionSec=1month

runcmd:
  - systemctl enable --now qemu-guest-agent
  # Docker dal repo ufficiale DEBIAN (non ubuntu!)
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  - chmod a+r /etc/apt/keyrings/docker.asc
  - |
    echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update -qq
  - DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  - usermod -aG docker ${VM_USER}
  - systemctl restart systemd-journald
  - apt-get --purge autoremove -y -qq && apt-get clean
  - touch /var/lib/cloud/instance/PROVISIONED

final_message: "VM ${VM_NAME} pronta dopo \$UPTIME secondi"
CIEOF

cat > "$SEED_DIR/meta-data" <<CIEOF
instance-id: ${VM_NAME}-$(date +%s)
local-hostname: ${VM_NAME}
CIEOF

SEED="$POOL_DIR/${VM_NAME}-seed.iso"
run "cloud-localds '$SEED_DIR/seed.iso' '$SEED_DIR/user-data' '$SEED_DIR/meta-data'"
run "sudo cp '$SEED_DIR/seed.iso' '$SEED'"
ok "seed cloud-init generato"

# ---------------------------------------------------------------- ip riservato
say "5. Riserva DHCP (IP stabile — vedi docs/VM-KVM-GUIDE.md)"
MAC=$(printf '52:54:00:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
if virsh -c qemu:///system net-dumpxml "$NET" 2>/dev/null | grep -q "ip='$VM_IP'"; then
  echo "  riserva per $VM_IP già presente: la sostituisco"
  run "virsh -c qemu:///system net-update $NET delete ip-dhcp-host \"<host ip='$VM_IP'/>\" --live --config || true"
fi
run "virsh -c qemu:///system net-update $NET add ip-dhcp-host \
  \"<host mac='$MAC' name='$VM_NAME' ip='$VM_IP'/>\" --live --config"
ok "$MAC → $VM_IP (persistente)"

# ---------------------------------------------------------------- create
say "6. Creazione VM"
run "sudo virt-install \
  --name '$VM_NAME' \
  --memory $VM_RAM_MB --vcpus $VM_VCPU \
  --cpu host-passthrough \
  --disk path='$DISK',format=qcow2,bus=virtio \
  --disk path='$SEED',device=cdrom \
  --network network=$NET,mac=$MAC,model=virtio \
  --os-variant debian12 \
  --graphics none --console pty,target_type=serial \
  --import --noautoconsole"
run "virsh -c qemu:///system autostart '$VM_NAME'"
ok "VM creata e impostata in autostart"

# ---------------------------------------------------------------- wait
if [ "$DRY" = 0 ]; then
  say "7. Attesa provisioning (cloud-init installa docker: 2-4 min)"
  for i in $(seq 1 60); do
    if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 \
         "$VM_USER@$VM_IP" 'test -f /var/lib/cloud/instance/PROVISIONED' 2>/dev/null; then
      ok "provisioning completato"; break
    fi
    printf '\r  attesa... %ds' $((i*10)); sleep 10
  done
  echo
  ssh -o ConnectTimeout=5 "$VM_USER@$VM_IP" 'docker --version && docker compose version' 2>/dev/null \
    && ok "docker operativo" || echo -e "  \033[33m!\033[0m docker non ancora pronto: ricontrolla tra un minuto"
fi

cat <<NEXT

  VM:   $VM_NAME   ($VM_VCPU vCPU, ${VM_RAM_MB}MB, ${VM_DISK_GB}G qcow2)
  IP:   $VM_IP     (riserva DHCP: non cambia più)
  SSH:  ssh $VM_USER@$VM_IP

  PROSSIMI PASSI
    1) snapshot pulito PRIMA di installare i servizi:
         virsh -c qemu:///system snapshot-create-as $VM_NAME clean-install
    2) deploy dei servizi:
         scp -r services/ $VM_USER@$VM_IP:~/llm-services/
         ssh $VM_USER@$VM_IP 'cd ~/llm-services && cp .env.example .env && chmod 600 .env'
         # compila .env, poi:  docker compose build && docker compose up -d
    3) forward sull'host:  ./deploy-all.sh 2
NEXT
