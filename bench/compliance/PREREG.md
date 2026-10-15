# Sonde di conformità API sulla catena `auto`: pre-registrazione

Protocollo di [ADR-0021](../../docs/adr/0021-misurare-prima-di-adottare-e-oh-my-openagent.md);
pratica importata da OpenHands ([ADR-0025](../../docs/adr/0025-pratiche-openhands-importate-con-misura.md) §2).
Scritto **prima** di vedere i numeri; le soglie non si cambiano dopo.

## Domanda
La catena `auto` (ADR-0016) passa da Ollama ad Anthropic e poi a OpenRouter a metà
conversazione. Esiste una storia di messaggi che una lane accetta e un'altra rifiuta?
Se sì, il fallback stesso è un punto di rottura: il locale cade, il cloud risponde 400.

## Metodo
- 8 forme malformate (`probe.py`, da OpenHands `tests/integration/tests/a01..a08`, MIT).
- Lane: `auto` (la sua deployment = il locale) + i suoi fallbacks, letti dalla config.
- Ogni richiesta passa **dal gateway** con `disable_fallbacks: true`, `temperature: 0`,
  `max_tokens: 16`: si misura quello che vede il client, riparazioni di LiteLLM comprese.
- 1 run per cella (la risposta 2xx/4xx è deterministica per forma); se una cella è
  `n/a` (5xx, timeout, 429) si ripete fino a 3 volte, poi resta `n/a`.
- Chiave: virtual key dedicata con budget (`BENCH_KEY`), mai la master key.

## Metrica e soglie
| ID | Metrica | Soglia |
|---|---|---|
| C1 (primaria) | celle divergenti: forme accettate da una lane e rifiutate da un'altra disponibile | **≥ 1 → il test diventa bloccante** nel workflow funzionale (L5) e la forma va in `AGENTS.md` come trappola |
| C2 | lane disponibili | ≥ 2, altrimenti la misura non vale e si rifà |
| C3 (guardia) | costo di un run completo (`/spend/logs`, chiave del bench) | ≤ 0,05 $ |

Se C1 = 0: le sonde restano **settimanali e non bloccanti**, per accorgersi quando un
provider o un aggiornamento di LiteLLM cambia comportamento.

## Cosa NON dice
- Non dice se l'agente produce davvero quelle storie: dice solo cosa succede se le produce.
- Il risultato vale per la versione di LiteLLM e dei provider del giorno del run.

## Esito
_(da compilare dopo il primo run sul gateway reale: data, versione LiteLLM, TSV in `bench/results/`)_
