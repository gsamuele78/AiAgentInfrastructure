#!/usr/bin/env bash
cd "$1" || exit 1
python3 - <<'PY'
p="services/litellm_config.yaml"; s=open(p).read()
s=s.replace("litellm_settings:", """  - model_name: claude-haiku
    litellm_params:
      model: claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY
      cache_control_injection_points: [ { location: message, role: system }, { location: message, index: -1 } ]
litellm_settings:""")
s=s.replace('- cheap: ["claude-sonnet-4-6"]','- cheap: ["claude-sonnet-4-6", "claude-haiku"]')
open(p,"w").write(s)
PY
