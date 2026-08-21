# INSTALL GUIDE

> **ORDINE PSE: la VM va su e verificata PRIMA di pulire l'host.**
> Invertirlo ti lascia senza gateway a metà migrazione.

Percorso guidato: `./scripts/deploy-all.sh` (8 fasi con checkpoint).
Sotto, la versione manuale.

## Fase 0 — Hardware
```bash
./scripts/detect-hardware.sh --emit-config   # sizing VM + modello locale
```

## Fase 1 — VM: creazione + servizi
**Automatico** (consigliato — vedi `VM-AUTOMATION.md`):
```bash
./scripts/create-vm.sh                # cloud-init: VM pronta con docker e IP riservato
virsh -c qemu:///system snapshot-create-as llm-vm clean-install
```
*Manuale* (fallback): `VM-DEBIAN-INSTALL.md` + `VM-KVM-GUIDE.md`. Poi in entrambi i casi:
```bash
scp -r services/ jfs@<VM_IP>:~/llm-services/
ssh jfs@<VM_IP>; cd ~/llm-services
cp .env.example .env && chmod 600 .env && $EDITOR .env    # chiavi NUOVE
docker compose build && docker compose up -d
curl -s http://127.0.0.1:4000/health/liveliness
```

## Fase 2 — Forward host → VM
```bash
sudo apt install -y socat
install -d ~/.config/litellm
cp systemd/forward.env.example ~/.config/litellm/forward.env
$EDITOR ~/.config/litellm/forward.env && chmod 600 ~/.config/litellm/forward.env
cp systemd/litellm-forward.service ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now litellm-forward.service
curl -s http://127.0.0.1:4000/health/liveliness    # DEVE rispondere
```

## Fase 3 — Pulizia host (solo se la Fase 2 risponde)
```bash
./scripts/cleanup-host.sh --dry-run
./scripts/cleanup-host.sh
```
Rimuove headroom proxy, ferma litellm pipx (resta come fallback), stop+disable
postgres host, mette in sicurezza il vecchio config con segreti in chiaro.

## Fase 4 — Tooling
```bash
./scripts/stack-selective-install.sh /path/al/tuo/repo
echo 'source '"$PWD"'/clients/shell-env.sh' >> ~/.bashrc && source ~/.bashrc
systemctl --user restart opencode.service
```

## Fase 5 — Doppia autenticazione
Vedi `DUAL-AUTH.md`. In sintesi: opencode/codex sul gateway (già fatto),
Claude Code sull'abbonamento (scegli variante A/B/C).

## Fase 6 — LLM locale (opzionale)
```bash
./scripts/setup-ollama.sh --dry-run && ./scripts/setup-ollama.sh
```
Razionale e scelta dei modelli: `GPU-LOCAL-LLM.md`. Bind su `192.168.122.1`,
**mai** `0.0.0.0` (Ollama non ha autenticazione).

## Fase 7 — Verifica
```bash
./scripts/test-scripts.sh        # L1/L2: contratti e invarianti degli script
./scripts/devops-audit.sh        # L4: best practice deploy
./scripts/audit-integration.py   # L3: configurazione
./scripts/test-all.sh            # L5: catena reale
```

## Fase 8 — Baseline
```bash
virsh -c qemu:///system snapshot-create-as llm-vm baseline --description "stack ok"
./scripts/restore-test.sh     # TC-05: OBBLIGATORIO almeno una volta
# nel repo:  /setup-matt-pocock-skills ; /grill-with-docs ; /graphify .
```

## Nuova installazione
Salta la Fase 3. Ordine: 0 → 1 → 2 → 4 → 5 → 6 → 7 → 8.
