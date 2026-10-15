#!/usr/bin/env python3
"""Sonde di conformita' API sulla catena `auto` (pratica importata da OpenHands, ADR-0025 §2).

Il problema, specifico dell'ibrido: la catena `auto` (ADR-0016) cambia provider a meta'
conversazione. Una storia che Ollama tollera (tool_use senza tool_result, id duplicati,
risultati paralleli in ordine sbagliato) puo' prendere un 400 da Anthropic -- e lo scopri
solo DOPO il fallback, cioe' quando il locale e' gia' caduto.

Le 8 forme sono quelle di OpenHands software-agent-sdk
(tests/integration/tests/a01..a08, MIT), riscritte in formato OpenAI per il gateway.
Ogni forma va a ogni lane ATTRAVERSO il gateway, con disable_fallbacks: si misura cosa
vede il client, compresa l'eventuale riparazione fatta da LiteLLM.

Esito per cella: accept (2xx) · reject (4xx) · n/a (5xx/timeout: lane non disponibile).
Divergenza = una forma accettata da una lane e rifiutata da un'altra della stessa catena.

Uso:
  probe.py --dry-run                      stampa i payload, nessuna rete
  probe.py [--lanes a,b,c] [--out f.tsv]  default: le lane di `auto` lette dalla config
Ambiente: LITELLM_BASE_URL (default http://127.0.0.1:4000), BENCH_KEY o LITELLM_MASTER_KEY.
Uscita: 0 nessuna divergenza · 3 divergenze · 2 meno di 2 lane disponibili.
Soglie pre-registrate: bench/compliance/PREREG.md.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TOOLS = [{"type": "function", "function": {
    "name": "terminal", "description": "Run a shell command",
    "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}}]


def call(i, cmd="ls -la"):
    return {"id": i, "type": "function", "function": {"name": "terminal", "arguments": json.dumps({"command": cmd})}}


def tool(i, out="file1.txt\nfile2.txt"):
    return {"role": "tool", "tool_call_id": i, "content": out}


SYS = {"role": "system", "content": "You are a helpful assistant."}
U1 = {"role": "user", "content": "List the files in the current directory."}
U2 = {"role": "user", "content": "Thanks. Now answer in one word: done?"}


def asst(text="I'll run that.", calls=None):
    m = {"role": "assistant", "content": text}
    if calls:
        m["tool_calls"] = calls
    return m


PATTERNS = {
    "a01_unmatched_tool_use": [SYS, U1, asst(calls=[call("call_a01")]), U2],
    "a02_unmatched_tool_result": [SYS, U1, asst("Here you go."), tool("call_a02"), U2],
    "a03_interleaved_user_msg": [SYS, U1, asst(calls=[call("call_a03")]), U2, tool("call_a03")],
    "a04_interleaved_asst_msg": [SYS, U1, asst(calls=[call("call_a04")]), asst("Still working."), tool("call_a04"), U2],
    "a05_duplicate_tool_call_id": [SYS, U1, asst(calls=[call("call_dup")]), tool("call_dup"),
                                   asst(calls=[call("call_dup", "pwd")]), tool("call_dup", "/tmp"), U2],
    "a06_wrong_tool_call_id": [SYS, U1, asst(calls=[call("call_a06")]), tool("call_zzz"), U2],
    "a07_parallel_missing_result": [SYS, U1, asst(calls=[call("call_p1"), call("call_p2", "pwd")]), tool("call_p1"), U2],
    "a08_parallel_wrong_order": [SYS, U1, asst(calls=[call("call_p1"), call("call_p2", "pwd")]),
                                 tool("call_p2", "/tmp"), tool("call_p1"), U2],
}


def auto_lanes(cfg_path):
    """`auto` (la sua deployment, cioe' il locale) + i suoi fallbacks, nell'ordine della config."""
    import yaml  # solo qui: --dry-run e i test non lo richiedono
    c = yaml.safe_load(Path(cfg_path).read_text())
    fb = [list(d.values())[0] for d in c["litellm_settings"]["fallbacks"] if "auto" in d][0]
    return ["auto"] + fb


def payload(lane, msgs):
    return {"model": lane, "messages": msgs, "tools": TOOLS, "max_tokens": 16,
            "temperature": 0, "disable_fallbacks": True}


def send(base, key, body, timeout):
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, ""
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read() or b"{}").get("error", {}).get("message", "")
        except ValueError:
            msg = ""
        return e.code, " ".join(str(msg).split())[:140]
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return 0, str(e)[:140]


def classify(status):
    if 200 <= status < 300:
        return "accept"
    if 400 <= status < 500 and status not in (401, 403, 404, 408, 429):
        return "reject"
    return "n/a"   # lane giu', auth, rate limit: non dice niente sulla forma


def divergences(results, lanes):
    """forme su cui due lane disponibili danno accept vs reject"""
    out = []
    for p in PATTERNS:
        seen = {results[(p, l)][0] for l in lanes if results[(p, l)][0] != "n/a"}
        if {"accept", "reject"} <= seen:
            out.append(p)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--lanes", help="lista separata da virgole (default: catena auto dalla config)")
    ap.add_argument("--config", default=str(REPO / "services/litellm_config.yaml"))
    ap.add_argument("--out", help="TSV dei risultati (default: solo stdout)")
    ap.add_argument("--timeout", type=float, default=60)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    lanes = a.lanes.split(",") if a.lanes else auto_lanes(a.config)
    if a.dry_run:
        for p, msgs in PATTERNS.items():
            print(f"# {p}\n{json.dumps(payload(lanes[0], msgs))}")
        print(f"# lane: {', '.join(lanes)}  (nessuna richiesta inviata)")
        return 0
    base = os.environ.get("LITELLM_BASE_URL", "http://127.0.0.1:4000")
    key = os.environ.get("BENCH_KEY") or os.environ.get("LITELLM_MASTER_KEY", "")
    results, rows = {}, ["pattern\tlane\toutcome\tstatus\tmessage"]
    for p, msgs in PATTERNS.items():
        for lane in lanes:
            st, msg = send(base, key, payload(lane, msgs), a.timeout)
            results[(p, lane)] = (classify(st), st, msg)
            rows.append(f"{p}\t{lane}\t{classify(st)}\t{st}\t{msg}")
    print("\n".join(rows))
    if a.out:
        Path(a.out).parent.mkdir(parents=True, exist_ok=True)
        Path(a.out).write_text("\n".join(rows) + "\n")
    up = [l for l in lanes if any(results[(p, l)][0] != "n/a" for p in PATTERNS)]
    div = divergences(results, lanes)
    print(f"\n# lane disponibili: {len(up)}/{len(lanes)} ({', '.join(up) or '-'})")
    print(f"# divergenze: {len(div)}" + (f" -> {', '.join(div)}" if div else ""))
    if len(up) < 2:
        return 2
    return 3 if div else 0


if __name__ == "__main__":
    sys.exit(main())
