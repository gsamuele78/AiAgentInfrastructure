# shellcheck shell=bash
# ============================================================
#  journal.sh -- registro delle modifiche di un run, per annullarle.
#  Meccanismo di ADR-0018 (regola 1): ogni run scrive cio' che cambia in
#    ${AIAGENT_STATE:-~/.local/state/aiagentinfra}/runs/<componente>-<timestamp>/
#  e il rollback lo ripercorre AL CONTRARIO. Sostituisce i .bak-<ts> sparsi.
#
#  Contratto per chi lo usa:
#    journal_begin <componente>      prima della prima modifica
#    journal_file  <path>            PRIMA di scrivere/cancellare un file
#    journal_undo  "<comando>"       DOPO un'azione riuscita: come annullarla
#    journal_rollback <dir-del-run>  ripercorre il registro all'indietro
#  Le funzioni rispettano DRY=1 (non scrivono niente, stampano soltanto) e
#  usano $SUDO (default: sudo se non root) per i file di sistema.
#
#  Il registro sta nella home dell'utente, 600: chi lo puo' modificare puo'
#  gia' eseguire comandi come quell'utente, quindi `eval` non allarga nulla.
# ============================================================

JOURNAL_ROOT="${AIAGENT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/aiagentinfra}/runs"
JRUN=""; JCHANGES=0
if [ -z "${SUDO+x}" ]; then
  if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo"; fi
fi

journal_begin(){
  local comp=$1 ts
  ts=$(date +%Y%m%d-%H%M%S)
  JRUN="$JOURNAL_ROOT/$comp-$ts"; JCHANGES=0
  [ "${DRY:-0}" = 1 ] && { echo "  [dry] registro del run: $JRUN"; return 0; }
  ( umask 077; mkdir -p "$JRUN/files" ) || { echo "  ✗ non posso creare $JRUN" >&2; return 1; }
  : > "$JRUN/actions.log"; chmod 600 "$JRUN/actions.log"
  ln -sfn "$JRUN" "$JOURNAL_ROOT/$comp-latest"
}

# Salva lo stato attuale di un file prima di toccarlo: il contenuto, oppure il
# fatto che non esisteva (allora il rollback lo cancella).
journal_file(){
  local p=$1 n
  [ "${DRY:-0}" = 1 ] && return 0
  [ -n "$JRUN" ] || { echo "  ✗ journal_file senza journal_begin" >&2; return 1; }
  n=$(( $(wc -l < "$JRUN/actions.log") + 1 ))
  if $SUDO test -e "$p"; then
    $SUDO cat "$p" > "$JRUN/files/$n" || return 1
    printf 'file\t%s\t%s\n' "$p" "$n" >> "$JRUN/actions.log"
  else
    printf 'file\t%s\t-\n' "$p" >> "$JRUN/actions.log"
  fi
  JCHANGES=$((JCHANGES+1))
}

journal_undo(){
  [ "${DRY:-0}" = 1 ] && return 0
  [ -n "$JRUN" ] || { echo "  ✗ journal_undo senza journal_begin" >&2; return 1; }
  printf 'undo\t%s\n' "$1" >> "$JRUN/actions.log"
  JCHANGES=$((JCHANGES+1))
}

# Dir del run: un percorso, un nome (<comp>-<ts>) o <comp>-latest.
journal_resolve(){
  local r=$1
  [ -d "$r" ] && { (cd "$r" && pwd -P); return; }
  [ -e "$JOURNAL_ROOT/$r" ] && { (cd "$JOURNAL_ROOT/$r" && pwd -P); return; }
  return 1
}

journal_list(){
  local comp=$1 d
  for d in "$JOURNAL_ROOT/$comp"-[0-9]*; do
    [ -f "$d/actions.log" ] || continue
    printf '  %s  %s azioni%s\n' "$(basename "$d")" "$(wc -l < "$d/actions.log")" \
      "$([ -f "$d/ROLLED_BACK" ] && echo '  (gia annullato)')"
  done
}

# Ripercorre il registro dall'ultima azione alla prima. Non si ferma al primo
# errore: un rollback a meta' e' peggio di uno che prova tutto e dice cosa e'
# rimasto. Ritorna 1 se almeno un passo e' fallito.
journal_rollback(){
  local dir=$1 line kind a b rc=0
  [ -f "$dir/actions.log" ] || { echo "  ✗ nessun registro in $dir" >&2; return 1; }
  [ -f "$dir/ROLLED_BACK" ] && { echo "  $dir: gia' annullato, niente da fare"; return 0; }
  [ -s "$dir/actions.log" ] || echo "  registro vuoto: il run non aveva cambiato niente"
  while IFS= read -r line; do
    IFS=$'\t' read -r kind a b <<<"$line"
    case "$kind" in
      file)
        if [ "$b" = "-" ]; then
          if [ "${DRY:-0}" = 1 ]; then echo "  [dry] rm $a (non esisteva prima)"
          else $SUDO rm -f "$a" && echo "  ↺ rimosso $a (non esisteva prima)" || { echo "  ✗ rm $a"; rc=1; }; fi
        else
          if [ "${DRY:-0}" = 1 ]; then echo "  [dry] ripristina $a"
          else $SUDO tee "$a" < "$dir/files/$b" >/dev/null && echo "  ↺ ripristinato $a" || { echo "  ✗ ripristino $a"; rc=1; }; fi
        fi ;;
      undo)
        if [ "${DRY:-0}" = 1 ]; then echo "  [dry] $a"
        else eval "$a" && echo "  ↺ $a" || { echo "  ✗ $a"; rc=1; }; fi ;;
      *) [ -n "$kind" ] && { echo "  ✗ riga sconosciuta nel registro: $line"; rc=1; } ;;
    esac
  done < <(tac "$dir/actions.log")
  [ "${DRY:-0}" = 1 ] || { [ "$rc" = 0 ] && date -Iseconds > "$dir/ROLLED_BACK"; }
  return "$rc"
}
