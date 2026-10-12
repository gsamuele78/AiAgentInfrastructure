#!/usr/bin/env bash
# ============================================================
#  tests/audit-host/run.sh -- scripts/audit-host.sh su una $HOME finta.
#  La $HOME contiene chiavi FINTE nei posti dove le aveva l'host vecchio
#  (opencode, codex, bashrc, unit di headroom, .env con postgres) e un virsh
#  finto con una VM. Verifica:
#    - nessun valore segreto finisce nel report (la regola che conta)
#    - le chiavi sono trovate tutte, e la stessa chiave ha la stessa impronta
#    - --backup: archivio 600 con i file e l'XML della VM
#    - l'host non cambia (i file esaminati hanno lo stesso sha256)
# ============================================================
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
P=0; F=0
ok(){ echo -e "  \033[32m✓\033[0m $1"; P=$((P+1)); }
ko(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo "$2" | tail -12 | sed 's/^/      /'; F=$((F+1)); }
W=$(mktemp -d); H="$W/home"; B="$W/bin"
mkdir -p "$H/.config/opencode" "$H/.codex" "$H/.claude" "$H/.config/systemd/user" "$H/proj" "$B"
# Composte a runtime: scritte per intero, farebbero scattare il job "Nessun
# segreto committato" (giustamente: lui non sa che sono finte).
OR="sk-or-v1-$(printf '0123456789abcdef%.0s' 1 2)"
AN="sk-ant-api03-$(printf 'AbCdEfGhIjKl%.0s' 1 2)"
PG=SuperS3cretPg99
MK=sk-litellm-master-0000111122223333
cat > "$H/.config/opencode/opencode.jsonc" <<J
{ "provider": { "or": { "options": { "baseURL": "http://127.0.0.1:8787/v1", "apiKey": "$OR" } } },
  "mcp": { "fetch": { "environment": { "API_KEY": "example-key" } } },
  "stats": { "avg_token_reduction": 0.12345678901234567, "firstTokenDate": "2026-06-23T10:11:12.345Z" } }
J
chmod 644 "$H/.config/opencode/opencode.jsonc"
printf 'model_provider="headroom"\n[model_providers.headroom]\nbase_url="http://127.0.0.1:8787/v1"\nexperimental_bearer_token="%s"\n' "$AN" > "$H/.codex/config.toml"
printf '{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:8787"}}\n' > "$H/.claude/settings.json"
printf 'export OPENROUTER_API_KEY=%s\nexport OPENAI_BASE_URL=http://127.0.0.1:8787/v1\n' "$OR" > "$H/.bashrc"
printf '[Service]\nExecStart=%%h/.local/bin/headroom proxy --port 8787 --openai-api-url https://openrouter.ai/api\nEnvironment=OPENROUTER_API_KEY=%s\n' "$OR" > "$H/.config/systemd/user/headroom.service"
printf 'DATABASE_URL=postgresql://llm:%s@localhost:5432/litellm\nLITELLM_MASTER_KEY=%s\n' "$PG" "$MK" > "$H/proj/.env"
# virsh finto: una VM in qemu:///system, nessuna in session
cat > "$B/virsh" <<'V'
#!/bin/sh
uri=""; while [ "$1" = -r ] || [ "$1" = -c ]; do [ "$1" = -c ] && { uri=$2; shift; }; shift; done
case "$1" in
  list) [ "$uri" = qemu:///system ] && { [ "${2:-}" = --all ] && [ "${3:-}" = --name ] && echo vecchia-vm || echo " -   vecchia-vm   shut off"; } ;;
  dumpxml) echo "<domain><name>$2</name></domain>" ;;
  dominfo) echo "Name: $2"; echo "State: shut off" ;;
  *) echo "(finto) $*" ;;
esac
V
chmod +x "$B/virsh"
# uv finto che fa quello che fa il vero: una cache in $HOME se nessuno la sposta
printf '#!/bin/sh\nmkdir -p "${UV_CACHE_DIR:-$HOME/.cache/uv}" && : > "${UV_CACHE_DIR:-$HOME/.cache/uv}/CACHEDIR.TAG"\necho "nessun tool"\n' > "$B/uv"
chmod +x "$B/uv"
before=$(cd "$H" && find . -type f -exec sha256sum {} + | sort)
# ALLOW_IN_SANDBOX: in CI gira dentro un container; qui si prova il report, non il guard.
out=$(HOME="$H" PATH="$B:$PATH" AIAGENT_STATE="$W/state" ALLOW_IN_SANDBOX=1 "$REPO/scripts/audit-host.sh" --backup 2>&1); rc=$?
R=$(ls "$W"/state/audit/*/report.md 2>/dev/null | head -1)

echo "── audit su \$HOME finta"
[ "$rc" = 0 ] && [ -f "$R" ] && ok "esce 0 e scrive il report" || { ko "audit fallito (rc=$rc)" "$out"; echo "Esito: $P ✓  $F ✗"; exit 1; }
leak=$(grep -nE "$OR|$AN|$PG|$MK|0123456789abcdef0123|AbCdEfGhIjKlAbCd" "$R")
[ -z "$leak" ] && ok "nessun segreto in chiaro nel report" || ko "SEGRETI NEL REPORT" "$leak"
leak=$(grep -nE "$OR|$AN|$PG|$MK" <<<"$out")
[ -z "$leak" ] && ok "nessun segreto sul terminale" || ko "segreti sul terminale" "$leak"
for k in openrouter anthropic password-in-url sk-generica; do
  grep -qE "\\| $k \\|" "$R" && ok "trovata la chiave di tipo $k" || ko "chiave $k non trovata" "$(sed -n '/## 10/,$p' "$R")"
done
n=$(grep -c "\`$(printf %s "$OR" | sha256sum | cut -c1-8)\`" "$R")
[ "$n" = 3 ] && ok "stessa chiave OpenRouter riconosciuta in 3 file (stessa impronta)" || ko "impronta OpenRouter in $n file (attesi 3: opencode, bashrc, unit)"
grep -q 'example-key' "$R" && ko "segnaposto contato come chiave" || ok "i segnaposto (example-key) non sono chiavi"
grep -qiE '\| (avg_token_reduction|firsttokendate) \|' "$R" && ko "numeri o date contati come chiavi" "$(grep -iE 'avg_token|firsttoken' "$R")" || ok "numeri e date non sono chiavi (falsi positivi del primo host vero)"
grep -q 'opencode.jsonc` | 644 ⚠️' "$R" && ok "permessi larghi segnalati" || ko "644 non segnalato"
grep -q 'http://127.0.0.1:8787' "$R" && ok "endpoint headroom :8787 elencato" || ko "endpoint :8787 mancante"
grep -q 'vecchia-vm' "$R" && ok "VM libvirt elencata" || ko "VM non elencata"

echo "── backup"
A=$(ls "$W"/state/audit/*/backup-*.tar.gz 2>/dev/null | head -1)
[ -f "$A" ] && [ "$(stat -c %a "$A")" = 600 ] && ok "archivio 600" || ko "archivio assente o permessi sbagliati"
l=$(tar -tzf "$A" 2>/dev/null)
for f in .codex/config.toml .config/opencode/opencode.jsonc .bashrc headroom.service proj/.env vm-xml/system-vecchia-vm.xml; do
  grep -q "$f" <<<"$l" && ok "nel backup: $f" || ko "manca nel backup: $f" "$l"
done
[ "$(stat -c %a "$(dirname "$R")")" = 700 ] && ok "cartella dell'audit 700" || ko "cartella dell'audit non 700"

echo "── l'host non cambia"
after=$(cd "$H" && find . -type f -exec sha256sum {} + | sort)
[ "$before" = "$after" ] && ok "file della \$HOME identici prima e dopo" || ko "l'audit ha modificato la \$HOME" "$(diff <(echo "$before") <(echo "$after"))"
out=$(HOME="$H" AIAGENT_STATE="$W/state2" "$REPO/scripts/audit-host.sh" --dry-run 2>&1)
[ ! -e "$W/state2" ] && ok "--dry-run non scrive niente" || ko "--dry-run ha scritto $W/state2"

rm -rf "$W"
echo "Esito: $P ✓  $F ✗"
[ "$F" = 0 ]
