# TEST PLAN

## Livelli
| Livello | Verifica | Dove | Auto |
|---|---|---|---|
| L1 Statico | sintassi, lint, segreti | CI `validate.yml` | ✅ |
| L1b Script | contratti, invarianti sicurezza, dry-run | `test-scripts.sh` (CI) | ✅ |
| L2 Build | immagine + gate callback | CI `validate.yml` | ✅ |
| L3 Config | client puntano dove devono | `audit-integration.py` | ✅ |
| L4 Infra | best practice deploy | `devops-audit.sh` | ✅ |
| L5 Funzionale | catena reale, compressione | `test-all.sh` | ✅ runner self-hosted, **bloccante** (ADR-0015) |
| L6 Manuale | auth, restore, snapshot | checklist | ❌ |

## Matrice requisiti → test
| Req | Test | Livello |
|---|---|---|
| F1 | `test-all.sh gateway` — liveness + /v1/models | L5 |
| F2 | `test-all.sh gateway` — alias coding/smart/cheap | L5 |
| F3 | `test-all.sh compress` — TC-01 | L5 |
| F4 | header provider OpenRouter | L6 |
| F5 | `test-all.sh local` — verifica che Ollama risponda; `local-fast`/`local-good` sono nel config versionato ma il test **non** verifica che il gateway li instradi | L5 |
| F6 | `test-all.sh biome` — `biome-coder` è nel config versionato; il test resta `skip` se il gateway non è raggiungibile o la VPN è giù | L5 |
| F7 | `/spend/logs` | L5 |
| F8 | `sync_openrouter.py --dry-run` — vedi `OPENROUTER-SYNC.md` | L5 |
| F9 | `/status` in Claude Code — TC-04 | L6 |
| N1 | `devops-audit.sh` §2 + CI `secrets` | L1/L4 |
| N3 | TC-05 restore + TC-06 snapshot | L6 |
| N4 | CI `syntax` + `build` | L1/L2 |

**TC-07 Invarianti di sicurezza negli script** — `test-scripts.sh` verifica nel
*codice* che: Ollama non venga mai bindato su `0.0.0.0`, postgres non pubblichi
porte, vLLM stia su loopback, le config siano `:ro`, `cleanup-host` faccia il
pre-check sul gateway (ordine PSE), `create-vm --destroy` chieda conferma, e
nessun segreto sia hardcoded. Gira su runner GitHub: nessuna dipendenza dall'host.

> **Dipendenze opzionali:** `test-scripts.sh` usa `pyyaml` se presente, altrimenti
> ripiega su `docker compose config` o su verifiche testuali. Un controllo non
> eseguibile risulta **skip**, mai fail: un test che fallisce per motivi
> ambientali erode la fiducia nella suite più di un test assente.

**TC-08 Dry-run non distruttivi** — ogni script che modifica il sistema espone
`--dry-run` e deve completarlo **anche su una macchina vuota**. Se un dry-run
crasha, crasherebbe anche l'esecuzione reale.

> Fino al 2026-08-21 questo caso era verificato con un `grep -- '--dry-run'` su
> una lista di 4 script scritta a mano: cercare la stringa non dimostra che il
> dry-run funzioni, e infatti `create-vm.sh --dry-run` usciva 1 (`USER: unbound
> variable`, poi `die` sui prerequisiti). Ora `test-scripts.sh` §2 deriva la
> lista da `scripts/*.sh` — l'unica eccezione sono gli script dichiarati
> read-only — e §2b **esegue** ogni dry-run con `env -u USER`.

## Casi critici
**TC-01 Compressione** — payload JSON 400 righe; atteso `prompt_tokens` ≪ payload
grezzo. Fallimento probabile: callback non caricato (il gate build lo intercetta).

**TC-02 Nessun bypass del gateway** — `audit-integration.py` §2/§5; 0 riferimenti
a `:8787` o a URL di provider. Intercetta la regressione più frequente: un tool
che si riscrive la config (`headroom wrap`).

**TC-03 Nessuna collisione di memoria** — ≤1 memory MCP; Serena con memory esclusa.

**TC-04 Abbonamento non scavalcato** — nessuna `ANTHROPIC_API_KEY`/`AUTH_TOKEN`;
`/status` indica l'abbonamento. Una variabile residua dirotta **silenziosamente**
la fatturazione: per questo è un test dedicato.

**TC-05 Restore del backup** — `restore-test.sh`: dump → DB scratch → verifica
tabelle → cleanup. **Obbligatorio almeno una volta.** Un backup non testato non è
un backup. Girava in CI `functional.yml`, ma vedi il limite qui sotto: il job non
può fallire, quindi finora "automatizzato" non voleva dire "verificato".

**TC-06 Rollback via snapshot** — snapshot → modifica distruttiva → revert →
`test-all.sh`. Atteso < 5 min.

## Esecuzione
```bash
# L1/L2 automatici a ogni push
./scripts/devops-audit.sh && ./scripts/audit-integration.py && ./scripts/test-all.sh
./scripts/restore-test.sh        # TC-05
```

## I test funzionali possono fallire (ADR-0015)
`functional.yml` **non ha più** `continue-on-error: true` sul job. Fino al
2026-08-21 ce l'aveva, e TC-01, TC-02, TC-04 e TC-05 giravano senza poter
fallire: un test che non può fallire non è un test. È così che la modalità
locale rotta di `restore-test.sh` è passata inosservata.

Il prezzo, dichiarato in ADR-0015: **a laptop spento il run settimanale risulta
rosso**. Un rosso «no runner» non è un rosso «test fallito» — si distinguono
aprendo il run. `functional` non è fra gli status check richiesti su `main`
(`GITHUB-SETUP.md` §2: `syntax`, `secrets`, `docs`), quindi non blocca i merge:
è un segnale da guardare, non un cancello. Se il rosso diventa costante perché
il laptop è sempre spento, la decisione va rivista, non subita.

**TC-08 e `sync_openrouter.py`:** il dry-run di questo script calcola un diff,
quindi ha bisogno del catalogo OpenRouter *e* del gateway. Su una macchina vuota
esce `2` («prerequisiti mancanti»), che è il comportamento corretto — un rifiuto
motivato, non un crash — ed è per questo che `test-scripts.sh` §2b lo salta
esplicitamente invece di eseguirlo. Il suo test vero è F8, livello L5.

## Nota: gli alias `coding` / `smart` / `cheap`
Non sono in `model_list`: esistono solo come chiavi di `litellm_settings.fallbacks`.
Funzionano perché il primo tentativo su un model group inesistente solleva
un'eccezione che `Router.async_function_with_fallbacks` intercetta per cercare i
fallback. Conseguenze: **non compaiono in `/v1/models`** (per questo `test-all.sh`
li segna `skip` e non `fail`), e il comportamento dipende da un dettaglio
implementativo di LiteLLM. Il test che conta è la completion reale su `cheap` in
`test-all.sh gateway`. Se si vuole un contratto esplicito, l'alternativa è
`router_settings.model_group_alias` — cambia il routing, quindi va deciso, non
subito.

## Criteri di uscita
L1–L5 senza fallimenti · TC-05 eseguito con esito positivo · TC-04 verificato ·
snapshot `baseline` presente.

## Regressioni sorvegliate
| Regressione | Sintomo | Test |
|---|---|---|
| `headroom wrap` riscrive i config | i tool tornano a :8787 | TC-02 |
| update immagine rompe il callback | nessuna compressione | build gate + TC-01 |
| IP VM cambia | gateway "giù" | `test-all.sh gateway` |
| un tool aggiunge la sua memoria | stato incoerente | TC-03 |
| variabile ANTHROPIC_* residua | fatturazione inattesa | TC-04 |

## Registro esecuzioni TC-05 (compilare)
| Data | Esito | Note |
|------|-------|------|
|      |       | *da eseguire la prima volta* |
