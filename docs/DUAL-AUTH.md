# DUAL-AUTH — abbonamento Claude Pro + gateway insieme

```
Claude Code ──OAuth abbonamento──► Anthropic          (nessun consumo API)
opencode/OpenChamber/Codex ──virtual key──► LiteLLM :4000 [headroom callback]
                                              └► OpenRouter / Anthropic / Ollama / BIOME
```

**Il punto che scioglie il dubbio:** skill, MCP e graphify vivono **nel client**,
non nel gateway. Li hai da entrambe le parti. La scelta riguarda solo se il
traffico passa dal proxy.

| Client | Auth | Perché |
|---|---|---|
| Claude Code | abbonamento Pro | già pagato: usalo per il lavoro interattivo |
| opencode / Codex | virtual key | serve routing, lane privacy/locale, spend |

## Variabili — la parte che si sbaglia
**Nessuna variabile `ANTHROPIC_*` globale** — con l'unica eccezione di
`ANTHROPIC_BASE_URL` nella variante B. Due errori silenziosi:
- `ANTHROPIC_API_KEY` impostata → **vince sull'abbonamento** (paghi a consumo)
- `ANTHROPIC_AUTH_TOKEN` impostata → Claude Code **non usa affatto** l'abbonamento

`clients/shell-env.sh` esporta solo le variabili OpenAI-compatibili. Claude Code
prende la configurazione da `~/.claude/settings.json`.

## Tre varianti per Claude Code
**(A) Abbonamento diretto** — nessuna variabile; `claude` → `/login`.
Mantieni skill/MCP/graphify. Perdi solo la compressione su questa lane.

**(B) Abbonamento + headroom** — `ANTHROPIC_BASE_URL=http://127.0.0.1:8787`,
riattivando il proxy standalone con upstream Anthropic. Recuperi la compressione.
**Questa è la variante in uso.** È un'**eccezione dichiarata** alle invarianti #1
e #2, formalizzata in [ADR-0014](adr/0014-headroom-standalone-per-la-lane-abbonamento.md):
leggilo prima di replicarla, in particolare i quattro limiti e le conseguenze
negative. In sintesi:
> - upstream **solo** `api.anthropic.com`, mai OpenRouter (era il bug di `CURRENT-STATE.md`);
> - **nessun altro client** su `:8787`: opencode, OpenChamber e Codex restano sul gateway;
> - i template in `clients/` non contengono `:8787` — la variante si configura sulla macchina;
> - pulisci l'host con `KEEP_HEADROOM=1 ./scripts/cleanup-host.sh`, altrimenti la spegni.

**(C) Abbonamento via LiteLLM** — `BASE_URL=:4000`, `ANTHROPIC_MODEL=anthropic-claude`,
`ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer sk-..."`, con
`forward_client_headers_to_llm_api: true` lato gateway. Aggiunge log e spend.
⚠️ Leggi la nota sui termini d'uso in `CLAUDE-SUBSCRIPTION.md`.

## Verifica
```bash
claude → /status     # deve dire ABBONAMENTO, non API key
opencode → /models   # coding / smart / cheap dal gateway
./scripts/test-all.sh claude   # TC-04
```
