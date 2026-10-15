#!/usr/bin/env python3
"""Misura le regole ask/deny dei client sul corpus di rischio (ADR-0025 §4, gate in PREREG.md).

  recall    = quota di destructive.txt che si ferma (ask o deny)   soglia >= 95 %
  falsi ask = quota di benign.txt che si ferma                       soglia <= 5 %
Per ciascun client, con la sua semantica:
  opencode     permission.bash: per segmento vince l'ULTIMA regola che corrisponde;
               nessuna regola = allow (il default di opencode per bash)
  Claude Code  permissions: deny > ask > allow; si assume un allow ampio (Bash(*)),
               cioe' il caso peggiore in cui solo ask/deny proteggono
Un comando composto si ferma se si ferma uno qualunque dei suoi segmenti.

Uso: check.py            misura e applica il gate (uscita 1 se fallisce)
     check.py --emit     stampa i blocchi da incollare nei client, da rules.py
     check.py --verbose  elenca mancati e falsi ask
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
import rules  # noqa: E402

RECALL_MIN, FALSE_ASK_MAX = 0.95, 0.05


def strip_jsonc(text):
    """toglie commenti // e /* */ fuori dalle stringhe, e le virgole finali"""
    out, i, n, s = [], 0, len(text), False
    while i < n:
        c = text[i]
        if s:
            out.append(c)
            if c == "\\":
                out.append(text[i + 1]); i += 1
            elif c == '"':
                s = False
        elif c == '"':
            s = True; out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            i = text.index("*/", i) + 2
            continue
        else:
            out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def segments(cmd):
    """divide su | || && ; & fuori dalle virgolette"""
    segs, cur, q, i = [], [], None, 0
    while i < len(cmd):
        c = cmd[i]
        if q:
            cur.append(c)
            if c == q:
                q = None
        elif c in "'\"":
            q = c; cur.append(c)
        elif c in "|;&":
            segs.append("".join(cur)); cur = []
            while i + 1 < len(cmd) and cmd[i + 1] in "|&":
                i += 1
        else:
            cur.append(c)
        i += 1
    segs.append("".join(cur))
    return [s.strip() for s in segs if s.strip()]


def glob_re(p):
    tail = p.endswith(" *")
    body = p[:-2] if tail else p
    rx = ".*".join(re.escape(x) for x in body.split("*"))
    return re.compile(rx + (r"(?: .*)?" if tail else ""), re.S)


def matches(pattern, seg):
    return glob_re(pattern).fullmatch(seg) is not None


def opencode_rules():
    cfg = json.loads(strip_jsonc((REPO / "clients/opencode.jsonc").read_text()))
    bash = cfg.get("permission", {}).get("bash", {})
    return list(bash.items()) if isinstance(bash, dict) else []


def claude_rules():
    cfg = json.loads((REPO / "clients/claude-settings.json").read_text())
    perms = cfg.get("permissions", {})
    pick = lambda k: [r[5:-1] for r in perms.get(k, []) if r.startswith("Bash(") and r.endswith(")")]
    return pick("ask"), pick("deny")


def decide_opencode(rs, cmd):
    worst = "allow"
    for seg in segments(cmd):
        d = "allow"
        for pat, act in rs:
            if matches(pat, seg):
                d = act
        if d == "deny" or (d == "ask" and worst == "allow"):
            worst = d
    return worst


def decide_claude(ask, deny, cmd):
    segs = segments(cmd)
    if any(matches(p, s) for p in deny for s in segs):
        return "deny"
    if any(matches(p, s) for p in ask for s in segs):
        return "ask"
    return "allow"


def corpus(name):
    return [l.rstrip("\n") for l in (HERE / name).read_text().splitlines() if l.strip() and not l.startswith("#")]


def emit():
    oc = {p: "ask" for p in rules.ASK} | {p: "deny" for p in rules.DENY}
    print('"permission": { "bash": ' + json.dumps(oc, ensure_ascii=False) + " }")
    print(json.dumps({"ask": [f"Bash({p})" for p in rules.ASK], "deny": [f"Bash({p})" for p in rules.DENY]}, ensure_ascii=False))


def main():
    if "--emit" in sys.argv:
        emit(); return 0
    verbose = "--verbose" in sys.argv
    bad = 0
    oc = opencode_rules()
    ask, deny = claude_rules()
    # coerenza: i due client portano esattamente rules.py
    want_oc = [(p, "ask") for p in rules.ASK] + [(p, "deny") for p in rules.DENY]
    if oc != want_oc:
        print("  ✗ RISK: clients/opencode.jsonc permission.bash diverge da tests/risk-corpus/rules.py (check.py --emit)"); bad += 1
    if ask != rules.ASK or deny != rules.DENY:
        print("  ✗ RISK: clients/claude-settings.json ask/deny divergono da tests/risk-corpus/rules.py (check.py --emit)"); bad += 1
    D, B = corpus("destructive.txt"), corpus("benign.txt")
    for client, fn in (("opencode", lambda c: decide_opencode(oc, c)), ("claude-code", lambda c: decide_claude(ask, deny, c))):
        miss = [c for c in D if fn(c) == "allow"]
        fa = [c for c in B if fn(c) != "allow"]
        rec, far = 1 - len(miss) / len(D), len(fa) / len(B)
        ok = rec >= RECALL_MIN and far <= FALSE_ASK_MAX
        print(f"  {'✓' if ok else '✗ RISK:'} {client}: recall {rec:.1%} ({len(D)-len(miss)}/{len(D)}, soglia ≥{RECALL_MIN:.0%})"
              f" · falsi ask {far:.1%} ({len(fa)}/{len(B)}, soglia ≤{FALSE_ASK_MAX:.0%})")
        if verbose or not ok:
            for c in miss:
                print(f"      mancato:   {c}")
            for c in fa:
                print(f"      falso ask: {c}")
        bad += 0 if ok else 1
        # insieme tenuto da parte: si riporta, non e' un gate (vedi PREREG.md, H1)
        H = [l.split("\t", 1) for l in corpus("heldout.txt")]
        hd = [c for k, c in H if k == "D"]; hb = [c for k, c in H if k == "B"]
        hmiss = [c for c in hd if fn(c) == "allow"]; hfa = [c for c in hb if fn(c) != "allow"]
        print(f"      tenuto da parte: recall {1-len(hmiss)/len(hd):.0%} ({len(hd)-len(hmiss)}/{len(hd)})"
              f" · falsi ask {len(hfa)}/{len(hb)}")
        if verbose:
            for c in hmiss:
                print(f"      tenuto, mancato:   {c}")
            for c in hfa:
                print(f"      tenuto, falso ask: {c}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
