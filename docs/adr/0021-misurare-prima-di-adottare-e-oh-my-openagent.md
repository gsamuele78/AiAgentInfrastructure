# 0021 — Misurare prima di adottare: protocollo di benchmark; oh-my-openagent come primo caso

- **Status**: Proposed — piano in [`PLAN-STACK-VALIDATION.md`](../PLAN-STACK-VALIDATION.md) (P0b, e una riga "misura" in ogni passo)
- **Data**: 2026-10-10
- **Relazione**: applica 0006 (un tool per layer). Rende verificabili 0016–0020.

## Contesto
Ogni componente proposto (CCR, oh-my-openagent, skill, catena `auto`, cache)
arriva con una promessa di prestazioni. Oggi il repo non ha modo di dire se un
cambiamento **migliora** qualcosa: TC-01 dice se la compressione c'è, non quanto
vale; nessun test misura costo, latenza o tasso di successo degli agenti.
Senza baseline, "più veloce" e "migliore" sono opinioni.

Il caso concreto è **oh-my-openagent** (OmO, plugin per opencode, v5.1.29).
Dal sorgente:

| Aspetto | Fatto | Conflitto |
|---|---|---|
| Licenza | **Sustainable Use License 1.0** (fair-code, non OSI): uso solo interno o non commerciale; redistribuzione solo gratuita | preferenza FOSS (PRD §5) |
| Modelli | provider `anthropic-subscription`; due sistemi di fallback propri (`model-fallback`, `runtime-fallback`); il profilo `recommended` non usa mai OpenRouter | ADR-0016: abbonamento solo da Claude Code; routing nel gateway |
| Memoria / MCP / skill | sistema di memoria proprio, MCP propri (websearch, context7, grep_app), skill set propri, loader di compatibilità Claude Code | ADR-0006, ADR-0007 |
| Telemetria | PostHog **attiva di default** (`OMO_SEND_ANONYMOUS_TELEMETRY=0` per spegnerla) | dati di ricerca riservati (PRD §5) |
| Maturità | 226 commit in 60 giorni; 26 voci in `known-issues.md`; issue aperte su hang e caricamento del plugin | vincolo 30 min/mese |
| Valore dichiarato | orchestratore multi-agente, agenti in background, todo enforcer, loop `/ulw-*` | **non misurato da nessuno di indipendente** |

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Adottare OmO perché "migliora le prestazioni" | eventuale guadagno di produttività | nessuna prova; 4 conflitti con ADR esistenti |
| Respingerlo sulla carta | zero costo | si decide senza dati, che è proprio il difetto da correggere |
| **Protocollo di misura + esperimento A/B isolato** | decisione basata su dati, riusabile per ogni proposta futura | costa token e tempo una tantum |

## Decisione
### 1. Protocollo (vale per ogni passo del piano e ogni componente futuro)
1. **Pre-registrazione**: prima di misurare si scrivono nella PR la metrica
   primaria, la baseline, la soglia di adozione e la soglia di regressione.
   Niente soglie scelte dopo aver visto i numeri.
2. **Baseline e variante sulla stessa macchina, stessa sessione**, stesso
   modello, `temperature: 0`, stessi task, ordine alternato (A B B A) per
   neutralizzare cache e riscaldamento.
3. **Ripetizioni**: ≥5 run per task (gli agenti non sono deterministici);
   si riportano mediana e IQR, mai un singolo run. Per il successo dei task,
   `pass@1` su ≥20 tentativi complessivi, con intervallo di Wilson.
4. **Metriche — sempre le stesse colonne**:

   | Famiglia | Metrica | Fonte |
   |---|---|---|
   | Qualità | task risolti (verifica deterministica dell'artefatto) | golden task L6 (ADR-0019) |
   | Costo | $ per task risolto; token input / **cached** / output | `/spend/logs` di LiteLLM |
   | Efficienza contesto | rapporto di compressione headroom; cache hit ratio | `usage` (TC-01, TC-09) |
   | Latenza | tempo al primo token, tempo totale per task | log del gateway |
   | Routing | quota di richieste servite dal locale | campo `model` / spend logs |
   | Operatività | durata install, cambiamenti al 2° run (deve essere 0), tempo di rollback, durata `validate` | `stack.py` con `hyperfine` (MIT/Apache-2.0) |
   | Affidabilità | tasso di flakiness dei test (rossi che passano al rerun) | storico CI |

5. **Gate di adozione**: si adotta solo se la metrica primaria migliora oltre
   la soglia **e** nessuna metrica di guardia peggiora oltre la sua (default:
   costo +10%, latenza +20%, qualità −0 punti) **e** nessuna invariante di
   `AGENTS.md` si rompe. Esito, numeri e grezzi in un ADR o nel registro
   del piano.
6. **Telemetria del benchmark**: solo locale (DB del gateway + `bench/results/`
   come artefatto CI), niente nomi macchina né path personali (repo pubblico).

### 2. oh-my-openagent: esperimento, non adozione
- **Isolamento**: profilo opencode separato (`OPENCODE_CONFIG_DIR` dedicato), la
  config di produzione non viene toccata; versione pinnata; telemetria spenta
  (`OMO_SEND_ANONYMOUS_TELEMETRY=0`, `OMO_DISABLE_POSTHOG=1`); **unico
  provider il gateway** (nessun `anthropic-subscription`); memoria e MCP propri
  disattivati, così si misura l'orchestrazione e non altro.
- **Baseline**: opencode puro (`--pure`) sulla catena `auto`/`coding`.
- **Metrica primaria**: task risolti sui golden task di sviluppo e design.
  Guardie: costo per task risolto, durata, token.
- **Soglia** (pre-registrata qui): +15 punti percentuali di task risolti con
  costo per task risolto ≤ +10%.
- **Anche superando la soglia**, la licenza SUL resta un blocco per
  l'adozione nel repo pubblico: si porterebbero dentro le **idee** che hanno
  prodotto il guadagno (es. todo enforcer, agenti in background via subagent
  nativi di opencode), non il plugin. Adottare il plugin in sé richiede un ADR
  che superi la preferenza FOSS esplicitamente.

## Conseguenze
**Positive:** ogni passo del piano ha un numero prima e dopo; i "sembra più
veloce" diventano verificabili; la stessa infrastruttura (golden task + spend
logs) serve alle eval L6 e a Dependabot (una PR di aggiornamento può essere
confrontata con la baseline).

**Negative — da non minimizzare:**
- **Costa token**: 2 varianti × 5 run × 8 task su un modello cloud è una spesa
  reale a ogni esperimento. Budget su virtual key dedicata, e `cheap` dove
  la qualità non è la metrica.
- **I golden task sono pochi e nostri**: un miglioramento su 8 task di questo
  repo non generalizza. È un campione, e va detto in ogni risultato.
- `temperature: 0` riduce ma **non elimina** il non determinismo; i fallback
  della catena `auto` cambiano modello a metà run e vanno disattivati durante
  le misure (modello fisso).
- Più disciplina in ogni PR: pre-registrare le soglie è lavoro in più.

**Da rivedere se:** esiste un benchmark esterno affidabile per agenti su
infrastruttura (non solo SWE-bench, che misura codice applicativo); o OmO cambia
licenza.
