#!/usr/bin/env bash
# conta le lane (righe "- model_name:") di una config LiteLLM
set -euo pipefail
f="${1:?uso: count-lanes.sh config.yaml}"
grep -c 'model_name' "$f"
