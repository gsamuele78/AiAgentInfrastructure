#!/usr/bin/env python3
"""Converte le tracce etichettate di bench/tasks nei due input di SkillRefiner (ADR-0025 §11).

SkillRefiner (OpenHands, MIT, commit 9a03ded) raffina una skill OFFLINE da tracce passate e
dal loro esito, senza nuovi rollout. Vuole (RUNNING.md §6):
  traces.jsonl          {"trace_id", "spans": [{"span_id","name","input_text","output_text",
                         "start_time","end_time"}]}
  binary_rewards.json   {trace_id: bool}  -- dal nostro check.sh, non dall'agente
Qui l'esito e' quello deterministico dei golden task (labels.jsonl di run.sh).

Uso: export.py RESULTS_DIR... --out DIR [--task t01] [--min-per-side 3]
Esce 2 se una delle due partizioni ha meno di --min-per-side tracce (SkillRefiner la
salterebbe: servono >= 3 successi e >= 3 fallimenti, e il paper ne usa centinaia).
"""
import argparse
import datetime as dt
import json
import sys
from pathlib import Path


def iso(ms):
    return dt.datetime.fromtimestamp((ms or 0) / 1000, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def spans(trace_path):
    out = []
    for i, line in enumerate(Path(trace_path).read_text().splitlines()):
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        p, ts = ev.get("part") or {}, ev.get("timestamp")
        if ev.get("type") == "tool_use":
            st = p.get("state") or {}
            out.append({"span_id": f"s{i}", "name": f"tool:{p.get('tool', '')}",
                        "input_text": json.dumps(st.get("input") or {}, ensure_ascii=False),
                        "output_text": str(st.get("error") or st.get("output") or "")[:4000],
                        "start_time": iso(ts), "end_time": iso(ts)})
        elif ev.get("type") == "text" and p.get("text"):
            out.append({"span_id": f"s{i}", "name": "agent_message", "input_text": "",
                        "output_text": p["text"][:4000], "start_time": iso(ts), "end_time": iso(ts)})
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("results", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--task", help="solo i task con questo prefisso (es. t01)")
    ap.add_argument("--min-per-side", type=int, default=3)
    a = ap.parse_args(argv)
    traces, rewards = [], {}
    for r in a.results:
        for line in (Path(r) / "traces" / "labels.jsonl").read_text().splitlines():
            lab = json.loads(line)
            tp = Path(lab["trace"])
            task = tp.parent.name
            if a.task and not task.startswith(a.task):
                continue
            tid = f"{Path(r).name}/{task}/{tp.stem}"
            sp = spans(tp) if tp.exists() else []
            if not any(s["output_text"] for s in sp):
                continue
            traces.append({"trace_id": tid, "spans": sp})
            rewards[tid] = bool(lab["pass"])
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "traces.jsonl").write_text("".join(json.dumps(t, ensure_ascii=False) + "\n" for t in traces))
    (out / "binary_rewards.json").write_text(json.dumps(rewards, indent=1))
    pos = sum(rewards.values())
    neg = len(rewards) - pos
    print(f"tracce: {len(traces)} · successi {pos} · fallimenti {neg} -> {out}")
    if min(pos, neg) < a.min_per_side:
        print(f"attenzione: servono >= {a.min_per_side} tracce per lato; SkillRefiner salterebbe la partizione")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
