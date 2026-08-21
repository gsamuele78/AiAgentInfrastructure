# shellcheck shell=bash
# Questo file va SORGATO (source), non eseguito: nessuno shebang.
# Sorgi da ~/.bashrc. NON esporta ANTHROPIC_*: scavalcherebbe l'abbonamento.
export PATH="$HOME/.opencode/bin:$PATH"
[ -r "$HOME/.config/litellm/master.key" ] && \
  export LITELLM_MASTER_KEY="$(cat "$HOME/.config/litellm/master.key")"
export OPENAI_BASE_URL="http://127.0.0.1:4000/v1"
export OPENAI_API_KEY="${LITELLM_MASTER_KEY:-}"
# Claude Code: vedi docs/DUAL-AUTH.md (3 varianti). NON impostare qui
# ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN.
