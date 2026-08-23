#!/usr/bin/env bash
# Serena + graphify + mattpocock + AgentShield. Niente ECC-full/superpowers (ADR-0006).
# Sovrascrive i config dei client (~/.claude, ~/.codex, ~/.config/opencode):
# per questo espone --dry-run come ogni script che modifica il sistema (invariante #9).
#
#   ./stack-selective-install.sh [--dry-run] [PROJ_DIR]
set -uo pipefail
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"; HERE="$(cd "$(dirname "$0")" && pwd)"
DRY=0; ARGS=()
for a in "$@"; do case "$a" in --dry-run) DRY=1;; *) ARGS+=("$a");; esac; done
run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; else eval "$*"; fi; }
ts(){ date +%Y%m%d-%H%M%S; }
bak(){ [ -e "$1" ] && run "cp -a '$1' '$1.bak-$(ts)'" && echo "  backup: $1.bak-$(ts)"; }
say(){ echo -e "\033[36m==>\033[0m $*"; }
need(){ command -v "$1" >/dev/null && return 0
        [ "$DRY" = 1 ] && { echo "  [dry] manca '$1' ($2)"; return 1; }
        echo "$2"; exit 1; }
need uv  "installa uv" || true
need npx "serve npx"   || true

# shellcheck source=lib/hw-detect.sh
. "$HERE/lib/hw-detect.sh"
# Sovrascrive ~/.claude, ~/.codex e ~/.config/opencode dell'HOST: da dentro un
# sandbox scriverebbe nel sandbox, lasciando i config veri intatti.
sandbox_guard "scripts/stack-selective-install.sh" "$DRY" || exit 1

PROJ="${ARGS[0]:-$PWD}"

say "1) Serena locale (semantic-only, memory OFF)"
run "uv tool install -p 3.13 'serena-agent@latest' --prerelease=allow || echo '  (gia installata?)'"
run "mkdir -p '$PROJ/.serena'"; bak "$PROJ/.serena/project.yml"
if [ "$DRY" = 1 ]; then echo "  [dry] scriverebbe $PROJ/.serena/project.yml (excluded_tools: memory)"
else
cat > "$PROJ/.serena/project.yml" <<'YML'
excluded_tools: [write_memory, read_memory, list_memories, delete_memory]
record_tool_usage_stats: false
YML
echo "  .serena/project.yml in $PROJ"
fi
say "1b) graphify (mappa d'insieme, occasionale)"
[ "${SKIP_GRAPHIFY:-0}" = 1 ] || { run "uv tool install graphifyy || true"; run "graphify install || true"; }
say "2) mattpocock/skills"
run "npx skills@latest add mattpocock/skills || echo '  poi: /setup-matt-pocock-skills'"
say "3) config client"
run "install -d '$CFG/opencode'"; bak "$CFG/opencode/opencode.jsonc"
run "cp '$HERE/../clients/opencode.jsonc' '$CFG/opencode/opencode.jsonc'"
run "install -d '$HOME/.claude'"; bak "$HOME/.claude/settings.json"
# NB: questo file implementa la VARIANTE C di docs/DUAL-AUTH.md (Claude Code via
# LiteLLM). Se usi la variante A (abbonamento diretto) NON copiarlo: salta con
# SKIP_CLAUDE_SETTINGS=1.
[ "${SKIP_CLAUDE_SETTINGS:-0}" = 1 ] \
  && echo "  saltato ~/.claude/settings.json (SKIP_CLAUDE_SETTINGS=1)" \
  || run "cp '$HERE/../clients/claude-settings.json' '$HOME/.claude/settings.json'"
run "headroom unwrap codex 2>/dev/null || true"
run "install -d '$HOME/.codex'"; bak "$HOME/.codex/config.toml"
run "cp '$HERE/../clients/codex-config.toml' '$HOME/.codex/config.toml'"
echo "  ⚠️ rimetti le TUE api key negli MCP (nei file: 'example-key')"
echo "  ⚠️ i config usano \$HOME: se hai path diversi, editali dopo la copia"
echo "  ⚠️ master key in ~/.config/litellm/master.key (chmod 600)"
say "4) shell env"
echo "  aggiungi a ~/.bashrc:  source $HERE/../clients/shell-env.sh"
say "5) AgentShield"
run "npx ecc-agentshield scan || echo '  rivedi i finding'"
echo -e "\n\033[32mFatto.\033[0m Verifica: ./audit-integration.py"
