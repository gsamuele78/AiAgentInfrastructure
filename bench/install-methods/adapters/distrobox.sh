# shellcheck shell=bash
# distrobox: un contenitore da immagine pinnata; dentro, gli stessi mattoni
# della baseline. Node e opencode vanno nel filesystem del contenitore
# (/opt/bench), graphify con uv tool finisce nella $HOME, che distrobox
# CONDIVIDE con l'host. Rollback = ricreare il contenitore e reinstallare A.
# R1 (file rimasti dopo la rimozione) dice cosa sopravvive in $HOME.
BOX=bench-p2b
HR="/run/host$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # il repo visto da dentro

m_prereq(){
  [ "$(id -u)" != 0 ] || { echo "distrobox va usato da utente (podman rootless)"; return 1; }
  local c; for c in distrobox podman uv; do command -v "$c" >/dev/null || { echo "manca $c"; return 1; }; done
  # Le immagini restano nello storage dell'utente vero: non sono "file del metodo" in $HOME.
  cat > "$WORK/storage.conf" <<EOF
[storage]
driver = "overlay"
graphroot = "$REAL_HOME/.local/share/containers/storage"
runroot = "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers"
EOF
  export CONTAINERS_STORAGE_CONF="$WORK/storage.conf"
  # distrobox-enter ripassa il comando da un eval di sh: sulla riga di comando
  # solo uno script e argomenti semplici, niente $(...) ne' variabili.
  {
    echo '#!/bin/bash'
    echo 'set -e'
    printf "export BENCH_CACHE='%s'\n" "$BENCH_CACHE"
    echo 'export PATH="/opt/bench/bin:$HOME/.local/bin:$PATH"'
    printf ". '%s/pins.sh'; . '%s/adapters/common.sh'\n" "$HR" "$HR"
    printf "uv(){ '/run/host%s' \"\$@\"; }\n" "$(command -v uv)"
    cat <<'EOF'
case "$1" in
  setup)
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends xz-utils curl ca-certificates >/dev/null
    sudo install -d -o "$(id -u)" /opt/bench ;;
  apply)
    s=$2
    node_tarball "$(pin node "$s")" /opt/bench
    opencode_npm "$(pin opencode "$s")" /opt/bench
    graphify_uv "$(pin graphify "$s")"
    w="node=$(pin node "$s") opencode=$(pin opencode "$s") graphify=$(pin graphify "$s")"
    [ "$(cat /opt/bench/pins 2>/dev/null)" = "$w" ] || echo "$w" > /opt/bench/pins ;;
  versions) versions ;;
  state) cat /opt/bench/pins ;;
esac
EOF
  } > "$WORK/in.sh"
}
m_path(){ :; }
_in(){ distrobox enter -n "$BOX" -- bash "/run/host$WORK/in.sh" "$@"; }
m_setup(){ distrobox create --yes --name "$BOX" --image "$DISTROBOX_IMAGE" && _in setup; }
m_apply(){ _in apply "$1"; }
m_rollback(){ distrobox rm --force "$BOX" && m_setup && m_apply A; }
m_versions(){ _in versions 2>/dev/null; }
m_state(){ echo "$DISTROBOX_IMAGE"; _in state; }
m_uninstall(){ distrobox rm --force "$BOX" >/dev/null 2>&1; }
