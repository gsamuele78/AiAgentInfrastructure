#!/usr/bin/env bash
# ============================================================
#  audit-host.sh -- fotografia dell'host PRIMA di pulire o migrare.
#  Sola lettura: non ferma, non sposta, non cancella niente.
#
#  Cosa guarda: config dei client AI (opencode, codex, claude, openchamber,
#  litellm, headroom), shell e ambiente, unit systemd (utente e sistema),
#  porte, processi, container, postgres, tool installati, VM libvirt e
#  Vagrant. Le chiavi trovate NON compaiono nel report: solo tipo, impronta
#  (sha256, 8 caratteri) e lunghezza (scripts/lib/redact.py).
#
#    ./audit-host.sh [--dry-run] [--backup] [--out DIR]
#      --backup  copia anche i file trovati (config, rc, unit, XML delle VM)
#                in un archivio 600: e' lui a contenere le chiavi in chiaro.
#
#  Il report e l'archivio restano sull'host, in
#  ${AIAGENT_STATE:-~/.local/state/aiagentinfra}/audit/<data>/ (700).
#  Il report si puo' condividere; l'archivio NO.
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RED="$HERE/lib/redact.py"
DRY=0; BACKUP=0; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --backup) BACKUP=1 ;;
    --out) OUT="${2:?--out DIR}"; shift ;;
    -h|--help) sed -n 2,20p "$0"; exit 0 ;;
    *) echo "opzione sconosciuta: $1" >&2; exit 2 ;;
  esac; shift
done
# shellcheck source=lib/hw-detect.sh
. "$HERE/lib/hw-detect.sh"
# Da un Flatpak/toolbox fotograferebbe il sandbox (unit, porte, VM: tutto
# vuoto o sbagliato) e il report direbbe "host pulito". Meglio fermarsi.
sandbox_guard "scripts/audit-host.sh" "$DRY" || exit 1
TS=$(date +%Y%m%d-%H%M%S)
OUT="${OUT:-${AIAGENT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/aiagentinfra}/audit/$TS}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
# Servizi e processi che interessano: lo stack vecchio e quello nuovo.
PAT='headroom|litellm|ollama|postgres|pgsql|openhands|mem0|opencode|openchamber|serena|vllm|llama|open-?webui|n8n|davmail|libvirt|vagrant|qemu|podman|docker'

if [ "$DRY" = 1 ]; then
  echo "[dry] report in $OUT/report.md (700/600), nessuna modifica all'host"
  echo "[dry] sezioni: host, config client, shell/env, systemd, porte, processi, container, postgres, tool, VM, disco"
  [ "$BACKUP" = 1 ] && echo "[dry] archivio $OUT/backup-$TS.tar.gz (600) con config, rc, unit e XML delle VM"
  command -v python3 >/dev/null || echo "[dry] manca python3: serve per oscurare le chiavi"
  exit 0
fi
command -v python3 >/dev/null || { echo "✗ serve python3 (oscura le chiavi nel report)" >&2; exit 2; }
( umask 077; mkdir -p "$OUT" ) || { echo "✗ non posso creare $OUT" >&2; exit 1; }
REP="$OUT/report.md"; ( umask 077; : > "$REP" )
# I tool interrogati (uv, npm, brew, mise, vagrant) scrivono cache e log in
# $HOME anche solo per elencare: li si manda in una cartella usa e getta.
SCRATCH=$(mktemp -d); trap 'rm -rf "$SCRATCH"' EXIT
export UV_CACHE_DIR="$SCRATCH/uv" npm_config_cache="$SCRATCH/npm" npm_config_update_notifier=false \
       npm_config_logs_max=0 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 \
       MISE_CACHE_DIR="$SCRATCH/mise" VAGRANT_CHECKPOINT_DISABLE=1 PIPX_LOG_DIR="$SCRATCH/pipx"
FILES="$OUT/.files"; : > "$FILES"

w(){ printf '%s\n' "$*" >> "$REP"; }
h(){ w ""; w "## $*"; w ""; echo "  · $*"; }
# blocco: esegue un comando (timeout 15 s), oscura i segreti, lo mette nel report
blk(){ local t=$1; shift
  w "**$t**"; w '```'
  if command -v "$1" >/dev/null 2>&1; then
    timeout 15 "$@" 2>&1 | python3 "$RED" filter | head -200 >> "$REP"
  else echo "($1 non installato)" >> "$REP"; fi
  w '```'; }
have(){ command -v "$1" >/dev/null 2>&1; }
# file da esaminare (e da salvare con --backup): solo file regolari leggibili
add(){ local f; for f in "$@"; do [ -f "$f" ] && [ -r "$f" ] && echo "$f" >> "$FILES"; done; }
st(){ stat -c '%a %s %y' "$1" 2>/dev/null | cut -d. -f1; }

echo "==> audit dell'host -> $REP"
w "# Audit dell'host — $TS"
w ""
w "Sola lettura. Le chiavi sono oscurate: tipo, impronta (sha256, 8 car.) e lunghezza."
w "Stessa impronta = stessa chiave in più posti."

# ------------------------------------------------------------ host
h "1. Host"
blk "os-release" sh -c 'grep -E "^(NAME|VERSION_ID|VARIANT_ID|IMAGE_ID|ID)=" /etc/os-release'
blk "kernel, uptime" sh -c 'uname -r; uptime -p'
if have rpm-ostree; then
  blk "rpm-ostree: pacchetti stratificati (requested)" sh -c \
    "rpm-ostree status --json | python3 -c 'import json,sys;d=json.load(sys.stdin)[\"deployments\"];b=[x for x in d if x.get(\"booted\")][0];print(\"immagine:\",b.get(\"container-image-reference\",\"-\"));print(\"layered:\",\" \".join(b.get(\"requested-packages\",[])) or \"nessuno\");print(\"deployment:\",len(d))'"
fi
( umask 077; "$HERE/detect-hardware.sh" --json > "$OUT/facts.json" 2>/dev/null ) && w "Fatti hw/OS completi: \`facts.json\` (detect-hardware.sh --json)."

# ------------------------------------------------------------ config client
h "2. Config dei client AI"
add "$CFG"/opencode/*.json "$CFG"/opencode/*.jsonc "$HOME"/opencode.json "$HOME"/opencode.jsonc "$HOME"/.opencode.json \
    "$HOME"/.codex/config.toml "$HOME"/.codex/auth.json \
    "$HOME"/.claude/settings.json "$HOME"/.claude/settings.local.json "$HOME"/.claude.json "$HOME"/.mcp.json \
    "$CFG"/openchamber/*.json "$HOME"/litellm_config.yaml "$HOME"/litellm_config.yaml.* "$CFG"/litellm/* \
    "$CFG"/headroom/* "$HOME"/.headroom/*.json "$HOME"/.headroom/*.toml "$HOME"/.headroom/*.yaml "$HOME"/.mem0/*.json
# opencode.jsonc e .env sparsi nei progetti (profondita' 4, niente node_modules)
find "$HOME" -maxdepth 4 \( -name node_modules -o -name .git -o -name .cache -o -name .local -o -name .var \) -prune -o \
  -type f \( -name 'opencode.json' -o -name 'opencode.jsonc' -o -name '*litellm*.y*ml' -o -name '.env' \) -print 2>/dev/null \
  | head -50 >> "$FILES"
sort -u -o "$FILES" "$FILES"
w "| file | permessi | byte | modificato | = repo |"
w "|---|---|---|---|---|"
while IFS= read -r f; do
  same="–"
  case "$f" in
    "$CFG/opencode/opencode.jsonc") cmp -s "$f" "$REPO/clients/opencode.jsonc" && same="sì" || same="no" ;;
    "$HOME/.codex/config.toml") cmp -s "$f" "$REPO/clients/codex-config.toml" && same="sì" || same="no" ;;
    "$HOME/.claude/settings.json") cmp -s "$f" "$REPO/clients/claude-settings.json" && same="sì" || same="no" ;;
  esac
  read -r mode size mt <<<"$(st "$f")"
  flag=""; [ $((8#$mode & 8#077)) -ne 0 ] && flag=" ⚠️"
  w "| \`$f\` | $mode$flag | $size | $mt | $same |"
done < "$FILES"
w ""; w "⚠️ = leggibile da gruppo o altri: se contiene chiavi, vanno considerate esposte."
w ""; w "Le chiavi contenute in questi file sono nella sezione 10."

# ------------------------------------------------------------ shell / env
h "3. Shell e ambiente"
RC=""
for f in "$HOME"/.bashrc "$HOME"/.bash_profile "$HOME"/.profile "$HOME"/.zshrc "$HOME"/.zprofile \
         "$HOME"/.bashrc.d/* "$CFG"/fish/config.fish "$CFG"/fish/conf.d/*.fish \
         "$CFG"/environment.d/*.conf "$HOME"/.pam_environment; do
  [ -f "$f" ] && [ -r "$f" ] && RC="$RC$f"$'\n'
done
printf '%s' "$RC" >> "$FILES"
w "Righe rilevanti (export, source, URL, proxy) dei file di shell:"; w '```'
printf '%s' "$RC" | while IFS= read -r f; do
  grep -nHiE "export|^[A-Z_]+=|source|\. |set -x|KEY|TOKEN|SECRET|BASE_URL|PROXY|HEADROOM|LITELLM|OPENAI|ANTHROPIC|OPENROUTER|OLLAMA|alias (claude|codex|opencode)" "$f" 2>/dev/null \
    | grep -vE '^\S+:[0-9]+:\s*#' | python3 "$RED" filter >> "$REP"
done
w '```'
w "Variabili d'ambiente rilevanti di QUESTA shell (valori segreti oscurati):"; w '```'
env | grep -E '^[A-Z_]*(KEY|TOKEN|SECRET|BASE_URL|_URL|PROXY|HEADROOM|LITELLM|OPENAI|ANTHROPIC|OPENROUTER|OLLAMA|MODEL)[A-Z_]*=' \
  | sort | python3 "$RED" filter >> "$REP"
w '```'
have systemctl && blk "ambiente del manager systemd utente" sh -c "systemctl --user show-environment | grep -vE '^(PATH|XDG_DATA_DIRS|DBUS|DISPLAY|WAYLAND|XAUTH)'"

# ------------------------------------------------------------ systemd
h "4. Unit systemd"
if have systemctl; then
  blk "unit utente pertinenti" sh -c "systemctl --user list-unit-files --no-pager --no-legend | grep -iE '$PAT'"
  blk "unit utente attive/fallite pertinenti" sh -c "systemctl --user list-units --all --no-pager --no-legend | grep -iE '$PAT'"
  blk "unit di sistema pertinenti" sh -c "systemctl list-unit-files --no-pager --no-legend | grep -iE '$PAT'"
  blk "linger (servizi utente senza login)" loginctl show-user "$(id -un)" -p Linger
  for u in $(systemctl --user list-unit-files --no-pager --no-legend 2>/dev/null | awk '{print $1}' | grep -iE "$PAT"); do
    blk "systemctl --user cat $u ($(systemctl --user is-enabled "$u" 2>/dev/null)/$(systemctl --user is-active "$u" 2>/dev/null))" systemctl --user cat "$u"
  done
  for u in $(systemctl list-unit-files --no-pager --no-legend 2>/dev/null | awk '{print $1}' | grep -iE "$PAT" | grep -vE '^(libvirt|virt|podman|docker)'); do
    blk "systemctl cat $u ($(systemctl is-enabled "$u" 2>/dev/null)/$(systemctl is-active "$u" 2>/dev/null))" systemctl cat "$u"
  done
fi
for f in "$CFG"/systemd/user/*.service "$CFG"/systemd/user/*.d/*.conf "$CFG"/containers/systemd/*; do
  [ -f "$f" ] && echo "$f" >> "$FILES"
done

# ------------------------------------------------------------ porte e processi
h "5. Porte in ascolto e processi"
blk "porte TCP in ascolto" sh -c "ss -ltnpH 2>/dev/null | awk '{print \$4, \$6}' | sort -u"
w "Porte note: 3000 opencode web · 4000 LiteLLM · 5432 postgres · 8787 headroom · 11434 Ollama · 1025/1143 DavMail."
blk "processi pertinenti (argomenti oscurati)" sh -c "ps -eo user,pid,etime,rss,args --no-headers | grep -iE '$PAT' | grep -v -e grep -e audit-host"

# ------------------------------------------------------------ container e postgres
h "6. Container e postgres"
blk "podman (utente): container" podman ps -a --format '{{.Names}}  {{.Image}}  {{.Status}}  {{.Ports}}'
blk "podman (utente): volumi" podman volume ls
blk "podman (utente): immagini pertinenti" sh -c "podman images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep -iE '$PAT|pg|litellm|headroom' || true"
blk "docker: container" docker ps -a --format '{{.Names}}  {{.Image}}  {{.Status}}'
blk "distrobox" distrobox list
blk "toolbox" toolbox list
blk "postgres nativo" sh -c 'rpm -q postgresql-server postgresql 2>/dev/null || dpkg -l "postgresql*" 2>/dev/null | grep ^ii; ls -ld /var/lib/pgsql /var/lib/postgresql 2>/dev/null; true'

# ------------------------------------------------------------ tool
h "7. Tool installati"
w "| tool | percorso | versione |"; w "|---|---|---|"
for t in headroom litellm opencode openchamber claude codex serena uv uvx pipx mise brew node npm python3 ollama podman docker vagrant virsh virt-manager distrobox; do
  p=$(command -v "$t" 2>/dev/null) || { w "| $t | – | – |"; continue; }
  v=$(timeout 5 "$t" --version 2>/dev/null </dev/null | head -1 | python3 "$RED" filter | tr -d '|')
  w "| $t | \`$p\` | ${v:-?} |"
done
blk "uv tool list" uv tool list
blk "pipx list" pipx list --short
blk "npm -g" npm ls -g --depth=0
blk "mise ls" mise ls
blk "brew (pertinenti)" sh -c "brew list --versions 2>/dev/null | grep -iE '$PAT|node|python|uv' || true"
blk "flatpak (pertinenti)" sh -c "flatpak list --app --columns=application,version 2>/dev/null | grep -iE 'virt|boxes|vagrant|code|llm|ollama|alpaca' || true"

# ------------------------------------------------------------ VM
h "8. Macchine virtuali"
VMDIR="$OUT/vm-xml"
if have virsh; then
  for uri in qemu:///system qemu:///session; do
    blk "virsh $uri: domini" virsh -r -c "$uri" list --all
    for d in $(timeout 15 virsh -r -c "$uri" list --all --name 2>/dev/null); do
      blk "[$uri] $d: info" virsh -r -c "$uri" dominfo "$d"
      blk "[$uri] $d: dischi" sh -c "virsh -r -c '$uri' domblklist '$d' --details | awk 'NR>2 && \$4!=\"-\" && \$4!=\"\" {print \$4}' | while read -r p; do printf '%s  ' \"\$p\"; du -h --apparent-size \"\$p\" 2>/dev/null | cut -f1 || echo '(non leggibile)'; done"
      blk "[$uri] $d: snapshot" virsh -r -c "$uri" snapshot-list "$d"
      blk "[$uri] $d: indirizzi" virsh -r -c "$uri" domifaddr "$d"
      ( umask 077; mkdir -p "$VMDIR" ) && timeout 15 virsh -r -c "$uri" dumpxml "$d" > "$VMDIR/${uri##*/}-$d.xml" 2>/dev/null
    done
    blk "virsh $uri: reti" virsh -r -c "$uri" net-list --all
    blk "virsh $uri: pool" virsh -r -c "$uri" pool-list --all --details
  done
else w "virsh non installato."; fi
blk "immagini libvirt" sh -c 'ls -la /var/lib/libvirt/images "$HOME/.local/share/libvirt/images" 2>&1'
blk "vagrant: ambienti noti (cache, non verificata)" vagrant global-status
blk "vagrant: box" vagrant box list
blk "vagrant: plugin" vagrant plugin list
blk "Vagrantfile nella home (profondità 4)" sh -c "find '$HOME' -maxdepth 4 \( -name .cache -o -name .local -o -name node_modules \) -prune -o -name Vagrantfile -print 2>/dev/null | head -20"
w "Vagrant: upstream è BUSL dal 2.3.8 (ADR-0022, scartato). Il pacchetto Debian (2.3.7+git, \"2.3.8.dev\") è l'ultimo MPL ma è congelato: da dismettere, non da migrare."

# ------------------------------------------------------------ disco
h "9. Spazio occupato"
blk "du" sh -c "du -sh '$HOME/.vagrant.d' '$HOME/.local/share/containers' '$HOME/.local/share/libvirt' '$HOME/.cache/uv' '$HOME/.cache/pip' '$HOME/.npm' '$HOME/.local/share/mise' '$HOME/.ollama' /var/lib/libvirt/images 2>/dev/null"

# ------------------------------------------------------------ segreti (dopo, per avere tutti i file)
sort -u -o "$FILES" "$FILES"
mapfile -t SCANNED < "$FILES"
h "10. Segreti trovati (tutti i file esaminati)"
SCAN=$(python3 "$RED" scan "${SCANNED[@]}" 2>&1); w "$SCAN"
N=$(grep -cE '^\| `.*` \| [0-9]+ \| ' <<<"$SCAN"); U=$(grep -oE '\| `[0-9a-f]{8}` \|' <<<"$SCAN" | sort -u | wc -l)

# ------------------------------------------------------------ backup
if [ "$BACKUP" = 1 ]; then
  ARC="$OUT/backup-$TS.tar.gz"
  EXTRA=(); [ -d "$VMDIR" ] && EXTRA=(-C "$OUT" vm-xml)
  ( umask 077; tar -czf "$ARC" --ignore-failed-read -T "$FILES" "${EXTRA[@]}" 2>/dev/null )
  chmod 600 "$ARC"
  w ""; w "## Backup"; w ""
  w "Archivio \`$ARC\` (600, $(du -h "$ARC" | cut -f1)), sha256 \`$(sha256sum "$ARC" | cut -c1-16)…\`."
  w "Contiene le chiavi IN CHIARO: cifralo (\`gpg -c\`) o spostalo nel password manager, poi cancella l'originale."
fi
rm -f "$FILES"
chmod 600 "$REP"
echo ""
echo "Fatto. Report: $REP"
echo "  segreti nei file: $N occorrenze, $U impronte distinte (stessa impronta = stessa chiave)"
echo "  valori oscurati nel report (anche env, processi, unit): $(grep -o '«REDATTO' "$REP" | wc -l)"
[ "$BACKUP" = 1 ] && echo "  backup: $ARC  (600, contiene le chiavi in chiaro: cifralo con gpg -c)"
echo "  Il report non contiene chiavi: si può incollare nel thread. Rileggilo comunque prima (host, percorsi)."
