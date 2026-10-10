# shellcheck shell=bash
# shellcheck disable=SC2034  # M_* li legge run.sh
# brew: node@24 e opencode da homebrew-core; graphify con uv tool. Homebrew
# installa solo l'ultima versione di una formula: non c'e' modo supportato di
# chiedere 24.20.0 o di tornarci. Si misura comunque A1, A2, P1, P2.
M_CAN_ROLLBACK=0
M_ROLLBACK_WHY="Homebrew installa solo l'ultima versione della formula: nessun pin esatto, nessun ritorno a una versione precedente (brew extract in un tap locale e' un ripiego, non un rollback)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1

m_prereq(){
  [ "$(id -u)" != 0 ] || { echo "Homebrew non gira come root"; return 1; }
  BREW=$(command -v brew || ls /home/linuxbrew/.linuxbrew/bin/brew 2>/dev/null) || { echo "manca brew"; return 1; }
  command -v uv >/dev/null || { echo "manca uv"; return 1; }
}
m_path(){
  local p; p=$("$BREW" --prefix)
  M_EXTRA_DIRS="$p/Cellar/node@24 $p/Cellar/opencode"
  export PATH="$p/opt/node@24/bin:$p/bin:$HOME/.local/bin:$PATH"
}
m_apply(){
  local f; for f in node@24 opencode; do
    "$BREW" list --versions "$f" >/dev/null 2>&1 || "$BREW" install -q "$f" || return 1
  done
  graphify_uv "$(pin graphify "$1")"
}
m_rollback(){ return 1; }
m_state(){ "$BREW" list --versions node@24 opencode; }
m_uninstall(){ "$BREW" uninstall -q node@24 opencode >/dev/null 2>&1; uv tool uninstall graphifyy >/dev/null 2>&1; }
