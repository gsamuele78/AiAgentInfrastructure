#!/usr/bin/env python3
"""Lint delle skill di progetto (ADR-0019 §1-2; pratica importata da OpenHands
extensions/tests/test_catalog_schema.py e test_skills_catalog.py, MIT; ADR-0025 §5).

  S1 ogni SKILL.md ha frontmatter con `name` e `description`; name == nome della cartella,
     [a-z0-9-], description <= 1024 caratteri (limite di Claude Code e opencode)
  S2 nessun nome in due cartelle: opencode legge sia .agents/skills sia .claude/skills,
     una skill in entrambe e' un duplicato in context. Se .claude/skills e' il symlink
     a ../.agents/skills (la scelta di ADR-0019) e' la stessa cartella: nessun duplicato
  S3 nessun nome che collide con un comando integrato dei client (es. code-review, ADR-0006)
Stampa anche i token stimati delle descrizioni, che restano sempre in context.

Uso: check.py [--root DIR]   (default: la radice del repo)
"""
import argparse
import re
import sys
from pathlib import Path

DIRS = [".agents/skills", ".claude/skills"]
BUILTIN = {  # comandi/skill integrati di Claude Code e opencode con cui una skill collide
    "code-review", "review", "security-review", "init", "simplify", "loop", "run", "compact",
    "clear", "help", "config", "model", "memory", "agents", "mcp", "doctor", "status", "share",
}
NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def frontmatter(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end < 0:
        return None
    fm = {}
    for line in text[4:end].splitlines():
        m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip("'\"")
        elif line.startswith((" ", "\t")) and fm:  # continuazione (description: >)
            k = list(fm)[-1]
            fm[k] = (fm[k] + " " + line.strip()).strip()
    return fm


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    root = Path(ap.parse_args(argv).root)
    errs, seen, tokens, n = [], {}, 0, 0
    real = {}
    for d in DIRS:
        p = root / d
        if p.exists():
            real.setdefault(p.resolve(), d)
    for rp, d in real.items():
        for sk in sorted(rp.glob("*/SKILL.md")):
            n += 1
            name_dir = sk.parent.name
            fm = frontmatter(sk.read_text())
            where = f"{d}/{name_dir}"
            if fm is None:
                errs.append(f"S1 {where}: SKILL.md senza frontmatter"); continue
            name, desc = fm.get("name", ""), fm.get("description", "")
            if not name or not desc:
                errs.append(f"S1 {where}: manca name o description")
            if name and name != name_dir:
                errs.append(f"S1 {where}: name '{name}' diverso dalla cartella")
            if name and not NAME.match(name):
                errs.append(f"S1 {where}: name '{name}' non in [a-z0-9-]")
            if len(desc) > 1024:
                errs.append(f"S1 {where}: description di {len(desc)} caratteri (> 1024)")
            key = name or name_dir
            if key in seen:
                errs.append(f"S2 '{key}' in {seen[key]} e in {d}: duplicato in context")
            seen.setdefault(key, d)
            if key in BUILTIN:
                errs.append(f"S3 {where}: '{key}' collide con un comando integrato dei client")
            tokens += len(desc) // 4
    for e in errs:
        print(f"  ✗ SKILL {e}")
    print(f"  skill: {n} in {len(real)} cartella/e reali · ~{tokens} token di descrizioni sempre in context")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
