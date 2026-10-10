#!/usr/bin/env bash
# ============================================================
#  install-user-tools.sh -- strato S3 (ADR-0018, ADR-0024): Node, opencode e
#  graphify alle versioni pinnate in stack/, solo in $HOME (mai S1, mai sudo).
#
#    ./install-user-tools.sh [--dry-run] [--backend auto|mise|script]
#    ./install-user-tools.sh --check            solo verifica: versioni == pin
#    ./install-user-tools.sh --rollback [RUN]   annulla l'ultimo run (o RUN)
#    ./install-user-tools.sh --list             run registrati
#
#  auto   = mise (installato con verifica sha256 se manca); se mise non si puo'
#           avere, ripiega sullo script CON UN AVVISO, registrato nel journal.
#  mise   = solo mise: se non si puo', fallisce (niente ripiego).
#  script = tarball Node + npm --prefix ~/.local + uv tool (il ripiego).
#  Misurati entrambi in P2b (bench/install-methods, workflow bench-install).
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DRY=0; BACKEND=auto; MODE=install; RUN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --backend) BACKEND=${2:-}; shift ;;
    --check) MODE=check ;;
    --rollback) MODE=rollback; case "${2:-}" in ""|--*) ;; *) RUN=$2; shift ;; esac ;;
    --list) MODE=list ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
  esac; shift
done
case "$BACKEND" in auto|mise|script) ;; *) echo "--backend: auto, mise o script" >&2; exit 2 ;; esac
export DRY

# shellcheck disable=SC2034  # letta da journal.sh
SUDO=""   # solo $HOME: il journal non deve usare sudo
# shellcheck source=lib/hw-detect.sh
. "$HERE/lib/hw-detect.sh"
# shellcheck source=lib/journal.sh
. "$HERE/lib/journal.sh"
# shellcheck source=lib/user-tools.sh
. "$HERE/lib/user-tools.sh"
say(){ echo -e "\033[36m==>\033[0m $*"; }
warn(){ echo -e "  \033[33m!\033[0m $*" >&2; }
MISE_BIN="$UT_PREFIX/bin/mise"

case "$MODE" in
  list) journal_list user-tools; exit 0 ;;
  rollback)
    d=$(journal_resolve "${RUN:-user-tools-latest}") || { echo "  ✗ run non trovato: ${RUN:-user-tools-latest}" >&2; exit 1; }
    say "rollback di $d"; journal_rollback "$d"; exit $? ;;
esac

ut_pins || exit 1
say "pin: node $UT_NODE · opencode $UT_OPENCODE · graphify $UT_GRAPHIFY · mise $UT_MISE"

if [ "$MODE" = check ]; then
  export PATH="$UT_MISE_SHIMS:$UT_PREFIX/bin:$PATH"
  ut_verify; exit $?
fi

# Scrive SOLO in $HOME, come stack-selective-install.sh: in un devcontainer e' legittimo.
sandbox_guard "scripts/install-user-tools.sh" "$DRY" warn || exit 1
for c in curl tar sha256sum uv; do
  command -v "$c" >/dev/null && continue
  [ "$DRY" = 1 ] && { echo "  [dry] manca $c"; continue; }
  echo "  ✗ manca $c" >&2; exit 1
done

use_mise(){
  local new old
  [ "$DRY" = 1 ] && { echo "  [dry] mise $UT_MISE in $MISE_BIN (sha256), frammento $UT_MISE_FRAGMENT, mise install"; return 0; }
  ut_mise_bootstrap "$UT_MISE" "$MISE_BIN" || return 10
  new=$(ut_mise_toml "$UT_NODE" "$UT_OPENCODE" "$UT_GRAPHIFY")
  old=$(cat "$UT_MISE_FRAGMENT" 2>/dev/null)
  if [ "$new" != "$old" ]; then
    # Ordine voluto: il rollback ripercorre al contrario, quindi prima
    # ripristina il frammento e POI rilancia mise install sulle versioni vecchie
    # (che mise tiene affiancate: nessun download).
    journal_undo "'$MISE_BIN' install" && journal_file "$UT_MISE_FRAGMENT" || return 1
    mkdir -p "$(dirname "$UT_MISE_FRAGMENT")" && printf '%s\n' "$new" > "$UT_MISE_FRAGMENT" || return 1
    echo "  $UT_MISE_FRAGMENT: scritto"
  else echo "  $UT_MISE_FRAGMENT: invariato"; fi
  MISE_YES=1 "$MISE_BIN" install || return 1
  export PATH="$UT_MISE_SHIMS:$PATH"
}
use_script(){
  local before n o g
  [ "$DRY" = 1 ] && { echo "  [dry] node $UT_NODE in $UT_PREFIX/opt (sha256), opencode-ai@$UT_OPENCODE con npm --prefix $UT_PREFIX, uv tool graphifyy==$UT_GRAPHIFY"; return 0; }
  export PATH="$UT_PREFIX/bin:$PATH"
  before=$(ut_versions)
  n=$(sed -n 's/.*node=\([^ ]*\).*/\1/p' <<<"$before"); o=$(sed -n 's/.*opencode=\([^ ]*\).*/\1/p' <<<"$before"); g=$(sed -n 's/.*graphify=\([^ ]*\).*/\1/p' <<<"$before")
  # Rollback = reinstallare le versioni di prima (le versioni Node restano affiancate in opt/).
  if [ "$before" != "node=$UT_NODE opencode=$UT_OPENCODE graphify=$UT_GRAPHIFY" ] && [ -n "$n$o$g" ]; then
    journal_undo "ut_script_install '${n:-$UT_NODE}' '${o:-$UT_OPENCODE}' '${g:-$UT_GRAPHIFY}'" || return 1
  fi
  ut_script_install "$UT_NODE" "$UT_OPENCODE" "$UT_GRAPHIFY"
}

journal_begin user-tools || exit 1
case "$BACKEND" in
  mise) say "backend: mise"; use_mise || { echo "  ✗ mise non disponibile e --backend mise non ripiega" >&2; exit 1; } ;;
  script) say "backend: script"; use_script || exit 1 ;;
  auto)
    say "backend: mise (auto)"
    use_mise; rc=$?
    if [ "$rc" = 10 ]; then
      warn "mise $UT_MISE non scaricabile o sha256 non verificato: RIPIEGO sullo script (ADR-0024 §5)"
      journal_undo "echo 'questo run ha usato il ripiego script'"
      say "backend: script (ripiego)"; use_script || exit 1
    elif [ "$rc" != 0 ]; then exit 1; fi ;;
esac

[ "$DRY" = 1 ] && exit 0
say "verifica"
ut_verify || { warn "rollback: $0 --rollback"; exit 1; }
echo "  shell: clients/shell-env.sh mette $UT_MISE_SHIMS e $UT_PREFIX/bin nel PATH"
echo "  registro: $JRUN  (annulla con: $0 --rollback)"
