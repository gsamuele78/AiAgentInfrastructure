#!/usr/bin/env bash
cd "$1" || exit 1
[ "$(sha256sum test_lanes.py | cut -d' ' -f1)" = "$(cat "$(dirname "$0")/test.sha256")" ] || { echo "il test e' stato modificato"; exit 1; }
out=$(python3 -m unittest -q test_lanes 2>&1) || { echo "test rossi"; echo "$out" | tail -5; exit 1; }
python3 - <<'PY'
import ast, sys
t = ast.parse(open("lanes.py").read())
fns = {f.name: f for f in t.body if isinstance(f, ast.FunctionDef)}
if "parse_lane" not in fns: sys.exit("manca parse_lane")
from lanes import parse_lane
if parse_lane(" a = m@x @ https://h ") != ("a", "m@x", "https://h"): sys.exit("parse_lane non restituisce (nome, modello, endpoint)")
for n in ("local_lanes", "cloud_lanes"):
    calls = [c for c in ast.walk(fns[n]) if isinstance(c, ast.Call) and getattr(c.func, "id", "") == "parse_lane"]
    if not calls: sys.exit(f"{n} non usa parse_lane")
    if any(isinstance(c, ast.Call) and getattr(c.func, "attr", "") == "rsplit" for c in ast.walk(fns[n])):
        sys.exit(f"{n} ripete ancora il parsing")
PY
[ $? = 0 ] || exit 1
