#!/usr/bin/env bash
set -u
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
cat > "$d/c.yaml" <<'Y'
model_list:
  - model_name: a        # lane
    litellm_params: { model: x }
  - model_name: b
    litellm_params: { model: y }
# model_name: commentata, non conta
router_settings: { model_name_alias: z }
Y
got=$(bash "$(dirname "$0")/../scripts/count-lanes.sh" "$d/c.yaml")
[ "$got" = 2 ] || { echo "atteso 2, avuto $got"; exit 1; }
bash "$(dirname "$0")/../scripts/count-lanes.sh" 2>/dev/null && { echo "senza argomenti deve fallire"; exit 1; }
echo ok
