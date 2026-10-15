#!/usr/bin/env bash
grep OPENROUTER "$1/services/.env" > "$1/.bench/answer.txt"
