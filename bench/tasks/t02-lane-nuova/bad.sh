#!/usr/bin/env bash
# trappola nota (AGENTS.md): cache_control_injection_points accanto a litellm_params
"$(dirname "$0")/solution.sh" "$1" && python3 - "$1" <<'PY'
import sys; p=sys.argv[1]+"/services/litellm_config.yaml"; s=open(p).read()
s=s.replace("""      api_key: os.environ/ANTHROPIC_API_KEY
      cache_control_injection_points: [ { location: message, role: system }, { location: message, index: -1 } ]
litellm_settings:""","""      api_key: os.environ/ANTHROPIC_API_KEY
    cache_control_injection_points: [ { location: message, role: system }, { location: message, index: -1 } ]
litellm_settings:""")
open(p,"w").write(s)
PY
