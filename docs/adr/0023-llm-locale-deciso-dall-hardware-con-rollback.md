# 0023 — LLM locale: l'hardware sceglie fra i modelli del gateway; installazione verificata, annullabile e rimovibile

- **Status**: Accepted
- **Data**: 2026-10-10
- **Relazione**: applica 0008 (Ollama su host), 0016 (catena `auto`) e la regola 1
  di 0018 (registro dei run), che resta *Proposed* per il resto dello stack.
  Non supersede nulla.

## Contesto
Richiesta: rilevare dall'hardware quale LLM locale si può deployare, installarlo
e farlo girare se l'hardware regge, con verifiche a ogni passo, rollback
disponibile durante l'installazione e una rimozione.

Lo stato prima di questa decisione, letto nel codice:

1. **Due tabelle hardware → modello**, in `detect-hardware.sh` e in
   `setup-ollama.sh`, già divergenti (valori di offload diversi).
2. **Il modello scelto non era quello che il gateway usa.** Con ≥ 20 GB di VRAM
   si scaricava solo `qwen2.5-coder:14b`, mentre `auto` e `local-good` puntano
   a `qwen2.5-coder:7b`: il primo anello di `auto` rispondeva "model not found"
   e il gateway passava al cloud **in silenzio**, a ogni richiesta.
3. **Nessuna verifica bloccante**: i controlli finali erano avvertenze; un
   Ollama in ascolto su `0.0.0.0` (invariante #3) non fermava niente.
4. **Il download falliva dopo il bind**: `ollama pull` parla a `127.0.0.1` per
   default, ma il servizio era stato appena spostato su `virbr0`.
5. **Nessun rollback, nessuna rimozione**, nessun gate su RAM o disco; su un OS
   atomico l'installer upstream fallisce (crea l'utente con home in `/usr/share`,
   in sola lettura).

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Correggere solo i bug, tenere la tabella per VRAM | poco codice | il disallineamento con il gateway resta possibile a ogni modifica di una delle due parti |
| Ansible (playbook Ollama) | idempotenza e `--check` nativi | già valutato e rinviato in ADR-0017: un secondo linguaggio per un solo componente |
| `stack.py` (P3) prima, poi Ollama | un solo meccanismo per tutto | P3 è giorni di lavoro; il deploy è adesso |
| **Tabella unica sui modelli del gateway + registro dei run in bash** | stesso formato che `stack.py` erediterà; provabile su un sistema finto | codice nostro, stime di memoria da confermare sull'hardware reale |

## Decisione
1. **I modelli sono quelli del gateway.** `scripts/lib/llm-plan.sh` conosce solo
   i modelli che `litellm_config.yaml` referenzia (`LLM_MODEL_SMALL`,
   `LLM_MODEL_MAIN`). L'hardware decide quali entrano (VRAM, RAM utilizzabile =
   totale − VM − 4 GB host, disco), con quattro verdetti: `gpu`, `gpu-offload`,
   `cpu` (solo il 3B: `auto` va al cloud per scelta, perché un 7B su CPU come
   primo anello è più lento del cloud), `none` (nessuna modifica, uscita 3).
   `detect-hardware.sh` e `setup-ollama.sh` usano la stessa funzione.
2. **Ogni passo verifica il proprio risultato.** Controlli duri (binario
   risponde; servizio attivo e in ascolto **solo** su `virbr0`; ogni modello del
   piano presente; il modello principale **risponde** a una richiesta reale)
   → rollback automatico del run. Controlli morbidi (firewall, raggiungibilità
   dalla VM, velocità, coerenza delle lane) → avvertenza, nessun rollback.
3. **Registro dei run** (`scripts/lib/journal.sh`, regola 1 di ADR-0018): ogni
   modifica annotata prima di farla, rollback in ordine inverso, run idempotente
   = registro vuoto e rimosso. `--rollback [RUN]` annulla un run passato,
   Ctrl-C annulla quello in corso.
4. **`--remove`** disinstalla tutto e **verifica** che non resti niente; non è
   annullabile (si reinstalla) e chiede conferma esplicita.
5. **Versione di Ollama pinnata** in `stack/versions.conf` (`OLLAMA_VERSION`,
   accettato dall'installer ufficiale): Dependabot non lo legge, è dichiarato.
6. **OS atomico senza Ollama: raccomandazione, non azione** (S1 di ADR-0018).

## Conseguenze
**Positive:** `auto` e le lane locali puntano sempre a modelli presenti, o lo
script lo dice; un'installazione a metà non resta mai sul sistema; rilanciare è
sicuro; i 48 scenari di `tests/setup-ollama/run.sh` girano in CI senza GPU né
systemd; il formato del registro è quello che `stack.py` riuserà.

**Negative — da non minimizzare:**
- **Le soglie di memoria sono stime** (pesi Q4 + KV a 16k in q8 + margine), non
  misure su questa macchina. Il primo deploy le conferma o le corregge
  (`DEPLOY-RUNBOOK.md` passo 10, token/s nella scheda).
- **Il sistema finto non è il sistema vero**: gli stub replicano il
  comportamento documentato di systemd, `ss`, del CLI e dell'API di Ollama, non
  i loro bug. L'installer vero di ollama.com e una GPU vera li prova solo il
  primo deploy.
- **Il rollback di un run che ha installato Ollama cancella `/usr/share/ollama`**,
  compresi modelli scaricati a mano **dopo** quel run. Il rollback di un run che
  ha trovato Ollama già installato invece non tocca né il binario né i modelli
  preesistenti.
- **Su Bazzite non è automatico**: con Ollama da brew il servizio è utente, e lo
  script (che gestisce il servizio di sistema) si fermerebbe annullando il run.
- Il verdetto `cpu` rinuncia al 7B anche dove girerebbe: è una scelta di
  esperienza d'uso, non un limite tecnico. `MODELS=...` la scavalca.
- Più codice bash da mantenere: ≈ 600 righe fra script e librerie (prima ≈ 190), ≈ 230 di test.

**Da rivedere se:** cambiano i modelli delle lane locali (le stime vanno
aggiornate con loro); arriva `stack.py` (P3), che deve assorbire `journal.sh`
invece di affiancarlo; le misure del primo deploy smentiscono le soglie.
