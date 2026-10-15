#!/usr/bin/env bash
cd "$1" || exit 1
cat > lanes.py <<'PY'
"""Elenco delle lane da un file di testo: una riga "nome=modello@endpoint"."""


def parse_lane(line):
    name, rest = line.split("=", 1)
    model, endpoint = rest.rsplit("@", 1)
    return name.strip(), model.strip(), endpoint.strip()


def _lanes(text):
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            yield line


def local_lanes(text):
    return [l for l in (parse_lane(x) for x in _lanes(text))
            if l[2].startswith("http://192.168.") or l[2].startswith("http://127.")]


def cloud_lanes(text):
    return [l for l in (parse_lane(x) for x in _lanes(text)) if l[2].startswith("https://")]
PY
