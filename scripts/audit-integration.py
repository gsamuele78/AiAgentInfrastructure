#!/usr/bin/env python3
"""Verifica l'integrazione dello stack con HINT concreti. Solo lettura.
Exit 1 se almeno un FAIL. Solo stdlib."""
from __future__ import annotations
import json, os, re, sys, shutil, socket, subprocess, urllib.request, urllib.error
from pathlib import Path
HOME=Path.home(); CFG=Path(os.environ.get("XDG_CONFIG_HOME", HOME/".config"))
PROXY=os.environ.get("LITELLM_PROXY","http://127.0.0.1:4000"); KEY=os.environ.get("LITELLM_MASTER_KEY","")
GW=("127.0.0.1:4000","localhost:4000")
C={"g":"\033[32m","y":"\033[33m","r":"\033[31m","b":"\033[36m","0":"\033[0m"}
fails=0; warns=0
def L(s,m,h=""):
    global fails,warns
    col={"PASS":C["g"],"WARN":C["y"],"FAIL":C["r"],"INFO":C["b"]}[s]
    print(f"  {col}{s}{C['0']} {m}")
    if h: print(f"        \033[2mhint:\033[0m {h}")
    if s=="FAIL": fails+=1
    if s=="WARN": warns+=1
def rj(p):
    if not p.exists(): return None
    t=p.read_text(encoding="utf-8",errors="ignore")
    t=re.sub(r'^\s*//.*$','',t,flags=re.M); t=re.sub(r'/\*.*?\*/','',t,flags=re.S); t=re.sub(r',(\s*[}\]])',r'\1',t)
    try: return json.loads(t)
    except Exception as e: L("WARN",f"{p} non parsabile ({e})"); return None
def rt(p): return p.read_text(encoding="utf-8",errors="ignore") if p.exists() else None
def sec(t): print(f"\n{C['b']}== {t} =={C['0']}")
def port(n):
    with socket.socket() as s:
        s.settimeout(0.5); return s.connect_ex(("127.0.0.1",n))==0

sec("1. Gateway LiteLLM")
try:
    urllib.request.urlopen(f"{PROXY}/health/liveliness",timeout=4); L("PASS",f"vivo su {PROXY}")
    if KEY:
        r=urllib.request.Request(f"{PROXY}/v1/models",headers={"Authorization":f"Bearer {KEY}"})
        d=json.load(urllib.request.urlopen(r,timeout=6)).get("data",[])
        L("PASS" if len(d)>1 else "WARN",f"{len(d)} modelli esposti")
    else: L("WARN","LITELLM_MASTER_KEY non in env","source clients/shell-env.sh")
except (urllib.error.URLError,OSError):
    L("FAIL",f"non raggiungibile su {PROXY}","VM su? litellm-forward attivo? (VM-KVM-GUIDE.md)")

sec("2. opencode.jsonc")
oc=rj(CFG/"opencode"/"opencode.jsonc")
if oc is None: L("INFO","assente -> nuova installazione","copia clients/opencode.jsonc")
else:
    pr=oc.get("provider",{})
    bad=[(n,(p.get("options") or {}).get("baseURL","")) for n,p in pr.items()
         if (p.get("options") or {}).get("baseURL","") and not any(h in (p.get("options") or {}).get("baseURL","") for h in GW)]
    for n,u in bad: L("FAIL",f"provider '{n}' -> {u}","collassa in UN provider 'litellm' -> :4000")
    if not bad: L("PASS",f"provider -> gateway ({len(pr)})")
    if len(pr)>2: L("WARN",f"{len(pr)} provider","col gateway ne basta UNO")
    mcp=oc.get("mcp",{})
    lg=[k for k in mcp if len(k)>12 or "/" in k or "sequentialthinking" in k]
    L("WARN" if lg else "PASS", f"alias MCP {'lunghi: '+', '.join(lg) if lg else 'corti ('+str(len(mcp))+')'}",
      "accorcia: reason/mem/fs/ctx7/crawl/fetch" if lg else "")
    sr=next((v for k,v in mcp.items() if "serena" in k.lower()),None)
    if not sr: L("WARN","Serena non configurata","aggiungi il blocco 'serena' (ide-assistant)")
    elif "ide-assistant" in " ".join(sr.get("command",[])): L("PASS","Serena semantic-only")
    else: L("WARN","Serena senza --context ide-assistant","evita overlap coi tool harness")
    act=[k for k,v in mcp.items() if v.get("enabled",True)]
    L("PASS" if len(act)<=8 else "WARN",f"{len(act)} MCP attivi","" if len(act)<=8 else "tieni <10 MCP e <80 tool")

sec("3. Memory collision (ADR-0007)")
ms=[]
if oc:
    mcp=oc.get("mcp",{})
    if any(k.lower() in ("mem","memory") or "memory" in k.lower() for k in mcp): ms.append("memory MCP")
    if any("mem0" in k.lower() for k in mcp): ms.append("mem0")
    if any("serena" in k.lower() for k in mcp):
        sp=Path.cwd()/".serena"/"project.yml"
        off=sp.exists() and "write_memory" in sp.read_text(errors="ignore")
        L("PASS" if off else "WARN","Serena memory disabilitata" if off else "Serena memory NON esclusa",
          "" if off else "scrivi .serena/project.yml (MEMORY-POLICY.md)")
ctx=Path.cwd()/"AGENTS.md"
L("PASS" if ctx.exists() else "INFO",f"memory progetto: {'AGENTS.md' if ctx.exists() else 'assente'}",
  "" if ctx.exists() else "AGENTS.md e' il contesto letto dagli agenti")
L("PASS" if len(ms)<=1 else "FAIL",f"memory cross-sessione: {len(ms)} ({ms or 'nessuna'})",
  "" if len(ms)<=1 else "tienine UNA sola")

sec("4. openchamber")
oh=rj(CFG/"openchamber"/"settings.json")
if oh is None: L("INFO","assente","opzionale; eredita da opencode")
elif any(("baseurl" in k.lower() or "apibase" in k.lower()) for k in oh):
    L("WARN","ha un baseURL proprio","deve ereditare dal server opencode")
else: L("PASS","GUI su opencode (corretto)")

sec("5. claude / codex / shell")
cl=rj(HOME/".claude"/"settings.json")
if cl:
    b=(cl.get("env") or {}).get("ANTHROPIC_BASE_URL","")
    if "4000" in b: L("PASS","claude code -> :4000")
    elif "8787" in b: L("WARN","claude code -> :8787","ok se headroom-optional -> litellm")
    elif b: L("FAIL",f"claude code -> {b}","repointa a :4000")
if os.environ.get("ANTHROPIC_API_KEY"):
    L("WARN","ANTHROPIC_API_KEY in env: SCAVALCA l'abbonamento","unset (DUAL-AUTH.md)")
if os.environ.get("ANTHROPIC_AUTH_TOKEN"):
    L("INFO","ANTHROPIC_AUTH_TOKEN: Claude Code non usera' l'abbonamento","ok se voluto")
cx=rt(HOME/".codex"/"config.toml")
if cx:
    if "8787" in cx and "127.0.0.1:4000" not in cx: L("WARN","codex -> :8787","headroom unwrap codex")
    elif "127.0.0.1:4000" in cx: L("PASS","codex -> :4000")
for rc in (HOME/".bashrc",HOME/".profile",HOME/".zshrc"):
    t=rt(rc)
    if t and "8787" in t and "BASE_URL" in t: L("WARN",f"{rc.name}: export a :8787","usa clients/shell-env.sh")

sec("6. Servizi host residui")
def active(u,user=True):
    c=["systemctl"]+(["--user"] if user else [])+["is-active",u]
    try: return subprocess.run(c,capture_output=True,text=True,timeout=5).stdout.strip()=="active"
    except Exception: return False
L("WARN" if active("headroom.service") else "PASS",
  "headroom.service attivo" if active("headroom.service") else "headroom proxy non attivo",
  "non serve col callback: scripts/cleanup-host.sh" if active("headroom.service") else "")
L("WARN" if active("postgresql.service",False) else "PASS",
  "postgresql host attivo" if active("postgresql.service",False) else "postgres host non attivo",
  "verificato litellm-only: systemd/postgres-decision.md" if active("postgresql.service",False) else "")

sec("7. Agenti")
L("PASS" if shutil.which("opencode") else "WARN",f"opencode {'installato' if shutil.which('opencode') else 'non nel PATH'}",
  "" if shutil.which("opencode") else "curl -fsSL https://opencode.ai/install | bash")
L("PASS" if shutil.which("serena") else "WARN",f"serena {'installata' if shutil.which('serena') else 'assente'}",
  "" if shutil.which("serena") else "uv tool install -p 3.13 serena-agent@latest --prerelease=allow")
L("PASS" if shutil.which("graphify") else "INFO",f"graphify {'installato' if shutil.which('graphify') else 'assente'}",
  "" if shutil.which("graphify") else "uv tool install graphifyy (opzionale)")
srv=port(3000)
L("PASS" if srv else "INFO",f"opencode server :3000 {'attivo' if srv else 'non attivo'}",
  "" if srv else "systemctl --user start opencode.service")
if shutil.which("openchamber") and srv:
    L("WARN","openchamber e opencode possono contendersi la :3000","openchamber --port 3001 (AGENTS-SETUP.md)")

sec("8. Metodologia & security")
dirs=[HOME/".claude"/"skills",CFG/"opencode"/"skill",Path.cwd()/".agents"]
mp=any(d.exists() and any(("grill" in p.name or "to-spec" in p.name) for p in d.rglob("*")) for d in dirs if d.exists())
L("PASS" if mp else "INFO",f"mattpocock {'presenti' if mp else 'assenti'}","" if mp else "npx skills@latest add mattpocock/skills")
sp=any(d.exists() and any("superpowers" in p.name.lower() for p in d.rglob("*")) for d in dirs if d.exists())
if mp and sp: L("FAIL","mattpocock + superpowers insieme","OVERLAP: tienine uno (ADR-0006)")

print(f"\n{C['b']}== Esito =={C['0']}\n  FAIL: {fails}   WARN: {warns}")
if fails: print(f"  {C['r']}NON uniforme: risolvi i FAIL.{C['0']}"); sys.exit(1)
print(f"  {C['y']}Ok con avvertenze.{C['0']}" if warns else f"  {C['g']}Uniforme.{C['0']}")
