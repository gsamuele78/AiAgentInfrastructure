# 0002 — Headroom come proxy davanti a LiteLLM
- **Status**: **Superseded by [0003](0003-headroom-come-callback.md)**
- **Data**: 2026-06-24

## Contesto
Ridurre i token consumati dagli agenti. Headroom offre compressione reversibile
ed espone un proxy HTTP su :8787.

## Decisione (allora)
Proxy headroom davanti: agenti → headroom → LiteLLM.

## Perché è stata superata
La documentazione ufficiale Headroom ("With LiteLLM Proxy") prescrive
l'integrazione via **callback** nel `pre_call_hook`. Il proxy davanti comporta
doppio hop, compressione fuori dal gateway e copertura di un solo upstream.
Inoltre la configurazione reale osservata puntava `--openai-api-url` a
OpenRouter, **bypassando LiteLLM** e annullando routing, budget e spend.
