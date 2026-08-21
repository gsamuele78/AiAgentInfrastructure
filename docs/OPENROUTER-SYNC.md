# Sincronizzazione del catalogo OpenRouter (ADR-0004, requisito F8)

`scripts/sync_openrouter.py` riconcilia il catalogo OpenRouter dentro il DB di
LiteLLM. Chiude il gap fra ADR-0004 — deciso il 2026-06-24 — e il codice, che
per mesi si è fermato a `STORE_MODEL_IN_DB=true` senza il loop di
riconciliazione che l'ADR prescrive.

## Perché serve
Il wildcard `openrouter/*` in `litellm_config.yaml` **instrada** ma:
- non popola `/v1/models` → il dropdown dei client resta vuoto;
- non porta il pricing → lo spend tracking (F7) resta a zero.

Registrare a mano centinaia di modelli che cambiano ogni settimana è
insostenibile per un maintainer singolo, e rigenerare il file richiederebbe un
restart. La riconciliazione via API non lo richiede: è il motivo della scelta.

## Uso
```bash
source clients/shell-env.sh          # serve LITELLM_MASTER_KEY

./scripts/sync_openrouter.py --dry-run          # stampa il piano, non tocca nulla
./scripts/sync_openrouter.py                    # applica, chiedendo conferma
./scripts/sync_openrouter.py --yes              # senza conferma (per cron)
./scripts/sync_openrouter.py --filter anthropic # solo gli id che contengono la stringa
./scripts/sync_openrouter.py --no-prune         # aggiunge e aggiorna, non cancella
```

Variabili: `LITELLM_MASTER_KEY` (obbligatoria), `LITELLM_PROXY`
(default `http://127.0.0.1:4000`), `OPENROUTER_MODELS_URL`.

Uscite: `0` allineato · `1` errore durante l'applicazione · `2` prerequisiti
mancanti (master key assente, gateway o catalogo irraggiungibili).

## La proprietà di sicurezza che conta
Lo script **cancella solo i modelli che ha creato lui**, riconosciuti da
`model_info.managed_by == "sync_openrouter"`. I modelli curati a mano —
`claude-*`, `anthropic-claude`, `or-private`, `or-pareto-code`, `local-fast`,
`local-good`, `biome-coder` — non vengono mai toccati, qualunque cosa risponda
OpenRouter.

Seconda rete di protezione: con `--filter` il catalogo scaricato è parziale, e
il prune viene **disattivato automaticamente**. Senza, un `--filter anthropic`
cancellerebbe tutto il resto del catalogo gestito.

## Cosa scrive
Per ogni modello: `model_name = openrouter/<id>`, `litellm_params.model =
openrouter/<id>`, `api_key = os.environ/OPENROUTER_API_KEY`, e in `model_info`
il marchio `managed_by`, il pricing (`input_cost_per_token`,
`output_cost_per_token`) e `max_input_tokens` quando OpenRouter lo espone.
Un pricing pari a `0` o `-1` viene trattato come ignoto e omesso.

## Quando eseguirlo
Non è automatico, e non deve esserlo: ADR-0010 dice che la CI valida, non
rilascia. A mano quando serve un modello nuovo, oppure da cron sulla VM:
```bash
# crontab -e nella VM — lunedì 06:30, dopo il backup
30 6 * * 1 cd ~/llm-services && LITELLM_MASTER_KEY=$(cat ~/.master.key) \
  /path/to/sync_openrouter.py --yes >> ~/sync.log 2>&1
```

## Endpoint usati, e perche'
| Operazione | Endpoint | Nota |
|---|---|---|
| Aggiunta | `POST /model/new` | e' un **create** secco (`_add_model_to_db` → `table.create`): rimandarci un id esistente duplica o va in errore, non fa upsert |
| Aggiornamento prezzo | `POST /model/update` | aggiorna **solo** `litellm_params`, in merge con l'esistente, e non tocca `model_info` — il marchio `managed_by` sopravvive |
| Rimozione | `POST /model/delete` | per `model_info.id` |

Il pricing sta in `litellm_params`, non in `model_info`, per due ragioni: è lì
che LiteLLM lo accetta (`LiteLLMParamsTypedDict`, sezione *custom pricing*), ed
è l'unico blob che `/model/update` sa aggiornare. **Il diff rilegge il prezzo da
`litellm_params`**: `/model/info` riempie `model_info` con i default della cost
map di LiteLLM, quindi confrontarsi con quello significherebbe fare il diff con
un valore che non abbiamo scritto noi — e non aggiornare mai, o riscrivere ogni
volta.

## Limiti noti
- **Sincronizza tutto il catalogo** (centinaia di modelli). È ciò che ADR-0004
  voleva — il problema era il dropdown vuoto — ma un elenco lunghissimo ha un
  costo di usabilità. `--filter` esiste per chi preferisce un sottoinsieme, al
  prezzo di rinunciare al prune.
- **Non gestisce i rate limit di OpenRouter**: una sola GET al catalogo, quindi
  in pratica non è un problema, ma non c'è retry.
- **Il diff guarda solo il pricing**, non il resto dei metadati: un modello che
  cambia solo `context_length` non viene aggiornato.
