#!/usr/bin/env python3
"""Genera una config LiteLLM "mock" dalla config VERA del gateway.

Pratica importata da OpenHands (mock LLM per e2e deterministici, ADR-0025 §3):
stessi model_name, stessi gruppi, stessi fallbacks e router_settings di
services/litellm_config.yaml, ma nessun provider reale e nessun segreto:
  - lane locali (ollama_chat/*) e BIOME -> api_base su una porta chiusa:
    falliscono come "Ollama spento", quindi il router fa fallback DAVVERO;
  - lane cloud -> mock_response "MOCK:<model_name>": la risposta dice chi ha
    risposto, cosi' il test verifica l'ordine della catena;
  - --mask: aggiunge il callback di bench/secret-canary/secret_mask.py (ADR-0025 §6);
  - --fail NOME: quella lane cloud risponde InternalServerError (per provare
    il secondo anello);
  - callback headroom -> probe_callback.handler (registra le chiamate);
  - niente database: general_settings ridotto alla master key di test.
Se cambia la catena in services/litellm_config.yaml, il mock la segue da solo.

Uso: gen-config.py [--src services/litellm_config.yaml] [--fail lane]... > mock.yaml
"""
import argparse
import sys
from pathlib import Path

import yaml

CLOSED = "http://127.0.0.1:9"  # discard: nessuno ascolta -> connection refused


def mock_entry(entry, fail):
    name = entry["model_name"]
    p = entry.get("litellm_params", {})
    model = str(p.get("model", ""))
    out = {"model_name": name}
    if model.startswith(("ollama", "ollama_chat")) or "api_base" in p:
        q = {"model": model, "api_base": CLOSED, "timeout": 5}
        for k in ("num_ctx",):
            if k in p:
                q[k] = p[k]
        out["litellm_params"] = q
    else:
        resp = "litellm.InternalServerError" if name in fail else f"MOCK:{name}"
        q = {"model": "openai/mock-" + name.replace("/", "-").replace("*", "any"),
             "api_key": "sk-mock", "mock_response": resp}
        if "cache_control_injection_points" in p:
            q["cache_control_injection_points"] = p["cache_control_injection_points"]
        out["litellm_params"] = q
    if "model_info" in entry:
        out["model_info"] = entry["model_info"]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(Path(__file__).resolve().parents[2] / "services/litellm_config.yaml"))
    ap.add_argument("--fail", action="append", default=[])
    ap.add_argument("--mask", action="store_true", help="aggiunge bench/secret-canary/secret_mask.handler")
    a = ap.parse_args()
    src = yaml.safe_load(Path(a.src).read_text())
    ls = dict(src.get("litellm_settings", {}))
    ls["callbacks"] = (["secret_mask.handler"] if a.mask else []) + ["probe_callback.handler"]
    ls["num_retries"] = 0
    ls["request_timeout"] = 30
    cfg = {
        "model_list": [mock_entry(e, set(a.fail)) for e in src["model_list"]],
        "litellm_settings": ls,
        "router_settings": src.get("router_settings", {}),
        "general_settings": {"master_key": "sk-mock-ci"},
    }
    yaml.safe_dump(cfg, sys.stdout, sort_keys=False)


if __name__ == "__main__":
    main()
