#!/usr/bin/env bash
# ============================================================
#  tests/agent-practices/run.sh -- le pratiche importate da OpenHands (ADR-0025), offline.
#  Nessuna rete, nessun LLM, nessun gateway: gira dentro test-scripts.sh e in CI.
#  Il gateway mock (tests/gateway-mock/run.sh) e' a parte: installa LiteLLM.
# ============================================================
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO" || exit 1
P=0; F=0
step(){ # step <nome> <comando...>
  local name=$1; shift
  if out=$("$@" 2>&1); then echo -e "  \033[32m✓\033[0m $name"; P=$((P+1))
  else echo -e "  \033[31m✗\033[0m $name"; echo "$out" | grep -E '✗|FAIL|Error|error' | head -8 | sed 's/^/      /'; F=$((F+1)); fi
}
step "§1 golden task sani + early stopper (bench/tasks/validate.sh)" bench/tasks/validate.sh
step "§2 sonde di conformita' API (bench/compliance)" python3 -m unittest -q bench/compliance/test_probe.py
step "§4 RISK: regole ask/deny dei client sul corpus (tests/risk-corpus)" python3 tests/risk-corpus/check.py
step "§5 SKILL: lint delle skill (tests/skills)" tests/skills/run.sh
step "§6 mascheramento dei segreti (bench/secret-canary)" python3 -m unittest -q bench/secret-canary/test_secret_mask.py
step "§7 euristiche dei loop (bench/stuck)" python3 -m unittest -q bench/stuck/test_analyze.py
step "§8 variante di compattazione generabile (bench/compaction)" python3 bench/compaction/variant.py
step "§9 AGENTS: deriva di AGENTS.md (tests/agents-md)" python3 tests/agents-md/check.py
step "§10 cornice per testo non fidato (bench/tasks/lib)" python3 -m unittest -q bench/tasks/lib/test_untrusted.py
step "§11 export per SkillRefiner (bench/skillrefiner)" python3 -m unittest -q bench/skillrefiner/test_export.py
echo -e "\n  pratiche OpenHands: \033[32m✓ $P\033[0m  \033[31m✗ $F\033[0m"
[ "$F" = 0 ]
