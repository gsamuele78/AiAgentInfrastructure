# 0009 — mTLS per M2M, Keycloak per gli umani
- **Status**: Accepted
- **Data**: 2026-07-27

## Contesto
Il server BIOME (L40S) è su VPN di ateneo. Esporre vLLM a tutta la VPN è
inaccettabile. Disponibili step-ca e Keycloak (progetto Infra-IAM-PKI).

## Alternative considerate
| Opzione | Adatta a M2M | Dipendenze runtime |
|---|---|---|
| Solo firewall | — | insufficiente |
| Keycloak/OIDC davanti a vLLM | ❌ serve un browser | Keycloak sempre up |
| **mTLS con step-ca** | ✅ | nessuna |

## Decisione
LiteLLM → vLLM: **mTLS** step-ca, vLLM su `127.0.0.1`, nginx unico ingresso,
firewall sulla subnet VPN. Umani → UI LiteLLM: **Keycloak OIDC**.
Agenti → LiteLLM: virtual key.

## Conseguenze
**Positive:** quattro livelli indipendenti; nessuna dipendenza da Keycloak nel
percorso dati.
**Negative:** gestione certificati su entrambi i lati; se scadono il gateway cade
(mitigato: `step ca renew --daemon`).
**Da rivedere se:** l'accesso viene esteso a utenti umani diretti.
