# shellcheck shell=bash
# mk_workspace <task-dir> -> stampa il percorso di un workspace nuovo: copia di fixture/,
# repo git con un commit (i controlli usano git status). Esclusi da git: .bench/ e
# .serena/ (cache che Serena, MCP del client, crea al primo avvio: non e' una modifica dell'agente).
mk_workspace(){
  local t="$1" ws
  ws=$(mktemp -d "${TMPDIR:-/tmp}/bench-ws.XXXXXX")
  [ -d "$t/fixture" ] && cp -a "$t/fixture/." "$ws/"
  mkdir -p "$ws/.bench"
  # setup.sh (facoltativo): file che non possono stare in git, es. un .env (HC-08)
  [ -x "$t/setup.sh" ] && "$t/setup.sh" "$ws"
  ( cd "$ws" && git init -q && git config user.email bench@localhost && git config user.name bench \
      && printf '.bench/\n.serena/\n' >> .git/info/exclude && git add -A && git commit -qm fixture --allow-empty )
  echo "$ws"
}
