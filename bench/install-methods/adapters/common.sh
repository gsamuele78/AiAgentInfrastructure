# shellcheck shell=bash
# Mattoni condivisi dagli adattatori: Node da tarball verificato, opencode da
# npm con prefisso, graphify con uv. E' il modo "senza gestore" della baseline,
# riusato da brew/nix/distrobox per i tool che quei gestori non pinnano.

# node_tarball <versione> <prefisso>: Node in <prefisso>/opt/node-v<versione>,
# link in <prefisso>/bin. sha256 confrontato con SHASUMS256.txt ufficiale.
node_tarball(){
  local v=$1 p=$2 arch f url sums
  case "$(uname -m)" in x86_64) arch=x64 ;; aarch64) arch=arm64 ;; *) return 1 ;; esac
  f="node-v$v-linux-$arch.tar.xz"
  if [ ! -x "$p/opt/node-v$v/bin/node" ]; then
    url="https://nodejs.org/dist/v$v"
    mkdir -p "$p/opt" "$BENCH_CACHE"
    [ -f "$BENCH_CACHE/$f" ] || curl -fsSL "$url/$f" -o "$BENCH_CACHE/$f" || return 1
    sums=$(curl -fsSL "$url/SHASUMS256.txt") || return 1
    (cd "$BENCH_CACHE" && grep " $f\$" <<<"$sums" | sha256sum -c --quiet -) || { echo "sha256 di $f non torna" >&2; return 1; }
    mkdir -p "$p/opt/node-v$v.tmp" && tar -xJf "$BENCH_CACHE/$f" -C "$p/opt/node-v$v.tmp" --strip-components=1 \
      && mv "$p/opt/node-v$v.tmp" "$p/opt/node-v$v" || return 1
  fi
  mkdir -p "$p/bin"
  local b; for b in node npm npx; do
    [ "$(readlink "$p/bin/$b" 2>/dev/null)" = "$p/opt/node-v$v/bin/$b" ] || ln -sfn "$p/opt/node-v$v/bin/$b" "$p/bin/$b"
  done
}

# opencode_npm <versione> <prefisso>: salta se la versione e' gia' quella.
opencode_npm(){
  local v=$1 p=$2
  [ "$(PATH="$p/bin:$PATH" opencode --version 2>/dev/null)" = "$v" ] && return 0
  PATH="$p/bin:$PATH" npm install -g --prefix "$p" --no-fund --no-audit --loglevel=error "opencode-ai@$v" >/dev/null
}

# graphify_uv <versione>: uv tool in $HOME; salta se la versione e' gia' quella.
graphify_uv(){
  local v=$1
  [ "$(graphify --version 2>/dev/null)" = "graphify $v" ] && return 0
  uv tool install -q --force "graphifyy==$v" 2>/dev/null
}

# versions: una riga, stesso formato per tutti i metodi.
versions(){
  printf 'node=%s opencode=%s graphify=%s\n' \
    "$(node --version 2>/dev/null | sed 's/^v//')" \
    "$(opencode --version 2>/dev/null | head -1)" \
    "$(graphify --version 2>/dev/null | sed 's/^graphify //')"
}
