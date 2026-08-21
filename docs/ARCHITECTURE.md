# ARCHITECTURE

```
  HOST ermes                                  VM KVM locale (virt-manager)
  ┌────────────────────────────┐             ┌──────────────────────────────┐
  │ VSCodium + OpenChamber     │             │ docker compose:              │
  │ opencode :3000 ────────────┼─127.0.0.1───┤   litellm :4000              │
  │ Claude Code (abbonamento)  │   :4000     │     └─[headroom callback]    │
  │ Codex                      │  (socat →   │   postgres (rete interna)    │
  │ Serena + graphify (uv)     │   VM_IP)    └──────────────────────────────┘
  │ Ollama :11434 su virbr0    │                snapshot virsh = rollback
  └────────────────────────────┘
                    └──── VPN ateneo ────► BIOME L40S (vLLM, mTLS)
```

Le decisioni sono tracciate in `adr/`. Sintesi:

- **0001** LiteLLM è l'unico ingresso.
- **0003** Headroom comprime come *callback* dentro LiteLLM (supersede 0002).
- **0004** I modelli OpenRouter vivono nel DB, riconciliati a caldo.
- **0005** Servizi in VM, IDE sull'host; `socat` mantiene il loopback.
- **0006** Un tool per layer: Serena, graphify, mattpocock, AgentShield.
- **0007** Una memoria per livello.
- **0008** Ollama sull'host (niente passthrough), bind su virbr0.
- **0009** mTLS per M2M verso BIOME; Keycloak solo per gli umani.
- **0010** CI di validazione + functional su runner self-hosted; nessun CD.

## Autenticazione (doppia rotta)
| Client | Auth | Vedi |
|---|---|---|
| Claude Code | abbonamento Pro (OAuth) | `DUAL-AUTH.md` |
| opencode / OpenChamber / Codex | virtual key LiteLLM | `INSTALL_GUIDE.md` |
