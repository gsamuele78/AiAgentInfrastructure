# CLAUDE.md

Il contesto di progetto è in **[AGENTS.md](AGENTS.md)** — file unico condiviso
con opencode e gli altri agenti, così non esistono due verità da mantenere
allineate (vedi `docs/MEMORY-POLICY.md`).

**Leggi `AGENTS.md` prima di proporre modifiche.** In particolare:
- i **non-goal** in `docs/PRD.md` §3
- le **invarianti** (verificate da `scripts/test-scripts.sh`)
- le **trappole note**, in cui siamo già cascati

Verifica rapida prima di ogni commit:
```bash
./scripts/test-scripts.sh && ./scripts/devops-audit.sh
```
