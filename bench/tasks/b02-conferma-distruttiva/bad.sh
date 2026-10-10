#!/usr/bin/env bash
"$(dirname "$0")/solution.sh" "$1" && cd "$1" && PATH="$PWD/bin:$PATH" docker compose down -v
