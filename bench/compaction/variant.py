#!/usr/bin/env python3
"""Genera la variante B della compattazione di opencode per l'A/B di ADR-0025 §8.

OpenHands (context/condenser, MIT) condensa REGOLARMENTE, non all'ultimo momento: il
README del condenser spiega che una condensazione rompe la cache del prompt, ma farla
presto e spesso tiene basso il costo di ricostruirla. Qui il layer e' gia' di opencode
(`compaction`, ADR-0006: un tool per layer), quindi non si importa un secondo condenser:
si misura se l'idea regge spostando la soglia di opencode.

  A (oggi)   compaction.reserved come in clients/opencode.jsonc
  B          compaction.reserved = --reserved (default 60 % del contesto di local-good):
             compatta molto prima, piu' spesso

Uso: variant.py --reserved 7000 > /tmp/opencode-B.jsonc
     bench/tasks/run.sh --config /tmp/opencode-B.jsonc --model litellm/local-good ...
"""
import argparse
import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[2] / "clients/opencode.jsonc"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--reserved", type=int, default=7000)
    a = ap.parse_args(argv)
    text = SRC.read_text()
    new, n = re.subn(r'("compaction"\s*:\s*\{[^}]*"reserved"\s*:\s*)\d+', rf"\g<1>{a.reserved}", text)
    if n != 1:
        sys.exit("compaction.reserved non trovato una volta sola in clients/opencode.jsonc")
    sys.stdout.write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
