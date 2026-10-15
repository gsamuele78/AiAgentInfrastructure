# 0026 — pin-bump: mise propone gli aggiornamenti dei pin che Dependabot non sa leggere

- **Status**: Proposed
- **Data**: 2026-10-15
- **Relazione**: estende [0020](0020-dependabot-e-scala-di-autoaggiornamento.md) (stesso cooldown, stessa merge manuale di [0010](0010-ci-non-cd.md)); usa mise di [0024](0024-mise-per-gli-strumenti-utente-misurato.md); misura P1 di [0017](0017-manifest-componenti-e-validatore-unico.md).

## Contesto
La misura di P1 (`stack/components.toml`, `tracked`) era 22/26 (84 %), sotto
l'obiettivo del 90 %. Tre dei quattro componenti mancanti hanno il pin in
`stack/versions.conf`: Node (`NODE_VERSION`), mise (`MISE_VERSION`) e Ollama
(`OLLAMA_VERSION`). Nessun ecosistema di Dependabot legge quel file, né
`.tool-versions`, `mise.toml` o `.nvmrc` (verificato sulla documentazione di
GitHub, 2026-10-15). Il quarto, mattpocock, aspetta P4.

Il proprietario ha chiesto di arrivare al 90 % "con il programma scelto", cioè
mise (ADR-0024). mise sa già rispondere alla domanda giusta: `mise latest
<spec>` rispetta `MINIMUM_RELEASE_AGE`, quindi applica lo stesso cooldown di
ADR-0020 (provato: `node@24` con 7d → 24.21.0, con 400d → 24.7.0).
`mise outdated --bump` invece salta di major (Node 26): non si usa.

## Alternative considerate
| Opzione | Pro | Contro |
|---------|-----|--------|
| **pin-bump: `scripts/bump-pins.sh` + workflow settimanale che apre la PR** | usa mise già adottato; il pin resta dove lo leggono gli script; cooldown e merge manuale identici a Dependabot | un secondo bot da mantenere; le PR aperte da `GITHUB_TOKEN` non avviano la CI da sole |
| Renovate (regex manager su `versions.conf`) | legge qualsiasi file, un solo bot per tutto | servizio o app esterna in più, seconda configurazione accanto a Dependabot, rumore doppio sugli ecosistemi già coperti |
| Dockerfile "sentinella" (`FROM ollama/ollama:X`) letto da Dependabot | zero codice nuovo | file che nessuno costruisce: mente su cosa sia (già respinto in P1) |
| Pin in `mise.toml` + submodule o altro trucco | — | Dependabot non legge comunque `mise.toml`; sposta il problema |
| Restare a mano | niente da mantenere | 84 %: obiettivo non raggiunto, e "a mano" in pratica vuol dire "mai" |

## Decisione
Una riga di `stack/versions.conf` con il commento `# bump: <spec mise>` è
aggiornata da `scripts/bump-pins.sh`, che chiede a mise l'ultima versione con
cooldown 7 giorni e non torna mai indietro; `.github/workflows/pin-bump.yml` lo
esegue il lunedì e apre (o aggiorna) una PR dal ramo `bot/pin-bump`. In
`components.toml`, `tracked` vuol dire "pin letto da un bot che apre la PR":
Dependabot oppure pin-bump. Node resta sulla LTS 24 (`node@24`).

## Conseguenze
**Positive:**
- P1 a 25/26 (96 %): Node, mise e Ollama tracciati; resta solo mattpocock (P4).
- Il pin resta in un posto solo: gli script che leggono `versions.conf` non
  cambiano (i commenti in coda erano già tollerati da `ut_pins`, `tool_pin`, `source`).
- Sulle PR che toccano il bump, un job `--dry-run` prova con la rete vera che
  ogni spec si risolve; `test-scripts.sh` prova il comportamento con un mise finto.

**Negative / costi accettati:**
- Serve l'impostazione del repo **Allow GitHub Actions to create and approve
  pull requests** (`docs/GITHUB-SETUP.md` §4c): senza, il passo della PR fallisce rosso.
- Le PR aperte con `GITHUB_TOKEN` non avviano `validate.yml`: il workflow lo
  lancia sul ramo con `workflow_dispatch`. Il risultato si legge nei run del
  ramo, non nei check della PR. Un PAT o una GitHub App lo eviterebbero, al
  prezzo di un segreto da ruotare: per ora no.
- Un bump di Ollama cambia il comportamento dei modelli locali e uno di Node può
  rompere opencode: la PR è una proposta, si prova prima di unire (ADR-0010).
- Il backend `github:` di mise (mise, Ollama) usa l'API di GitHub: senza token
  il limite anonimo basta di rado, quindi il workflow passa `GITHUB_TOKEN`.

**Da rivedere se:** Dependabot aggiunge un ecosistema per mise o per
`.tool-versions`; i bot diventano tre (allora Renovate per tutto); il ramo
`bot/pin-bump` resta aperto senza merge per più di un mese (il bot non serve).
