#!/usr/bin/env python3
"""redact.py -- trova e oscura i segreti nei testi (audit dell'host).

Usato da scripts/audit-host.sh. Solo stdlib. Il valore di un segreto non esce
MAI: al suo posto un'impronta (sha256, 8 caratteri) e la lunghezza, cosi' si
vede se la stessa chiave compare in piu' file senza poterla leggere.

  redact.py filter            stdin -> stdout con i segreti oscurati
  redact.py scan FILE...      tabella markdown: segreti, URL, riferimenti env
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

# Prefissi noti: si oscurano ovunque compaiano.
PREFIXES = [
    ("anthropic", r"sk-ant-[A-Za-z0-9_\-]{16,}"),
    ("openrouter", r"sk-or-v1-[A-Za-z0-9]{16,}"),
    ("openai-project", r"sk-proj-[A-Za-z0-9_\-]{16,}"),
    ("sk-generica", r"sk-[A-Za-z0-9_\-]{20,}"),
    ("github", r"gh[pousr]_[A-Za-z0-9]{20,}"),
    ("github-pat", r"github_pat_[A-Za-z0-9_]{20,}"),
    ("google", r"AIza[0-9A-Za-z_\-]{30,}"),
    ("slack", r"xox[abprs]-[A-Za-z0-9\-]{10,}"),
    ("huggingface", r"hf_[A-Za-z0-9]{20,}"),
    ("firecrawl", r"fc-[a-f0-9]{24,}"),
    ("tavily", r"tvly-[A-Za-z0-9\-]{16,}"),
    ("mem0", r"m0-[A-Za-z0-9]{16,}"),
    ("context7", r"ctx7sk-[A-Za-z0-9\-]{16,}"),
    ("gitlab", r"glpat-[A-Za-z0-9_\-]{16,}"),
    ("jwt", r"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"),
]
PREFIX_RE = re.compile(
    r"(?<![A-Za-z0-9_\-])(" + "|".join(f"(?P<p{i}>{p})" for i, (_, p) in enumerate(PREFIXES)) + r")"
)
KEYNAME = (r"[A-Za-z0-9_.\-]*(?:api[_\-]?key|apikey|secret|token|passw(?:or)?d|pwd|"
           r"master[_\-]?key|authorization|credential|private[_\-]?key|access[_\-]?key)[A-Za-z0-9_.\-]*")
# chiave = valore, chiave: valore, "chiave": "valore", --chiave valore
KV_RE = re.compile(
    r"(?i)(?P<k>(?:--)?[\"']?" + KEYNAME + r"[\"']?)(?P<sep>\s*[:=]\s*|(?<=[a-z])\s+(?=\S))"
    r"(?P<q>[\"']?)(?P<v>[^\"'\s,;}#]{6,})(?P=q)"
)
BEARER_RE = re.compile(r"(?i)\b(bearer|basic)\s+([A-Za-z0-9._~+/=\-]{8,})")
URLCRED_RE = re.compile(r"(?P<pre>[a-z][a-z0-9+.\-]*://[^:/@\s\"']+:)(?P<v>[^@/\s\"']+)(?P<post>@)")
URL_RE = re.compile(r"\b([a-z][a-z0-9+.\-]*)://(?:[^@/\s\"']+@)?([A-Za-z0-9.\-\[\]]+)(:\d+)?")
ENVREF_RE = re.compile(r"os\.environ/([A-Z_][A-Z0-9_]*)|\$\{([A-Z_][A-Z0-9_]*)[^}]*\}|\{env:([A-Z_][A-Z0-9_]*)\}")
PLACEHOLDERS = {"example-key", "changeme", "change-me", "your-key", "your_api_key", "xxx", "xxxx",
                "none", "null", "true", "false", "bearer", "basic", "redacted", "placeholder"}
MENTIONS = ["headroom", "litellm", "openrouter", ":8787", ":4000", "ollama", ":11434", "postgres"]


def fp(v: str) -> str:
    return hashlib.sha256(v.encode()).hexdigest()[:8]


def tag(kind: str, v: str) -> str:
    return f"«REDATTO:{kind} fp={fp(v)} len={len(v)}»"


# Non sono segreti: numeri (anche decimali/esponenziali) e date ISO. Sul primo
# host vero i contatori di headroom (avg_token_reduction: 0.1234...) erano 1150
# falsi positivi su 1190 righe.
NUMERIC_RE = re.compile(r"-?\d+(\.\d+)?([eE][-+]?\d+)?")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}([tT ][\d:.]+)?(z|[+-]\d{2}:?\d{2})?")


def is_placeholder(v: str) -> bool:
    lv = v.lower().strip()
    return (lv in PLACEHOLDERS or NUMERIC_RE.fullmatch(lv) is not None or DATE_RE.fullmatch(lv) is not None or lv.startswith(("$", "os.environ/", "{env:", "<", "env:", "%"))
            or lv.startswith(("http://", "https://", "/", "~", "./")) or set(lv) <= set("x*-_.")
            or "example" in lv)


TAG_RE = re.compile(r"(«REDATTO:[^»]*»)")


def outside_tags(line: str, rx: re.Pattern, fn) -> str:
    """Applica rx solo fuori dai segreti gia' oscurati (niente doppie etichette)."""
    return "".join(part if TAG_RE.fullmatch(part) else rx.sub(fn, part) for part in TAG_RE.split(line))


def redact(line: str, found: list | None = None) -> str:
    def add(kind, v):
        if found is not None:
            found.append((kind, fp(v), len(v)))

    def pre(m):
        v = m.group(1)
        kind = next(PREFIXES[i][0] for i in range(len(PREFIXES)) if m.group(f"p{i}"))
        add(kind, v)
        return tag(kind, v)

    line = PREFIX_RE.sub(pre, line)

    def urlcred(m):
        v = m.group("v")
        if v.startswith("«") or is_placeholder(v):
            return m.group(0)
        add("password-in-url", v)
        return m.group("pre") + tag("password-in-url", v) + m.group("post")

    line = outside_tags(line, URLCRED_RE, urlcred)

    def bearer(m):
        v = m.group(2)
        if v.startswith("«") or is_placeholder(v):
            return m.group(0)
        add("bearer", v)
        return f"{m.group(1)} {tag('bearer', v)}"

    line = outside_tags(line, BEARER_RE, bearer)

    def kv(m):
        v = m.group("v")
        if v.startswith("«") or "«REDATTO" in v or is_placeholder(v):
            return m.group(0)
        kind = m.group("k").strip("\"'-").lower()
        add(kind, v)
        return m.group("k") + m.group("sep") + m.group("q") + tag(kind, v) + m.group("q")

    return outside_tags(line, KV_RE, kv)


def scan(paths: list[str]) -> int:
    print("| file | riga | tipo | impronta | lung. |")
    print("|---|---|---|---|---|")
    urls, refs, ment = {}, {}, {}
    for p in paths:
        try:
            text = Path(p).read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            print(f"| `{p}` | – | non leggibile ({e.strerror}) | – | – |")
            continue
        for n, line in enumerate(text.splitlines(), 1):
            found: list = []
            redact(line, found)
            for kind, f, ln in found:
                print(f"| `{p}` | {n} | {kind} | `{f}` | {ln} |")
            for m in URL_RE.finditer(line):
                u = f"{m.group(1)}://{m.group(2)}{m.group(3) or ''}"
                urls.setdefault(u, set()).add(p)
            for m in ENVREF_RE.finditer(line):
                refs.setdefault(next(g for g in m.groups() if g), set()).add(p)
        low = text.lower()
        for w in MENTIONS:
            c = low.count(w)
            if c:
                ment.setdefault(w, []).append(f"`{Path(p).name}`×{c}")
    print("\n**Endpoint citati** (solo schema://host:porta):\n")
    for u in sorted(urls):
        print(f"- `{u}` — {', '.join(f'`{x}`' for x in sorted(urls[u]))}")
    print("\n**Variabili d'ambiente richieste dai config:**\n")
    for r in sorted(refs):
        print(f"- `{r}` — {', '.join(f'`{x}`' for x in sorted(refs[r]))}")
    print("\n**Menzioni:** " + ("; ".join(f"{w}: {' '.join(v)}" for w, v in ment.items()) or "nessuna"))
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[1] == "filter":
        for line in sys.stdin:
            sys.stdout.write(redact(line))
        return 0
    if len(argv) >= 3 and argv[1] == "scan":
        return scan(argv[2:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
