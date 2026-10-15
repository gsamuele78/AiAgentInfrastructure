#!/usr/bin/env bash
cd "$1" || exit 1
mkdir -p docs/decisioni && printf 'Esito: accettata\n\nRequisito F2 (§2).\n' > docs/decisioni/ha.md
