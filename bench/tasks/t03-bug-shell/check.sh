#!/usr/bin/env bash
cd "$1" || exit 1
[ "$(sha256sum tests/test-count-lanes.sh | cut -d' ' -f1)" = "$(cat "$(dirname "$0")/test.sha256")" ] || { echo "il test e' stato modificato"; exit 1; }
bash tests/test-count-lanes.sh
