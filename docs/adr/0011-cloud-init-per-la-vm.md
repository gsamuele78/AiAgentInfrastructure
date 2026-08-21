# 0011 — cloud-init invece di installazione manuale per la VM

- **Status**: Accepted
- **Data**: 2026-08-21

## Contesto
`VM-DEBIAN-INSTALL.md` documentava una procedura **manuale** in virt-manager
(ISO netinstall, tasksel, docker a mano). Il PRD pone come obiettivo G6
«deploy riproducibile senza conoscenza tacita»: una procedura che dipende dal
ricordarsi di deselezionare i task in `tasksel` **viola quell'obiettivo**.

## Alternative considerate
| Opzione | Riproducibile | Attrito | Note |
|---|---|---|---|
| Installazione manuale (ISO) | ❌ dipende dall'operatore | alto | stato precedente |
| Preseed Debian | ✅ | medio | sintassi ostica, debug difficile |
| **Cloud image + cloud-init** | ✅ | basso | standard de facto; immagine già minimale |
| Packer + template | ✅ | alto | sovradimensionato per 1 VM |

## Decisione
`scripts/create-vm.sh` usa la **cloud image Debian genericcloud** con
**cloud-init**: utente e chiave SSH, docker dal repo ufficiale, hardening
(daemon.json, journald dimensionato), riserva DHCP automatica, qcow2, autostart.

## Conseguenze
**Positive:** VM identica a ogni ricreazione; nessun passo dimenticabile;
l'IP è stabile per costruzione (riserva DHCP creata dallo script); `--destroy`
rende il ciclo ripetibile; `VM-DEBIAN-INSTALL.md` resta come *fallback manuale*
e documentazione del razionale.
**Negative / costi accettati:** dipendenza da `cloud-image-utils` e `virtinst`;
l'URL dell'immagine va aggiornato al cambio di stable Debian; lo script non
verifica la firma GPG dell'immagine (solo HTTPS) — accettabile per una VM
interna, da irrobustire se un giorno serve una catena di fiducia completa.
**Da rivedere se:** le VM diventano più d'una e con ruoli diversi → allora
Packer o Terraform/libvirt hanno senso.
