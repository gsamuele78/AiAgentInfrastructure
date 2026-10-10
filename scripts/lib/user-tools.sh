# shellcheck shell=bash
# shellcheck disable=SC2034  # UT_* letti da install-user-tools.sh e dal benchmark
# ============================================================
#  user-tools.sh -- strato S3 (ADR-0018): Node, opencode, graphify in $HOME.
#  ADR-0024: mise e' il percorso primario; lo "script" (tarball Node verificato,
#  npm con prefisso, uv tool) e' il ripiego. Entrambi leggono gli STESSI pin di
#  stack/ e passano la STESSA verifica (ut_verify).
#  Usato da scripts/install-user-tools.sh e da bench/install-methods (P2b),
#  cosi' la CI misura il codice vero, non una copia.
# ============================================================

UT_STACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../stack" && pwd)"
UT_CACHE="${USER_TOOLS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/aiagentinfra/user-tools}"
UT_PREFIX="${USER_TOOLS_PREFIX:-$HOME/.local}"
UT_MISE_FRAGMENT="${XDG_CONFIG_HOME:-$HOME/.config}/mise/conf.d/aiagentinfra.toml"
UT_MISE_SHIMS="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"

# ut_pins: UT_NODE UT_OPENCODE UT_GRAPHIFY UT_MISE da stack/ (un posto per pin).
ut_pins(){
  UT_NODE=$(sed -n 's/^NODE_VERSION=\([^[:space:]#]*\).*/\1/p' "$UT_STACK/versions.conf")
  UT_MISE=$(sed -n 's/^MISE_VERSION=\([^[:space:]#]*\).*/\1/p' "$UT_STACK/versions.conf")
  UT_GRAPHIFY=$(sed -n 's/^graphifyy==\([^[:space:]#]*\).*/\1/p' "$UT_STACK/requirements-tools.txt")
  UT_OPENCODE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["dependencies"].get("opencode-ai",""))' "$UT_STACK/package.json")
  local v; for v in UT_NODE UT_MISE UT_GRAPHIFY UT_OPENCODE; do
    [ -n "${!v}" ] || { echo "  ✗ pin mancante: $v (stack/)" >&2; return 1; }
  done
}

ut_arch(){ case "$(uname -m)" in x86_64) echo x64 ;; aarch64) echo arm64 ;; *) return 1 ;; esac; }

# --- percorso "script" ------------------------------------------------
# ut_node_tarball <versione> <prefisso>: Node in <prefisso>/opt/node-v<v>, link
# in <prefisso>/bin; sha256 confrontato con lo SHASUMS256.txt ufficiale.
ut_node_tarball(){
  local v=$1 p=$2 arch f url sums b
  arch=$(ut_arch) || return 1
  f="node-v$v-linux-$arch.tar.xz"
  if [ ! -x "$p/opt/node-v$v/bin/node" ]; then
    url="https://nodejs.org/dist/v$v"
    mkdir -p "$p/opt" "$UT_CACHE"
    [ -f "$UT_CACHE/$f" ] || curl -fsSL "$url/$f" -o "$UT_CACHE/$f" || return 1
    sums=$(curl -fsSL "$url/SHASUMS256.txt") || return 1
    (cd "$UT_CACHE" && grep " $f\$" <<<"$sums" | sha256sum -c --quiet -) \
      || { echo "  ✗ sha256 di $f non torna" >&2; rm -f "$UT_CACHE/$f"; return 1; }
    rm -rf "$p/opt/node-v$v.tmp"; mkdir -p "$p/opt/node-v$v.tmp"
    tar -xJf "$UT_CACHE/$f" -C "$p/opt/node-v$v.tmp" --strip-components=1 \
      && mv "$p/opt/node-v$v.tmp" "$p/opt/node-v$v" || return 1
  fi
  mkdir -p "$p/bin"
  for b in node npm npx; do
    [ "$(readlink "$p/bin/$b" 2>/dev/null)" = "$p/opt/node-v$v/bin/$b" ] || ln -sfn "$p/opt/node-v$v/bin/$b" "$p/bin/$b"
  done
}

# ut_opencode_npm <versione> <prefisso>: salta se e' gia' quella.
ut_opencode_npm(){
  local v=$1 p=$2
  [ "$(PATH="$p/bin:$PATH" opencode --version 2>/dev/null)" = "$v" ] && return 0
  PATH="$p/bin:$PATH" npm_config_update_notifier=false npm install -g --prefix "$p" --no-fund --no-audit --loglevel=error "opencode-ai@$v" >/dev/null
}

# ut_graphify_uv <versione>: uv tool in $HOME; salta se e' gia' quella.
ut_graphify_uv(){
  local v=$1
  [ "$(graphify --version 2>/dev/null)" = "graphify $v" ] && return 0
  uv tool install -q --force "graphifyy==$v" 2>/dev/null
}

ut_script_install(){
  ut_node_tarball "$1" "$UT_PREFIX" && ut_opencode_npm "$2" "$UT_PREFIX" && ut_graphify_uv "$3"
}

# --- percorso mise ----------------------------------------------------
# ut_mise_bootstrap <versione> <destinazione>: binario della release ufficiale,
# sha256 da SHASUMS256.txt della stessa release. Salta se c'e' gia' quella versione.
ut_mise_bootstrap(){
  local v=$1 dest=$2 arch f url
  [ "$("$dest" --version 2>/dev/null | cut -d' ' -f1)" = "$v" ] && return 0
  arch=$(ut_arch) || return 1
  f="mise-v$v-linux-$arch"; url="https://github.com/jdx/mise/releases/download/v$v"
  mkdir -p "$UT_CACHE" "$(dirname "$dest")"
  curl -fsSL "$url/$f" -o "$UT_CACHE/$f" || return 1
  (cd "$UT_CACHE" && curl -fsSL "$url/SHASUMS256.txt" | grep -E " (\./)?$f\$" | sed 's| \./| |' | sha256sum -c --quiet -) \
    || { echo "  ✗ sha256 di $f non torna" >&2; rm -f "$UT_CACHE/$f"; return 1; }
  install -m 755 "$UT_CACHE/$f" "$dest"
}

# ut_mise_toml <node> <opencode> <graphify>: il frammento che mise legge da
# conf.d. Si GENERA dai pin: non e' una seconda verita'.
# allow_builds: il backend npm di mise non esegue i postinstall (default
# sicuro); opencode-ai scarica li' il binario, quindi va permesso per nome.
ut_mise_toml(){
  cat <<EOF
# Generato da scripts/install-user-tools.sh dai pin di stack/ (ADR-0024).
# Non modificare: si riscrive a ogni run. Rollback: --rollback.
[tools]
node = "$1"
"npm:opencode-ai" = { version = "$2", allow_builds = ["opencode-ai"] }
"pipx:graphifyy" = "$3"

[settings]
pipx.uvx = true
EOF
}

# --- verifica comune --------------------------------------------------
ut_versions(){
  printf 'node=%s opencode=%s graphify=%s\n' \
    "$(node --version 2>/dev/null | sed 's/^v//')" \
    "$(opencode --version 2>/dev/null | head -1)" \
    "$(graphify --version 2>/dev/null | sed 's/^graphify //')"
}
# ut_verify: 0 se le versioni sul PATH sono i pin; stampa da dove arriva node.
ut_verify(){
  local want got
  want="node=$UT_NODE opencode=$UT_OPENCODE graphify=$UT_GRAPHIFY"
  got=$(ut_versions)
  echo "  node da: $(command -v node 2>/dev/null || echo '-')"
  if [ "$got" = "$want" ]; then echo "  ✓ $got"; return 0; fi
  echo "  ✗ atteso $want" >&2; echo "    trovato $got" >&2; return 1
}
