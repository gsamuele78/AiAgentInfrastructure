# shellcheck shell=bash
# ============================================================
#  hw-detect.sh -- rilevamento hardware e OS, condiviso fra
#  detect-hardware.sh e setup-ollama.sh. Va SORGATO, non eseguito.
#
#  Principio: non si deduce un fatto sul sistema da un indizio che
#  vale solo su alcune distribuzioni. La GPU si cerca sul bus PCI,
#  non nella presenza di `nvidia-smi`; i comandi di installazione
#  dipendono dalla famiglia dell'OS, non da un `apt` dato per scontato.
# ============================================================

# Radici sovrascrivibili: servono a TESTARE il rilevamento (non si puo'
# procurarsi una GPU NVIDIA o un OS atomico dentro la CI). In esercizio
# restano i default e il comportamento e' identico.
: "${SYSFS_ROOT:=/sys}"
: "${OS_RELEASE_FILE:=/etc/os-release}"
: "${OSTREE_MARKER:=/run/ostree-booted}"

# --- OS ---------------------------------------------------------------
# Famiglie: ostree (Fedora atomico: Silverblue/Kinoite/Bazzite/Bluefin),
# fedora, debian, arch, suse, unknown.
os_field(){ [ -r "$OS_RELEASE_FILE" ] && sed -n "s/^$1=//p" "$OS_RELEASE_FILE" | tr -d '"' | head -1; }

os_pretty(){ os_field PRETTY_NAME || echo "sconosciuto"; }

os_is_atomic(){ [ -f "$OSTREE_MARKER" ] || command -v rpm-ostree >/dev/null 2>&1; }

# uBlue = Bazzite / Bluefin / Aurora: hanno `ujust` con ricette proprie.
os_is_ublue(){ command -v ujust >/dev/null 2>&1; }

os_family(){
  local id like
  id=$(os_field ID); like=$(os_field ID_LIKE)
  if os_is_atomic; then echo ostree; return; fi
  case " $id $like " in
    *" debian "*|*" ubuntu "*) echo debian ;;
    *" fedora "*|*" rhel "*|*" centos "*) echo fedora ;;
    *" arch "*) echo arch ;;
    *" suse "*|*" opensuse "*) echo suse ;;
    *) echo unknown ;;
  esac
}

# Comando d'installazione corretto per la famiglia. $1 = 'libvirt' | 'docker'.
# I nomi dei pacchetti cambiano fra distribuzioni: qui stanno quelli che
# servono davvero a create-vm.sh (virt-install, virsh, qemu-img, cloud-localds).
pkg_hint(){
  case "$(os_family):$1" in
    ostree:libvirt) echo "rpm-ostree install libvirt virt-install virt-manager cloud-utils qemu-img && systemctl reboot" ;;
    fedora:libvirt) echo "sudo dnf install -y libvirt virt-install virt-manager cloud-utils qemu-img" ;;
    debian:libvirt) echo "sudo apt install -y libvirt-daemon-system virtinst virt-manager cloud-image-utils qemu-utils" ;;
    arch:libvirt)   echo "sudo pacman -S --needed libvirt virt-install virt-manager qemu-img  # cloud-image-utils: AUR" ;;
    suse:libvirt)   echo "sudo zypper install -y libvirt virt-install virt-manager cloud-utils" ;;
    *:libvirt)      echo "installa: libvirt, virt-install, virt-manager, qemu-img, cloud-localds" ;;
    ostree:docker)  echo "serve solo NELLA VM. Sull'host un OS atomico ha gia' podman; per docker: rpm-ostree install docker-ce (richiede reboot)" ;;
    fedora:docker)  echo "serve solo NELLA VM (sull'host basta podman)" ;;
    debian:docker)  echo "serve solo NELLA VM: docs/VM-AUTOMATION.md" ;;
    *:docker)       echo "serve solo NELLA VM" ;;
    *) echo "installa: $1" ;;
  esac
}

# Comando per installare UN pacchetto con lo stesso nome ovunque (es. socat).
# Torna stringa vuota sugli OS atomici: li' non si installa al volo, serve
# rpm-ostree e un reboot -- il chiamante deve avvisare, non eseguire.
pkg_install_cmd(){
  case "$(os_family)" in
    debian) echo "sudo apt install -y $1" ;;
    fedora) echo "sudo dnf install -y $1" ;;
    arch)   echo "sudo pacman -S --needed $1" ;;
    suse)   echo "sudo zypper install -y $1" ;;
    *)      echo "" ;;
  esac
}

# --- GPU NVIDIA -------------------------------------------------------
# Indirizzi PCI delle GPU NVIDIA presenti FISICAMENTE, senza dipendere da
# driver o tool: vendor 0x10de e classe 0x03xx (display controller).
# Funziona anche a driver scaricato, dGPU spenta o nvidia-smi assente --
# i tre casi in cui `command -v nvidia-smi` mente.
nvidia_pci_devices(){
  local d v c
  for d in "$SYSFS_ROOT"/bus/pci/devices/*/; do
    [ -r "${d}vendor" ] && [ -r "${d}class" ] || continue
    read -r v < "${d}vendor" || continue
    [ "$v" = "0x10de" ] || continue
    read -r c < "${d}class" || continue
    case "$c" in 0x03*) basename "$d" ;; esac
  done
}

# Nome leggibile della GPU. lspci se c'e', altrimenti l'id PCI grezzo:
# meglio "10de:2820" di niente.
nvidia_pci_name(){
  local addr="$1" out dev
  if command -v lspci >/dev/null 2>&1; then
    out=$(lspci -s "$addr" 2>/dev/null | sed 's/^[^ ]* //')
    [ -n "$out" ] && { echo "$out"; return; }
  fi
  dev=$(sed 's/^0x//' "$SYSFS_ROOT/bus/pci/devices/$addr/device" 2>/dev/null)
  echo "NVIDIA [10de:${dev:-????}]"
}

# Driver attualmente legato al dispositivo (nvidia, nouveau, vfio-pci, oppure vuoto).
nvidia_pci_driver(){
  # Due trappole: `readlink -f` su un percorso inesistente stampa comunque il
  # percorso risolto (si otterrebbe "driver" invece di niente), e fallisce se
  # un componente intermedio manca. `readlink` semplice legge il target del
  # symlink cosi' com'e', che e' esattamente quello che serve.
  local p="$SYSFS_ROOT/bus/pci/devices/$1/driver" l
  [ -L "$p" ] || return 0
  l=$(readlink "$p" 2>/dev/null) && [ -n "$l" ] && basename "$l"
}

# Come nvidia_pci_driver ma non torna mai vuoto: per la stampa.
nvidia_pci_driver_label(){ local d; d=$(nvidia_pci_driver "$1"); echo "${d:-nessuno}"; }

nvidia_kernel_module_loaded(){ [ -e /proc/driver/nvidia/version ]; }

# Perche' nvidia-smi non c'e', in una riga, con il rimedio giusto per QUESTO OS.
nvidia_missing_hint(){
  local drv="${1:-}"
  # Lo stato del driver viene PRIMA della famiglia dell'OS: se la GPU e' in
  # passthrough o su nouveau, il consiglio di cambiare immagine e' fuori bersaglio.
  case "$drv" in
    vfio-pci) echo "GPU assegnata a VFIO (passthrough): l'host non la usa. ADR-0008 sceglie Ollama sull'host, quindi qui il passthrough e' di troppo."; return ;;
    nouveau)  echo "driver in uso: nouveau (open source). nvidia-smi arriva solo col driver proprietario." ;;
  esac
  if os_is_ublue && os_is_atomic; then
    echo "immagine senza driver proprietari. Su Bazzite/uBlue il driver sta NELL'IMMAGINE:" \
         "rpm-ostree rebase ostree-unverified-registry:ghcr.io/ublue-os/bazzite-nvidia:stable" \
         "(o -gnome-nvidia), poi reboot. 'ujust --list' per le ricette del tuo sistema."
  elif os_is_atomic; then
    echo "OS atomico: i driver NVIDIA si aggiungono con rpm-ostree (o cambiando immagine), non con dnf install."
  else
    case "$drv" in
      nouveau) : ;;   # gia' detto sopra
      "") echo "nessun driver legato al dispositivo: dGPU spenta (Optimus/supergfxctl) o driver non installato." ;;
      *) echo "driver in uso: $drv. Installa gli strumenti NVIDIA per avere nvidia-smi." ;;
    esac
  fi
}

# --- Disco ------------------------------------------------------------
# Il filesystem che ospitera' davvero il disco della VM. Su un OS atomico
# `df /` riporta l'overlay composefs (dimensione ~ meta' della RAM), che non
# c'entra nulla con lo spazio disponibile per un qcow2.
vm_disk_path(){
  local p
  for p in /var/lib/libvirt/images /var/lib/libvirt /var; do
    [ -d "$p" ] && { echo "$p"; return; }
  done
  echo /
}
