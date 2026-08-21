# 0005 — Servizi in VM KVM, IDE e tooling sull'host
- **Status**: Accepted
- **Data**: 2026-07-27

## Contesto
Servono isolamento e rollback rapido, ma gli agenti devono vedere il filesystem
del codice.

## Alternative considerate
| Opzione | Isolamento | Rollback | Attrito |
|---|---|---|---|
| Tutto sull'host | basso | nessuno | minimo |
| **Servizi in VM, IDE su host** | buono | snapshot | forward :4000 |
| Tutto in VM | massimo | snapshot | workspace da montare, IDE remoto |

## Decisione
`litellm + postgres` in VM KVM locale; opencode, OpenChamber, Serena e workspace
sull'host. `socat` mantiene `127.0.0.1:4000`.

## Conseguenze
**Positive:** snapshot `virsh` prima delle run agentiche; nessun mount rw del
workspace nei container; config invariate.
**Negative:** un servizio in più; l'IP VM va bloccato (riserva DHCP) altrimenti
il forward si rompe.
**Da rivedere se:** i servizi si spostano su host dedicato o sul cluster.
