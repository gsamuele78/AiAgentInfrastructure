# Compattazione presto o tardi: pre-registrazione

Protocollo di [ADR-0021](../../docs/adr/0021-misurare-prima-di-adottare-e-oh-my-openagent.md);
idea di OpenHands `context/condenser/README.md` (MIT;
[ADR-0025](../../docs/adr/0025-pratiche-openhands-importate-con-misura.md) §8).
Non si importa il condenser di OpenHands: il layer è di opencode (ADR-0006).

## Domanda
Compattare prima e più spesso (B) costa meno di compattare all'ultimo (A), senza perdere
task risolti? Conta soprattutto su `local-good` (contesto 12288), dove la compattazione
scatta davvero; sulle lane cloud da 200k i golden task non la raggiungono.

## Metodo
- A = `clients/opencode.jsonc` (oggi `reserved: 10000`); B = `variant.py --reserved 7000`.
- `bench/tasks/run.sh --model litellm/local-good --reps 5 --tier t --config <A|B>`, ordine ABBA.
- Metriche: token input totali (primaria), rapporto token in cache / input, pass@1 dei t\*.

## Soglie (scritte prima)
Si adotta B (si cambia `compaction.reserved` nel client) se: token input ≤ 85 % di A
**e** pass@1 dei t\* non più basso **e** rapporto di cache non peggiore di 5 punti.
Altrimenti A resta.

## Limite dichiarato
I golden task sono brevi: se in A la compattazione scatta in meno del 20 % dei run, la
misura non dice niente e si rifà con un task lungo dedicato.

## Esito
_(da compilare)_
