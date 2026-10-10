#!/usr/bin/env bash
# ============================================================
#  e2e di scripts/install-user-tools.sh (ADR-0024) — rete vera, $HOME usa e getta.
#  Non sta in test-scripts.sh (scarica ~300 MB): gira nel workflow bench-install.
#
#  1. auto con GitHub raggiungibile  -> mise, versioni == pin, rilancio = 0 azioni
#  2. auto con GitHub BLOCCATO       -> ripiego script CON avviso, versioni == pin
#  3. --backend mise, GitHub bloccato -> fallisce (mai ripiego silenzioso)
#  4. per mise e script: pin A -> pin B -> --rollback -> di nuovo A
#
#    tests/user-tools/e2e.sh [scenario...]   (default: tutti)
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK=$(mktemp -d); PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
ko(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "$2" | tail -15 | sed 's/^/      /'; FAIL=$((FAIL+1)); }
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
newhome(){ HOME=$(mktemp -d "$WORK/home.XXXX"); export HOME; }
INST="$ROOT/scripts/install-user-tools.sh"

# curl finto: GitHub non risponde, il resto passa (il caso visto in P2b).
mkdir -p "$WORK/blocked"
cat > "$WORK/blocked/curl" <<EOF
#!/bin/sh
for a in "\$@"; do case "\$a" in *github.com*) echo "curl: (56) 403 (finto, e2e)" >&2; exit 56;; esac; done
exec $(command -v curl) "\$@"
EOF
chmod +x "$WORK/blocked/curl"

# Copia del repo con i pin "A" (precedenti) per provare il rollback.
REPO_A="$WORK/repo-a"; mkdir -p "$REPO_A"
(cd "$ROOT" && tar -cf - scripts stack) | tar -xf - -C "$REPO_A"
sed -i 's/^NODE_VERSION=.*/NODE_VERSION=24.20.0/' "$REPO_A/stack/versions.conf"
python3 - "$REPO_A/stack/package.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["dependencies"]["opencode-ai"] = "1.18.33"
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
sed -i 's/^graphifyy==.*/graphifyy==0.9.73/' "$REPO_A/stack/requirements-tools.txt"
WANT_A="node=24.20.0 opencode=1.18.33 graphify=0.9.73"

s_auto(){
  echo "── 1. auto, GitHub raggiungibile"; newhome
  out=$("$INST" 2>&1) || { ko "install auto" "$out"; return; }
  grep -q 'node da: .*/mise/shims/node' <<<"$out" && ok "usa mise" || ko "non usa mise" "$out"
  grep -q 'RIPIEGO' <<<"$out" && ko "ripiego senza motivo" "$out" || ok "nessun ripiego"
  "$INST" >/dev/null 2>&1; n=$(wc -l < "$HOME/.local/state/aiagentinfra/runs/user-tools-latest/actions.log")
  [ "$n" = 0 ] && ok "rilancio: 0 azioni nel journal" || ko "rilancio: $n azioni"
  "$INST" --check >/dev/null && ok "--check verde" || ko "--check rosso"
}
s_fallback(){
  echo "── 2. auto, GitHub bloccato"; newhome
  out=$(PATH="$WORK/blocked:$PATH" "$INST" 2>&1) || { ko "install con ripiego" "$out"; return; }
  grep -q 'RIPIEGO' <<<"$out" && ok "avviso di ripiego stampato" || ko "ripiego silenzioso" "$out"
  grep -q 'node da: .*/.local/bin/node' <<<"$out" && ok "usa lo script" || ko "non usa lo script" "$out"
  grep -q 'ripiego script' "$HOME/.local/state/aiagentinfra/runs/user-tools-latest/actions.log" \
    && ok "ripiego registrato nel journal" || ko "ripiego non registrato"
  "$INST" --check >/dev/null && ok "--check verde" || ko "--check rosso"
}
s_strict(){
  echo "── 3. --backend mise, GitHub bloccato"; newhome
  if PATH="$WORK/blocked:$PATH" "$INST" --backend mise >/dev/null 2>&1; then ko "doveva fallire"
  else ok "fallisce, nessun ripiego"; fi
  [ -e "$HOME/.local/bin/node" ] && ko "ha installato lo script lo stesso" || ok "niente installato dallo script"
}
s_rollback(){
  local b=$1 out
  echo "── 4. rollback, backend $b"; newhome
  "$REPO_A/scripts/install-user-tools.sh" --backend "$b" >/dev/null 2>&1 || { ko "install A"; return; }
  "$INST" --backend "$b" >/dev/null 2>&1 || { ko "install B"; return; }
  "$INST" --check >/dev/null && ok "B installato" || ko "B non verificato"
  out=$("$INST" --rollback 2>&1) || { ko "--rollback" "$out"; return; }
  got=$(PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH" bash -c ". '$ROOT/scripts/lib/user-tools.sh'; ut_versions")
  [ "$got" = "$WANT_A" ] && ok "dopo il rollback: $got" || ko "dopo il rollback: $got (atteso $WANT_A)"
}

[ $# -gt 0 ] || set -- auto fallback strict rollback-mise rollback-script
for s in "$@"; do
  case "$s" in
    auto) s_auto ;; fallback) s_fallback ;; strict) s_strict ;;
    rollback-mise) s_rollback mise ;; rollback-script) s_rollback script ;;
    *) echo "scenario sconosciuto: $s" >&2; exit 2 ;;
  esac
done
chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"
echo "Esito: $PASS ✓  $FAIL ✗"
[ "$FAIL" = 0 ]
