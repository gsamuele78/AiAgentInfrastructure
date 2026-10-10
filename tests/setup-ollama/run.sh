#!/usr/bin/env bash
# ============================================================
#  tests/setup-ollama/run.sh -- ciclo completo di setup-ollama.sh su un
#  sistema FINTO: install → verifiche → fallimento → rollback automatico,
#  rollback manuale, idempotenza, rimozione, decisioni dall'hardware.
#
#  I comandi di sistema (systemctl, ss, ip, ollama, curl, ufw, ...) sono stub
#  in stubs/ che tengono lo stato in $OLLAMA_ROOT/.fake; i percorsi di sistema
#  stanno sotto $OLLAMA_ROOT. Non tocca l'host, non scarica niente: gira in CI.
#  Cosa NON prova: l'installer vero di ollama.com, una GPU vera, systemd vero.
#  Quelli li prova il primo deploy (docs/DEPLOY-RUNBOOK.md, passo 10).
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/scripts/setup-ollama.sh"
STUBS="$HERE/stubs"
P=0; F=0
ok(){ echo -e "  \033[32m✓\033[0m $1"; P=$((P+1)); }
ko(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo "$2" | tail -15 | sed 's/^/      /'; F=$((F+1)); }
sec(){ echo -e "\n\033[36m── $1\033[0m"; }

new_root(){
  R=$(mktemp -d); mkdir -p "$R/home" "$R/sys/bus/pci/devices"
  export OLLAMA_ROOT="$R"
}
# so: esegue setup-ollama.sh nel sistema finto. Profilo hw di default = laptop
# del PRD (RTX A2000 4 GB, 31 GB RAM). Uscita in $RC, output in $OUT.
so(){
  OUT=$(env -i PATH="$STUBS:${XPATH:+$XPATH:}$R/usr/local/bin:/usr/bin:/bin" HOME="$R/home" \
    OLLAMA_ROOT="$R" AIAGENT_STATE="$R/state" SUDO="" ALLOW_IN_SANDBOX=1 \
    OLLAMA_INSTALL_CMD="$STUBS/fake-install" FAKE_STUBS="$STUBS" \
    SYSFS_ROOT="$R/sys" OSTREE_MARKER="$R/ostree-booted" OS_RELEASE_FILE=/dev/null \
    HW_VRAM_MB="${HW_VRAM_MB:-4096}" HW_RAM_GB="${HW_RAM_GB:-31}" HW_DISK_GB="${HW_DISK_GB:-120}" \
    ${XENV:-} bash "$SCRIPT" "$@" 2>&1 </dev/null); RC=$?
}
models(){ tr '\n' ' ' < "$R/.fake/models" 2>/dev/null; }
exists(){ [ -e "$R$1" ]; }
runs(){ find "$R/state/runs" -maxdepth 1 -name 'ollama-2*' -type d 2>/dev/null | wc -l; }
expect(){ # expect <descrizione> <condizione bash>
  if eval "$2"; then ok "$1"; else ko "$1" "rc=$RC
$OUT"; fi
}

sec "1. Installazione da zero, laptop del PRD (4 GB VRAM, 31 GB RAM)"
new_root; so
expect "esce 0" '[ "$RC" = 0 ]'
expect "piano gpu-offload con 3b + 7b" 'grep -q "verdetto: gpu-offload" <<<"$OUT"'
expect "modelli scaricati: 3b e 7b" '[ "$(models)" = "qwen2.5-coder:3b qwen2.5-coder:7b " ]'
expect "override con bind su virbr0" 'grep -q "OLLAMA_HOST=192.168.122.1:11434" "$R/etc/systemd/system/ollama.service.d/override.conf"'
expect "ascolta solo su 192.168.122.1:11434" '[ "$(cat "$R/.fake/listen")" = "192.168.122.1:11434" ]'
expect "CLI usato con OLLAMA_HOST giusto (pull riuscito dopo il bind)" 'grep -q "scaricato" <<<"$OUT"'
expect "registro del run creato" '[ "$(runs)" = 1 ] && [ -s "$R/state/runs/ollama-latest/actions.log" ]'
expect "prova reale: il modello risponde" 'grep -q "risponde (20.0 token/s)" <<<"$OUT"'
expect "lane auto coerente col gateway" 'grep -q "lane auto → qwen2.5-coder:7b: disponibile" <<<"$OUT"'
# shellcheck disable=SC2034  # usato dentro le condizioni di expect (eval)
FIRST=$(readlink "$R/state/runs/ollama-latest")

sec "2. Secondo run identico (TC-10: idempotenza)"
sleep 1; so
expect "esce 0" '[ "$RC" = 0 ]'
expect "nessuna modifica dichiarata" 'grep -q "nessuna modifica" <<<"$OUT"'
expect "nessun nuovo registro, latest invariato" '[ "$(runs)" = 1 ] && [ "$(readlink "$R/state/runs/ollama-latest")" = "$FIRST" ]'

sec "3. Rollback manuale del run (TC-11)"
so --rollback --yes
expect "esce 0" '[ "$RC" = 0 ]'
expect "binario rimosso (installato da quel run)" '! exists /usr/local/bin/ollama'
expect "unit, override e modelli rimossi" '! exists /etc/systemd/system/ollama.service && ! exists /etc/systemd/system/ollama.service.d && ! exists /usr/share/ollama'
expect "run marcato come annullato" '[ -f "$FIRST/ROLLED_BACK" ]'
so --rollback --yes
expect "secondo rollback: niente da fare, esce 0" '[ "$RC" = 0 ] && grep -q "gia. annullato" <<<"$OUT"'

sec "4. Ollama ascolta su 0.0.0.0 → rollback automatico (invariante #3)"
new_root; XENV="FAKE_LISTEN=0.0.0.0:11434" so; XENV=""
expect "esce 1" '[ "$RC" = 1 ]'
expect "errore specifico dell'invariante, non quello generico" 'grep -q "esposto alla LAN" <<<"$OUT"'
expect "rollback automatico eseguito" 'grep -q "Rollback automatico" <<<"$OUT"'
expect "niente resta installato" '! exists /usr/local/bin/ollama && ! exists /etc/systemd/system/ollama.service.d/override.conf'

sec "5. Download del 7b fallito → rollback automatico"
new_root; XENV="FAKE_PULL_FAIL=qwen2.5-coder:7b" so; XENV=""
expect "esce 1" '[ "$RC" = 1 ] && grep -q "download di qwen2.5-coder:7b fallito" <<<"$OUT"'
expect "anche il 3b gia scaricato viene tolto, binario rimosso" '! exists /usr/local/bin/ollama && ! exists /usr/share/ollama'

sec "6. Il modello non risponde a una richiesta reale → rollback automatico"
new_root; XENV="FAKE_GEN_EMPTY=1" so; XENV=""
expect "esce 1, rollback" '[ "$RC" = 1 ] && grep -q "non risponde a una richiesta reale" <<<"$OUT" && ! exists /usr/local/bin/ollama'

sec "7. KEEP_ON_FAIL=1: lo stato resta, poi --rollback lo pulisce"
new_root; XENV="FAKE_GEN_EMPTY=1 KEEP_ON_FAIL=1" so; XENV=""
expect "esce 1 e lascia lo stato" '[ "$RC" = 1 ] && exists /usr/local/bin/ollama && grep -q "KEEP_ON_FAIL=1" <<<"$OUT"'
so --rollback --yes
expect "il rollback successivo pulisce" '[ "$RC" = 0 ] && ! exists /usr/local/bin/ollama'

sec "8. Ollama gia' presente con un modello suo: il rollback non lo tocca"
new_root
env OLLAMA_ROOT="$R" bash "$STUBS/fake-install"
echo "llama3.2:1b" > "$R/.fake/models"
so
expect "install saltata, esce 0" '[ "$RC" = 0 ] && grep -q "gia. installato" <<<"$OUT"'
so --rollback --yes
expect "binario preesistente conservato" 'exists /usr/local/bin/ollama'
expect "modello preesistente conservato, quelli del run tolti" '[ "$(models)" = "llama3.2:1b " ]'
expect "override del run rimosso" '! exists /etc/systemd/system/ollama.service.d/override.conf'

sec "9. --remove: disinstalla tutto e lo verifica"
new_root; so
so --remove --yes
expect "esce 0 e dichiara nessuna traccia" '[ "$RC" = 0 ] && grep -q "nessuna traccia" <<<"$OUT"'
expect "binario, lib, unit, modelli spariti" '! exists /usr/local/bin/ollama && ! exists /usr/local/lib/ollama && ! exists /etc/systemd/system/ollama.service && ! exists /usr/share/ollama'
new_root; so; so --remove --yes --keep-models
expect "--keep-models conserva i modelli" '[ "$RC" = 0 ] && exists /usr/share/ollama && ! exists /usr/local/bin/ollama'
new_root; so; so --remove
expect "senza --yes e senza conferma non rimuove niente" '[ "$RC" = 1 ] && exists /usr/local/bin/ollama'

sec "10. Decisioni dall'hardware"
new_root; HW_VRAM_MB=0 HW_RAM_GB=8 so
expect "CPU con 8 GB: verdetto none, esce 3, nessuna modifica" '[ "$RC" = 3 ] && ! exists /usr && [ ! -d "$R/state" ]'
new_root; HW_VRAM_MB=0 HW_RAM_GB=16 so
expect "CPU con 16 GB: solo il 3b" '[ "$RC" = 0 ] && [ "$(models)" = "qwen2.5-coder:3b " ]'
expect "e avverte che auto salta il locale" 'grep -q "lane auto → qwen2.5-coder:7b NON scaricato" <<<"$OUT"'
new_root; HW_VRAM_MB=24576 HW_RAM_GB=64 so
expect "24 GB VRAM: 3b + 7b in VRAM (niente 14b che nessuna lane usa)" '[ "$RC" = 0 ] && grep -q "verdetto: gpu" <<<"$OUT" && ! grep -q "verdetto: gpu-offload" <<<"$OUT" && [ "$(models)" = "qwen2.5-coder:3b qwen2.5-coder:7b " ]'
new_root; HW_DISK_GB=3 so
expect "disco pieno: none, esce 3" '[ "$RC" = 3 ] && ! exists /usr'
new_root; XENV="FAKE_TPS=2" so; XENV=""
expect "2 token/s: installato ma con avvertenza (niente rollback)" '[ "$RC" = 0 ] && grep -q "piu. lento del cloud" <<<"$OUT" && exists /usr/local/bin/ollama'

sec "11. Prerequisiti mancanti: si ferma PRIMA di cambiare qualcosa"
new_root; touch "$R/ostree-booted"; so
expect "OS atomico senza ollama: esce 2 con raccomandazione, nessuna modifica" '[ "$RC" = 2 ] && grep -q "brew install ollama" <<<"$OUT" && ! exists /usr'
new_root; XENV="FAKE_NO_VIRBR0=1" so; XENV=""
expect "virbr0 assente: esce 2, nessuna modifica" '[ "$RC" = 2 ] && ! exists /usr'
new_root; XENV="FAKE_NO_VIRBR0=1 LOCAL_ONLY=1" so; XENV=""
expect "LOCAL_ONLY=1: bind su 127.0.0.1" '[ "$RC" = 0 ] && [ "$(cat "$R/.fake/listen")" = "127.0.0.1:11434" ]'

sec "12. Firewall: la regola aggiunta dal run sparisce col rollback"
new_root; XPATH="$STUBS/fw" so
expect "ufw attivo: regola 11434 aggiunta" '[ "$RC" = 0 ] && grep -q 11434 "$R/.fake/ufw"'
XPATH="$STUBS/fw" so --rollback --yes
expect "il rollback la rimuove" '[ "$RC" = 0 ] && ! grep -q 11434 "$R/.fake/ufw"'

sec "13. --dry-run e --plan non scrivono niente"
new_root; so --dry-run
expect "--dry-run esce 0 senza file" '[ "$RC" = 0 ] && ! exists /usr && [ ! -d "$R/state" ]'
new_root; so --plan
expect "--plan esce 0 senza file" '[ "$RC" = 0 ] && ! exists /usr && [ ! -d "$R/state" ] && grep -q verdetto <<<"$OUT"'
new_root; so --remove --dry-run
expect "--remove --dry-run esce 0" '[ "$RC" = 0 ]'

echo -e "\n\033[36m── Esito setup-ollama\033[0m  \033[32m✓ $P\033[0m  \033[31m✗ $F\033[0m"
[ "$F" = 0 ]
