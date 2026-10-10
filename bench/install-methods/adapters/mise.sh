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
# Il gestore stesso: binario della release ufficiale, sha256 da SHASUMS256.txt.
# MISE_BIN (gia' scaricato altrove) evita la rete, per le prove locali.
m_setup(){
  local arch f url
  [ "$(mise --version 2>/dev/null | cut -d' ' -f1)" = "$MISE_VERSION" ] && return 0
  mkdir -p "$HOME/.local/bin"
  if [ -n "${MISE_BIN:-}" ]; then cp "$MISE_BIN" "$HOME/.local/bin/mise"; else
    case "$(uname -m)" in x86_64) arch=x64 ;; aarch64) arch=arm64 ;; *) return 1 ;; esac
    f="mise-v$MISE_VERSION-linux-$arch"; url="https://github.com/jdx/mise/releases/download/v$MISE_VERSION"
    curl -fsSL "$url/$f" -o "$BENCH_CACHE/$f" || return 1
    (cd "$BENCH_CACHE" && curl -fsSL "$url/SHASUMS256.txt" | grep " \./$f\$\| $f\$" | sed "s| \./| |" | sha256sum -c --quiet -) || return 1
    install -m 755 "$BENCH_CACHE/$f" "$HOME/.local/bin/mise"
  fi
}
m_apply(){
  local s=$1 new
  new=$(cat <<EOF
[tools]
node = "$(pin node "$s")"
"npm:opencode-ai" = { version = "$(pin opencode "$s")", allow_builds = ["opencode-ai"] }
"pipx:graphifyy" = "$(pin graphify "$s")"

[settings]
pipx.uvx = true
EOF
)
  [ "$(cat "$MISE_CFG" 2>/dev/null)" = "$new" ] || { mkdir -p "${MISE_CFG%/*}"; printf '%s\n' "$new" > "$MISE_CFG"; }
  mise install
}
m_rollback(){ m_apply A; }
m_state(){ cat "$MISE_CFG"; }
m_uninstall(){ rm -rf "$XDG_DATA_HOME/mise" "$XDG_STATE_HOME/mise" "${MISE_CFG%/*}" "$HOME/.local/bin/mise"; }
