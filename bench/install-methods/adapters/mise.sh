# shellcheck shell=bash
# mise: un solo file (config.toml) dichiara Node, opencode (backend npm) e
# graphify (backend pipx, eseguito con uv). Le versioni restano affiancate:
# il rollback e' rimettere il file precedente (in un repo: git) + mise install.
# Il backend npm di mise NON esegue gli script di installazione (default
# sicuro); opencode-ai scarica il binario nel postinstall, quindi va permesso
# per nome con allow_builds. Senza, si installa ma non parte (visto in P2b).
MISE_CFG="$XDG_CONFIG_HOME/mise/config.toml"
export MISE_YES=1 MISE_QUIET=1

m_prereq(){
  local c; for c in curl uv sha256sum; do command -v "$c" >/dev/null || { echo "manca $c"; return 1; }; done
}
m_path(){ export PATH="$XDG_DATA_HOME/mise/shims:$HOME/.local/bin:$PATH"; }
# Il gestore e il file: ut_mise_bootstrap e ut_mise_toml di scripts/lib/user-tools.sh.
# MISE_BIN (gia' scaricato altrove) evita la rete, per le prove locali.
m_setup(){
  if [ -n "${MISE_BIN:-}" ]; then mkdir -p "$HOME/.local/bin"; cp "$MISE_BIN" "$HOME/.local/bin/mise"
  else ut_mise_bootstrap "$MISE_VERSION" "$HOME/.local/bin/mise"; fi
}
m_apply(){
  local s=$1 new
  new=$(ut_mise_toml "$(pin node "$s")" "$(pin opencode "$s")" "$(pin graphify "$s")")
  [ "$(cat "$MISE_CFG" 2>/dev/null)" = "$new" ] || { mkdir -p "${MISE_CFG%/*}"; printf '%s\n' "$new" > "$MISE_CFG"; }
  mise install
}
m_rollback(){ m_apply A; }
m_state(){ cat "$MISE_CFG"; }
m_uninstall(){ rm -rf "$XDG_DATA_HOME/mise" "$XDG_STATE_HOME/mise" "${MISE_CFG%/*}" "$HOME/.local/bin/mise"; }
