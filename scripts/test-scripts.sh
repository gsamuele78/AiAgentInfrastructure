#!/usr/bin/env bash
# ============================================================
#  test-scripts.sh -- test degli SCRIPT stessi (L1/L2 del test plan).
#  Non tocca il sistema: verifica sintassi, contratti, idempotenza
#  dei dry-run e le invarianti di sicurezza del codice.
#  Gira anche in CI su runner GitHub (nessuna dipendenza dall'host).
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
P=0;F=0
ok(){ echo -e "  \033[32m✓\033[0m $1"; P=$((P+1)); }
ko(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo -e "     \033[2m$2\033[0m"; F=$((F+1)); }
sec(){ echo -e "\n\033[36m━━ $1 ━━\033[0m"; }

sec "1. Sintassi ed eseguibilità"
for s in scripts/*.sh; do
  bash -n "$s" && ok "sintassi $(basename "$s")" || ko "sintassi $(basename "$s")"
  [ -x "$s" ] && ok "eseguibile $(basename "$s")" || ko "$(basename "$s") non eseguibile" "chmod +x $s"
done
python3 -m py_compile scripts/*.py && ok "python compila" || ko "python non compila"

sec "2. Contratto: ogni script supporta --dry-run o è read-only"
# Gli script SOLO-LETTURA sono l'eccezione dichiarata; tutti gli altri devono
# esporre --dry-run. La lista non e' piu' hardcoded: si deriva da scripts/*.sh,
# cosi' un nuovo script entra automaticamente nel contratto (invariante #9).
READONLY="detect-hardware.sh devops-audit.sh test-all.sh test-scripts.sh"
READONLY_PY="audit-integration.py"
DRYRUN_SCRIPTS=""
for f in scripts/*.sh; do
  b=$(basename "$f")
  case " $READONLY " in *" $b "*)
    grep -qE 'sudo (rm|systemctl (stop|disable)|mv)' "$f" \
      && ko "$b dichiarato read-only ma modifica il sistema" || ok "$b è read-only"
    continue;;
  esac
  # Fuori dai commenti: un commento d'uso che cita --dry-run senza che il flag
  # sia parsato passerebbe il controllo e non simulerebbe niente.
  if grep -v '^[[:space:]]*#' "$f" | grep -q -- '--dry-run'; then
    ok "$b espone --dry-run"; DRYRUN_SCRIPTS="$DRYRUN_SCRIPTS $b"
  else
    ko "$b senza --dry-run" "gli script che modificano il sistema devono poterlo simulare"
  fi
done

# Anche gli script python che modificano lo stato devono esporre --dry-run.
for f in scripts/*.py; do
  b=$(basename "$f")
  case " $READONLY_PY " in *" $b "*) ok "$b è read-only"; continue;; esac
  # In python i docstring non iniziano con '#': togliere i commenti non basta,
  # il flag va cercato come STRINGA nel codice (add_argument("--dry-run")),
  # altrimenti un docstring d'uso che lo cita basterebbe a passare.
  grep -qE "[\"']--dry-run[\"']" "$f" && ok "$b espone --dry-run" \
    || ko "$b senza --dry-run" "modifica il DB del gateway: deve poterlo simulare"
done

sec "2b. TC-08: i dry-run completano anche su una macchina vuota"
# Cercare la stringa '--dry-run' col grep non dimostra nulla: il dry-run va
# ESEGUITO. È così che si scopre che create-vm.sh moriva su $USER non impostato.
for b in $DRYRUN_SCRIPTS; do
  if out=$(env -u USER "scripts/$b" --dry-run 2>&1); then ok "$b --dry-run esce 0"
  else ko "$b --dry-run fallisce (exit $?)" "$(echo "$out" | tail -3)"; fi
done
# sync_openrouter.py e' escluso da 2b per costruzione: il suo dry-run calcola un
# diff, quindi ha bisogno del catalogo OpenRouter E del gateway. Su una macchina
# vuota esce 2 ("prerequisiti mancanti"), che e' il comportamento giusto: non e'
# un crash, e' un rifiuto motivato. Il suo test vero e' F8, livello L5.
echo -e "  \033[2m–\033[0m sync_openrouter.py --dry-run \033[2m(serve il gateway: test L5, non L1b)\033[0m"

# Il comando atteso dipende dall'OS su cui gira il test: si chiede alla stessa
# funzione che lo script usa, invece di scrivere "apt install" a mano qui.
pkg_hint_probe(){ ( . scripts/lib/hw-detect.sh; pkg_hint libvirt | awk '{print $1" "$2}' ); }

sec "3. Invarianti di sicurezza nel codice"
# Ollama non deve mai essere bindato su tutte le interfacce
grep -q 'OLLAMA_HOST=.*0\.0\.0\.0' scripts/setup-ollama.sh \
  && ko "setup-ollama binda Ollama su 0.0.0.0" "Ollama non ha auth: solo virbr0" \
  || ok "Ollama non viene bindato su 0.0.0.0"
# nessun segreto hardcoded
grep -rInE '(sk-ant-[A-Za-z0-9]{20,}|sk-or-v1-[A-Za-z0-9]{20,})' scripts/ services/ services-biome/ clients/ 2>/dev/null \
  | grep -viE 'CHANGEME|example|placeholder|<' \
  && ko "segreto hardcoded" || ok "nessun segreto hardcoded"
# cleanup-host deve avere il pre-check sul gateway (ordine PSE)
grep -q 'health/liveliness' scripts/cleanup-host.sh \
  && ok "cleanup-host verifica il gateway prima di pulire" \
  || ko "cleanup-host senza pre-check" "ordine PSE: VM su PRIMA della pulizia"
# create-vm --destroy deve chiedere conferma esplicita
grep -A3 'DESTROY.*=.*1' scripts/create-vm.sh | grep -q 'read -rp' \
  && ok "create-vm --destroy richiede conferma" || ko "--destroy senza conferma"
# TC-02: nessun config client deve puntare al vecchio proxy headroom (:8787).
# È la regressione piu' frequente del repo ('headroom wrap' riscrive i config).
grep -rn ':8787' clients/ 2>/dev/null \
  && ko "riferimento a :8787 nei config client" "invariante #1: un solo gateway" \
  || ok "nessun client punta a :8787"
# Il Dockerfile non deve usare 'pip': l'immagine upstream (Wolfi + venv uv) non
# ce l'ha. È il bug che teneva rossa la CI da sempre.
grep -qE '^RUN[[:space:]]+pip[[:space:]]' services/Dockerfile \
  && ko "Dockerfile usa 'pip'" "l'immagine base non ha pip: usa uv sul venv /app/.venv" \
  || ok "Dockerfile non usa 'pip' (immagine base senza pip)"
# I nomi della lane locale devono essere gli stessi ovunque.
if grep -q 'local-small' scripts/*.sh docs/*.md --exclude=test-scripts.sh 2>/dev/null; then
  ko "lane locale: 'local-small' convive con 'local-fast'/'local-good'" "un nome solo"
else ok "lane locale: nomi coerenti (local-fast / local-good)"; fi

# Repo PUBBLICO: nessun identificatore interno nei file versionati.
# La subnet 192.168.122.0/24 e' esclusa apposta: e' il default di libvirt,
# uguale ovunque, e gli script la usano davvero (docs/GITHUB-SETUP.md §2).
# Copre utenti, nomi macchina e domini interni. NON gli IP: distinguerne uno
# interno da 0.0.0.0 o dalla subnet libvirt richiederebbe un pattern fragile --
# per quelli vale la regola scritta in GITHUB-SETUP.md, non un grep.
LEAKS=$(grep -rInE '(@?\bjfs\b|\bermes\b|\.unibo\.it)' --exclude-dir=.git --exclude=test-scripts.sh . 2>/dev/null | grep -viE 'permess|CHANGEME|<dominio' || true)
[ -z "$LEAKS" ] && ok "nessun identificatore interno versionato (repo pubblico)" \
  || ko "identificatore interno nei file versionati" "$(echo "$LEAKS" | head -3)"

# --- Regole HC di Infra-Iam-PKI portate qui (ADR-0022, docs/ALIGNMENT-INFRA-IAM-PKI.md).
# L'ID HC resta nel commento: la corrispondenza fra i due repo deve essere cercabile.
# HC-03 (adattata): ogni script dichiara `set -uo pipefail` (o -euo) prima del codice.
# Qui `-e` NON e' obbligatorio: diversi script lo tolgono apposta per gestire gli
# errori di run() a mano (trappola nota in AGENTS.md); -u e pipefail si'.
NOSTRICT=""
for f in scripts/*.sh; do
  first=$(grep -m1 -E '^[[:space:]]*set[[:space:]]+-' "$f" || true)
  printf '%s' "$first" | grep -qE 'set -e?uo pipefail' || NOSTRICT="$NOSTRICT $(basename "$f")"
done
[ -z "$NOSTRICT" ] && ok "HC-03: ogni script dichiara set -uo pipefail" \
  || ko "HC-03: script senza 'set -uo pipefail':$NOSTRICT" "variabili non definite e pipe rotte passerebbero in silenzio"
# HC-08: nessun .env vero, chiave o certificato privato tracciato da git.
if git rev-parse --git-dir >/dev/null 2>&1; then
  TRACKED=$(git ls-files | grep -E '(^|/)\.env$|(^|/)[^/]*\.env$|\.key$|\.pem$|(^|/)master\.key$|(^|/)forward\.env$' || true)
  [ -z "$TRACKED" ] && ok "HC-08: nessun .env/chiave tracciato da git" \
    || ko "HC-08: file segreti tracciati" "$(echo "$TRACKED" | head -3)"
else
  echo -e "  \033[2m–\033[0m HC-08 non verificabile (non e' un checkout git)"
fi
# HC-09: nessun servizio monta il socket di docker (controllo totale dell'host).
SOCK=$(grep -nE '/var/run/docker\.sock|/run/docker\.sock' services/docker-compose.yml services-biome/docker-compose.yml || true)
[ -z "$SOCK" ] && ok "HC-09: nessun servizio monta docker.sock" \
  || ko "HC-09: docker.sock montato in un compose" "$SOCK"

# --- P1 (ADR-0017/0020) + HC-07: versioni pinnate, nel formato che Dependabot legge.
# Un tag mobile o un @latest non si puo' aggiornare da un bot ne' riprodurre.
if python3 -c 'import tomllib' 2>/dev/null; then
  python3 - <<'PYX' && ok "HC-07/P1: nessun @latest, tag mobile o npx senza versione; FROM con digest" || ko "HC-07/P1: versione mobile o non pinnata" "pin in stack/, services/Dockerfile, compose (ADR-0020)"
import pathlib, re, sys
bad = []
files = [p for d in ("clients", "scripts", "services", "services-biome", "stack") for p in pathlib.Path(d).rglob("*")
         if p.is_file() and p.suffix in (".sh", ".py", ".json", ".jsonc", ".toml", ".yml", ".yaml", ".txt", "")
         and p.name != "test-scripts.sh" and "__pycache__" not in p.parts] + [pathlib.Path(".mcp.json")]
FLOAT = [(r"@latest\b", "@latest"), (r"--prerelease=allow", "--prerelease=allow"), (r":latest\b", ":latest"),
         (r"\bmain-stable\b", "main-stable"), (r"git\+https://", "uvx/pip da git HEAD"),
         (r"\$\{[A-Z_]*TAG[A-Z_]*(:-[^}]*)?\}", "tag da variabile")]
for f in files:
    for n, line in enumerate(f.read_text(errors="ignore").splitlines(), 1):
        code = line.split("#", 1)[0] if f.suffix in (".sh", ".py", ".toml", ".yml", ".yaml", ".txt", "") else line
        if code.lstrip().startswith("//"): continue
        for rx, why in FLOAT:
            if re.search(rx, code): bad.append(f"{f}:{n} {why}")
        # Invocazioni npx: sempre `-y` (non interattivo) e sempre `pkg@versione`.
        # Forme: ["npx","-y","pkg@1.2.3"] (client) e run "npx -y 'pkg@$PIN'" (script).
        for m in re.finditer(r'npx["\',\s]+-y["\',\s]+["\']?((?:@[\w.-]+/)?[\w.-]+)(@[\w.$-]+)?', code):
            if not m.group(2): bad.append(f"{f}:{n} npx -y {m.group(1)} senza versione")
        if re.search(r'run\s+"npx\s+(?!-y\b)', code): bad.append(f"{f}:{n} npx senza -y")
for line in pathlib.Path("services/Dockerfile").read_text().splitlines():
    m = re.match(r"\s*FROM\s+(\S+)", line, re.I)
    if m and "/" in m.group(1) and "@sha256:" not in m.group(1):
        bad.append(f"services/Dockerfile: FROM {m.group(1)} senza digest")
for f in ("services/docker-compose.yml", "services-biome/docker-compose.yml"):
    for m in re.finditer(r"^\s*image:\s*\"?([^\s\"#]+)", pathlib.Path(f).read_text(), re.M):
        img = m.group(1)
        if img.endswith(":local"): continue          # costruita dal Dockerfile
        tag = img.rsplit(":", 1)[1] if ":" in img.split("/")[-1] else ""
        if not re.match(r"v?\d+\.\d+", tag): bad.append(f"{f}: {img} (tag mobile o assente)")
if bad: print("    " + "\n    ".join(bad[:8])); sys.exit(1)
PYX
  python3 - <<'PYX' && ok "P1: i pin nei client coincidono con stack/ (serena, MCP)" || ko "P1: pin dei client diversi da stack/" "allinea i client alla PR di Dependabot (stack/requirements-tools.txt)"
import json, pathlib, re, sys
req = dict(re.findall(r"^([\w.-]+)==(\S+)", pathlib.Path("stack/requirements-tools.txt").read_text(), re.M))
npm = json.loads(pathlib.Path("stack/package.json").read_text())["dependencies"]
bad = []
for f in ("clients/opencode.jsonc", "clients/codex-config.toml", ".mcp.json"):
    t = pathlib.Path(f).read_text()
    for v in re.findall(r"serena-agent==([\w.]+)", t):
        if v != req.get("serena-agent"): bad.append(f"{f}: serena-agent=={v} != {req.get('serena-agent')}")
    if "serena" in t and "serena-agent==" not in t: bad.append(f"{f}: Serena senza pin")
    for pkg, v in re.findall(r'"((?:@[\w.-]+/)?[\w.-]+)@(\d[\w.-]*)"', t):
        if pkg not in npm: bad.append(f"{f}: {pkg} non e' in stack/package.json")
        elif npm[pkg] != v: bad.append(f"{f}: {pkg}@{v} != {npm[pkg]}")
cb = re.search(r"^headroom-ai==(\S+)", pathlib.Path("services/requirements-callback.txt").read_text(), re.M)
if not cb: bad.append("services/requirements-callback.txt senza headroom-ai==")
if "requirements-callback.txt" not in pathlib.Path("services/Dockerfile").read_text():
    bad.append("services/Dockerfile non usa requirements-callback.txt")
if bad: print("    " + "\n    ".join(bad)); sys.exit(1)
PYX
  python3 - <<'PYX' && ok "P1: stack/components.toml coerente (ogni pin esiste e contiene il componente)" || ko "P1: stack/components.toml incoerente" "ADR-0017"
import pathlib, sys, tomllib
comps = tomllib.load(open("stack/components.toml", "rb"))["component"]
bad, ids = [], set()
for c in comps:
    for k in ("id", "layer", "scope", "required", "pin", "key", "tracked"):
        if k not in c: bad.append(f"{c.get('id','?')}: manca {k}")
    if c["id"] in ids: bad.append(f"{c['id']}: duplicato")
    ids.add(c["id"])
    if c["pin"] == "none":
        if c["tracked"]: bad.append(f"{c['id']}: tracked senza pin")
        if not c.get("note"): bad.append(f"{c['id']}: pin none senza motivo (note)")
    elif not pathlib.Path(c["pin"]).is_file(): bad.append(f"{c['id']}: {c['pin']} non esiste")
    elif c["key"] not in pathlib.Path(c["pin"]).read_text(): bad.append(f"{c['id']}: {c['key']} non in {c['pin']}")
tr = sum(1 for c in comps if c["tracked"])
print(f"    misura P1: {tr}/{len(comps)} componenti con pin letto da Dependabot ({100*tr//len(comps)}%)")
if bad: print("    " + "\n    ".join(bad)); sys.exit(1)
PYX
else
  echo -e "  \033[2m–\033[0m controlli P1 saltati (serve python >= 3.11 per tomllib)"
fi

sec "4. Compose: validi e senza esposizioni indebite"
# pyyaml puo' mancare su una macchina pulita: in quel caso SKIP, non FAIL.
# Un controllo che fallisce per motivi ambientali e' peggio di un controllo assente.
if python3 -c 'import yaml' 2>/dev/null; then
  HAVE_YAML=1
else
  HAVE_YAML=0
  echo -e "  \033[2m–\033[0m controlli YAML saltati (pyyaml assente: pip install pyyaml)"
fi

for d in services services-biome; do
  if [ "$HAVE_YAML" = 1 ]; then
    python3 -c "import yaml,sys; yaml.safe_load(open('$d/docker-compose.yml'))" \
      && ok "$d/docker-compose.yml valido" || ko "$d/docker-compose.yml non valido"
  elif command -v docker >/dev/null 2>&1; then
    # `docker compose config` richiede un .env vero: --env-file cambia solo
    # l'interpolazione, non soddisfa la chiave `env_file:` del servizio.
    # Lo creiamo temporaneamente e lo togliamo SEMPRE: questo script dichiara
    # di non toccare nulla e deve essere vero anche nel ramo di fallback.
    # ENVF assoluto: il trap scatta DOPO il cd, un path relativo punterebbe altrove.
    ( ENVF="$PWD/$d/.env"; TMPENV=0
      [ -f "$ENVF" ] || { cp "$PWD/$d/.env.example" "$ENVF"; TMPENV=1; }
      trap '[ "$TMPENV" = 1 ] && rm -f "$ENVF"' EXIT
      cd "$d" && BIND_IP=127.0.0.1 docker compose config >/dev/null 2>&1 ) \
      && ok "$d/docker-compose.yml valido (via docker compose)" \
      || echo -e "  \033[2m–\033[0m $d/docker-compose.yml non verificabile qui"
  else
    echo -e "  \033[2m–\033[0m $d/docker-compose.yml non verificabile (ne' pyyaml ne' docker)"
  fi
done

# postgres non deve pubblicare porte. Fallback su grep: non richiede pyyaml
# ed e' l'ancora di sicurezza se il parser non e' disponibile.
if [ "$HAVE_YAML" = 1 ]; then
  python3 - <<'PYX' && ok "postgres non esposto su porta host" || ko "postgres esposto"
import yaml,sys
c=yaml.safe_load(open("services/docker-compose.yml"))
sys.exit(1 if c["services"]["db"].get("ports") else 0)
PYX
else
  grep -qE '^\s*-\s*"?[0-9.]*:?5432:5432' services/docker-compose.yml \
    && ko "postgres esposto su porta host" || ok "postgres non esposto (verifica testuale)"
fi
# vLLM deve stare su loopback
grep -q '"127.0.0.1:8000:8000"' services-biome/docker-compose.yml \
  && ok "vLLM su loopback (solo nginx lo espone)" || ko "vLLM non su loopback"
# config montate read-only
grep -q ':ro' services/docker-compose.yml && ok "config montata :ro" || ko "config non :ro"
# HC-01: ogni servizio ha limiti di memoria E cpu (niente OOM a cascata nella VM da 4 GB).
if [ "$HAVE_YAML" = 1 ]; then
  python3 - <<'PYX' && ok "HC-01: ogni servizio ha deploy.resources.limits (memory e cpus)" || ko "HC-01: servizio senza limiti di risorse"
import sys, yaml
# Eccezione DICHIARATA: vLLM sul server BIOME condivide la macchina coi workload di
# ricerca, ma un limite di RAM scelto senza misure lo ucciderebbe al caricamento
# del modello. Va dimensionato sul server reale (docs/ALIGNMENT-INFRA-IAM-PKI.md).
EXEMPT = {"services-biome/docker-compose.yml:vllm"}
bad = []
for f in ("services/docker-compose.yml", "services-biome/docker-compose.yml"):
    for name, svc in (yaml.safe_load(open(f)).get("services") or {}).items():
        if f"{f}:{name}" in EXEMPT:
            continue
        lim = ((svc.get("deploy") or {}).get("resources") or {}).get("limits") or {}
        if not (lim.get("memory") and lim.get("cpus")):
            bad.append(f"{f}:{name}")
if bad:
    print("    " + ", ".join(bad)); sys.exit(1)
PYX
else
  echo -e "  \033[2m–\033[0m HC-01 non verificabile (pyyaml assente)"
fi

# ADR-0015: un job con `continue-on-error: true` gira ma non puo' fallire.
# E' come non averlo. `continue-on-error` a livello di STEP resta lecito.
for wf in .github/workflows/*.yml; do
  if grep -qE '^\s{4}continue-on-error:\s*true' "$wf"; then
    ko "$(basename "$wf"): continue-on-error a livello di job" \
       "ADR-0015: un test che non puo' fallire non e' un test"
  else
    ok "$(basename "$wf"): nessun job non-bloccante"
  fi
done

# Repo pubblico + runner self-hosted: un trigger `pull_request` su un workflow
# self-hosted = esecuzione di codice arbitrario sull'host (GITHUB-SETUP.md §4).
for wf in .github/workflows/*.yml; do
  grep -q 'self-hosted' "$wf" || continue
  if grep -qE '^\s+pull_request(_target)?\s*:' "$wf"; then
    ko "$(basename "$wf"): trigger pull_request su runner self-hosted" \
       "chiunque apra una PR eseguirebbe codice sull'host"
  else
    ok "$(basename "$wf"): self-hosted non innescabile da una PR"
  fi
done

# La GPU si cerca sul BUS PCI, non nella presenza di nvidia-smi: dedurre
# l'hardware da un binario mente su OS atomico senza driver proprietari
# (Bazzite/Silverblue), a dGPU spenta (Optimus) e dentro un container.
for f in scripts/detect-hardware.sh scripts/setup-ollama.sh; do
  b=$(basename "$f")
  grep -q 'nvidia_pci_devices' "$f" \
    && ok "$b rileva la GPU dal bus PCI, non da nvidia-smi" \
    || ko "$b deduce la GPU dalla presenza di nvidia-smi" "falso negativo su OS atomico o dGPU spenta"
done
# deploy-all.sh non decide sulla GPU: delega a setup-ollama.sh --plan (stessa
# tabella di detect-hardware.sh). Un `command -v nvidia-smi` qui era la trappola nota.
if grep -q 'command -v nvidia-smi' scripts/deploy-all.sh || ! grep -q 'setup-ollama.sh --plan' scripts/deploy-all.sh; then
  ko "deploy-all.sh decide sulla GPU da solo" "deve delegare a setup-ollama.sh --plan (scripts/lib/llm-plan.sh)"
else ok "deploy-all.sh delega la decisione sulla GPU a setup-ollama.sh --plan"; fi
# La verifica della fase 7 deve poter fallire: con `|| true` uno stack rosso
# arrivava alla fase 8 (baseline) come se fosse verde.
if grep -qE '(devops-audit\.sh|audit-integration\.py|test-all\.sh)[^"]*\|\|[[:space:]]*true' scripts/deploy-all.sh; then
  ko "deploy-all.sh: verifica neutralizzata da '|| true'" "uno stack rosso non deve arrivare alla baseline"
else ok "deploy-all.sh: la verifica della fase 7 puo' fallire"; fi
# I passi della VM si eseguono, non si stampano: un segnaposto <VM_IP> in
# deploy-all.sh vuol dire che un passo e' tornato manuale.
if grep -q '<VM_IP>' scripts/deploy-all.sh; then
  ko "deploy-all.sh: passi della VM stampati con <VM_IP> invece che eseguiti" "usa VM_IP/VM_SSH e vm()"
else ok "deploy-all.sh: i passi della VM sono eseguiti, non stampati"; fi
# Ogni script che modifica l'HOST deve rifiutarsi di partire da dentro un
# sandbox: scriverebbe nel sandbox lasciando il sistema com'era, e il silenzio
# e' il modo peggiore di sbagliare. Su Bazzite capita spesso: molte app,
# terminali compresi, sono Flatpak.
for b in $DRYRUN_SCRIPTS; do
  case "$b" in backup-db.sh|restore-test.sh) continue ;; esac  # girano NELLA VM
  grep -q 'sandbox_guard' "scripts/$b" && ok "$b si ferma se e' dentro un sandbox" \
    || ko "$b non controlla il sandbox" "da un Flatpak scriverebbe nel sandbox, non sull'host"
done

# I comandi d'installazione non possono essere hardcoded su una distribuzione:
# `apt install` su Fedora/Bazzite e' un consiglio che non funziona.
# Eccezione legittima: il blocco cloud-init di create-vm.sh e' DATO, non
# codice eseguito qui, e la VM e' Debian per costruzione (IMG_URL punta a una
# cloud image Debian). Le righe fra <<CIEOF e CIEOF sono quindi escluse.
PKGHITS=$(for f in scripts/*.sh; do
  [ "$(basename "$f")" = test-scripts.sh ] && continue
  awk -v F="$f" '
    /<<CIEOF/ {inci=1} inci && /^CIEOF$/ {inci=0; next}
    !inci && /(apt|apt-get|dnf|pacman|zypper)[[:space:]]+install/ {printf "%s:%d:%s\n", F, NR, $0}
  ' "$f"
done)
[ -z "$PKGHITS" ] && ok "nessun gestore di pacchetti hardcoded (si usa pkg_hint)" \
  || ko "comando d'installazione hardcoded negli script" "$(echo "$PKGHITS" | head -3)"

# create-vm.sh: --destroy e' distruttivo, quindi il sandbox_guard deve venire
# PRIMA. Da un sandbox le chiamate virsh hanno "|| true" e lo script stampava
# "VM rimossa" uscendo 0 senza toccare niente: un falso successo su un percorso
# distruttivo e' peggio di un errore.
# Controllo STRUTTURALE, non comportamentale: per esercitare davvero il percorso
# servirebbe passare il nome esatto della VM alla conferma, cioe' far eseguire a
# una suite dichiarata read-only un `virsh destroy`. Il primo tentativo passava
# la conferma sbagliata e quindi si fermava li', dando la risposta giusta per il
# motivo sbagliato -- verde anche col guard spostato dopo.
GLINE=$(grep -n 'sandbox_guard "scripts/create-vm.sh"' scripts/create-vm.sh | head -1 | cut -d: -f1)
DLINE=$(grep -n 'if \[ "\$DESTROY" = 1 \]' scripts/create-vm.sh | head -1 | cut -d: -f1)
if [ -n "$GLINE" ] && [ -n "$DLINE" ] && [ "$GLINE" -lt "$DLINE" ]; then
  ok "create-vm: il sandbox_guard precede il percorso --destroy"
else
  ko "create-vm: --destroy non e' protetto dal sandbox_guard" \
     "da un sandbox stamperebbe 'VM rimossa' uscendo 0 senza toccare niente"
fi
# setup-ollama.sh ha due rami distruttivi (--rollback, --remove): il guard deve
# venire PRIMA di entrambi, per la stessa ragione di create-vm --destroy.
GL=$(grep -n 'sandbox_guard "scripts/setup-ollama.sh"' scripts/setup-ollama.sh | head -1 | cut -d: -f1)
RL=$(grep -n 'if \[ "\$MODE" = rollback \]' scripts/setup-ollama.sh | head -1 | cut -d: -f1)
ML=$(grep -n 'if \[ "\$MODE" = remove \]' scripts/setup-ollama.sh | head -1 | cut -d: -f1)
if [ -n "$GL" ] && [ -n "$RL" ] && [ -n "$ML" ] && [ "$GL" -lt "$RL" ] && [ "$GL" -lt "$ML" ]; then
  ok "setup-ollama: il sandbox_guard precede --rollback e --remove"
else
  ko "setup-ollama: --rollback/--remove non protetti dal sandbox_guard" "il guard va prima dei rami distruttivi"
fi
# Il comando d'installazione deve arrivare anche in esecuzione REALE: morendo
# sul primo tool mancante non veniva mai stampato, e restava solo "manca X".
PREREQ_OUT=$(env PATH=/nonexistent:/usr/bin:/bin scripts/create-vm.sh 2>&1 || true)
printf '%s' "$PREREQ_OUT" | grep -q "$(pkg_hint_probe)" \
  && ok "create-vm stampa il comando d'installazione anche fuori dal dry-run" \
  || ko "create-vm non stampa il comando d'installazione in esecuzione reale" "die sul primo mancante lo rendeva irraggiungibile"
# firewalld: la zona conta. libvirt mette virbr0 in una zona che RIFIUTA il
# traffico verso l'host tranne dhcp/dns/ssh/tftp/icmp; una rich rule nella zona
# default non si applica, e la porta resta chiusa mentre lo script dice il contrario.
grep -q 'get-zone-of-interface' scripts/setup-ollama.sh \
  && ok "setup-ollama apre la porta nella zona di virbr0, non nella default" \
  || ko "setup-ollama usa la zona firewalld default" "virbr0 sta nella zona 'libvirt': la regola non si applicherebbe"

# create-vm.sh: l'--os-variant deve SEGUIRE l'immagine, non essere un letterale.
# Un nome scritto a mano si disallinea in silenzio quando cambia la stable, e
# nessuno se ne accorge perche' virt-install non protesta per una release vicina.
grep -qE -- '--os-variant[[:space:]]+debian[0-9]' scripts/create-vm.sh \
  && ko "create-vm.sh ha un --os-variant scritto a mano" "va derivato da IMG_URL (pick_os_variant)" \
  || ok "create-vm.sh deriva l'--os-variant dall'immagine"
# E il valore emesso deve combaciare con l'immagine (o ripiegare di una release).
OSV_OUT=$(env -u USER scripts/create-vm.sh --dry-run 2>&1)
IMG_MAJ=$(printf '%s' "$OSV_OUT" | sed -n 's/.*debian-\([0-9]\{1,\}\)-genericcloud.*/\1/p' | head -1)
VAR_MAJ=$(printf '%s' "$OSV_OUT" | sed -n 's/.*--os-variant debian\([0-9]\{1,\}\).*/\1/p' | head -1)
if [ -n "$IMG_MAJ" ] && [ -n "$VAR_MAJ" ]; then
  if [ "$VAR_MAJ" = "$IMG_MAJ" ] || [ "$VAR_MAJ" = "$((IMG_MAJ-1))" ]; then
    ok "os-variant (debian$VAR_MAJ) coerente con l'immagine (debian$IMG_MAJ)"
  else
    ko "os-variant debian$VAR_MAJ contro immagine debian$IMG_MAJ" "disallineati"
  fi
else
  echo -e "  \033[2m–\033[0m os-variant non verificabile (dry-run senza immagine Debian)"
fi

# Ogni hostname usato come api_base nel config del gateway deve corrispondere a
# un servizio del compose (o essere un IP/host esterno). Un `biome-tls` senza
# servizio non risolve: la lane fallisce al primo uso, non al deploy.
if python3 -c 'import yaml' 2>/dev/null; then
  python3 - <<'PYX' && ok "api_base: ogni hostname interno ha un servizio" || ko "api_base punta a un hostname senza servizio"
import re, sys, yaml
cfg = yaml.safe_load(open("services/litellm_config.yaml"))
comp = yaml.safe_load(open("services/docker-compose.yml"))
services = set(comp.get("services") or {})
bad = []
for m in cfg.get("model_list") or []:
    base = (m.get("litellm_params") or {}).get("api_base") or ""
    host = re.sub(r"^https?://", "", base).split("/")[0].split(":")[0]
    if not host or re.match(r"^[\d.]+$", host) or "." in host:
        continue            # IP o FQDN esterno: fuori dal compose
    if host not in services:
        bad.append(f"{m.get('model_name')} -> {host}")
if bad:
    print("   ", "; ".join(bad)); sys.exit(1)
PYX
else
  echo -e "  \033[2m–\033[0m api_base non verificabile (pyyaml assente)"
fi

# ADR-0016: catena `auto` (locale -> Anthropic -> OpenRouter) e prompt caching.
# Tutti errori che non si vedono al deploy: una chiave di cache nel posto
# sbagliato viene ignorata senza un warning, un num_ctx disallineato tronca.
if python3 -c 'import yaml' 2>/dev/null; then
  CTX_SH=$(sed -n 's/^CTX=\([0-9]\{1,\}\)$/\1/p' scripts/setup-ollama.sh | head -1)
  CTX_SH="$CTX_SH" python3 - <<'PYX' && ok "catena auto: locale -> Anthropic -> OpenRouter, cache e contesto coerenti" || ko "catena auto / prompt caching incoerenti (ADR-0016)"
import os, sys, yaml
cfg = yaml.safe_load(open("services/litellm_config.yaml"))
ml = cfg.get("model_list") or []
names = {m.get("model_name") for m in ml}
ls = cfg.get("litellm_settings") or {}
err = []
# 1. cache_control_injection_points fuori da litellm_params = ignorato.
for m in ml:
    if "cache_control_injection_points" in m:
        err.append(f"{m['model_name']}: cache_control_injection_points fuori da litellm_params")
# 2. ogni deployment Claude a pagamento ha i breakpoint di cache.
for m in ml:
    p = m.get("litellm_params") or {}
    if "claude" in str(p.get("model", "")) and p.get("api_key") \
       and not p.get("cache_control_injection_points"):
        err.append(f"{m['model_name']}: Claude senza prompt caching")
# 3. `auto` e' un gruppo vero, e il suo deployment e' locale.
autos = [m for m in ml if m.get("model_name") == "auto"]
if not autos:
    err.append("manca il gruppo 'auto'")
else:
    p = autos[0]["litellm_params"]
    if not str(p.get("model", "")).startswith("ollama"):
        err.append("auto: il primo anello non e' locale")
    ctx = p.get("num_ctx"); mit = (autos[0].get("model_info") or {}).get("max_input_tokens")
    if not (isinstance(ctx, int) and isinstance(mit, int) and mit < ctx):
        err.append(f"auto: serve max_input_tokens < num_ctx (ora {mit} / {ctx})")
    if os.environ.get("CTX_SH") and str(ctx) != os.environ["CTX_SH"]:
        err.append(f"auto: num_ctx {ctx} != OLLAMA_CONTEXT_LENGTH {os.environ['CTX_SH']} in setup-ollama.sh")
# 4. ordine della catena: Anthropic prima di OpenRouter; stessi anelli per i
#    fallback d'errore e per quelli di contesto.
def chain(key):
    for d in ls.get(key) or []:
        if "auto" in d: return d["auto"]
    return None
fb, cw = chain("fallbacks"), chain("context_window_fallbacks")
if not fb: err.append("auto senza fallbacks")
elif fb != cw: err.append("auto: fallbacks e context_window_fallbacks diversi")
else:
    for n in fb:
        if n not in names: err.append(f"auto: fallback '{n}' non e' un model_name")
    prov = [str(next(m for m in ml if m["model_name"] == n)["litellm_params"]["model"]) for n in fb if n in names]
    kinds = ["or" if x.startswith("openrouter/") else "anthropic" for x in prov]
    if kinds != sorted(kinds, key=lambda k: k == "or"):
        err.append(f"auto: ordine errato {fb} (Anthropic prima di OpenRouter)")
if err:
    print("    " + "\n    ".join(err)); sys.exit(1)
PYX
else
  echo -e "  \033[2m–\033[0m catena auto non verificabile (pyyaml assente)"
fi
# ADR-0016: Claude Code Router non e' adottato. Un client che punta a :3456 e'
# un secondo gateway (invariante #1), e quello che importa il login OAuth.
grep -rn ':3456\|:3458' clients/ 2>/dev/null \
  && ko "client verso Claude Code Router (:3456)" "ADR-0016: un solo gateway" \
  || ok "nessun client punta a Claude Code Router"
grep -q '"model": "litellm/auto"' clients/opencode.jsonc \
  && ok "opencode usa la catena auto del gateway" || ko "opencode non usa litellm/auto" "ADR-0016"
# shell-env puo' passare ANTHROPIC_* a un singolo processo (claude-gw), mai esportarle:
# scavalcherebbero l'abbonamento in ogni shell.
grep -qE '^[[:space:]]*export[[:space:]]+ANTHROPIC_' clients/shell-env.sh \
  && ko "shell-env.sh esporta ANTHROPIC_*" "scavalca l'abbonamento (DUAL-AUTH.md)" \
  || ok "shell-env.sh non esporta ANTHROPIC_*"

# Serena (ADR-0006/0007): 'ide-assistant' e' deprecato e Serena lo rimappa in
# silenzio su 'claude-code', il contesto sbagliato per opencode. E la memoria
# va esclusa per INTERO: rename/edit_memory e onboarding sono arrivati dopo.
grep -rn 'ide-assistant' clients/ 2>/dev/null \
  && ko "client con --context ide-assistant" "deprecato: Serena lo mappa su claude-code; usa 'ide'" \
  || ok "Serena: nessun contesto deprecato nei client"
MEMTOOLS_ALL="write_memory read_memory list_memories delete_memory rename_memory edit_memory onboarding"
MISSING_MEM=""
for t in $MEMTOOLS_ALL; do
  grep -qE "^MEMTOOLS=\".*\b$t\b" scripts/stack-selective-install.sh || MISSING_MEM="$MISSING_MEM $t"
done
[ -z "$MISSING_MEM" ] && ok "Serena: l'installer esclude tutti i tool di memoria (ADR-0007)" \
  || ko "Serena: tool di memoria non esclusi dall'installer:$MISSING_MEM" "una memoria per livello"
# serena-agent 1.7.0 esige `language_servers` in project.yml: un file scritto a
# mano senza quel campo fa fallire il caricamento (KeyError). L'installer deve
# farlo generare a Serena, mai scriverlo con un heredoc.
if grep -qE 'cat[[:space:]]*>[[:space:]]*"?(\$\{?SPY\}?|[^ ]*project\.yml)' scripts/stack-selective-install.sh; then
  ko "l'installer scrive project.yml a mano" "Serena 1.7.0: KeyError 'language_servers'; usa 'serena project create'"
else
  ok "l'installer fa generare project.yml a Serena (niente heredoc)"
fi
# .serena/project.yml del repo (ADR-0022): completo e con la memoria esclusa.
if [ "$HAVE_YAML" = 1 ]; then
  MEMTOOLS_ALL="$MEMTOOLS_ALL" python3 - <<'PYX' && ok ".serena/project.yml: language_servers presenti, 7 tool di memoria esclusi" || ko ".serena/project.yml incompleto o memoria non esclusa" "ADR-0007/0022"
import os, sys, yaml
d = yaml.safe_load(open(".serena/project.yml"))
miss = set(os.environ["MEMTOOLS_ALL"].split()) - set(d.get("excluded_tools") or [])
ok = d.get("language_servers") and d.get("project_name") and not miss
if not ok: print("    mancano:", sorted(miss) or "language_servers/project_name")
sys.exit(0 if ok else 1)
PYX
else
  echo -e "  \033[2m–\033[0m .serena/project.yml non verificabile (pyyaml assente)"
fi
# Claude Code nel repo: il tool Read non deve poter aprire .env e chiavi
# (permissions.deny, come in Infra-Iam-PKI). Non ferma `cat` da Bash: e' una cintura.
python3 - <<'PYX' && ok ".claude/settings.json nega la lettura di .env, chiavi e backup" || ko ".claude/settings.json senza deny sui segreti" "ADR-0022"
import json, sys
deny = set(json.load(open(".claude/settings.json")).get("permissions", {}).get("deny", []))
need = {"Read(**/.env)", "Read(**/*.key)", "Read(**/*.pem)", "Read(**/backups/**)", "Read(~/.config/litellm/**)"}
miss = need - deny
if miss: print("    mancano:", sorted(miss))
sys.exit(1 if miss else 0)
PYX

sec "6. Comportamento: LLM locale su un sistema finto (tests/setup-ollama)"
# Install → verifiche → fallimento → rollback automatico, rollback manuale,
# idempotenza, rimozione, decisioni dall'hardware. Stub al posto di systemd,
# ollama, curl: gira ovunque, non tocca l'host.
# SKIP_BEHAVIOR=1 lo salta: lo usa tests/mutation/run.sh per le mutazioni dei
# controlli statici, che non hanno bisogno dei 48 scenari a ogni copia del repo.
if [ "${SKIP_BEHAVIOR:-0}" = 1 ]; then
  echo -e "  \033[2m–\033[0m scenari saltati (SKIP_BEHAVIOR=1)"
elif HOUT=$(tests/setup-ollama/run.sh 2>&1); then
  ok "setup-ollama: $(printf '%s' "$HOUT" | grep -o '✓ [0-9]*' | tail -1 | tr -d '✓ ') scenari verdi (install, rollback, remove, hw)"
else
  ko "setup-ollama: scenari rossi" "$(printf '%s' "$HOUT" | grep '✗' | head -5)"
fi

sec "5. Coerenza documentazione"
for f in $(grep -oE '\(([0-9]{4}-[a-z0-9-]+\.md)\)' docs/adr/README.md | tr -d '()'); do
  [ -f "docs/adr/$f" ] && ok "ADR $f indicizzato ed esistente" || ko "ADR $f mancante"
done
for f in docs/adr/[0-9]*.md; do
  grep -q '^- \*\*Status\*\*' "$f" || ko "$(basename "$f") senza Status"
done
[ -f AGENTS.md ] && ok "AGENTS.md presente (contesto per gli agenti)" || ko "AGENTS.md mancante"
[ -f CLAUDE.md ] && grep -q AGENTS.md CLAUDE.md && ok "CLAUDE.md rimanda ad AGENTS.md (una sola verita')" || ko "CLAUDE.md assente o non allineato"
# ogni script deve essere citato almeno una volta nei doc
for f in scripts/*.sh scripts/*.py; do
  b=$(basename "$f"); n="${b%.*}"
  grep -rq "$n" docs/ README.md AGENTS.md && ok "$n documentato" \
    || ko "$n non citato nella documentazione"
done

echo -e "\n\033[36m━━ Esito ━━\033[0m\n  \033[32m✓ $P\033[0m   \033[31m✗ $F\033[0m"
[ "$F" -gt 0 ] && exit 1
echo -e "  \033[32mTutti i test superati.\033[0m"
