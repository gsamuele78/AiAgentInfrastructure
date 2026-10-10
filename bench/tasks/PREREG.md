# Golden task e early stopper: pre-registrazione

Protocollo di [ADR-0021](../../docs/adr/0021-misurare-prima-di-adottare-e-oh-my-openagent.md);
[ADR-0025](../../docs/adr/0025-pratiche-openhands-importate-con-misura.md) §1.
Scritto prima di qualunque run su un modello vero.

## M1 — Baseline P0b (prima riga del registro del piano)
- `run.sh --model litellm/local-good --reps 5 --early-stop off` (45 run), poi lo stesso
  con `--model litellm/claude-opus-4-8` se il budget della chiave lo consente.
- Si registrano: pass@1 per tier con Wilson 95 %, $ per task risolto, token
  input/cached/output, mediana dei secondi, quota servita dal locale (`/spend/logs`).
- Nessuna soglia: è la baseline. Va nel registro di `docs/PLAN-STACK-VALIDATION.md`.

## M2 — Early stopper (adozione come default di `run.sh`)
- Ordine ABBA sullo stesso modello e giorno: `--early-stop off`, `on`, `on`, `off`,
  ognuno `--reps 5` su tutti i task.
- **Primaria**: costo totale della suite (somma `cost`), on vs off.
- **Adotta** (default `on`) se: costo on ≤ 70 % di off **e** pass@1 dei t\* con `on` non
  più basso di off oltre 5 punti **e** nessun run fermato dallo stop di `stop.txt` ha un
  controllo che passa (lo stop deve scattare solo su fallimenti certi).
- Altrimenti default `off` e lo stopper resta solo come tetto di budget.
- Nota onesta: lo shortlist iniziale chiedeva "verdetto uguale al 100 %"; con agenti non
  deterministici due run non hanno lo stesso verdetto nemmeno senza stopper, quindi il
  confronto si fa sui tassi, come sopra.

## Validazione strutturale (già in CI)
`validate.sh`: per ogni task V1 workspace vuoto bocciato, V2 soluzione promossa, V3
soluzione sbagliata bocciata, V5 regole di stop silenziose sulla soluzione; ≥2 task per
ruolo; early stopper E1–E3 su un agente finto. Prova del 2026-10-10: tutto verde, e
`run.sh` arriva in fondo con opencode 1.18.34 vero contro il gateway mock.

## Esito
_(M1 e M2 da compilare dopo i run: data, modello, TSV in `bench/results/`)_
