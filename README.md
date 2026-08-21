# AiAgentInfrastructure

Infrastruttura per agenti AI a **maintainer singolo**: un gateway LiteLLM (con
compressione Headroom come callback) in VM KVM locale, agenti sull'host, lane
per dati sensibili, LLM locale e self-hosted BIOME.

```
  HOST                                         VM KVM
  Claude Code ──abbonamento──► Anthropic       ┌──────────────────────────┐
  opencode / OpenChamber ─┐                    │ litellm :4000            │
  Codex ──────────────────┼─127.0.0.1:4000────►│  └─[headroom callback]   │
  Serena + graphify       │      (socat)       │ postgres (rete interna)  │
  Ollama :11434 (virbr0) ─┘                    └──────────────────────────┘
                    └─ VPN ateneo ─► BIOME L40S (vLLM, mTLS)
```

## Quickstart
```bash
./scripts/detect-hardware.sh --emit-config   # cosa regge la macchina
./scripts/deploy-all.sh --dry-run            # vedi le 8 fasi
./scripts/deploy-all.sh                      # esegui con checkpoint
./scripts/test-all.sh                        # verifica tutto
```

## Struttura
```
├── docs/
│   ├── PRD.md                requisiti, scope, non-goals, accettazione
│   ├── adr/                  10 Architecture Decision Records
│   ├── TEST-PLAN.md          matrice requisiti→test, casi critici
│   ├── INSTALL_GUIDE.md      ★ deploy passo-passo
│   ├── DUAL-AUTH.md          abbonamento Claude Pro + gateway insieme
│   ├── CLAUDE-SUBSCRIPTION.md  auth, precedenza variabili, termini d'uso
│   ├── AGENTS-SETUP.md       opencode, OpenChamber, MCP, VSCodium
│   ├── VM-DEBIAN-INSTALL.md  netinstall minimale
│   ├── VM-KVM-GUIDE.md       rete, riserva DHCP, snapshot
│   ├── DOCKER-HARDENING.md   data-root, log driver, journald
│   ├── GPU-LOCAL-LLM.md      Ollama su A2000 (4 GB) + offload
│   ├── BIOME-L40S.md         vLLM + mTLS step-ca
│   ├── GITHUB-SETUP.md       primo push, branch protection, runner
│   ├── ARCHITECTURE.md · TOOLS-STACK.md · MEMORY-POLICY.md
│   ├── DEVOPS-AUDIT.md       best practice + debito riconosciuto
│   └── CURRENT-STATE.md      stato verificato dell'host
├── services/                 gira nella VM (compose + Dockerfile + config)
├── clients/                  opencode.jsonc, claude, codex, shell-env
├── systemd/                  forward VM + note di rimozione
├── scripts/                  deploy, audit, test, backup, restore, detect
└── .github/workflows/        validate (CI) + functional (self-hosted)
```

## Principi
- **Un gateway**, un punto di compressione (ADR-0001, 0003)
- **Un tool per layer**: Serena · graphify · mattpocock · AgentShield (ADR-0006)
- **Una memoria per livello** (ADR-0007)
- Servizi in VM snapshot-abile; config `:ro`; solo DB e workspace scrivibili
- Segreti in file 600, **mai** nei config o negli unit systemd
- **Onesto, non ottimista**: i limiti si documentano (vedi `DEVOPS-AUDIT.md`)

## Licenza
MIT — vedi `LICENSE`.
