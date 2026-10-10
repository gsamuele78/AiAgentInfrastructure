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
# Modalita' 'warn', non 'block': questo script scrive SOLO config utente
# (~/.claude, ~/.codex, ~/.config/opencode, $PROJ/.serena) e installa tool con
# uv/npx. Dentro un devcontainer configurarli li' e' legittimo, non un errore --
# a differenza di chi tocca systemd o libvirt, che sono stato di sistema.
sandbox_guard "scripts/stack-selective-install.sh" "$DRY" warn || exit 1

PROJ="${ARGS[0]:-$PWD}"

say "1) Serena locale (semantic-only, memory OFF)"
run "uv tool install -p 3.13 'serena-agent@latest' --prerelease=allow || echo '  (gia installata?)'"
# Tutti i tool che leggono/scrivono la memoria di Serena (ADR-0007), compresi
# quelli aggiunti dopo la prima stesura: rename/edit_memory e onboarding (che
# scrive memorie). Nomi = classi *Tool in snake_case (serena/tools/memory_tools.py).
MEMTOOLS="write_memory read_memory list_memories delete_memory rename_memory edit_memory onboarding"
# NON si scrive un project.yml a mano: serena-agent 1.7.0 esige `language_servers`
# (FIELDS_WITHOUT_DEFAULTS) e il vecchio file di due righe faceva fallire il
# caricamento del progetto con KeyError. Lo genera Serena (rileva i linguaggi);
# qui si sostituisce solo la riga `excluded_tools: []` del template.
# `< <(yes)` e non `yes |`: con pipefail, il SIGPIPE di yes renderebbe falsa la pipeline.
SPY="$PROJ/.serena/project.yml"
if [ -f "$SPY" ]; then
  MISS=""; for t in $MEMTOOLS; do grep -qE "^[[:space:]]*-[[:space:]]*${t}[[:space:]]*$|excluded_tools:.*\\b${t}\\b" "$SPY" || MISS="$MISS $t"; done
  # Idempotente: un file esistente non si sovrascrive (niente .bak), si segnala.
  [ -z "$MISS" ] && echo "  $SPY: gia' conforme, nessuna scrittura" \
    || echo "  ⚠️ $SPY non esclude:$MISS -> aggiungili a excluded_tools (ADR-0007)"
elif [ "$DRY" = 1 ]; then
  echo "  [dry] serena project create '$PROJ' + excluded_tools: [${MEMTOOLS// /, }]"
else
  serena project create "$PROJ" < <(yes) >/dev/null || { echo "  ✗ serena project create fallito"; exit 1; }
  grep -q '^excluded_tools: \[\]$' "$SPY" || { echo "  ✗ template Serena cambiato: excluded_tools non trovato in $SPY"; exit 1; }
  sed -i "s/^excluded_tools: \[\]\$/excluded_tools: [${MEMTOOLS// /, }]/" "$SPY"
  echo "  $SPY creato (memoria esclusa)"
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
