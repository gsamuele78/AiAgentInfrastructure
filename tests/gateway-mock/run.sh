#!/usr/bin/env bash
# ============================================================
#  tests/gateway-mock/run.sh -- la catena del gateway, in CI, senza segreti.
#  Pratica importata da OpenHands (mock LLM per e2e deterministici; ADR-0025 §3).
#  Avvia il proxy LiteLLM alla STESSA versione del Dockerfile con una config
#  generata da services/litellm_config.yaml (gen-config.py): lane locali su una
#  porta chiusa, lane cloud con mock_response. Verifica:
#    G1 ogni model_name della config vera e' servito (/v1/models; i wildcard no, per costruzione)
#    G2 auto: locale giu' -> primo fallback della config vera
#    G3 auto: anche il primo anello giu' -> secondo fallback
#    G4 disable_fallbacks: la richiesta fallisce invece di saltare (serve a bench/compliance)
#    G5 prompt oltre max_input_tokens -> context_window_fallbacks, il locale non e' chiamato
#    G6 i callback configurati vengono invocati (successo e fallimento)
#  Cosa NON prova: provider veri, headroom vero, il DB. Restano L5 (test-all.sh).
#  Uso: tests/gateway-mock/run.sh   (LITELLM_BIN=... per un litellm gia' installato)
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ echo -e "  \033[32m✓\033[0m $1"; P=$((P+1)); }
ko(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo "$2" | tail -8 | sed 's/^/      /'; F=$((F+1)); }

# versione = quella del FROM del Dockerfile: il mock non puo' divergere dal gateway
VER=$(sed -n 's|^FROM ghcr.io/berriai/litellm-database:v\([0-9.]*\)@.*|\1|p' "$REPO/services/Dockerfile")
[ -n "$VER" ] || { echo "versione LiteLLM non trovata nel Dockerfile"; exit 1; }
W=$(mktemp -d); PIDS=""
cleanup(){ for p in $PIDS; do kill "$p" 2>/dev/null; done; [ -n "${KEEP:-}" ] && echo "lasciato: $W" || rm -rf "$W"; }
trap cleanup EXIT

if [ -n "${LITELLM_BIN:-}" ]; then
  PY="$(dirname "$LITELLM_BIN")/python"
else
  python3 -m venv "$W/venv" && "$W/venv/bin/pip" install -q "litellm[proxy]==$VER" \
    || { echo "installazione litellm[proxy]==$VER fallita"; exit 1; }
  LITELLM_BIN="$W/venv/bin/litellm"; PY="$W/venv/bin/python"
fi
cp "$HERE/probe_callback.py" "$W/"
cd "$W" || exit 1   # LiteLLM importa probe_callback dalla directory corrente
# porte libere scelte dal kernel: due run in parallelo non si parlano addosso
free_port(){ "$PY" -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1])"; }
PA=$(free_port); PB=$(free_port)

FIRST=$("$PY" -c "import yaml,sys;c=yaml.safe_load(open(sys.argv[1]));fb=[list(d.values())[0] for d in c['litellm_settings']['fallbacks'] if 'auto' in d][0];print(fb[0]);print(fb[1])" "$REPO/services/litellm_config.yaml")
FB1=$(echo "$FIRST" | sed -n 1p); FB2=$(echo "$FIRST" | sed -n 2p)
CWF=$("$PY" -c "import yaml,sys;c=yaml.safe_load(open(sys.argv[1]));print([list(d.values())[0] for d in c['litellm_settings']['context_window_fallbacks'] if 'auto' in d][0][0])" "$REPO/services/litellm_config.yaml")

# start <porta> <args gen-config...>
start(){
  local port=$1; shift
  "$PY" "$HERE/gen-config.py" "$@" > "$W/mock-$port.yaml" || return 1
  # niente subshell: $! deve essere il proxy, o il kill di cleanup non lo ferma
  PROBE_CALLBACK_LOG="$W/cb-$port.jsonl" "$LITELLM_BIN" --config "$W/mock-$port.yaml" --port "$port" > "$W/proxy-$port.log" 2>&1 &
  local pid=$!; PIDS="$PIDS $pid"
  for _ in $(seq 1 90); do
    kill -0 "$pid" 2>/dev/null || break   # morto (es. porta occupata): non parlare con un altro proxy
    curl -sf "localhost:$port/health/liveliness" >/dev/null && return 0; sleep 1
  done
  ko "proxy mock non partito sulla porta $port" "$(tail -20 "$W/proxy-$port.log")"; return 1
}
# ask <porta> <json> -> contenuto della risposta, o ERR:<messaggio>
ask(){
  printf '%s' "$2" | curl -s "localhost:$1/v1/chat/completions" -H 'Authorization: Bearer sk-mock-ci' \
    -H 'content-type: application/json' -d @- | "$PY" -c "import json,sys
d=json.load(sys.stdin)
print(d['choices'][0]['message']['content'] if 'choices' in d else 'ERR:'+str(d.get('error',{}).get('message',''))[:160])"
}
# i callback sono asincroni: si aspetta che il log raggiunga N righe
waitcb(){ for _ in $(seq 1 20); do [ "$(cat "$1" 2>/dev/null | wc -l)" -ge "$2" ] && return 0; sleep 0.5; done; return 1; }
HI='"messages":[{"role":"user","content":"ciao"}]'

echo -e "\n\033[36m── gateway mock (LiteLLM $VER, catena da services/litellm_config.yaml)\033[0m"
start $PA || exit 1
want=$("$PY" -c "import yaml,sys;print('\n'.join(sorted(e['model_name'] for e in yaml.safe_load(open(sys.argv[1]))['model_list'] if '*' not in e['model_name'])))" "$REPO/services/litellm_config.yaml")
got=$(curl -s localhost:$PA/v1/models -H 'Authorization: Bearer sk-mock-ci' | "$PY" -c "import json,sys;print('\n'.join(sorted(m['id'] for m in json.load(sys.stdin)['data'])))")
missing=$(comm -23 <(echo "$want") <(echo "$got"))
[ -z "$missing" ] && ok "G1 tutti i model_name serviti" || ko "G1 model_name non serviti" "$missing"

r=$(ask $PA "{\"model\":\"auto\",$HI}")
[ "$r" = "MOCK:$FB1" ] && ok "G2 auto con locale giu' -> $FB1" || ko "G2 auto: atteso MOCK:$FB1, avuto $r"

r=$(ask $PA "{\"model\":\"auto\",\"disable_fallbacks\":true,$HI}")
[[ "$r" == ERR:* ]] && ok "G4 disable_fallbacks: errore, nessun salto" || ko "G4 disable_fallbacks ignorato: $r"

waitcb "$W/cb-$PA.jsonl" 3   # G2: fallimento locale + successo; G4: fallimento
n0=$(cat "$W/cb-$PA.jsonl" 2>/dev/null | wc -l)
big=$("$PY" -c "import json;print(json.dumps({'model':'auto','messages':[{'role':'user','content':'parola '*20000}]}))")
r=$(ask $PA "$big")
waitcb "$W/cb-$PA.jsonl" "$((n0+1))"
local_called=$(tail -n +"$((n0+1))" "$W/cb-$PA.jsonl" | grep -c '"model": "qwen' || true)
if [ "$r" = "MOCK:$CWF" ] && [ "$local_called" = 0 ]; then ok "G5 prompt lungo -> $CWF senza chiamare il locale"
else ko "G5 context_window_fallbacks: avuto $r, chiamate al locale: $local_called"; fi

if grep -q '"event": "success"' "$W/cb-$PA.jsonl" 2>/dev/null && grep -q '"event": "failure"' "$W/cb-$PA.jsonl"; then
  ok "G6 callback invocato su successo e fallimento"
else ko "G6 callback mai invocato" "$(cat "$W/cb-$PA.jsonl" 2>/dev/null)"; fi

start $PB --fail "$FB1" || exit 1
r=$(ask $PB "{\"model\":\"auto\",$HI}")
[ "$r" = "MOCK:$FB2" ] && ok "G3 auto con $FB1 giu' -> $FB2" || ko "G3 secondo anello: atteso MOCK:$FB2, avuto $r"

echo -e "\n  gateway mock: \033[32m✓ $P\033[0m  \033[31m✗ $F\033[0m"
[ "$F" = 0 ]
