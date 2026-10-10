# shellcheck shell=bash
# ============================================================
#  platform.sh -- dai FATTI (hw-detect.sh) alle SCELTE, per strato (ADR-0018).
#  Va SORGATO dopo hw-detect.sh e journal.sh. Nessuno script esistente lo
#  usa ancora: e' la base su cui P3 (stack.py) costruisce.
#
#  Decisione = una riga  AZIONE|COMANDO|NOTA
#    apply      lo script puo' farlo da solo (reversibile, registrato nel journal)
#    recommend  si stampa il comando, NON si esegue (S1: reboot, rebase, driver)
#    skip       niente da fare
#    stop       da qui non si deve fare (sandbox): rilanciare sull'host
#
#  Regola 2 di ADR-0018: ciò che sta in S1 (pacchetti di sistema, driver) non
#  e' MAI automatico. Su Debian/Fedora classico si applica solo con ALLOW_S1=1;
#  su un OS atomico mai, nemmeno col flag (rpm-ostree = reboot).
#  Tabella verificata da tests/platform/run.sh (TC-13).
# ============================================================

# platform_decide <cosa> [argomento]
#   pkg <nome>     S1: un pacchetto di sistema con lo stesso nome ovunque (es. socat)
#   gpu-driver     S1: driver NVIDIA per la GPU presente sul bus PCI
#   svc            S2: unit systemd in /etc (Ollama, forward)
#   user-tools     S3: tool utente in $HOME, versione dal pin
#   keep-alive     S4: OLLAMA_KEEP_ALIVE dal tipo di macchina
platform_decide(){
  local what=$1 arg=${2:-} sb fam
  sb=$(sandbox_kind); fam=$(os_family)
  case "$what" in
    pkg)
      [ -n "$sb" ] && { echo "stop||sandbox $sb: $(host_run_hint "pkg $arg")"; return; }
      pkg_present "$arg" && { echo "skip||$arg gia' installato"; return; }
      if [ "$fam" = ostree ]; then
        echo "recommend|rpm-ostree install $arg && systemctl reboot|OS atomico: layer + reboot, mai automatico"; return
      fi
      local cmd; cmd=$(pkg_install_cmd "$arg")
      [ -z "$cmd" ] && { echo "recommend|installa $arg|famiglia OS '$fam' sconosciuta"; return; }
      if [ "${ALLOW_S1:-0}" = 1 ]; then echo "apply|$cmd|S1 con ALLOW_S1=1"
      else echo "recommend|$cmd|S1: serve ALLOW_S1=1 per eseguirlo"; fi ;;
    gpu-driver)
      local addr drv
      addr=$(nvidia_pci_devices | head -1)
      [ -z "$addr" ] && { echo "skip||nessuna GPU NVIDIA sul bus PCI"; return; }
      [ -n "$sb" ] && { echo "stop||sandbox $sb: lo stato del driver si vede solo dall'host"; return; }
      drv=$(nvidia_pci_driver "$addr")
      case "$drv" in
        nvidia)   echo "skip||driver nvidia gia' legato a $addr" ;;
        vfio-pci) echo "skip||GPU in passthrough VFIO: l'host non la usa (ADR-0008)" ;;
        *)
          if os_is_ublue && [ "$fam" = ostree ]; then
            echo "recommend|rpm-ostree rebase ostree-unverified-registry:ghcr.io/ublue-os/bazzite-nvidia:stable && systemctl reboot|uBlue: il driver sta nell'immagine (-nvidia)"
          elif [ "$fam" = ostree ]; then
            echo "recommend|rpm-ostree install akmod-nvidia && systemctl reboot|OS atomico: layer del driver + reboot"
          elif [ "$fam" = debian ]; then
            echo "recommend|sudo apt install -y nvidia-driver firmware-misc-nonfree && sudo reboot|Debian: componenti contrib/non-free attivi, poi reboot"
          elif [ "$fam" = fedora ]; then
            echo "recommend|sudo dnf install -y akmod-nvidia && sudo reboot|Fedora: repo RPM Fusion nonfree"
          else
            echo "recommend|installa il driver NVIDIA proprietario|famiglia OS '$fam'"
          fi ;;
      esac ;;
    svc)
      [ -n "$sb" ] && { echo "stop||sandbox $sb: le unit dell'host non si vedono da qui"; return; }
      echo "apply||/etc scrivibile su Debian e sugli OS atomici: render + sha256 + journal" ;;
    user-tools)
      # Modalita' 'warn' di sandbox_guard: dentro un devcontainer configurare
      # i tool utente e' legittimo (stack-selective-install.sh fa lo stesso).
      echo "apply||S3 identico sui due OS: \$HOME, versione dal pin${sb:+ (sandbox $sb: scrive nel sandbox)}" ;;
    keep-alive)
      if [ "$(hw_chassis)" = laptop ]; then echo "apply|OLLAMA_KEEP_ALIVE=2m|laptop: termico e batteria"
      else echo "skip||default di Ollama"; fi ;;
    *) echo "stop||decisione sconosciuta: $what"; return 1 ;;
  esac
}

# pkg_present <nome>: 0 installato, 1 assente, 2 non so dirlo (nessun gestore noto).
pkg_present(){
  case "$(os_family)" in
    debian) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    fedora|ostree|suse) rpm -q "$1" >/dev/null 2>&1 ;;
    arch) pacman -Q "$1" >/dev/null 2>&1 ;;
    *) return 2 ;;
  esac
}

# pkg_add <nome>: esegue SOLO se la decisione e' 'apply'. Ritorna
#   0 fatto o gia' presente · 2 stop (sandbox) · 3 solo raccomandato (stampato)
# Su apply registra nel journal come annullarlo (rimuove solo cio' che ha aggiunto).
pkg_add(){
  local name=$1 action cmd note
  IFS='|' read -r action cmd note <<<"$(platform_decide pkg "$name")"
  case "$action" in
    skip) echo "  $name: $note"; return 0 ;;
    stop) echo "  ✗ $name: $note" >&2; return 2 ;;
    recommend) echo "  → $name: $cmd   ($note)"; return 3 ;;
    apply)
      if [ "${DRY:-0}" = 1 ]; then echo "  [dry] $cmd"; return 0; fi
      # Senza journal non si saprebbe come annullarlo: si rifiuta PRIMA di installare.
      [ -n "${JRUN:-}" ] || { echo "  ✗ pkg_add $name senza journal_begin: non annullabile, non eseguo" >&2; return 1; }
      eval "$cmd" || return 1
      case "$(os_family)" in
        debian) journal_undo "sudo apt remove -y $name" ;;
        fedora) journal_undo "sudo dnf remove -y $name" ;;
      esac ;;
  esac
}

# svc_render <sorgente> <destinazione> [modo]: scrive SOLO se il contenuto cambia
# (sha256), e solo dopo aver salvato lo stato precedente nel journal. Nessun .bak.
# Ritorna 0 invariato · 10 scritto · 2 stop · 1 errore. Il daemon-reload e' del chiamante.
svc_render(){
  local src=$1 dst=$2 mode=${3:-644} action note new old
  IFS='|' read -r action _ note <<<"$(platform_decide svc)"
  [ "$action" = stop ] && { echo "  ✗ $dst: $note" >&2; return 2; }
  [ -r "$src" ] || { echo "  ✗ sorgente illeggibile: $src" >&2; return 1; }
  new=$(sha256sum < "$src" | cut -d' ' -f1)
  old=$($SUDO sha256sum < "$dst" 2>/dev/null | cut -d' ' -f1)
  [ "$new" = "$old" ] && { echo "  $dst: invariato"; return 0; }
  if [ "${DRY:-0}" = 1 ]; then echo "  [dry] scrive $dst (sha256 ${old:0:12}… → ${new:0:12}…)"; return 10; fi
  journal_file "$dst" || return 1
  $SUDO install -D -m "$mode" "$src" "$dst" || return 1
  echo "  $dst: scritto"; return 10
}

# tool_pin <chiave>: la versione pinnata in stack/ (un solo posto, ADR-0020).
# Cerca in requirements-tools.txt (pkg==v), package.json (dependencies) e
# versions.conf (CHIAVE=v). Vuoto + ritorno 1 se il pin non c'e'.
tool_pin(){
  local stack v
  stack="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../stack" && pwd)"
  v=$(sed -n "s/^$1==\([^[:space:]#]*\).*/\1/p" "$stack/requirements-tools.txt" 2>/dev/null | head -1)
  [ -z "$v" ] && v=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["dependencies"].get(sys.argv[2],""))' \
                     "$stack/package.json" "$1" 2>/dev/null)
  [ -z "$v" ] && v=$(sed -n "s/^$1=\"\{0,1\}\([^\"[:space:]#]*\).*/\1/p" "$stack/versions.conf" 2>/dev/null | head -1)
  [ -n "$v" ] && { echo "$v"; return 0; }
  return 1
}
