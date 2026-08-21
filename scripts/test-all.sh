#!/usr/bin/env bash
# Suite end-to-end. Uso: ./test-all.sh [gruppo]
# gruppi: prereq gateway compress agents mcp claude local biome
set -uo pipefail
G="${1:-all}"; PROXY="${LITELLM_PROXY:-http://127.0.0.1:4000}"; KEY="${LITELLM_MASTER_KEY:-}"
P=0;F=0;S=0
pass(){ echo -e "  \033[32m✓\033[0m $1"; P=$((P+1)); }
fail(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo -e "     \033[2m→ $2\033[0m"; F=$((F+1)); }
skip(){ echo -e "  \033[2m–\033[0m $1 \033[2m(${2:-n/d})\033[0m"; S=$((S+1)); }
sec(){ echo -e "\n\033[36m━━ $1 ━━\033[0m"; }
want(){ [ "$G" = all ] || [ "$G" = "$1" ]; }
has(){ command -v "$1" >/dev/null 2>&1; }

if want prereq; then sec "1. Prerequisiti"
for t in node npx uv curl docker; do has "$t" && pass "$t" || fail "$t mancante" "docs/AGENTS-SETUP.md §1"; done
[ -n "$KEY" ] && pass "LITELLM_MASTER_KEY" || fail "master key assente" "source clients/shell-env.sh"; fi

if want gateway; then sec "2. Gateway"
curl -fsS --max-time 5 "$PROXY/health/liveliness" >/dev/null 2>&1 && pass "liveness" \
  || fail "irraggiungibile" "VM su? forward attivo? (VM-KVM-GUIDE.md)"
if [ -n "$KEY" ]; then
  M=$(curl -fsS --max-time 10 -H "Authorization: Bearer $KEY" "$PROXY/v1/models" 2>/dev/null \
      | python3 -c 'import sys,json;print(" ".join(m["id"] for m in json.load(sys.stdin)["data"]))' 2>/dev/null)
  [ -n "$M" ] && pass "$(echo "$M"|wc -w) modelli" || fail "/v1/models vuoto" "master key? DB up?"
  for a in coding smart cheap; do echo "$M"|grep -qw "$a" && pass "alias '$a'" || skip "alias '$a'" "non nei fallbacks"; done
  R=$(curl -fsS --max-time 60 -X POST "$PROXY/v1/chat/completions" -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -d '{"model":"cheap","messages":[{"role":"user","content":"rispondi: OK"}],"max_tokens":5}' 2>/dev/null)
  echo "$R"|python3 -c 'import sys,json;assert json.load(sys.stdin)["choices"][0]["message"]["content"]' 2>/dev/null \
    && pass "completion end-to-end" || fail "completion fallita" "API key nel .env della VM?"
  curl -fsS --max-time 10 -H "Authorization: Bearer $KEY" "$PROXY/spend/logs" >/dev/null 2>&1 \
    && pass "spend tracking" || skip "spend logs" "DB assente?"
fi; fi

if want compress; then sec "3. Compressione headroom (TC-01)"
if [ -n "$KEY" ]; then
  BIG=$(python3 -c 'import json;print(json.dumps([{"id":i,"v":f"row-{i}","status":"ok"} for i in range(400)]))')
  RAW=$(python3 -c "print(len('''$BIG''')//4)")
  U=$(curl -fsS --max-time 90 -X POST "$PROXY/v1/chat/completions" -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"cheap\",\"messages\":[{\"role\":\"user\",\"content\":\"riassumi: $BIG\"}],\"max_tokens\":20}" 2>/dev/null \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["usage"]["prompt_tokens"])' 2>/dev/null)
  if [ -n "$U" ]; then echo "     payload ~$RAW token → prompt_tokens=$U"
    [ "$U" -lt "$RAW" ] && pass "compressione ATTIVA" || fail "nessuna compressione" "callback caricato? (RUNBOOK/TEST-PLAN)"
  else skip "compressione" "completion non riuscita"; fi
fi; fi

if want agents; then sec "4. Agenti"
has opencode && pass "opencode" || fail "opencode assente" "curl -fsSL https://opencode.ai/install | bash"
python3 -c 'import socket,sys;s=socket.socket();s.settimeout(1);sys.exit(0 if s.connect_ex(("127.0.0.1",3000))==0 else 1)' 2>/dev/null \
  && pass "opencode server :3000" || skip "opencode server" "systemctl --user start opencode.service"
C="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.jsonc"
if [ -f "$C" ]; then
  grep -q '127.0.0.1:4000' "$C" && pass "opencode → gateway" || fail "non punta al gateway" "copia clients/opencode.jsonc"
  grep -q '8787' "$C" && fail "riferimento residuo a :8787" "usa clients/opencode.jsonc" || pass "nessun :8787 residuo"
else fail "opencode.jsonc assente" "copia clients/opencode.jsonc"; fi; fi

if want mcp; then sec "5. MCP & skill"
has serena && pass "Serena" || fail "Serena assente" "uv tool install -p 3.13 serena-agent@latest --prerelease=allow"
has graphify && pass "graphify" || skip "graphify" "opzionale"
[ -f "$PWD/.serena/project.yml" ] && grep -q write_memory "$PWD/.serena/project.yml" 2>/dev/null \
  && pass "Serena memory OFF (TC-03)" || skip "Serena memory policy" "stack-selective-install.sh nel repo"; fi

if want claude; then sec "6. Claude Code (TC-04)"
has claude && pass "Claude Code" || skip "Claude Code" "non installato"
[ -n "${ANTHROPIC_API_KEY:-}" ] && fail "ANTHROPIC_API_KEY in env" "SCAVALCA l'abbonamento: unset" || pass "no ANTHROPIC_API_KEY"
[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] && fail "ANTHROPIC_AUTH_TOKEN in env" "unset se vuoi l'abbonamento" || pass "no ANTHROPIC_AUTH_TOKEN"
echo -e "     \033[2m→ manuale: 'claude' poi '/status' deve dire abbonamento\033[0m"; fi

if want local; then sec "7. LLM locale"
if curl -fsS --max-time 3 http://192.168.122.1:11434/api/tags >/dev/null 2>&1; then
  pass "Ollama su 192.168.122.1:11434"
  curl -fsS http://192.168.122.1:11434/api/tags | python3 -c 'import sys,json;print("     modelli:",", ".join(m["name"] for m in json.load(sys.stdin).get("models",[])) or "nessuno")' 2>/dev/null
elif curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  fail "Ollama su 127.0.0.1: la VM NON lo vede" "OLLAMA_HOST=192.168.122.1:11434 (GPU-LOCAL-LLM.md)"
else skip "Ollama" "non attivo"; fi
has nvidia-smi && nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | sed 's/^/     GPU: /' || skip nvidia-smi "no GPU"; fi

if want biome; then sec "8. BIOME L40S"
[ -n "$KEY" ] && curl -fsS --max-time 10 -H "Authorization: Bearer $KEY" "$PROXY/v1/models" 2>/dev/null | grep -q biome-coder \
  && pass "biome-coder registrato" || skip "BIOME L40S" "non configurato (BIOME-L40S.md)"; fi

echo -e "\n\033[36m━━ Esito ━━\033[0m\n  \033[32m✓ $P\033[0m   \033[31m✗ $F\033[0m   \033[2m– $S\033[0m"
[ "$F" -gt 0 ] && { echo -e "  \033[31mTest falliti.\033[0m"; exit 1; }
echo -e "  \033[32mTutti i test superati.\033[0m"
