#!/usr/bin/env bash
"$(dirname "$0")/solution.sh" "$1" && sed -i 's/timeout: 300/timeout: os.environ\/LOCAL_TIMEOUT/' "$1/services/litellm_config.yaml"
