#!/usr/bin/env bash
# ============================================================
#  bench/tasks/run.sh -- golden task contro un agente vero (L6, P0b; ADR-0019 §6, ADR-0025 §1).
#  Struttura importata da OpenHands (software-agent-sdk tests/integration, MIT):
#    t*  richiesti: verifica deterministica dell'artefatto (check.sh)
#    b*  comportamento: l'agente fa la cosa giusta (non implementa se chiedi un parere,
#        non distrugge dati senza conferma). Tasso riportato a parte, non blocca.
#  L'early stopper (lib/early_stop.py) ferma il run quando il fallimento e' gia' certo.
#
#  Uso:
#    run.sh [--model litellm/local-good] [--reps 5] [--tier t|b|all] [--ids t01,b02]
#           [--early-stop on|off] [--out bench/results/<data>] [--dry-run]
#  Default modello: local-good, che non ha fallbacks nel gateway (ADR-0021: modello fisso).
#  Config del client: clients/opencode.jsonc del repo (OPENCODE_CONFIG), cosi' si misura
#  la config versionata, permission comprese. I t* girano con --auto (approva cio' che non
#  e' deny), i b* senza: li' le regole ask del client fanno parte di cio' che si misura.
#  Servono: opencode al pin di stack/package.json, il gateway su LITELLM_BASE_URL e la
#  variabile LITELLM_MASTER_KEY (una virtual key con budget, mai la master key vera).
#  Uscita: TSV + tracce etichettate (riusabili da bench/stuck e SkillRefiner) in --out.
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib/workspace.sh
. "$HERE/lib/workspace.sh"
MODEL=litellm/local-good; REPS=5; TIER=all; IDS=""; ES=on; DRY=0
OUT="$REPO/bench/results/tasks-$(date -u +%Y%m%dT%H%M%SZ)"
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL=$2; shift ;; --reps) REPS=$2; shift ;; --tier) TIER=$2; shift ;;
    --ids) IDS=$2; shift ;; --early-stop) ES=$2; shift ;; --out) OUT=$2; shift ;;
    --dry-run) DRY=1 ;; -h|--help) sed -n 2,22p "$0"; exit 0 ;;
    *) echo "opzione sconosciuta: $1"; exit 2 ;;
  esac; shift
done
tasks=()
for t in "$HERE"/[tb][0-9][0-9]-*/; do
  t=${t%/}; id=$(basename "$t"); tier=$(sed -n 's/^tier=//p' "$t/meta")
  [ "$TIER" != all ] && [ "$tier" != "$TIER" ] && continue
  [ -n "$IDS" ] && [[ ",$IDS," != *",${id%%-*},"* ]] && continue
  tasks+=("$t")
done
[ ${#tasks[@]} -gt 0 ] || { echo "nessun task selezionato"; exit 2; }
echo "modello $MODEL · ripetizioni $REPS · early stop $ES · task: ${#tasks[@]} -> $OUT"
if [ "$DRY" = 1 ]; then
  for t in "${tasks[@]}"; do echo "  [dry-run] $(basename "$t"): opencode run --format json -m $MODEL \"$(head -c 60 "$t/task.md")...\""; done
  exit 0
fi
command -v opencode >/dev/null || { echo "opencode non trovato (./scripts/install-user-tools.sh)"; exit 1; }
mkdir -p "$OUT/traces"
TSV="$OUT/results.tsv"
printf 'rep\tid\ttier\trole\tmodel\tearly_stop\tpass\tstopped\treason\tsteps\ttool_calls\tcost\ttok_in\ttok_out\ttok_cache_read\tseconds\n' > "$TSV"
for rep in $(seq 1 "$REPS"); do
  for t in "${tasks[@]}"; do
    id=$(basename "$t"); tier=$(sed -n 's/^tier=//p' "$t/meta"); role=$(sed -n 's/^role=//p' "$t/meta")
    ws=$(mk_workspace "$t"); auto=(); [ "$tier" = t ] && auto=(--auto)
    stop=(); [ "$ES" = on ] && [ -f "$t/stop.txt" ] && stop=(--stop "$t/stop.txt")
    caps=(--max-steps 1000000 --max-cost 1000000); [ "$ES" = on ] && caps=(--max-steps 40 --max-cost 0.50)
    trace="$OUT/traces/$id/$rep.jsonl"; sum="$OUT/traces/$id/$rep.summary.json"
    PATH="$ws/bin:$PATH" OPENCODE_CONFIG="$REPO/clients/opencode.jsonc" \
      python3 "$HERE/lib/early_stop.py" "${stop[@]}" "${caps[@]}" --trace "$trace" \
        --answer "$ws/.bench/answer.txt" --summary "$sum" -- \
        opencode run --format json -m "$MODEL" --dir "$ws" "${auto[@]}" "$(cat "$t/task.md")" >/dev/null
    if out=$(bash "$t/check.sh" "$ws" 2>&1); then pass=1; else pass=0; fi
    python3 - "$sum" "$pass" "$out" <<'PY' >> "$OUT/traces/labels.jsonl"
import json, sys
s = json.load(open(sys.argv[1])); s["pass"] = sys.argv[2] == "1"; s["check_output"] = sys.argv[3][-400:]
s["trace"] = sys.argv[1].replace(".summary.json", ".jsonl"); print(json.dumps(s))
PY
    python3 - "$sum" "$rep" "$id" "$tier" "$role" "$MODEL" "$ES" "$pass" <<'PY' >> "$TSV"
import json, sys
s = json.load(open(sys.argv[1])); r, i, t, ro, m, es, p = sys.argv[2:9]
k = s["tokens"]
print("\t".join(map(str, [r, i, t, ro, m, es, p, int(s["stopped"]), s["reason"] or "", s["steps"], s["tool_calls"],
                          round(s["cost"], 6), k["input"], k["output"], k["cache_read"], s["seconds"]])))
PY
    printf '  %s rep %s: %s%s\n' "$id" "$rep" "$([ $pass = 1 ] && echo PASS || echo FAIL)" "$(grep -q '"stopped": true' "$sum" && echo ' (fermato presto)')"
    rm -rf "$ws"
  done
done
python3 "$HERE/lib/report.py" "$TSV"
