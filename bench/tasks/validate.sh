#!/usr/bin/env bash
# ============================================================
#  bench/tasks/validate.sh -- i golden task sono sani? Offline, nessun LLM.
#  Per ogni task (ADR-0025 §1, accettazione di P0b):
#    V1 il controllo BOCCIA il workspace appena creato (il task non e' gia' risolto)
#    V2 il controllo PROMUOVE la soluzione di riferimento (solution.sh)
#    V3 il controllo BOCCIA la soluzione sbagliata (bad.sh): sa fallire
#    V4 meta e task.md presenti; tier t (richiesto) o b (comportamento)
#    V5 le regole di stop non scattano sui comandi della soluzione
#  E l'early stopper (lib/early_stop.py) su un agente finto:
#    E1 ferma su un tool vietato · E2 ferma oltre il budget · E3 lascia finire un run pulito
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/workspace.sh
. "$HERE/lib/workspace.sh"
P=0; F=0
ok(){ echo -e "  \033[32m✓\033[0m $1"; P=$((P+1)); }
ko(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo "$2" | tail -5 | sed 's/^/      /'; F=$((F+1)); }
ROLES=""
echo -e "\n\033[36m── golden task (bench/tasks)\033[0m"
for t in "$HERE"/[tb][0-9][0-9]-*/; do
  t=${t%/}; id=$(basename "$t")
  # shellcheck disable=SC1091
  tier=$(sed -n 's/^tier=//p' "$t/meta" 2>/dev/null); role=$(sed -n 's/^role=//p' "$t/meta" 2>/dev/null)
  if [ -s "$t/task.md" ] && [[ "$tier" =~ ^[tb]$ ]] && [ -n "$role" ] && [ "${id:0:1}" = "$tier" ]; then ok "$id V4 meta ($tier, $role)"
  else ko "$id V4 meta/task.md mancanti o tier incoerente col nome"; fi
  ROLES="$ROLES $role"
  ws=$(mk_workspace "$t"); out=$(bash "$t/check.sh" "$ws" 2>&1) && ko "$id V1 il controllo promuove il workspace vuoto" "$out" || ok "$id V1 workspace vuoto bocciato"; rm -rf "$ws"
  ws=$(mk_workspace "$t"); bash "$t/solution.sh" "$ws" >/dev/null 2>&1
  out=$(bash "$t/check.sh" "$ws" 2>&1) && ok "$id V2 soluzione di riferimento promossa" || ko "$id V2 soluzione di riferimento bocciata" "$out"; rm -rf "$ws"
  ws=$(mk_workspace "$t"); bash "$t/bad.sh" "$ws" >/dev/null 2>&1
  out=$(bash "$t/check.sh" "$ws" 2>&1) && ko "$id V3 soluzione sbagliata promossa (controllo che non protegge)" || ok "$id V3 soluzione sbagliata bocciata"; rm -rf "$ws"
  if [ -f "$t/stop.txt" ]; then
    hit=$(grep -E '^\s*[^#]' "$t/solution.sh" | python3 -I -c "
import re,sys
rules=[l.split(':',1) for l in open(sys.argv[1]).read().splitlines() if l.strip() and not l.startswith('#')]
for line in sys.stdin:
  for k,rx in rules:
    if k=='cmd' and re.search(rx,line): print(line.strip())" "$t/stop.txt")
    [ -z "$hit" ] && ok "$id V5 regole di stop silenziose sulla soluzione" || ko "$id V5 lo stop scatta sulla soluzione" "$hit"
  fi
done
for r in system-engineering sviluppo software-design prd; do
  n=$(tr ' ' '\n' <<<"$ROLES" | grep -cx "$r")
  [ "$n" -ge 2 ] && ok "ruolo $r: $n task" || ko "ruolo $r: $n task (P0b ne chiede 2 per ruolo)"
done

echo -e "\n\033[36m── early stopper (agente finto)\033[0m"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cat > "$W/agent.py" <<'PY'
import json, sys, time
for ev in json.load(open(sys.argv[1])):
    print(json.dumps(ev), flush=True); time.sleep(0.01)
time.sleep(5)  # se lo stopper non uccide, il test se ne accorge dalla durata
PY
ev(){ printf '%s' "$1" > "$W/ev.json"; }
step='{"type":"step_finish","part":{"cost":0.2,"tokens":{"input":100,"output":10}}}'
ev "[{\"type\":\"tool_use\",\"part\":{\"tool\":\"bash\",\"state\":{\"input\":{\"command\":\"docker compose -f services/docker-compose.yml down -v\"}}}},$step]"
python3 "$HERE/lib/early_stop.py" --stop "$HERE/b02-conferma-distruttiva/stop.txt" --trace "$W/t" --summary "$W/s" -- python3 "$W/agent.py" "$W/ev.json"; rc=$?
[ "$rc" = 3 ] && grep -q 'comando vietato' "$W/s" && ok "E1 fermato su comando vietato" || ko "E1 non fermato (rc=$rc)" "$(cat "$W/s")"
ev "[$step,$step,$step,{\"type\":\"text\",\"part\":{\"text\":\"x\"}}]"
python3 "$HERE/lib/early_stop.py" --max-cost 0.5 --trace "$W/t" --summary "$W/s" -- python3 "$W/agent.py" "$W/ev.json"; rc=$?
[ "$rc" = 3 ] && grep -q 'costo oltre' "$W/s" && ok "E2 fermato oltre il budget" || ko "E2 budget ignorato (rc=$rc)" "$(cat "$W/s")"
printf 'import json\nprint(json.dumps({"type":"tool_use","part":{"tool":"read","state":{"input":{}}}}))\nprint(json.dumps({"type":"text","part":{"text":"fatto"}}))\n' > "$W/clean.py"
python3 "$HERE/lib/early_stop.py" --stop "$HERE/b01-solo-parere/stop.txt" --trace "$W/t" --answer "$W/a" --summary "$W/s" -- python3 "$W/clean.py"; rc=$?
[ "$rc" = 0 ] && [ "$(cat "$W/a")" = fatto ] && ok "E3 run pulito arriva in fondo, risposta salvata" || ko "E3 run pulito (rc=$rc)" "$(cat "$W/s")"

echo -e "\n  golden task: \033[32m✓ $P\033[0m  \033[31m✗ $F\033[0m"
[ "$F" = 0 ]
