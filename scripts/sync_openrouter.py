#!/usr/bin/env python3
"""Riconcilia il catalogo OpenRouter nel DB di LiteLLM (ADR-0004).

Il wildcard `openrouter/*` instrada ma non popola /v1/models (dropdown vuoto)
e non porta il pricing (spend a zero). Questo script calcola il diff tra il
catalogo OpenRouter e i modelli gia' nel DB, e lo applica a caldo via
/model/new e /model/delete: nessun restart, nessuna model_list a mano.

SICUREZZA -- la proprieta' che conta:
  cancella SOLO i modelli che ha creato lui, riconosciuti da
  model_info.managed_by == "sync_openrouter". I modelli curati a mano
  (claude-*, or-private, local-*, biome-coder) non vengono mai toccati,
  qualunque cosa risponda OpenRouter.

Uso:
  ./sync_openrouter.py --dry-run          # stampa il piano, non tocca nulla
  ./sync_openrouter.py                    # applica (chiede conferma)
  ./sync_openrouter.py --yes              # applica senza conferma (cron)
  ./sync_openrouter.py --filter anthropic # solo gli id che contengono la stringa
  ./sync_openrouter.py --no-prune         # aggiunge e aggiorna, non cancella

Env:
  LITELLM_MASTER_KEY  obbligatoria
  LITELLM_PROXY       default http://127.0.0.1:4000
  OPENROUTER_MODELS_URL  default https://openrouter.ai/api/v1/models

Exit: 0 ok (anche se non c'e' nulla da fare) · 1 errore · 2 prerequisiti mancanti.
Solo stdlib.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

TAG = "sync_openrouter"  # marchio dei modelli gestiti: NON cambiarlo alla leggera
PROXY = os.environ.get("LITELLM_PROXY", "http://127.0.0.1:4000").rstrip("/")
KEY = os.environ.get("LITELLM_MASTER_KEY", "")
OR_URL = os.environ.get("OPENROUTER_MODELS_URL", "https://openrouter.ai/api/v1/models")

C = {"g": "\033[32m", "y": "\033[33m", "r": "\033[31m", "b": "\033[36m", "d": "\033[2m", "0": "\033[0m"}


def sec(t: str) -> None:
    print(f"\n{C['b']}== {t} =={C['0']}")


def ok(m: str) -> None:
    print(f"  {C['g']}✓{C['0']} {m}")


def warn(m: str) -> None:
    print(f"  {C['y']}!{C['0']} {m}")


def die(m: str, hint: str = "", code: int = 1):
    print(f"  {C['r']}✗{C['0']} {m}", file=sys.stderr)
    if hint:
        print(f"     {C['d']}→ {hint}{C['0']}", file=sys.stderr)
    sys.exit(code)


def http(url: str, payload: dict | None = None, timeout: int = 30) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data)
    req.add_header("Accept", "application/json")
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    if KEY and url.startswith(PROXY):
        req.add_header("Authorization", f"Bearer {KEY}")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read().decode("utf-8", "replace")
    return json.loads(body) if body.strip() else {}


def price(v) -> float | None:
    """OpenRouter espone il pricing come stringa USD/token. '0' e '-1' = ignoto."""
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return f if f > 0 else None


def fetch_openrouter(flt: str | None) -> dict[str, dict]:
    try:
        d = http(OR_URL)
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as e:
        die(f"catalogo OpenRouter non raggiungibile: {e}",
            "serve rete verso openrouter.ai; OPENROUTER_MODELS_URL per un mirror", 2)
    out: dict[str, dict] = {}
    for m in d.get("data", []):
        mid = m.get("id")
        if not mid or (flt and flt not in mid):
            continue
        p = m.get("pricing") or {}
        out[mid] = {
            "in": price(p.get("prompt")),
            "out": price(p.get("completion")),
            "ctx": m.get("context_length"),
        }
    return out


def fetch_litellm() -> tuple[dict[str, dict], int]:
    """Ritorna (modelli gestiti da noi, numero di modelli curati a mano)."""
    try:
        d = http(f"{PROXY}/model/info")
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as e:
        die(f"gateway non raggiungibile su {PROXY}: {e}",
            "VM su? litellm-forward attivo? master key corretta? (VM-KVM-GUIDE.md)", 2)
    managed: dict[str, dict] = {}
    manual = 0
    for m in d.get("data", []):
        info = m.get("model_info") or {}
        name = m.get("model_name", "")
        if info.get("managed_by") != TAG:
            manual += 1
            continue
        managed[name] = {
            "id": info.get("id"),
            "in": info.get("input_cost_per_token"),
            "out": info.get("output_cost_per_token"),
        }
    return managed, manual


def same_price(a, b) -> bool:
    if a is None and b is None:
        return True
    if a is None or b is None:
        return False
    return abs(float(a) - float(b)) < 1e-12


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--dry-run", action="store_true", help="stampa il piano, non applica")
    ap.add_argument("--yes", action="store_true", help="applica senza chiedere conferma")
    ap.add_argument("--filter", default=None, metavar="SUBSTR", help="solo gli id che contengono SUBSTR")
    ap.add_argument("--no-prune", action="store_true", help="non cancellare i modelli spariti da OpenRouter")
    a = ap.parse_args()

    if not KEY:
        die("LITELLM_MASTER_KEY non impostata", "source clients/shell-env.sh", 2)

    sec("1. Catalogo OpenRouter")
    desired = fetch_openrouter(a.filter)
    ok(f"{len(desired)} modelli" + (f" (filtro '{a.filter}')" if a.filter else ""))
    if not desired:
        warn("catalogo vuoto: non tocco nulla (un filtro troppo stretto?)")
        return 0

    sec("2. Stato nel DB LiteLLM")
    current, manual = fetch_litellm()
    ok(f"{len(current)} gestiti da {TAG}, {manual} curati a mano (mai toccati)")

    sec("3. Diff")
    add, upd, rm = [], [], []
    for mid, d in desired.items():
        name = f"openrouter/{mid}"
        cur = current.get(name)
        if cur is None:
            add.append((name, mid, d))
        elif not (same_price(cur["in"], d["in"]) and same_price(cur["out"], d["out"])):
            upd.append((name, mid, d, cur))
    if not a.no_prune:
        wanted = {f"openrouter/{m}" for m in desired}
        # Con --filter il catalogo e' parziale: cancellare sarebbe una strage.
        if a.filter:
            warn("--filter attivo: prune disabilitato (il catalogo e' parziale)")
        else:
            rm = [(n, c["id"]) for n, c in current.items() if n not in wanted]
    print(f"  {C['g']}+{len(add)}{C['0']} da aggiungere   "
          f"{C['y']}~{len(upd)}{C['0']} pricing cambiato   "
          f"{C['r']}-{len(rm)}{C['0']} da rimuovere")
    for n, _, d in add[:10]:
        print(f"    {C['d']}+ {n}  in={d['in']} out={d['out']}{C['0']}")
    if len(add) > 10:
        print(f"    {C['d']}  ... e altri {len(add)-10}{C['0']}")
    for n, _, d, cur in upd[:10]:
        print(f"    {C['d']}~ {n}  {cur['in']}->{d['in']} / {cur['out']}->{d['out']}{C['0']}")
    if len(upd) > 10:
        print(f"    {C['d']}  ... e altri {len(upd)-10}{C['0']}")
    for n, _ in rm[:10]:
        print(f"    {C['d']}- {n}{C['0']}")
    if len(rm) > 10:
        print(f"    {C['d']}  ... e altri {len(rm)-10}{C['0']}")

    if not (add or upd or rm):
        ok("gia' allineato: nulla da fare")
        return 0
    if a.dry_run:
        print(f"\n{C['d']}dry-run: nessuna modifica applicata.{C['0']}")
        return 0
    if not a.yes:
        try:
            if input("\n  Applicare? [y/N] ").strip().lower() != "y":
                print("  annullato")
                return 0
        except EOFError:
            die("stdin non interattivo: usa --yes oppure --dry-run")

    sec("4. Applicazione")
    errs = 0

    def body(name: str, mid: str, d: dict, mid_id: str | None = None) -> dict:
        params = {"model": f"openrouter/{mid}", "api_key": "os.environ/OPENROUTER_API_KEY"}
        info = {"managed_by": TAG}
        if d["in"] is not None:
            info["input_cost_per_token"] = d["in"]
        if d["out"] is not None:
            info["output_cost_per_token"] = d["out"]
        if d["ctx"]:
            info["max_input_tokens"] = d["ctx"]
        if mid_id:
            info["id"] = mid_id
        return {"model_name": name, "litellm_params": params, "model_info": info}

    for n, mid, d in add:
        try:
            http(f"{PROXY}/model/new", body(n, mid, d)); print(f"  + {n}")
        except Exception as e:  # noqa: BLE001 - un modello rotto non ferma il sync
            warn(f"add {n}: {e}"); errs += 1
    for n, mid, d, cur in upd:
        # /model/new con lo stesso id fa upsert del pricing.
        try:
            http(f"{PROXY}/model/new", body(n, mid, d, cur["id"])); print(f"  ~ {n}")
        except Exception as e:  # noqa: BLE001
            warn(f"update {n}: {e}"); errs += 1
    for n, mid_id in rm:
        if not mid_id:
            warn(f"delete {n}: id assente, salto"); errs += 1; continue
        try:
            http(f"{PROXY}/model/delete", {"id": mid_id}); print(f"  - {n}")
        except Exception as e:  # noqa: BLE001
            warn(f"delete {n}: {e}"); errs += 1

    sec("Esito")
    if errs:
        print(f"  {C['y']}completato con {errs} errori{C['0']} — rilancia con --dry-run per il residuo")
        return 1
    ok("catalogo allineato")
    print(f"  {C['d']}verifica: curl -H \"Authorization: Bearer $LITELLM_MASTER_KEY\" {PROXY}/v1/models{C['0']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
