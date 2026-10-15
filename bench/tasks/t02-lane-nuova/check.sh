#!/usr/bin/env bash
cd "$1" || exit 1
python3 - <<'PY'
import sys, yaml
c = yaml.safe_load(open("services/litellm_config.yaml"))
lanes = {m["model_name"]: m for m in c["model_list"]}
h = lanes.get("claude-haiku")
if not h: sys.exit("manca la lane claude-haiku")
p = h.get("litellm_params", {})
if "haiku-4-5-20251001" not in str(p.get("model", "")): sys.exit("modello sbagliato: %s" % p.get("model"))
if p.get("api_key") != "os.environ/ANTHROPIC_API_KEY": sys.exit("api_key non da os.environ/ANTHROPIC_API_KEY")
if "cache_control_injection_points" not in p: sys.exit("cache_control_injection_points non DENTRO litellm_params")
if "cache_control_injection_points" in h: sys.exit("cache_control_injection_points fuori da litellm_params (LiteLLM lo ignora)")
fb = [list(d.values())[0] for d in c["litellm_settings"]["fallbacks"] if "cheap" in d]
if not fb or fb[0][-1] != "claude-haiku": sys.exit("claude-haiku non e' l'ultimo fallback di cheap: %s" % fb)
if "claude-sonnet-4-6" not in lanes: sys.exit("lane esistente rimossa")
PY
[ $? = 0 ] || exit 1
! grep -Eq 'sk-[A-Za-z0-9]{10,}' services/litellm_config.yaml || { echo "segreto letterale nel file"; exit 1; }
