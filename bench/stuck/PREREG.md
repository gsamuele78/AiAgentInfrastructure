# Loop degli agenti: pre-registrazione (solo misura)

Protocollo di [ADR-0021](../../docs/adr/0021-misurare-prima-di-adottare-e-oh-my-openagent.md);
euristiche di OpenHands `stuck_detector.py` (MIT;
[ADR-0025](../../docs/adr/0025-pratiche-openhands-importate-con-misura.md) §7).

## Domanda
I modelli piccoli della lane locale (7b, 3b) finiscono in loop più spesso di quelli cloud,
abbastanza da giustificare un guard?

## Metodo
- `analyze.py` sulle tracce di `bench/tasks/run.sh` (tutte le esecuzioni di M1 e M2), per
  modello. Soglie di OpenHands invariate (4 / 3 / 3 / 6, finestra 20 eventi).
- Controllo manuale: 10 tracce segnalate scelte a caso, giudicate "loop vero" o no.

## Soglia (scritta prima)
Si costruisce un guard (opzione di `early_stop.py` prima, plugin del client poi) **solo se**
≥ 5 % delle tracce della lane locale è segnalato **e** ≥ 8 delle 10 controllate a mano
sono loop veri. Altrimenti si registra il numero e ci si ferma.

## Esito
_(da compilare dopo M1)_
