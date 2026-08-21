# 0014 — Headroom standalone sulla sola lane abbonamento Claude Code
- **Status**: Accepted
- **Data**: 2026-08-21
- **Relazione con 0001 e 0003**: non li supersede. Dichiara **un'eccezione
  circoscritta**, perché un'eccezione praticata e non scritta è peggio di
  un'eccezione scritta.

## Contesto
Claude Code non passa dal gateway: usa l'abbonamento Pro via OAuth (ADR-0001 e
`DUAL-AUTH.md`). È una scelta economica — l'abbonamento è già pagato — ma ha un
costo tecnico: **la lane più usata è l'unica senza compressione**, perché la
compressione vive come callback dentro LiteLLM (ADR-0003) e su quella lane
LiteLLM non c'è.

`DUAL-AUTH.md` offriva tre varianti; la (B) reintroduce il proxy headroom
standalone su `:8787` con upstream Anthropic. Era documentata come opzione
neutra, ma contraddice due invarianti dichiarate in `AGENTS.md`:

- **#1** un solo gateway, nessun client parla direttamente a un provider;
- **#2** la compressione è un callback dentro LiteLLM, non un proxy davanti.

Peggio: `cleanup-host.sh` disinstalla proprio quel proxy e `audit-integration.py`
lo segnala come residuo da rimuovere. Chi usa la variante B viene contraddetto
dai suoi stessi script. Questo ADR chiude la contraddizione dichiarandola.

## Alternative considerate
| Opzione | Compressione su Claude Code | Invarianti | Costo |
|---|---|---|---|
| Variante A — abbonamento diretto | ❌ nessuna | ✅ intatte | zero, ma si rinuncia |
| Variante C — abbonamento via LiteLLM | ✅ (callback) | ✅ intatte | vedi la nota sui termini d'uso in `CLAUDE-SUBSCRIPTION.md` |
| **Variante B — headroom standalone** | ✅ | ⚠️ **eccezione a #1 e #2** | un servizio in più da mantenere |
| Rinunciare del tutto a headroom | ❌ | ✅ | si perde G3 del PRD |

La C sarebbe la più pulita sul piano architetturale, ma instrada il traffico
dell'abbonamento attraverso un proxy: è la variante su cui pesa il dubbio sui
termini d'uso. La B tiene il traffico su una rotta diretta verso Anthropic e
aggiunge solo la compressione.

## Decisione
La variante B è **ammessa, per la sola lane abbonamento di Claude Code**, entro
questi limiti:

1. `headroom.service` fa da proxy **solo** con upstream `api.anthropic.com`.
   Mai con upstream OpenRouter — è esattamente l'errore trovato in
   `CURRENT-STATE.md`, dove headroom scavalcava LiteLLM.
2. **Nessun altro client** usa `:8787`. opencode, OpenChamber e Codex restano
   sul gateway: l'invariante #1 vale per loro senza eccezioni.
3. I template versionati in `clients/` **non** contengono `:8787`. La variante B
   si configura sulla macchina, non nel repo — così un `git pull` non riabilita
   silenziosamente un proxy a chi ha scelto A o C.
4. `cleanup-host.sh` non rimuove `headroom.service` se la variante B è attiva:
   va invocato con `KEEP_HEADROOM=1`, oppure risponde no alla conferma.

## Conseguenze
**Positive:** la lane più usata guadagna la compressione (PRD G3) senza
instradare l'abbonamento attraverso il gateway.

**Negative — da non minimizzare:**
- Due punti di compressione invece di uno: un aggiornamento di `headroom-ai` può
  cambiare il comportamento su una lane e non sull'altra, e non c'è nessun test
  che confronti le due. TC-01 misura solo la lane LiteLLM.
- Un servizio systemd in più a carico del maintainer, contro il vincolo dei
  30 min/mese.
- L'invariante #1 smette di essere assoluta: chi legge `AGENTS.md` deve
  ricordarsi dell'eccezione. Per questo è annotata anche lì.
- Se `headroom.service` muore, Claude Code smette di funzionare in modo poco
  diagnosticabile — un `ANTHROPIC_BASE_URL` che punta a una porta chiusa.

**Enforcement:** `scripts/test-scripts.sh` §3 verifica che i template in
`clients/` non contengano `:8787` (limite 3). `audit-integration.py` segnala
`headroom.service` attivo come **INFO** con rimando a questo ADR, non più come
residuo da rimuovere.

**Da rivedere se:** il dubbio sui termini d'uso della variante C si scioglie (a
quel punto C è preferibile e questa eccezione va chiusa), oppure se headroom
acquista un modo di comprimere la lane abbonamento senza un processo separato.
