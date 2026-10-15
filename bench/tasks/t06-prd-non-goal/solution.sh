#!/usr/bin/env bash
cd "$1" || exit 1
mkdir -p docs/decisioni
printf 'Esito: respinta\n\nL'"'"'alta disponibilita'"'"' e'"'"' un non-obiettivo esplicito (PRD §3): il rollback e'"'"' lo snapshot.\n' > docs/decisioni/ha.md
