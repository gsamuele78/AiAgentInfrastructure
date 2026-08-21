# 0012 — Repo separato per il servizio LLM multi-tenant BIOME

- **Status**: Accepted
- **Data**: 2026-08-21

## Contesto
Il servizio LLM per i ricercatori BIOME (accesso da RStudio Server, in futuro
dal cluster Kubernetes) richiede multi-tenancy, quote per utente, audit e una
aspettativa di servizio verso terzi. Questo repo dichiara nel PRD §3
**«❌ Multi-tenancy — un utente»** come non-goal esplicito.

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Aggiungere qui il multi-tenant | nessuna duplicazione; un solo CI | **contraddice un non-goal del PRD**; mescola infrastruttura personale e istituzionale; ogni modifica al setup personale fa girare la CI del servizio condiviso |
| Monorepo con due cartelle e due PRD | separazione logica | governance ambigua: chi può mergiare cosa? il repo contiene `CURRENT-STATE.md` con la mappa dell'host personale |
| **Repo separato** | governance, lifecycle, visibilità e CI indipendenti | duplicazione controllata di 2-3 pattern |
| Repo separato + submodule condiviso | DRY | per 2 repo a questa scala il submodule costa più di quanto rende (single maintainer) |

## Decisione
Il servizio multi-tenant vive in un **repository separato** (proposto:
`BiomeLLMService`), con PRD, ADR, CI e ciclo di rilascio propri.
**Nessun submodule condiviso**: si accetta la duplicazione dei pochi pattern
comuni (mTLS step-ca, struttura del compose, forma del config LiteLLM).

Confine netto:
| | `AiAgentInfrastructure` (questo) | `BiomeLLMService` (nuovo) |
|---|---|---|
| Utenti | 1 (il maintainer) | N ricercatori, poi utenti k8s |
| Contiene | dettagli host personali (`/home/$USER`, IP interni, `CURRENT-STATE.md`) | solo configurazione istituzionale |
| SLA | nessuno | implicito verso i colleghi |
| Compliance | — | GDPR, policy di ateneo, audit |
| Visibilità | privata consigliata | da decidere col gruppo |

`services-biome/` **resta qui** finché è a uso singolo (il maintainer che chiama
vLLM dal proprio gateway). Migra nel nuovo repo quando si aggiunge il primo
tenant diverso dal maintainer: è quello il momento in cui cambia la natura del
servizio, non prima.

## Conseguenze
**Positive:** i non-goal restano veri; il repo personale può restare privato
mentre quello istituzionale è condivisibile col gruppo; la CI del servizio non
dipende dalle modifiche al laptop; possibilità di dare accesso a colleghi su un
solo repo.
**Negative / costi accettati:** due repo da mantenere; duplicazione di 2-3
pattern (accettata: sincronizzarli a mano una volta l'anno costa meno di un
submodule); un cambiamento che tocca entrambi richiede due PR.
**Da rivedere se:** i pattern duplicati diventano più di 3-4, o divergono in
modo dannoso → allora una libreria condivisa versionata (non un submodule).
