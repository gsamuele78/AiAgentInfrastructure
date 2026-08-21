# Abbonamento Claude Pro attraverso il gateway

LiteLLM documenta ufficialmente questo scenario: Claude Code fa l'OAuth con
l'abbonamento e LiteLLM **inoltra** l'header di autenticazione ad Anthropic,
restando in mezzo per compressione, logging e controlli.

## Configurazione
Lato LiteLLM (`services/litellm_config.yaml`):
```yaml
model_list:
  - model_name: anthropic-claude
    litellm_params: { model: anthropic/claude-sonnet-4-6 }   # nessuna api_key
litellm_settings:
  forward_client_headers_to_llm_api: true
```
Lato Claude Code:
```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:4000"
export ANTHROPIC_MODEL="anthropic-claude"
export ANTHROPIC_CUSTOM_HEADERS="x-litellm-api-key: Bearer sk-<virtual-key>"
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
```
Il trucco: l'`Authorization` resta libero per l'OAuth, la chiave LiteLLM viaggia
su header custom.

## Precedenza delle credenziali
- `ANTHROPIC_API_KEY` presente → vince sull'abbonamento (fatturazione a consumo)
- `ANTHROPIC_AUTH_TOKEN` presente → l'abbonamento non viene nemmeno tentato

Verifica sempre con `/status`. Il test TC-04 automatizza questo controllo.

## Nota sui termini d'uso — leggila
LiteLLM documenta il forwarding e qui il **client resta Claude Code**. Tuttavia
fonti terze riportano che i termini Anthropic limitano l'uso dei token OAuth a
Claude Code e claude.ai, e che le integrazioni terze devono usare API key.

- ✅ Claude Code → LiteLLM → Anthropic (header inoltrato): il client è Claude Code
- ❌ estrarre il token OAuth e usarlo da opencode/script: fuori dai termini

Non esiste una fonte ufficiale Anthropic che copra il caso "proxy locale in
mezzo". È il tuo account: se vuoi appoggiartici stabilmente verifica i termini
correnti; in caso di dubbio usa la **variante A** (Claude Code diretto) e le API
key per la lane gateway.

## Limiti
Pro ha limiti più stretti di Max: sessioni agentiche lunghe li toccano. Quando
Claude Code esaurisce la finestra, gli altri agenti continuano sulle lane del
gateway. Controlla con `/usage`.
