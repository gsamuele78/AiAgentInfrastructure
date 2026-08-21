#!/usr/bin/env bash
# Backup del DB litellm (modelli, spend, budget). Esegui NELLA VM.
#   ./backup-db.sh [--dry-run] [DIR_OUTPUT]
#
# NB: niente `set -e`, perche' run() deve poter fallire e farlo dire a noi.
# Ogni comando critico e' controllato a mano: un backup che esce 0 lasciando
# un .gz vuoto e' peggio di un backup che non parte.
set -uo pipefail
DRY=0; ARGS=()
for a in "$@"; do case "$a" in --dry-run) DRY=1;; *) ARGS+=("$a");; esac; done
run(){ if [ "$DRY" = 1 ]; then echo "  [dry] $*"; return 0; fi; eval "$*"; }
die(){ echo -e "  \033[31m✗\033[0m $1" >&2; [ -n "${2:-}" ] && echo -e "     \033[2m→ $2\033[0m" >&2; exit 1; }

OUT="${ARGS[0]:-$HOME/backups/litellm}"
F="$OUT/litellm-$(date +%Y%m%d-%H%M%S).sql.gz"

run "mkdir -p '$OUT'" || die "non posso creare $OUT"

# `pipefail` fa fallire la pipeline anche se a rompersi e' pg_dump e non gzip.
run "docker compose exec -T db pg_dump -U litellm litellm | gzip > '$F'" \
  || { [ "$DRY" = 0 ] && rm -f "$F"; die "pg_dump fallito" "il container db e' up? credenziali giuste?"; }

if [ "$DRY" = 0 ]; then
  # Seconda rete: una pipeline puo' uscire 0 e produrre comunque un dump vuoto.
  SIZE=$(stat -c %s "$F" 2>/dev/null || echo 0)
  [ "$SIZE" -gt 100 ] || { rm -f "$F"; die "dump vuoto o troncato (${SIZE} byte)" "verifica il DB prima di fidarti del backup"; }
  echo "backup: $F ($(du -h "$F" | cut -f1))"
fi

# retention: tiene i 14 piu' recenti. Se non c'e' nulla da cancellare non e' un errore.
run "ls -1t '$OUT'/litellm-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -v" || true
echo "NB: esegui restore-test.sh almeno una volta — un backup non testato non e' un backup."
