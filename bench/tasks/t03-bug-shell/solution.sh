#!/usr/bin/env bash
cd "$1" || exit 1
sed -i "s/^grep -c 'model_name' \"\$f\"$/grep -cE '^[[:space:]]*- model_name:' \"\$f\"/" scripts/count-lanes.sh
