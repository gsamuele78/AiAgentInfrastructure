# PRD — LLM Integration Gateway

| | |
|---|---|
| **Owner** | Gianfranco Sammartano — IT Officer, BiGeA / BIOME |
| **Status** | in implementazione |
| **Aggiornato** | 2026-07-27 |

## 1. Problema
Ogni strumento AI (opencode, OpenChamber, Claude Code, Codex) ha credenziali ed
endpoint propri. Quattro difetti **osservati sul sistema reale**:
1. **Credenziali sparse e in chiaro** — API key duplicate in `~/litellm_config.yaml`
   (perm 664), in `opencode.jsonc`, nelle variabili di shell. Rotazione impossibile.
2. **Nessun controllo di spesa** — zero visibilità sui costi.
3. **Nessuna garanzia sui dati** — materiale di ricerca non pubblicato inviato a
   provider scelti implicitamente, con policy di logging ignote.
4. **Configurazione fragile** — 8 provider duplicati verso lo stesso proxy, alias
   MCP che causano errori di tool-calling, headroom che bypassava LiteLLM.

## 2. Obiettivi
| # | Obiettivo | Metrica |
|---|-----------|---------|
| G1 | Punto di ingresso unico | 1 gateway; 0 client diretti a provider |
| G2 | Credenziali centralizzate | 0 segreti world-readable; rotazione in 1 punto |
| G3 | Riduzione token | compressione misurabile su payload tool-heavy |
| G4 | Lane dati sensibili | ≥1 percorso in cui i dati non escono |
| G5 | Sostenibile da 1 persona | < 30 min/mese |
| G6 | Riproducibile | deploy da zero senza conoscenza tacita |

## 3. Non-obiettivi (espliciti)
- ❌ Alta disponibilità / clustering — è una workstation; il rollback è lo snapshot.
- ❌ Multi-tenancy — un utente (virtual key esistono, gestione BIOME fuori scope).
- ❌ Deployment automatico (CD) — la CI valida, non rilascia (ADR-0010).
- ❌ Sostituire i modelli cloud col locale — il locale è Tier 0.
- ❌ Fine-tuning/training — solo inferenza.

## 4. Requisiti
### Funzionali
| ID | Requisito | Priorità |
|----|-----------|----------|
| F1 | Endpoint OpenAI-compatibile unico | MUST |
| F2 | Routing multi-provider con fallback | MUST |
| F3 | Compressione contesto pre-invio | MUST |
| F4 | Lane privacy (no logging/training) | MUST |
| F5 | Lane locale su GPU workstation | SHOULD |
| F6 | Lane self-hosted BIOME (L40S) | COULD |
| F7 | Spend tracking e budget | SHOULD |
| F8 | Catalogo modelli aggiornabile senza editing manuale | SHOULD |
| F9 | Uso dell'abbonamento Claude Pro dove possibile | SHOULD |

### Non-funzionali
| ID | Requisito | Verifica |
|----|-----------|----------|
| N1 | Nessun segreto leggibile da altri utenti | `devops-audit.sh` §2 + CI |
| N2 | Gateway non raggiungibile dalla LAN | bind loopback + NAT |
| N3 | Ripristino < 5 min | snapshot VM (TC-06) |
| N4 | Config validabile prima del deploy | CI + `dockerd --validate` |
| N5 | Nessuna dipendenza non mantenibile da 1 persona | audit trimestrale |

## 5. Vincoli
- **Single maintainer**: ogni componente deve giustificare il costo di manutenzione.
- **Hardware**: laptop (RTX A2000 Laptop 4 GB, 31 GB RAM) + server BIOME (2× L40S 48 GB).
- **Rete**: BIOME solo via VPN di ateneo.
- **Licenze**: preferenza FOSS (MIT/Apache-2.0/GPL).
- **Dati**: ricerca non pubblicata → riservatezza.

## 6. Criteri di accettazione
- [ ] `test-all.sh` senza fallimenti (8 gruppi)
- [ ] `audit-integration.py` senza FAIL
- [ ] `devops-audit.sh` senza FAIL
- [ ] compressione misurata (TC-01)
- [ ] nessun client bypassa il gateway (TC-02)
- [ ] `.env` e chiavi con permessi 600
- [ ] snapshot `baseline` + **restore testato (TC-05)**
- [ ] deploy riproducibile da `INSTALL_GUIDE.md`

## 7. Rischi
| Rischio | Impatto | Prob. | Mitigazione |
|---|---|---|---|
| Gateway SPOF | alto | media | litellm pipx come fallback; snapshot |
| IP VM cambia | medio | **alta** | riserva DHCP + risoluzione per nome |
| Termini d'uso abbonamento via proxy | medio | bassa | variante A (diretto) come fallback |
| Backup mai testato | alto | media | TC-05 nei criteri + CI functional |
| Deriva della configurazione | medio | alta | audit script + CI |
| Stack oltre il mantenibile | alto | **alta** | non-goals espliciti; un tool per layer |

## 8. Backlog (fuori scope ora)
Virtual key per ricercatore BIOME · alerting · multi-agente/A2A · secret manager.
