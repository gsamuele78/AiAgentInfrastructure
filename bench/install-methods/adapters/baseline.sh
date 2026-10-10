# shellcheck shell=bash
# baseline: nessun gestore nuovo. Node da tarball verificato, opencode con npm
# in ~/.local, graphify con uv tool. Lo "stato dichiarato" e' il file dei pin,
# come stack/ nel repo; il rollback e' reinstallare i pin precedenti.
PINS_FILE="$HOME/.local/state/bench/pins"

m_prereq(){
  local c; for c in curl tar xz uv python3 sha256sum; do
    command -v "$c" >/dev/null || { echo "manca $c"; return 1; }
  done
}
m_path(){ export PATH="$HOME/.local/bin:$PATH"; }
m_apply(){
  local s=$1 want
  node_tarball "$(pin node "$s")" "$HOME/.local" || return 1
  opencode_npm "$(pin opencode "$s")" "$HOME/.local" || return 1
  graphify_uv "$(pin graphify "$s")" || return 1
  want="node=$(pin node "$s") opencode=$(pin opencode "$s") graphify=$(pin graphify "$s")"
  [ "$(cat "$PINS_FILE" 2>/dev/null)" = "$want" ] || { mkdir -p "${PINS_FILE%/*}"; echo "$want" > "$PINS_FILE"; }
}
m_rollback(){ m_apply A; }
m_state(){ cat "$PINS_FILE"; }
m_uninstall(){
  uv tool uninstall graphifyy >/dev/null 2>&1
  rm -rf "$HOME/.local/opt" "$HOME/.local/lib/node_modules" "$PINS_FILE"
  rm -f "$HOME/.local/bin/"{node,npm,npx,opencode}
}
