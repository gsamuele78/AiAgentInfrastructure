#!/usr/bin/env python3
"""Rilevatore di loop, offline, sulle tracce degli agenti (ADR-0025 §7: SOLO misura).

Euristiche e soglie di OpenHands (software-agent-sdk conversation/stuck_detector.py e
StuckDetectionThresholds, MIT), applicate alle tracce JSON di opencode
(`opencode run --format json`, come le salva bench/tasks/run.sh):
  L1 action_observation  stessa azione con la stessa osservazione >= 4 volte di fila
  L2 action_error        stessa azione che fallisce >= 3 volte di fila
  L3 monologue           stesso messaggio dell'agente >= 3 volte di fila
  L4 alternating         A,B,A,B,A,B con le stesse osservazioni (>= 6 passi)
Finestra: gli ultimi 20 eventi, come OpenHands. Non ferma niente: conta. Un guard si
costruisce solo se la misura lo giustifica (bench/stuck/PREREG.md).

Uso: analyze.py TRACCIA_O_DIR... [--json]
"""
import json
import sys
from pathlib import Path

WINDOW = 20
TH = {"action_observation": 4, "action_error": 3, "monologue": 3, "alternating": 6}


def load(path):
    """eventi normalizzati: ('act', chiave_azione, osservazione, errore) o ('msg', testo)"""
    out = []
    for line in Path(path).read_text().splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        p = ev.get("part") or {}
        if ev.get("type") == "tool_use":
            st = p.get("state") or {}
            key = p.get("tool", "") + " " + json.dumps(st.get("input") or {}, sort_keys=True)
            err = st.get("status") == "error"
            obs = str(st.get("error") if err else st.get("output", ""))[:2000]
            out.append(("act", key, obs, err))
        elif ev.get("type") == "text" and p.get("text"):
            out.append(("msg", p["text"].strip()))
    return out


def detect(events):
    found = set()
    ev = events[-WINDOW:]
    acts = [e for e in ev if e[0] == "act"]
    for i in range(len(acts)):
        run = acts[i:i + TH["action_observation"]]
        if len(run) == TH["action_observation"] and len({(a[1], a[2]) for a in run}) == 1 and not run[0][3]:
            found.add("action_observation")
        run = acts[i:i + TH["action_error"]]
        if len(run) == TH["action_error"] and len({a[1] for a in run}) == 1 and all(a[3] for a in run):
            found.add("action_error")
        run = acts[i:i + TH["alternating"]]
        if len(run) == TH["alternating"]:
            a, b = (run[0][1], run[0][2]), (run[1][1], run[1][2])
            if a != b and all((x[1], x[2]) == (a if j % 2 == 0 else b) for j, x in enumerate(run)):
                found.add("alternating")
    streak, last = 0, None
    for e in ev:
        if e[0] == "msg":
            streak = streak + 1 if e[1] == last else 1
            last = e[1]
            if streak >= TH["monologue"]:
                found.add("monologue")
        else:
            streak, last = 0, None
    return sorted(found)


def main(argv):
    as_json = "--json" in argv
    files = []
    for a in (x for x in argv if x != "--json"):
        p = Path(a)
        files += sorted(p.rglob("*.jsonl")) if p.is_dir() else [p]
    files = [f for f in files if f.name != "labels.jsonl"]
    res = {str(f): detect(load(f)) for f in files}
    flagged = {k: v for k, v in res.items() if v}
    if as_json:
        print(json.dumps(res, indent=2))
    else:
        for k, v in flagged.items():
            print(f"  loop {','.join(v)}: {k}")
        n = len(res)
        print(f"  tracce: {n} · con loop: {len(flagged)} ({len(flagged)/n:.0%})" if n else "  nessuna traccia")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
