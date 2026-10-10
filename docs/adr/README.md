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
| [0007](0007-una-memoria-per-livello.md) | Una memoria per livello | Accepted — file canonico **superseded by 0013** |
| [0008](0008-ollama-su-host.md) | Ollama su host, no passthrough | Accepted |
| [0009](0009-mtls-per-biome.md) | mTLS M2M, Keycloak per umani | Accepted |
| [0010](0010-ci-non-cd.md) | CI di validazione, nessun CD | Accepted — `continue-on-error` **superseded by 0015** |
| [0011](0011-cloud-init-per-la-vm.md) | cloud-init invece di installazione manuale | Accepted |
| [0012](0012-repo-separato-per-multi-tenant.md) | Repo separato per il multi-tenant BIOME | Accepted |
| [0013](0013-agents-md-come-memoria-di-progetto.md) | AGENTS.md come memoria di progetto | Accepted |
| [0014](0014-headroom-standalone-per-la-lane-abbonamento.md) | Headroom standalone sulla sola lane abbonamento | Accepted — **eccezione** a 0001/0003 |
| [0015](0015-test-funzionali-bloccanti.md) | I test funzionali possono fallire | Accepted |
| [0016](0016-catena-auto-nel-gateway-non-claude-code-router.md) | Catena `auto` nel gateway; Claude Code Router non adottato | Accepted |
| [0017](0017-manifest-componenti-e-validatore-unico.md) | Manifest dei componenti e validatore unico (`stack.py`) | Proposed |
| [0018](0018-installazione-idempotente-e-rollback-debian-bazzite.md) | Installazione idempotente e rollback su Debian 13 e Bazzite | Proposed |
| [0019](0019-pratiche-openhands-skill-per-ruolo-e-serena.md) | Pratiche OpenHands senza OpenHands; skill per ruolo; Serena per client | Proposed |
| [0020](0020-dependabot-e-scala-di-autoaggiornamento.md) | Dependabot e scala di autoaggiornamento | Accepted (stadio 0) |
| [0021](0021-misurare-prima-di-adottare-e-oh-my-openagent.md) | Misurare prima di adottare; oh-my-openagent come esperimento | Proposed |
| [0022](0022-standard-condiviso-con-infra-iam-pki.md) | Standard condiviso con Infra-Iam-PKI: cosa si adotta, chi possiede i controlli | Accepted |

Template: `_template.md`. Regole in `CONTRIBUTING.md`.
