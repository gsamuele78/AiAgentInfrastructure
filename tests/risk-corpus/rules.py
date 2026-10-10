"""Fonte unica delle regole ask/deny per i comandi shell (ADR-0025 §4).

Le stesse regole stanno, letterali, in clients/opencode.jsonc (permission.bash) e in
clients/claude-settings.json (permissions.ask/deny, forma Bash(...)): check.py verifica
che coincidano con questa lista e le misura sul corpus. Per cambiarle: qui, poi
`check.py --emit` stampa i due blocchi da incollare.

Sintassi: glob dei due client (`*` = qualunque sequenza; " *" finale = argomenti
opzionali). I comandi composti (| && || ;) si valutano per segmento, come fanno
entrambi: per questo "bash" nudo intercetta `curl ... | bash` senza toccare `bash x.sh`.
Patterns ispirati a OpenHands defense_in_depth (pattern.py, policy_rails.py; MIT).
"""

ASK = [
    # cancellazione ricorsiva
    "rm -r*", "rm -R*", "rm -fr*", "rm -fR*", "rm --recursive*", "rm --force*", "rm * -r*", "rm * -fr*",
    "sudo rm *", "find * -delete*", "find * -exec rm *", "shred *", "truncate *",
    # disco grezzo
    "dd * of=/dev/*", "dd of=/dev/*", "sudo dd *", "mkfs*", "sudo mkfs*", "wipefs *", "* > /dev/sd*",
    "* > /dev/nvme*",
    # fetch-to-exec: il segmento dopo la pipe e' un interprete nudo
    "bash", "sh", "zsh", "node", "python3 -", "python -", "bash -s*", "sh -s*", "sudo bash", "sudo sh",
    "eval *",
    # codice arbitrario che cancella
    "bash -c *rm -*", "sh -c *rm -*", "python* -c *rmtree*", "python* -c *os.system*",
    "python* -c *subprocess*", "perl -e *system*",
    # git che riscrive o butta via
    "git push --force*", "git push -f*", "git push * --force*", "git push * -f*",
    "git reset --hard*", "git clean -*f*", "git branch -D *",
    # container e VM
    "docker compose*down*-v*", "docker compose*down*--volumes*", "docker-compose*down*-v*",
    "docker volume rm *", "docker volume prune*", "docker system prune*",
    "virsh destroy *", "virsh undefine *", "virsh vol-delete *", "virsh snapshot-delete *",
    # database
    "*DROP DATABASE*", "*DROP TABLE*", "*TRUNCATE *",
    # permessi e host
    "chmod -R 777 *", "sudo chown -R *", "rpm-ostree reset*", "rpm-ostree rebase *",
]

DENY = [
    # irreversibili e mai legittimi da un agente
    "rm -rf /", "rm -rf /*", "rm -rf ~", "rm -rf ~/", "rm -rf $HOME", "chmod -R 777 /",
]
