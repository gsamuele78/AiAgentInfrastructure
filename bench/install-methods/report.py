#!/usr/bin/env python3
"""P2b: confronta i risultati di run.sh con le soglie di PREREG.md.

    bench/install-methods/report.py [dir-risultati]   -> tabella markdown su stdout

Le soglie qui sotto sono quelle pre-registrate: cambiarle dopo aver visto i
numeri viola ADR-0021.
"""
import glob
import json
import os
import sys

P1_MAX, P2_MAX, P3_MAX = 300, 3, 60
# G1 non si misura in CI (non c'e' Bazzite): e' un fatto di documentazione.
G1 = {
    "baseline": (True, "solo $HOME"),
    "mise": (True, "binario singolo in ~/.local/bin"),
    "brew": (True, "gia' nell'immagine Bazzite (/home/linuxbrew)"),
    "nix": (False, "serve /nix alla radice: su ostree e' un cambio S1 (mount o composefs)"),
    "distrobox": (True, "gia' nell'immagine Bazzite"),
}
# Regola 2: strumenti da mantenere per lo strato S3 (meno e' meglio).
TOOLS = {"mise": 1, "baseline": 3, "brew": 2, "nix": 2, "distrobox": 4}


def frac_ok(v):
    if not isinstance(v, str) or "/" not in v:
        return False
    a, b = v.split("/")
    return a == b and b != "0"


def verdict(r):
    if r.get("status") != "ok":
        return None, [f"{r.get('status')}: {r.get('reason') or r.get('step', '')}"]
    why = []
    if r.get("a1_pins_exact") is not True:
        why.append(f"A1 pin non esatti ({r.get('got_a')})")
    if r.get("a2_changed_files") != 0:
        why.append(f"A2 {r.get('a2_changed_files')} file cambiati al rilancio")
    if not frac_ok(r.get("a3_rollback_versions")):
        why.append(f"A3 {r.get('a3_rollback_versions')}" + (f" ({r['rollback_why']})" if r.get("rollback_why") else ""))
    if not frac_ok(r.get("a4_rollback_state")):
        why.append(f"A4 {r.get('a4_rollback_state')}")
    for key, lim, name in (("p1_install_s", P1_MAX, "P1"), ("p2_rerun_median_s", P2_MAX, "P2"),
                           ("p3_rollback_median_s", P3_MAX, "P3")):
        v = r.get(key)
        if isinstance(v, (int, float)) and v > lim:
            why.append(f"{name} {v}s > {lim}s")
    g1, g1why = G1.get(r["method"], (False, "?"))
    if not g1:
        why.append(f"G1 {g1why}")
    return not why, why


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "results")
    rows = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(d, "*.json")))]
    if not rows:
        print(f"nessun risultato in {d}")
        return 1
    cols = ("os", "method", "a1_pins_exact", "a2_changed_files", "a3_rollback_versions", "a4_rollback_state",
            "p1_install_s", "p2_rerun_median_s", "p3_rollback_median_s", "r1_residue_files", "r2_disk_mb")
    print("| " + " | ".join(cols) + " | esito |")
    print("|" + "---|" * (len(cols) + 1))
    eligible = {}
    for r in rows:
        ok, why = verdict(r)
        cell = ("non misurato: " if ok is None else "" if ok else "escluso: ") + ("ammesso" if ok else "; ".join(why))
        print("| " + " | ".join(str(r.get(c, "")) for c in cols) + f" | {cell} |")
        eligible.setdefault(r["method"], []).append(ok)
    # Un metodo e' ammesso se lo e' su ogni OS dove e' stato misurato.
    ok_methods = [m for m, v in eligible.items() if v and all(x is True for x in v if x is not None)
                  and any(x is True for x in v)]
    print()
    if not ok_methods:
        print("**Decisione (regola 4)**: nessun metodo supera le soglie; resta la baseline.")
        return 0

    def p3(m):
        vals = [r.get("p3_rollback_median_s") or 0 for r in rows if r["method"] == m and r.get("status") == "ok"]
        return max(vals) if vals else 0
    best = sorted(ok_methods, key=lambda m: (TOOLS.get(m, 9), p3(m)))
    print(f"**Ammessi**: {', '.join(best)}. **Decisione (regole 2-3)**: `{best[0]}` "
          f"({TOOLS.get(best[0])} strumento/i da mantenere, rollback {p3(best[0])} s nel caso peggiore).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
