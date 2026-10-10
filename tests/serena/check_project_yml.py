"""Carica .serena/project.yml con il ProjectConfig VERO di serena-agent.

Lanciato da check-project-yml.sh dentro `uvx --from serena-agent==<pin>`: cosi'
il test usa esattamente la versione pinnata in stack/requirements-tools.txt.
Verifica: il file si carica (A15: senza language_servers era KeyError), la
memoria e' esclusa per intero (ADR-0007) e Serena NON riscrive il file (un
file incompleto verrebbe completato al primo avvio, sporcando il working tree).
Uscita 0 ok, 1 fallito.
"""
import hashlib
import pathlib
import sys

from serena.config.serena_config import ProjectConfig, SerenaConfig

MEMORY_TOOLS = {"write_memory", "read_memory", "list_memories", "delete_memory",
                "rename_memory", "edit_memory", "onboarding"}
bad = 0
for root in sys.argv[1:] or ["."]:
    f = pathlib.Path(root, ".serena", "project.yml")
    before = hashlib.sha256(f.read_bytes()).hexdigest()
    try:
        cfg = ProjectConfig.load(root, SerenaConfig())
    except Exception as e:  # noqa: BLE001 - qualunque errore di caricamento e' un fallimento
        print(f"  FAIL {f}: non si carica ({type(e).__name__}: {e})"); bad += 1; continue
    missing = MEMORY_TOOLS - set(cfg.excluded_tools)
    rewritten = hashlib.sha256(f.read_bytes()).hexdigest() != before
    langs = [l.value for l in cfg.language_servers]
    if missing or rewritten or not langs:
        print(f"  FAIL {f}: memoria non esclusa {sorted(missing)}" if missing else "", end="")
        print(f"  FAIL {f}: riscritto da Serena (incompleto)" if rewritten else "", end="")
        print(f"  FAIL {f}: nessun language server" if not langs else "")
        bad += 1
    else:
        print(f"  ok   {f}: language_servers={langs}, 7 tool di memoria esclusi, non riscritto")
sys.exit(1 if bad else 0)
