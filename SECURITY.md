# Security Policy

## Cosa contiene (e cosa NON deve contenere) questo repo

Questo repository contiene **configurazione e script**, mai credenziali.
Tutti i segreti vivono in file esclusi da git:

| File | Dove | Permessi |
|------|------|----------|
| `services/.env` | VM | 600 |
| `~/.config/litellm/master.key` | host | 600 |
| `~/.config/litellm/forward.env` | host | 600 |
| certificati step-ca (`*.key`) | host/server | 600 |

La CI (`.github/workflows/validate.yml`, job `secrets`) fallisce se rileva
pattern di chiavi reali nei file committati.

## Se hai committato un segreto per errore

1. **Ruota subito la credenziale** — rimuoverla dalla history non basta: va
   considerata compromessa dal momento del push.
2. Riscrivi la history: `git filter-repo --path <file> --invert-paths`
3. Force-push e invalida i fork/clone esistenti.

## Superficie di esposizione (per design)

- Gateway LiteLLM: bind `127.0.0.1` (host) / rete NAT libvirt (VM). Mai in LAN.
- Postgres: solo rete interna del compose, nessuna porta pubblicata.
- Ollama: bind sul solo bridge libvirt (`192.168.122.1`), mai `0.0.0.0`
  (non ha autenticazione).
- vLLM su BIOME: `127.0.0.1` + nginx mTLS + firewall sulla subnet VPN.

## Segnalazioni

Repo personale a maintainer singolo: apri una issue con label `security`, o
contatta direttamente il maintainer per problemi sensibili.
