#!/usr/bin/env bash
# Verifica lo stack contro le best practice DevOps. Exit 1 se FAIL bloccanti.
set -uo pipefail
P=0;W=0;F=0
pass(){ echo -e "  \033[32mPASS\033[0m $1"; P=$((P+1)); }
warn(){ echo -e "  \033[33mWARN\033[0m $1"; [ -n "${2:-}" ] && echo -e "        \033[2m$2\033[0m"; W=$((W+1)); }
fail(){ echo -e "  \033[31mFAIL\033[0m $1"; [ -n "${2:-}" ] && echo -e "        \033[2m$2\033[0m"; F=$((F+1)); }
sec(){ echo -e "\n\033[36m== $1 ==\033[0m"; }
cd "$(dirname "$0")/.." || exit 1
SVC=services

sec "1. Immutabilita' & riproducibilita'"
grep -q 'image: litellm-headroom:local' $SVC/docker-compose.yml && pass "immagine taggata (build riproducibile)" || warn "nessun tag locale"
grep -qE 'sha256:' $SVC/.env 2>/dev/null && pass "immagine base pinnata a digest" || warn "tag mobile 'main-stable'" "PSE: pinna un digest sha256 prima della produzione"
grep -q ':ro' $SVC/docker-compose.yml && pass "config read-only" || fail "config non :ro"

sec "2. Segreti"
if [ -f $SVC/.env ]; then
  p=$(stat -c %a $SVC/.env 2>/dev/null)
  [ "$p" = 600 ] && pass ".env 600" || fail ".env permessi $p" "chmod 600 $SVC/.env"
else warn ".env non creato" "cp .env.example .env && chmod 600 .env"; fi
grep -qE '(api_key|password|master_key): *["'\'']?(sk-[A-Za-z0-9]{20,})' $SVC/litellm_config.yaml 2>/dev/null \
  && fail "segreti in chiaro nel config" "usa os.environ/VAR" || pass "nessun segreto nel config"
grep -q '\.env' .gitignore 2>/dev/null && pass ".env in .gitignore" || fail ".env non protetto"

sec "3. Least privilege"
grep -q 'no-new-privileges' $SVC/docker-compose.yml && pass "no-new-privileges" || warn "manca no-new-privileges"
grep -A3 '^  db:' $SVC/docker-compose.yml | grep -q '5432:5432' \
  && fail "postgres esposto su porta host" "basta la rete interna" || pass "postgres non esposto"

sec "4. Resilienza"
grep -q 'restart: unless-stopped' $SVC/docker-compose.yml && pass "restart policy" || warn "nessuna restart policy"
grep -q healthcheck $SVC/docker-compose.yml && pass "healthcheck presenti" || fail "healthcheck mancanti"
grep -q 'condition: service_healthy' $SVC/docker-compose.yml && pass "dipendenze ordinate" || warn "depends_on senza condition"
grep -q limits $SVC/docker-compose.yml && pass "limiti CPU/memoria" || warn "nessun limite risorse"

sec "5. Observability"
grep -q 'max-size' $SVC/docker-compose.yml && pass "log rotation" || warn "log senza rotation"
grep -q 'driver: local' $SVC/docker-compose.yml && pass "driver 'local' (compresso)" || warn "json-file: ok se usi un log shipper"
grep -q 'set_verbose: *false' $SVC/litellm_config.yaml && pass "verbose off (no prompt nei log)" || warn "set_verbose non disabilitato"

sec "5b. Docker daemon"
if [ -f /etc/docker/daemon.json ]; then
  grep -q log-driver /etc/docker/daemon.json && pass "daemon: log-driver" || warn "daemon senza log-driver" "docs/DOCKER-HARDENING.md"
  grep -q live-restore /etc/docker/daemon.json && pass "live-restore attivo" || warn "live-restore non attivo"
else warn "/etc/docker/daemon.json assente" "docs/DOCKER-HARDENING.md"; fi

sec "6. Backup & rollback"
[ -x scripts/backup-db.sh ] && pass "script di backup" || warn "nessuno script di backup"
[ -x scripts/restore-test.sh ] && pass "script di TEST del restore (TC-05)" || fail "restore non testabile" "un backup non testato non e' un backup"
echo -e "  \033[36mINFO\033[0m rollback: snapshot VM + .bak-* sui config"

sec "7. Change management"
[ -d .git ] && pass "repo git (config versionati)" || warn "non e' un repo git" "git init"
[ -d docs/adr ] && pass "$(ls docs/adr/[0-9]*.md 2>/dev/null | wc -l) ADR presenti" || warn "nessun ADR"
[ -f docs/PRD.md ] && pass "PRD presente" || warn "nessun PRD"
[ -f docs/TEST-PLAN.md ] && pass "test plan presente" || warn "nessun test plan"
[ -d .github/workflows ] && pass "CI configurata" || warn "nessuna CI"

sec "8. Supply chain"
grep -q 'python -c "from headroom' $SVC/Dockerfile && pass "gate fail-fast sul callback" || warn "nessun gate in build"
echo -e "  \033[36mINFO\033[0m 'npx ecc-agentshield scan' per l'audit dei config agente"

echo -e "\n\033[36m== Esito DevOps ==\033[0m\n  PASS: $P   WARN: $W   FAIL: $F"
[ "$F" -gt 0 ] && { echo -e "  \033[31mFAIL bloccanti.\033[0m"; exit 1; }
[ "$W" -gt 0 ] && echo -e "  \033[33mOk con avvertenze.\033[0m" || echo -e "  \033[32mTutto verificato.\033[0m"
exit 0
