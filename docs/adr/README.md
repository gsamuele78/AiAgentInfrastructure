# Architecture Decision Records

Formato MADR semplificato. Un file per decisione, numerato, **immutabile**:
una decisione non si modifica, si crea un nuovo ADR che la **supersede**.

| # | Titolo | Status |
|---|--------|--------|
| [0001](0001-litellm-come-gateway-unico.md) | LiteLLM come gateway unico | Accepted |
| [0002](0002-headroom-proxy-davanti.md) | Headroom come proxy davanti | **Superseded by 0003** |
| [0003](0003-headroom-come-callback.md) | Headroom come callback pre_call_hook | Accepted |
| [0004](0004-modelli-nel-db.md) | Modelli OpenRouter nel DB | Accepted |
| [0005](0005-servizi-in-vm.md) | Servizi in VM, IDE su host | Accepted |
| [0006](0006-un-tool-per-layer.md) | Un tool per layer | Accepted |
| [0007](0007-una-memoria-per-livello.md) | Una memoria per livello | Accepted |
| [0008](0008-ollama-su-host.md) | Ollama su host, no passthrough | Accepted |
| [0009](0009-mtls-per-biome.md) | mTLS M2M, Keycloak per umani | Accepted |
| [0010](0010-ci-non-cd.md) | CI di validazione, nessun CD | Accepted |
| [0011](0011-cloud-init-per-la-vm.md) | cloud-init invece di installazione manuale | Accepted |
| [0012](0012-repo-separato-per-multi-tenant.md) | Repo separato per il multi-tenant BIOME | Accepted |

Template: `_template.md`. Regole in `CONTRIBUTING.md`.
