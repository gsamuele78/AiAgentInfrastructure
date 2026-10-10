#!/usr/bin/env python3
"""AGENTS.md e' ancora vero? Controllo deterministico della deriva (ADR-0025 §9).

Adattato da OpenHands extensions/skills/github-agents-md-maintainer (MIT): la' un cron
settimanale fa riscrivere AGENTS.md a un LLM e apre una PR. Qui AGENTS.md e' curato a mano
(le trappole sono esperienza, non si rigenerano), quindi si importa solo la parte
deterministica: ogni riferimento verificabile deve puntare a qualcosa che esiste.

  A1 ogni comando del blocco "Comandi" che e' un file del repo esiste ed e' eseguibile
  A2 ogni percorso del repo citato (docs/, scripts/, tests/, bench/, services/, clients/,
     stack/) esiste
  A3 ogni ADR citato (ADR-00NN, 00NN) esiste in docs/adr/
  A4 i file citati da CLAUDE.md esistono
Uso: check.py [--root DIR]
"""
import argparse
import re
import sys
from pathlib import Path

PREFIX = r"(?:docs|scripts|tests|bench|services|services-biome|clients|stack|systemd)/"
PATH_RE = re.compile(r"(?<![\w./-])(" + PREFIX + r"[\w./-]*[\w/])")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    root = Path(ap.parse_args(argv).root)
    errs = []
    text = (root / "AGENTS.md").read_text()
    # A1: blocco Comandi
    m = re.search(r"## Comandi\s+```bash\n(.*?)```", text, re.S)
    cmds = m.group(1) if m else ""
    if not m:
        errs.append("A1 sezione '## Comandi' con blocco bash non trovata")
    for line in cmds.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        tok = line.split()[0]
        if "/" in tok and not tok.startswith(("$", "-")):
            p = root / tok.lstrip("./")
            if not p.exists():
                errs.append(f"A1 comando inesistente: {tok}")
            elif not p.stat().st_mode & 0o111:
                errs.append(f"A1 comando non eseguibile: {tok}")
    # A2: percorsi
    for p in sorted(set(PATH_RE.findall(text))):
        p = p.rstrip(".")
        if "*" in p or "<" in p:
            continue
        if not (root / p).exists():
            errs.append(f"A2 percorso citato inesistente: {p}")
    # A3: ADR
    adrs = {f.name[:4] for f in (root / "docs/adr").glob("[0-9][0-9][0-9][0-9]-*.md")}
    for n in sorted(set(re.findall(r"ADR-(\d{4})", text)) | set(re.findall(r"\b(00\d\d)\b", text))):
        if n not in adrs:
            errs.append(f"A3 ADR citato inesistente: {n}")
    # A4: CLAUDE.md
    cl = root / "CLAUDE.md"
    if cl.exists():
        for p in sorted(set(re.findall(r"\(([\w./-]+\.md)\)|`([\w./-]+\.(?:md|sh))`", cl.read_text()))):
            p = p[0] or p[1]
            q = p.split()[0].lstrip("./")
            if not (root / q).exists():
                errs.append(f"A4 CLAUDE.md cita un file inesistente: {q}")
    for e in errs:
        print(f"  ✗ AGENTS {e}")
    print(f"  AGENTS.md: {len(errs)} riferimenti rotti")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
