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
DRYRUN_SCRIPTS=""
for f in scripts/*.sh; do
  b=$(basename "$f")
  case " $READONLY " in *" $b "*)
    grep -qE 'sudo (rm|systemctl (stop|disable)|mv)' "$f" \
      && ko "$b dichiarato read-only ma modifica il sistema" || ok "$b è read-only"
    continue;;
  esac
  if grep -q -- '--dry-run' "$f"; then
    ok "$b espone --dry-run"; DRYRUN_SCRIPTS="$DRYRUN_SCRIPTS $b"
  else
    ko "$b senza --dry-run" "gli script che modificano il sistema devono poterlo simulare"
  fi
done

sec "2b. TC-08: i dry-run completano anche su una macchina vuota"
# Cercare la stringa '--dry-run' col grep non dimostra nulla: il dry-run va
# ESEGUITO. È così che si scopre che create-vm.sh moriva su $USER non impostato.
for b in $DRYRUN_SCRIPTS; do
  if out=$(env -u USER "scripts/$b" --dry-run 2>&1); then ok "$b --dry-run esce 0"
  else ko "$b --dry-run fallisce (exit $?)" "$(echo "$out" | tail -3)"; fi
done

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
    # --env-file: NON si scrive un .env dentro il repo. Questo script dichiara
    # di non toccare nulla e deve essere vero anche nel ramo di fallback.
    ( cd "$d" && BIND_IP=127.0.0.1 docker compose --env-file .env.example config >/dev/null 2>&1 ) \
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
