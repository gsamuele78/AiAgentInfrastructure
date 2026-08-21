# STATO VERIFICATO dell'host `ermes` (base della migrazione)

Non assunzioni: check eseguiti sul sistema reale.

| Componente | Stato verificato | Azione |
|---|---|---|
| `headroom.service` | :8787, `--openai-api-url https://openrouter.ai/api` → **bypassava litellm** | rimuovere (diventa callback) |
| `litellm` pipx 1.89.3 | unit `static` + `inactive (dead)`, :4000 chiusa | fermo; fallback, poi `pipx uninstall` |
| `postgresql@17` | :5432, **0 client**, solo db `postgres/template0/template1` | stop + disable (era litellm-only) |
| `opencode` | :3000 attivo, 8 provider → :8787, alias MCP lunghi, no Serena | config pulita |
| `openchamber` | solo temi/skillCatalogs, **nessun provider** | non toccare (eredita) |
| `claude code` / `codex` | → :8787 (codex wrappato da headroom) | repoint :4000 + `headroom unwrap` |
| shell `~/.bashrc` | export `*_BASE_URL` → :8787 | `clients/shell-env.sh` |
| `mem0-mcp-server` | installato ma **NON agganciato** | lasciare inerte |
| java :1025/1110/1143/1389 | **DavMail** | irrilevante |
| GPU | RTX A2000 **Laptop, 4096 MiB**, display su iGPU | Ollama host, 3B/7B-offload |
| RAM | **31 GB** (18 liberi), swap 29 GB | VM a 4 GB va bene |

## Rischio sicurezza rilevato
`~/litellm_config.yaml` conteneva **password postgres e master key in chiaro**,
permessi `664`. Nel nuovo stack i segreti stanno in `services/.env` (600) e nel
config solo `os.environ/`. **Non riutilizzare le credenziali vecchie.**

## Conclusione
Nessun conflitto: postgres e mem0 erano orfani, openchamber era già corretto.
La migrazione è un **repoint** (:8787 → :4000) più la rimozione del proxy.
