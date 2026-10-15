#!/usr/bin/env bash
cd "$1" || exit 1
python3 - <<'PY' || exit 1
import re, sys
t = open("docs/PRD.md").read()
func = t.split("### Funzionali", 1)[1].split("###", 1)[0]
rows = [r for r in func.splitlines() if r.startswith("|") and not set(r) <= set("|- ")]
cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows[1:]]
ids = [c[0] for c in cells]
if ids[:2] != ["F1", "F2"]: sys.exit("ID esistenti cambiati: %s" % ids)
f3 = [c for c in cells if c[0] == "F3"]
if len(f3) != 1: sys.exit("F3 assente o duplicato nella tabella funzionale")
c = f3[0]
if len(c) != 4: sys.exit("riga F3 con %d colonne invece di 4" % len(c))
if "spesa" not in c[1].lower(): sys.exit("testo del requisito F3 sbagliato: %s" % c[1])
if c[2] != "SHOULD": sys.exit("priorita' F3: %s" % c[2])
if len(c[3]) < 3: sys.exit("F3 senza criterio di verifica")
if "F3" in t.split("### Non-funzionali", 1)[1]: sys.exit("F3 finito tra i non-funzionali")
PY
