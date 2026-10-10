# shellcheck shell=bash
# Questo file va SORGATO (source), non eseguito: nessuno shebang.
# Sorgi da ~/.bashrc. NON esporta ANTHROPIC_*: scavalcherebbe l'abbonamento.
export PATH="$HOME/.opencode/bin:$PATH"
[ -r "$HOME/.config/litellm/master.key" ] && \
  export LITELLM_MASTER_KEY="$(cat "$HOME/.config/litellm/master.key")"
export OPENAI_BASE_URL="http://127.0.0.1:4000/v1"
export OPENAI_API_KEY="${LITELLM_MASTER_KEY:-}"
# Claude Code: vedi docs/DUAL-AUTH.md (3 varianti). NON esportare qui
# ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN.

# claude-gw — Claude Code sulla catena `auto` del gateway (ADR-0016), per quando
# la finestra dell'abbonamento e' esaurita. Le variabili valgono SOLO per questo
# processo (`env`, niente export): `claude` liscio resta sull'abbonamento.
# Fattura a consumo (API key Anthropic nel gateway, poi OpenRouter). Il tier
# locale qui non scatta quasi mai: il prompt di Claude Code supera i 12k token.
claude-gw() {
  [ -n "${LITELLM_MASTER_KEY:-}" ] || { echo "claude-gw: LITELLM_MASTER_KEY assente" >&2; return 1; }
  env -u ANTHROPIC_API_KEY \
    ANTHROPIC_BASE_URL="http://127.0.0.1:4000" \
    ANTHROPIC_AUTH_TOKEN="${LITELLM_VIRTUAL_KEY:-$LITELLM_MASTER_KEY}" \
    ANTHROPIC_MODEL="auto" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001" \
    claude "$@"
}
