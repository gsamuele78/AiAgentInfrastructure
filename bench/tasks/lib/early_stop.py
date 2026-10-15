#!/usr/bin/env python3
"""Esegue un agente che emette eventi JSON (opencode run --format json) e lo ferma presto.

Pratica importata da OpenHands (tests/integration/early_stopper.py, MIT; ADR-0025 §1):
quando un fallimento e' gia' certo -- l'agente ha chiamato un tool vietato, ha superato
i passi o il budget -- continuare costa token e non cambia il verdetto.

  early_stop.py --stop task/stop.txt --max-steps 40 --max-cost 0.50 \
                --trace out/trace.jsonl --answer ws/.bench/answer.txt \
                --summary out/summary.json -- opencode run --format json ...

stop.txt: una regola per riga, `tool:<regex>` sul nome del tool o `cmd:<regex>` sul
comando bash. Eventi letti: tool_use (part.tool, part.state.input), step_finish
(part.cost, part.tokens), text (part.text), error.
Uscita: 0 l'agente ha finito da solo · 3 fermato (motivo in summary) · altro = rc dell'agente.
"""
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path


def load_rules(path):
    rules = []
    if path and Path(path).exists():
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            kind, _, rx = line.partition(":")
            if kind not in ("tool", "cmd"):
                raise SystemExit(f"regola non valida in {path}: {line}")
            rules.append((kind, re.compile(rx)))
    return rules


def check_event(ev, rules):
    """motivo di stop per questo evento, o None"""
    if ev.get("type") != "tool_use":
        return None
    part = ev.get("part", {})
    name = str(part.get("tool", ""))
    cmd = str((part.get("state", {}).get("input") or {}).get("command", ""))
    for kind, rx in rules:
        if kind == "tool" and rx.search(name):
            return f"tool vietato: {name}"
        if kind == "cmd" and cmd and rx.search(cmd):
            return f"comando vietato: {cmd[:120]}"
    return None


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--stop")
    ap.add_argument("--max-steps", type=int, default=40)
    ap.add_argument("--max-cost", type=float, default=0.50)
    ap.add_argument("--trace", required=True)
    ap.add_argument("--answer")
    ap.add_argument("--summary", required=True)
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args(argv)
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    rules = load_rules(a.stop)
    s = {"stopped": False, "reason": None, "steps": 0, "tool_calls": 0, "cost": 0.0,
         "tokens": {"input": 0, "output": 0, "cache_read": 0}, "errors": 0}
    texts, t0 = [], time.monotonic()
    Path(a.trace).parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
    with open(a.trace, "w") as tr:
        for line in proc.stdout:
            tr.write(line)
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            t = ev.get("type")
            part = ev.get("part", {}) or {}
            if t == "tool_use":
                s["tool_calls"] += 1
            elif t == "step_finish":
                s["steps"] += 1
                s["cost"] += float(part.get("cost") or 0)
                tok = part.get("tokens") or {}
                s["tokens"]["input"] += int(tok.get("input") or 0)
                s["tokens"]["output"] += int(tok.get("output") or 0)
                s["tokens"]["cache_read"] += int((tok.get("cache") or {}).get("read") or 0)
            elif t == "text" and part.get("text"):
                texts.append(part["text"])
            elif t == "error":
                s["errors"] += 1
            reason = check_event(ev, rules)
            if not reason and s["steps"] > a.max_steps:
                reason = f"passi oltre {a.max_steps}"
            if not reason and s["cost"] > a.max_cost:
                reason = f"costo oltre {a.max_cost} $"
            if reason:
                s["stopped"], s["reason"] = True, reason
                proc.kill()
                break
    rc = proc.wait()
    s["seconds"] = round(time.monotonic() - t0, 2)
    s["rc"] = rc
    if a.answer:
        Path(a.answer).parent.mkdir(parents=True, exist_ok=True)
        Path(a.answer).write_text("\n".join(texts))
    Path(a.summary).write_text(json.dumps(s, indent=2))
    return 3 if s["stopped"] else rc


if __name__ == "__main__":
    sys.exit(main())
