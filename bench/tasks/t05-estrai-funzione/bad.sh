#!/usr/bin/env bash
# parse_lane aggiunta ma mai usata: il duplicato resta
cd "$1" && printf '\n\ndef parse_lane(line):\n    name, rest = line.split("=", 1)\n    model, endpoint = rest.rsplit("@", 1)\n    return name.strip(), model.strip(), endpoint.strip()\n' >> lanes.py
