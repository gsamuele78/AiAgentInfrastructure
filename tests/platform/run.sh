#!/usr/bin/env bash
# ============================================================
#  tests/platform/run.sh -- TC-13: dai fatti hw/OS alle scelte, su fixture.
#  Ogni scenario costruisce un sistema FINTO (os-release, bus PCI, batteria,
#  /proc, marcatori di sandbox, stub di ujust/rpm-ostree/dpkg/rpm/nvidia-smi)
#  e verifica:
#    - detect-hardware.sh --json: i fatti
#    - platform_decide: la scelta per strato (scripts/lib/platform.sh)
#    - pkg_add / svc_render: nessuna azione S1 automatica, idempotenza, journal
#  Non tocca l'host, gira anche dentro un container di CI.
#  Cosa NON prova: un rpm-ostree vero, un driver vero, un reboot. Quelli
#  restano prove manuali registrate (ADR-0018, conseguenze negative).
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FIX="$HERE/fixtures"
P=0; F=0
ok(){ echo -e "  \033[32m✓\033[0m $1"; P=$((P+1)); }
ko(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo "$2" | tail -12 | sed 's/^/      /'; F=$((F+1)); }
sec(){ echo -e "\n\033[36m── $1\033[0m"; }

# mk <os-release> [opzioni...] -- sistema finto in $R
#   atomic ublue laptop  gpu=<driver|none>  smi=<vram_mb>  sandbox=<flatpak|toolbox>
#   pkg=<nome> (installato)
mk(){
  R=$(mktemp -d); ROOTS="$ROOTS $R"
  mkdir -p "$R/etc" "$R/bin" "$R/proc" "$R/sys/bus/pci/devices" "$R/sys/class/power_supply" "$R/home" "$R/run"
  cp "$FIX/os-release.$1" "$R/etc/os-release"; shift
  printf 'processor\t: 0\nmodel name\t: Fake CPU\nflags\t\t: vmx\nprocessor\t: 1\n' > "$R/proc/cpuinfo"
  printf 'MemTotal:       32000000 kB\n' > "$R/proc/meminfo"
  : > "$R/pkgs"
  # gestori di pacchetti finti: lo stato e' $R/pkgs, una riga per pacchetto
  printf '#!/bin/sh\nfor a; do :; done; grep -qx "$a" "%s/pkgs" && printf "install ok installed"\n' "$R" > "$R/bin/dpkg-query"
  printf '#!/bin/sh\ngrep -qx "$2" "%s/pkgs"\n' "$R" > "$R/bin/rpm"
  # qualunque installazione eseguita davvero lascia una traccia qui
  for c in apt dnf rpm-ostree-run; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/executed"\n' "$c" "$R" > "$R/bin/$c"
  done
  printf '#!/bin/sh\nexec "$@"\n' > "$R/bin/sudo"
  for o in "$@"; do
    case "$o" in
      atomic) : > "$R/run/ostree-booted"
              printf '#!/bin/sh\necho "rpm-ostree $*" >> "%s/executed"\n' "$R" > "$R/bin/rpm-ostree" ;;
      ublue)  printf '#!/bin/sh\nexit 0\n' > "$R/bin/ujust" ;;
      laptop) mkdir -p "$R/sys/class/power_supply/BAT0" ;;
      gpu=*)  local d="$R/sys/bus/pci/devices/0000:01:00.0" drv=${o#gpu=}
              mkdir -p "$d" "$R/sys/bus/pci/drivers"
              echo 0x10de > "$d/vendor"; echo 0x030200 > "$d/class"; echo 0x25b8 > "$d/device"
              if [ "$drv" != none ]; then mkdir -p "$R/sys/bus/pci/drivers/$drv"; ln -s "../../drivers/$drv" "$d/driver"; fi ;;
      smi=*)  printf '#!/bin/sh\ncase "$*" in *memory.total*) echo %s ;; *) echo "GPU 0: Fake" ;; esac\n' "${o#smi=}" > "$R/bin/nvidia-smi" ;;
      sandbox=flatpak) : > "$R/.flatpak-info" ;;
      sandbox=toolbox) printf 'name="toolbox"\n' > "$R/run/.containerenv" ;;
      pkg=*)  echo "${o#pkg=}" >> "$R/pkgs" ;;
    esac
  done
  chmod +x "$R/bin/"*
}
# env pulito: niente PATH dell'host davanti agli stub, nessun marcatore reale
fenv(){ env -i PATH="$R/bin:/usr/bin:/bin" HOME="$R/home" SYSFS_ROOT="$R/sys" \
  OS_RELEASE_FILE="$R/etc/os-release" OSTREE_MARKER="$R/run/ostree-booted" PROC_ROOT="$R/proc" \
  SANDBOX_ROOT="$R" AIAGENT_STATE="$R/state" SUDO="" HW_DISK_GB=100 POOL_DIR="$R" ${XENV:-} "$@"; }
lib(){ fenv bash -c ". '$REPO/scripts/lib/hw-detect.sh'; . '$REPO/scripts/lib/journal.sh'; . '$REPO/scripts/lib/platform.sh'; $1" 2>&1; }
facts(){ JSON=$(fenv bash "$REPO/scripts/detect-hardware.sh" --json 2>/dev/null); }
jq_(){ printf '%s' "$JSON" | python3 -c "import json,sys; f=json.load(sys.stdin); print(json.dumps($1))" 2>/dev/null; }
# decide <cosa> <azione attesa> [regex sul comando/nota]
decide(){
  local out; out=$(lib "platform_decide $1")
  local a=${out%%|*}
  if [ "$a" = "$2" ] && { [ -z "${3:-}" ] || grep -qE -- "$3" <<<"$out"; }; then ok "$SCEN · $1 → $2${3:+ ($3)}"
  else ko "$SCEN · $1: atteso $2${3:+ /$3/}, ottenuto: $out"; fi
}
fact(){ local v; v=$(jq_ "$1"); [ "$v" = "$2" ] && ok "$SCEN · fatto $1 = $2" || ko "$SCEN · fatto $1: atteso $2, ottenuto ${v:-<json illeggibile>}" "$JSON"; }
ROOTS=""; trap 'rm -rf $ROOTS' EXIT

sec "1. Debian 13, desktop senza GPU"
SCEN=debian13; mk debian13
facts
fact 'f["schema"]' 1
fact 'f["os_family"]' '"debian"'
fact 'f["atomic"]' false
fact 'f["sandbox"]' null
fact 'f["gpus"]' '[]'
fact 'f["ram_gb"]' 30
fact 'f["kvm"]' true
decide "pkg socat" recommend "apt install -y socat"
XENV="ALLOW_S1=1" decide "pkg socat" apply "apt install -y socat"
decide gpu-driver skip
decide svc apply
decide user-tools apply
decide keep-alive skip

sec "2. Debian 13, laptop con RTX A2000 senza driver (PRD)"
SCEN=debian13-laptop; mk debian13 laptop gpu=none
facts
fact 'f["chassis"]' '"laptop"'
fact 'len(f["gpus"])' 1
fact 'f["gpus"][0]["driver"]' null
fact 'f["vram_mb"]' null
decide gpu-driver recommend "nvidia-driver"
XENV="ALLOW_S1=1" decide gpu-driver recommend "reboot"
decide keep-alive apply "OLLAMA_KEEP_ALIVE=2m"

sec "3. Debian 13, laptop con driver nvidia e 4 GB di VRAM"
SCEN=debian13-nvidia; mk debian13 laptop gpu=nvidia smi=4096
facts
fact 'f["gpus"][0]["driver"]' '"nvidia"'
fact 'f["vram_mb"]' 4096
fact 'f["llm_verdict"]' '"gpu-offload"'
decide gpu-driver skip "gia' legato"

sec "4. Bazzite (uBlue, atomico), GPU su nouveau"
SCEN=bazzite; mk bazzite atomic ublue gpu=nouveau
facts
fact 'f["os_family"]' '"ostree"'
fact 'f["atomic"]' true
fact 'f["ublue"]' true
fact 'f["os_id"]' '"bazzite"'
decide "pkg socat" recommend "rpm-ostree install socat"
XENV="ALLOW_S1=1" decide "pkg socat" recommend "mai automatico"
decide gpu-driver recommend "bazzite-nvidia"
decide svc apply
decide user-tools apply

sec "5. Bazzite -nvidia: driver nell'immagine"
SCEN=bazzite-nvidia; mk bazzite-nvidia atomic ublue gpu=nvidia smi=8192
facts
fact 'f["os_variant_id"]' '"bazzite-nvidia"'
fact 'f["vram_mb"]' 8192
decide gpu-driver skip

sec "6. Terminale Flatpak su Bazzite"
SCEN=flatpak; mk bazzite atomic ublue gpu=nouveau sandbox=flatpak
facts
fact 'f["sandbox"]' '"flatpak"'
decide "pkg socat" stop "flatpak-spawn --host"
decide gpu-driver stop
decide svc stop
decide user-tools apply "sandbox flatpak"

sec "7. Toolbox/distrobox su Fedora"
SCEN=toolbox; mk fedora sandbox=toolbox
facts
fact 'f["sandbox"]' '"toolbox"'
decide svc stop
decide "pkg socat" stop "distrobox-host-exec"

sec "8. Fedora Workstation (non atomico) e Silverblue (atomico, non uBlue)"
SCEN=fedora; mk fedora gpu=nouveau
facts; fact 'f["os_family"]' '"fedora"'
decide "pkg socat" recommend "dnf install -y socat"
decide gpu-driver recommend "akmod-nvidia"
SCEN=silverblue; mk silverblue atomic gpu=nouveau
facts; fact 'f["os_family"]' '"ostree"'; fact 'f["ublue"]' false
decide gpu-driver recommend "rpm-ostree install akmod-nvidia"

sec "9. GPU in passthrough VFIO, pacchetto gia' presente"
SCEN=vfio; mk debian13 gpu=vfio-pci pkg=socat
decide gpu-driver skip "VFIO"
decide "pkg socat" skip "gia' installato"

sec "10. Nessuna azione S1 automatica (pkg_add)"
SCEN=bazzite; mk bazzite atomic ublue
XENV="ALLOW_S1=1"; OUT=$(lib 'journal_begin plat; pkg_add socat; echo "rc=$?"'); XENV=""
grep -q 'rc=3' <<<"$OUT" && [ ! -e "$R/executed" ] \
  && ok "bazzite + ALLOW_S1=1: pkg_add stampa il comando, non lo esegue (rc 3)" \
  || ko "bazzite: pkg_add ha eseguito qualcosa o rc sbagliato" "$OUT
$(cat "$R/executed" 2>/dev/null)"
SCEN=debian13; mk debian13
OUT=$(lib 'pkg_add socat; echo "rc=$?"')
grep -q 'rc=3' <<<"$OUT" && [ ! -e "$R/executed" ] \
  && ok "debian senza ALLOW_S1: solo raccomandazione" || ko "debian: S1 eseguito senza flag" "$OUT"
XENV="ALLOW_S1=1"; OUT=$(lib 'pkg_add socat; echo "rc=$?"'); XENV=""
grep -q 'rc=1' <<<"$OUT" && [ ! -e "$R/executed" ] \
  && ok "debian + ALLOW_S1=1 senza journal: rifiuta prima di installare" || ko "pkg_add installa senza journal" "$OUT"
XENV="ALLOW_S1=1"; OUT=$(lib 'journal_begin plat; pkg_add socat; echo "rc=$?"; cat "$JRUN/actions.log"'); XENV=""
grep -q 'rc=0' <<<"$OUT" && grep -q 'apt install -y socat' "$R/executed" 2>/dev/null && grep -q 'apt remove -y socat' <<<"$OUT" \
  && ok "debian + ALLOW_S1=1: installa e registra come annullarlo" || ko "debian + ALLOW_S1=1: install o journal mancanti" "$OUT"

sec "11. svc_render: scrive solo se cambia, annullabile (TC-10/TC-11 per S2)"
SCEN=svc; mk debian13
printf '[Service]\nEnvironment=A=1\n' > "$R/unit.v1"; printf '[Service]\nEnvironment=A=2\n' > "$R/unit.v2"
DST="$R/etc/systemd/system/x.service"
OUT=$(lib "journal_begin plat; svc_render '$R/unit.v1' '$DST'; echo rc=\$?; svc_render '$R/unit.v1' '$DST'; echo rc=\$?")
grep -q 'rc=10' <<<"$OUT" && grep -q 'invariato' <<<"$OUT" && [ "$(grep -c rc=10 <<<"$OUT")" = 1 ] \
  && ok "primo run scrive, secondo identico non tocca niente" || ko "svc_render non idempotente" "$OUT"
OUT=$(lib "journal_begin plat; svc_render '$R/unit.v2' '$DST'; journal_rollback \"\$JRUN\"")
cmp -s "$DST" "$R/unit.v1" && ! ls "$R"/etc/systemd/system/*.bak* >/dev/null 2>&1 \
  && ok "modifica annullata dal journal, nessun .bak" || ko "rollback di svc_render fallito" "$OUT"
SCEN=svc-flatpak; mk debian13 sandbox=flatpak
OUT=$(lib "svc_render '$FIX/os-release.debian13' '$R/etc/x'; echo rc=\$?")
grep -q 'rc=2' <<<"$OUT" && [ ! -e "$R/etc/x" ] && ok "da un sandbox svc_render non scrive (rc 2)" || ko "svc_render ha scritto da un sandbox" "$OUT"

sec "12. tool_pin legge stack/ (un solo posto, ADR-0020)"
v=$(lib 'tool_pin serena-agent'); want=$(sed -n 's/^serena-agent==//p' "$REPO/stack/requirements-tools.txt")
[ -n "$v" ] && [ "$v" = "$want" ] && ok "tool_pin serena-agent = $v" || ko "tool_pin serena-agent: '$v' != '$want'"
v=$(lib 'tool_pin OLLAMA_VERSION'); [ -n "$v" ] && ok "tool_pin OLLAMA_VERSION = $v" || ko "tool_pin OLLAMA_VERSION vuoto"
lib 'tool_pin non-esiste' >/dev/null && ko "tool_pin inventa una versione" || ok "tool_pin su un componente ignoto: errore, nessuna versione"

echo -e "\n  piattaforma: \033[32m✓ $P\033[0m  \033[31m✗ $F\033[0m"
[ "$F" = 0 ]
