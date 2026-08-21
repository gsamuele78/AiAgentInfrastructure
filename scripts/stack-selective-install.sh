#!/usr/bin/env bash
# Serena + graphify + mattpocock + AgentShield. Niente ECC-full/superpowers (ADR-0006).
set -uo pipefail
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"; HERE="$(cd "$(dirname "$0")" && pwd)"
ts(){ date +%Y%m%d-%H%M%S; }
bak(){ [ -e "$1" ] && cp -a "$1" "$1.bak-$(ts)" && echo "  backup: $1.bak-$(ts)"; }
say(){ echo -e "\033[36m==>\033[0m $*"; }
command -v uv  >/dev/null || { echo "installa uv"; exit 1; }
command -v npx >/dev/null || { echo "serve npx"; exit 1; }

say "1) Serena locale (semantic-only, memory OFF)"
uv tool install -p 3.13 "serena-agent@latest" --prerelease=allow || echo "  (gia' installata?)"
PROJ="${1:-$PWD}"; mkdir -p "$PROJ/.serena"; bak "$PROJ/.serena/project.yml"
cat > "$PROJ/.serena/project.yml" <<'YML'
excluded_tools: [write_memory, read_memory, list_memories, delete_memory]
record_tool_usage_stats: false
YML
echo "  .serena/project.yml in $PROJ"
say "1b) graphify (mappa d'insieme, occasionale)"
[ "${SKIP_GRAPHIFY:-0}" = 1 ] || { uv tool install graphifyy || true; graphify install || true; }
say "2) mattpocock/skills"
npx skills@latest add mattpocock/skills || echo "  poi: /setup-matt-pocock-skills"
say "3) config client"
install -d "$CFG/opencode"; bak "$CFG/opencode/opencode.jsonc"
cp "$HERE/../clients/opencode.jsonc" "$CFG/opencode/opencode.jsonc"
install -d "$HOME/.claude"; bak "$HOME/.claude/settings.json"
cp "$HERE/../clients/claude-settings.json" "$HOME/.claude/settings.json"
headroom unwrap codex 2>/dev/null || true
install -d "$HOME/.codex"; bak "$HOME/.codex/config.toml"
cp "$HERE/../clients/codex-config.toml" "$HOME/.codex/config.toml"
echo "  ⚠️ rimetti le TUE api key negli MCP (nei file: 'example-key')"
echo "  ⚠️ master key in ~/.config/litellm/master.key (chmod 600)"
say "4) shell env"
echo "  aggiungi a ~/.bashrc:  source $HERE/../clients/shell-env.sh"
say "5) AgentShield"
npx ecc-agentshield scan || echo "  rivedi i finding"
echo -e "\n\033[32mFatto.\033[0m Verifica: ./audit-integration.py"
