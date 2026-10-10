#!/usr/bin/env bash
# ============================================================
#  P2b: misura un metodo di installazione/rollback dello strato S3
#  secondo bench/install-methods/PREREG.md (protocollo ADR-0021).
#
#    bench/install-methods/run.sh <metodo> [dir-risultati]
#    metodi: baseline mise brew nix distrobox
#
#  Ogni metodo lavora in una $HOME propria, usa e getta (BENCH_WORK, default
#  mktemp). Scrive <dir>/<os>-<metodo>.json; report.py li confronta.
#  Un metodo non disponibile qui esce 0 con status "skipped": la matrice CI
#  decide dove gira cosa.
# ============================================================
set -uo pipefail
METHOD=${1:?metodo: baseline mise brew nix distrobox}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR=$(mkdir -p "${2:-$HERE/../results}" && cd "${2:-$HERE/../results}" && pwd)
[ -f "$HERE/adapters/$METHOD.sh" ] || { echo "metodo sconosciuto: $METHOD" >&2; exit 2; }

REAL_HOME=$HOME
WORK=${BENCH_WORK:-$(mktemp -d)}
export HOME="$WORK/home-$METHOD"
export BENCH_CACHE="$HOME/.cache/bench"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" \
       XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$HOME" "$BENCH_CACHE"
LOG="$WORK/$METHOD.log"; : > "$LOG"
REPS_RERUN=${REPS_RERUN:-10}; REPS_ROLLBACK=${REPS_ROLLBACK:-5}

# shellcheck source=pins.sh
. "$HERE/pins.sh"
# shellcheck source=adapters/common.sh
. "$HERE/adapters/common.sh"
M_CAN_ROLLBACK=1; M_ROLLBACK_WHY=""; M_EXTRA_DIRS=""
m_setup(){ :; }; m_versions(){ versions; }; m_uninstall(){ :; }; m_disk_paths(){ :; }
# shellcheck disable=SC1090
. "$HERE/adapters/$METHOD.sh"

OS=$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}-${VERSION_ID:-x}")
R="$WORK/$METHOD.kv"; : > "$R"
kv(){ printf '%s=%s\n' "$1" "$2" >> "$R"; }
emit(){
  kv status "$1"
  python3 - "$R" "$OUTDIR/$OS-$METHOD.json" <<'PY'
import json, sys
d = {}
for line in open(sys.argv[1]):
    k, _, v = line.rstrip("\n").partition("=")
    if k.endswith("_times"):
        d[k] = [float(x) for x in v.split()] if v else []
    else:
        try: d[k] = json.loads(v) if v[:1] in "0123456789-[{tf" and v not in ("", "-") else v
        except ValueError: d[k] = v
json.dump(d, open(sys.argv[2], "w"), indent=1, sort_keys=True)
print(json.dumps(d, sort_keys=True))
PY
  echo "log: $LOG" >&2
  # Su errore il log resta in un temporaneo del runner: se ne stampa la coda.
  [ "$1" = error ] && { echo "--- ultime righe di $LOG ---" >&2; tail -40 "$LOG" >&2; }
  return 0
}
now(){ date +%s.%N; }
# timed <var> <cmd...>: tempo reale in secondi (2 decimali) in <var>; ritorna il codice del comando.
timed(){
  local __v=$1 t0 rc; shift
  t0=$(now); "$@" >>"$LOG" 2>&1; rc=$?
  printf -v "$__v" '%s' "$(python3 -c 'import sys;print(f"{float(sys.argv[1])-float(sys.argv[2]):.2f}")' "$(now)" "$t0")"
  return $rc
}
median(){ python3 -c 'import statistics,sys;v=[float(x) for x in sys.argv[1:]];print(round(statistics.median(v),2) if v else "")' "$@"; }
state_sha(){ m_state 2>>"$LOG" | sha256sum | cut -c1-16; }
# File cambiati sotto le directory gestite dopo il marker. Cache (~/.cache,
# ~/.npm/_cacache) escluse qui, da R1 e da R2: si possono cancellare senza effetti.
changed_since(){
  # shellcheck disable=SC2086
  find "$HOME" $M_EXTRA_DIRS -newer "$1" -type f ! -path "$HOME/.cache/*" ! -path "$HOME/.npm/_cacache/*" 2>/dev/null
}

kv method "$METHOD"; kv os "$OS"; kv arch "$(uname -m)"; kv date "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
WANT_A="node=$NODE_A opencode=$OPENCODE_A graphify=$GRAPHIFY_A"
kv want_a "$WANT_A"

# Non in una sottoshell: m_prereq puo' esportare variabili per il resto del run.
if ! m_prereq > "$WORK/prereq.out" 2>&1; then kv reason "$(tr '\n' ' ' < "$WORK/prereq.out")"; emit skipped; exit 0; fi
m_path

timed T m_setup || { kv step setup; emit error; exit 1; }; kv setup_s "$T"
timed T m_apply A || { kv step install-A; emit error; exit 1; }; kv p1_install_s "$T"
VA=$(m_versions); kv got_a "$VA"
[ "$VA" = "$WANT_A" ] && kv a1_pins_exact true || kv a1_pins_exact false
SA=$(state_sha); kv state_a "$SA"

# A2 + P2: rilancio idempotente
MARK="$WORK/marker"; touch "$MARK"; sleep 1.1
times=""
for _ in $(seq "$REPS_RERUN"); do timed T m_apply A || { kv step rerun; emit error; exit 1; }; times+="$T "; done
CH=$(changed_since "$MARK")
kv a2_changed_files "$(printf '%s' "$CH" | grep -c . || true)"
kv a2_examples "$(printf '%s\n' "$CH" | sed "s|$HOME|~|" | head -5 | tr '\n' ' ')"
kv p2_rerun_times "$times"; kv p2_rerun_median_s "$(median $times)"

# A3 + A4 + P3: aggiorna a B, torna ad A
if [ "$M_CAN_ROLLBACK" = 1 ]; then
  ok3=0; ok4=0; times=""; vb=""
  for _ in $(seq "$REPS_ROLLBACK"); do
    timed T m_apply B || { kv step install-B; emit error; exit 1; }
    vb=$(m_versions)
    timed T m_rollback || { kv step rollback; emit error; exit 1; }
    times+="$T "
    [ "$(m_versions)" = "$VA" ] && ok3=$((ok3+1))
    [ "$(state_sha)" = "$SA" ] && ok4=$((ok4+1))
  done
  kv got_b "$vb"; [ "$vb" = "$VA" ] && kv note "B indistinguibile da A: il rollback non e' messo alla prova"
  kv a3_rollback_versions "$ok3/$REPS_ROLLBACK"; kv a4_rollback_state "$ok4/$REPS_ROLLBACK"
  kv p3_rollback_times "$times"; kv p3_rollback_median_s "$(median $times)"
else
  kv a3_rollback_versions "n/a"; kv a4_rollback_state "n/a"; kv rollback_why "$M_ROLLBACK_WHY"
fi

# R2 + R1: spazio occupato, poi cosa resta dopo la disinstallazione
# shellcheck disable=SC2086
# m_disk_paths (facoltativo): percorsi fuori da $HOME che il metodo occupa (store di nix).
# shellcheck disable=SC2046
kv r2_disk_mb "$(du -smc --exclude="$HOME/.cache" --exclude="$HOME/.npm/_cacache" "$HOME" $M_EXTRA_DIRS $(m_disk_paths 2>/dev/null) 2>/dev/null | tail -1 | cut -f1)"
timed T m_uninstall; kv uninstall_s "$T"
LEFT=$(find "$HOME" -type f ! -path "$HOME/.cache/*" ! -path "$HOME/.npm/_cacache/*" 2>/dev/null)
kv r1_residue_files "$(printf '%s' "$LEFT" | grep -c . || true)"
kv r1_examples "$(printf '%s\n' "$LEFT" | sed "s|$HOME|~|" | head -5 | tr '\n' ' ')"
emit ok
[ -n "${BENCH_WORK:-}" ] || { chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"; }
HOME=$REAL_HOME
