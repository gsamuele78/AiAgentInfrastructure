# shellcheck shell=bash
# nix: Node e opencode da una release di nixpkgs (il pin e' la release, non il
# singolo pacchetto); graphify con uv tool (non e' in nixpkgs). Il rollback
# torna alla generazione del profilo registrata dopo A: "--rollback" da solo
# andrebbe alla generazione precedente, che dopo il secondo ciclo e' gia' B.
PROFILE="$XDG_STATE_HOME/bench-nix/profile"
GEN_A_FILE="$XDG_STATE_HOME/bench-nix/gen-a"

m_prereq(){
  local c; for c in nix-build nix-env uv; do command -v "$c" >/dev/null || { echo "manca $c"; return 1; }; done
}
m_path(){ export PATH="$PROFILE/bin:$HOME/.local/bin:$PATH"; }
_env(){
  local url; url=$(pin nixpkgs "$1")
  nix-build --no-out-link -E "with import (fetchTarball \"$url\") {}; buildEnv { name = \"bench-p2b-$1\"; paths = [ nodejs_24 opencode ]; }"
}
_gen(){ nix-env -p "$PROFILE" --list-generations | awk '/\(current\)/{print $1}'; }
m_apply(){
  local s=$1 out
  out=$(_env "$s" | tail -1) || return 1
  mkdir -p "${PROFILE%/*}"
  [ "$(readlink -f "$PROFILE")" = "$out" ] || nix-env -p "$PROFILE" --set "$out" || return 1
  [ "$s" = A ] && [ ! -f "$GEN_A_FILE" ] && _gen > "$GEN_A_FILE"
  graphify_uv "$(pin graphify "$s")"
}
m_rollback(){
  nix-env -p "$PROFILE" --switch-generation "$(cat "$GEN_A_FILE")" || return 1
  graphify_uv "$(pin graphify A)"
}
m_state(){ readlink -f "$PROFILE"; uv tool list 2>/dev/null | grep '^graphifyy'; }
m_disk_paths(){ nix-store -qR "$(readlink -f "$PROFILE")"; }
m_uninstall(){ uv tool uninstall graphifyy >/dev/null 2>&1; rm -rf "${PROFILE%/*}"; nix-collect-garbage >/dev/null 2>&1 || true; }
