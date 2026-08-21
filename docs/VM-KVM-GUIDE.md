# VM KVM locale (virt-manager / libvirt)

## Rete: l'host raggiunge la VM (niente bridge necessario)
La rete `default` di libvirt crea `virbr0` **sull'host**, che è quindi
`192.168.122.1` sulla stessa subnet della VM. Il NAT (MASQUERADE) si applica
solo al traffico che **esce** verso la rete fisica: host↔VM non lo attraversa.

Serve il bridge **solo** se un'altra macchina deve usare il gateway.
(Attenzione: `-netdev user` / SLIRP è un'altra cosa — subnet `10.0.2.x`, lì
servirebbe `hostfwd`. In virt-manager il default è virbr0.)

```bash
virsh -c qemu:///system domifaddr llm-vm
ip -4 addr show virbr0                       # 192.168.122.1/24
curl -s http://192.168.122.50:4000/health/liveliness
```
Se il container ascolta solo su `127.0.0.1` della VM, l'host non lo vede: per
questo il compose pubblica su `0.0.0.0:4000` (sicuro perché la VM è NAT-only).
Controlla anche `ufw` dentro la VM.

## ⚠️ L'IP della VM può cambiare — bloccalo
La lease DHCP è legata al MAC, ma **non è garantita**: scade, il file lease può
azzerarsi, un'altra VM può prendere l'IP. Se cambia, il forward punta nel vuoto.

**Soluzione 1 (consigliata) — riserva DHCP:**
```bash
virsh -c qemu:///system domiflist llm-vm      # MAC
virsh -c qemu:///system net-edit default      # range dinamico .100-.254
virsh -c qemu:///system net-update default add ip-dhcp-host \
  "<host mac='52:54:00:ab:cd:ef' name='llm-vm' ip='192.168.122.50'/>" --live --config
virsh -c qemu:///system reboot llm-vm         # serve per rinnovare la lease
virsh -c qemu:///system domifaddr llm-vm
```
`--live --config` = attiva ora **e** persiste.

**Soluzione 2 — risolvi per nome:**
```bash
sudo apt install -y libnss-libvirt
# /etc/nsswitch.conf →  hosts: files libvirt libvirt_guest dns
ping -c1 llm-vm
```
Poi in `forward.env`: `VM_IP=llm-vm`. Regge anche se l'IP cambia.

**Soluzione 3 — IP statico nel guest:** funziona, ma fuori dal pool dinamico e
la config vive nel guest. Meno IaC.

## Snapshot — la rete di sicurezza PSE
```bash
virsh -c qemu:///system snapshot-create-as llm-vm pre-run-$(date +%F) --atomic
virsh -c qemu:///system snapshot-list llm-vm
virsh -c qemu:///system snapshot-revert llm-vm pre-run-2026-07-27
```
Richiede **qcow2**. Snapshot a VM accesa include la RAM; a VM spenta è più
leggero e più sicuro per gli upgrade. Non sostituisce il backup DB: se torni
indietro perdi lo spend recente.

## Avvio automatico
```bash
virsh -c qemu:///system autostart llm-vm     # + restart: unless-stopped nel compose
```

## Checklist
- [ ] disco qcow2 · [ ] qemu-guest-agent · [ ] rete NAT (non bridge)
- [ ] **riserva DHCP** verificata · [ ] (opz.) libnss-libvirt
- [ ] `litellm-forward.service` attivo → `127.0.0.1:4000` risponde
- [ ] `virsh autostart` · [ ] snapshot `baseline`
