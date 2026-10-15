#!/usr/bin/env python3
"""Riassunto di results.tsv: pass@1 per tier con intervallo di Wilson, $ per task risolto (ADR-0021 §3)."""
import csv
import math
import sys
from statistics import median


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - h), min(1.0, c + h))


def main(path):
    rows = list(csv.DictReader(open(path), delimiter="\t"))
    for tier, label in (("t", "richiesti (t*)"), ("b", "comportamento (b*)")):
        r = [x for x in rows if x["tier"] == tier]
        if not r:
            continue
        k = sum(int(x["pass"]) for x in r)
        lo, hi = wilson(k, len(r))
        cost = sum(float(x["cost"]) for x in r)
        secs = [float(x["seconds"]) for x in r]
        print(f"{label}: pass@1 {k}/{len(r)} = {k/len(r):.0%} (Wilson 95%: {lo:.0%}-{hi:.0%})"
              f" · $/risolto {cost/k if k else float('inf'):.4f} · mediana {median(secs):.1f}s"
              f" · fermati presto {sum(int(x['stopped']) for x in r)}")
    if len(rows) < 20:
        print(f"attenzione: {len(rows)} tentativi < 20, pass@1 non confrontabile (ADR-0021 §3)")


if __name__ == "__main__":
    main(sys.argv[1])
