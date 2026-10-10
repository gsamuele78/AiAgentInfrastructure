# 0024 — mise gestisce lo strato S3 (Node, opencode, tool Python), lo script resta come ripiego; scelto per misura

- **Status**: Accepted (2026-10-10, mise primario + script di ripiego) — adozione in `scripts/install-user-tools.sh`
- **Data**: 2026-10-10
- **Relazione**: chiude la regola 5 di [0018](0018-installazione-idempotente-e-rollback-debian-bazzite.md) ("mise vs brew"); applica il protocollo di [0021](0021-misurare-prima-di-adottare-e-oh-my-openagent.md); `uv` per i tool Python resta come in [0022](0022-standard-condiviso-con-infra-iam-pki.md).

## Contesto
ADR-0018 mette Node, opencode e i tool Python nello strato S3 (`$HOME`, versione
pinnata, rollback = reinstallare il pin precedente) e lascia aperto *con cosa*:
`mise` o `brew`. Il proprietario ha chiesto se esista un metodo più pulito per
installare e tornare indietro (venv, distrobox, ...) e di misurarne accuratezza e
prestazioni. L'host è Bazzite 44 (ostree): niente cambi S1 automatici.

Soglie e regola di decisione sono state scritte **prima** dei numeri in
[`bench/install-methods/PREREG.md`](../../bench/install-methods/PREREG.md). Pin
di prova: Node 24.20.0→24.21.0, opencode 1.18.33→1.18.34, graphify 0.9.73→0.9.74.
Sequenza: installa A, rilancia ×10, aggiorna a B e torna ad A ×5, in una `$HOME`
usa e getta. CI: workflow `bench-install`, run del 2026-10-10 su `45d4867`.

## Risultati
Mediane, tempo reale. A3/A4 su 5 ripetizioni.

| Metodo | OS | A1 pin esatti | A2 file cambiati al rilancio | A3 versioni dopo rollback | A4 stato dopo rollback | P1 install (s) | P2 rilancio (s) | P3 rollback (s) | R1 residui | Esito |
|---|---|---|---|---|---|---|---|---|---|---|
| mise | Debian 13 | sì | 0 | 5/5 | 5/5 | 7,5 | 0,01 | **0,02** | 0 | ammesso |
| mise | Fedora 44 | sì | 0 | 5/5 | 5/5 | 6,2 | 0,02 | **0,02** | 0 | ammesso |
| mise | Ubuntu 24.04 | sì | 0 | 5/5 | 5/5 | 17,4 | 0,01 | **0,02** | 0 | ammesso |
| baseline (script nostro) | Debian 13 | sì | 0 | 5/5 | 5/5 | 9,4 | 0,69 | 4,93 | 11 | ammesso |
| baseline | Fedora 44 | sì | 0 | 5/5 | 5/5 | 10,4 | 0,72 | 5,01 | 11 | ammesso |
| baseline | Ubuntu 24.04 | sì | 0 | 5/5 | 5/5 | 10,6 | 0,72 | 4,98 | 11 | ammesso |
| nix | Ubuntu 24.04 | **no** (node 24.21.0, opencode 1.15.10) | 0 | 5/5 | 5/5 | 21,4 | 0,43 | 0,19 | 0 | escluso: A1, G1 |
| brew | Ubuntu 24.04 | **no** (node 24.21.0, opencode **v2.0.25**) | 0 | n/a | n/a | 97,6 | 0,82 | — | 2 | escluso: A1, A3, A4 |
| distrobox | Ubuntu 24.04 | sì | 1¹ | 5/5 | 5/5 | 10,8 | 0,88 | **72,5** | —¹ | escluso: P3 > 60 s |

¹ Il file cambiato è il database di podman e i 10 539 "residui" sono soprattutto
layer dell'immagine: la configurazione dello storage del benchmark non è stata
rispettata da podman. È un difetto della misura, non di distrobox, e non cambia
l'esito: distrobox è escluso comunque per P3.

**Letture che contano:**
- **nix** torna indietro bene (0,19 s, 5/5), ma pinna una *release* di nixpkgs,
  non la versione del singolo tool: opencode 1.15.10 invece di 1.18.33. Su
  Bazzite serve inoltre `/nix` alla radice, cioè un cambio S1 (G1).
- **brew** installa quello che la formula offre oggi: su Ubuntu opencode è
  **2.0.25**, una major diversa dal pin, senza un modo supportato di chiedere
  1.18.33 né di tornarci.
- **distrobox** isola Node e opencode nel contenitore, ma ogni rollback ricrea il
  contenitore (≈ 72 s), e ciò che sta in `$HOME` (graphify via `uv`, i log di npm,
  la config) **sopravvive** alla rimozione: non è un rollback del sistema. Resta
  utile solo come sandbox per agenti (memoria di progetto), non per il deploy.
- **baseline** è corretta, ma ogni rollback reinstalla opencode da npm (≈ 5 s) e
  lascia log in `~/.npm/_logs`; sono tre meccanismi da mantenere (tarball Node,
  npm, uv).
- **mise** tiene le versioni affiancate: il rollback è cambiare il file di
  config e rilanciare `mise install`, che non scarica nulla (0,02 s su tre OS).

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| **mise** (MIT) | un file per tre runtime; pin esatti; rollback 0,02 s; zero residui | un gestore in più; progetto con un maintainer principale; scarica da GitHub; il backend npm non esegue i postinstall (vedi sotto) |
| baseline (script nostro) | nessuno strumento nuovo; ammesso su tutto | 3 meccanismi; rollback 250× più lento; codice nostro da mantenere |
| brew | già nell'immagine Bazzite | nessun pin, nessun rollback; versione diversa dal pin già oggi |
| nix / home-manager (LGPL-2.1) | rollback per generazioni | pin per release, non per tool; `/nix` = cambio S1 su ostree |
| distrobox (GPL-3.0) | Node/opencode isolati dal sistema | `$HOME` condivisa: non è un rollback; 72 s per tornare indietro |

## Decisione
Lo strato S3 è gestito da **mise**, con lo script della baseline come ripiego (punto 5): un `mise.toml` in `stack/` dichiara Node,
opencode (backend `npm:`) e i tool Python (backend `pipx:` eseguito da `uv`); il
rollback è il `mise.toml` precedente da git + `mise install`.

Dettagli vincolanti:
1. **Script di installazione npm**: mise per default non li esegue (default
   sicuro, misurato in P2b: opencode si installa ma non parte). Si abilitano
   **per nome** con `allow_builds = ["<pacchetto>"]`, mai globalmente.
2. **Il binario di mise** si installa dalla release ufficiale con verifica
   sha256 (`SHASUMS256.txt`) in `~/.local/bin`; la versione è un pin in
   `stack/versions.conf`. Su Bazzite è S3: nessun `rpm-ostree`, nessun reboot.
3. **Pin** (cooldown ≥ 7 giorni, ADR-0020): Node **24.21.0** (LTS),
   opencode **1.18.34**, mise **2026.10.0**. opencode in `stack/package.json`
   (Dependabot npm lo segue); Node e mise in `stack/versions.conf` (a mano).
4. `uv` resta il motore dei tool Python (via `pipx.uvx = true`), e
   `uvx --from serena-agent==<pin>` nei client non cambia.
5. **Ripiego: lo script della baseline**, che ha superato le stesse soglie
   (A1–A4 pieni su tre OS, rollback ≈ 5 s). Vale la pena tenerlo perché il
   caso c'è già: in uno degli ambienti di questa misura le release di GitHub
   erano bloccate dal proxy e mise **non si poteva installare**, mentre
   nodejs.org, npm e PyPI rispondevano. Regole perché non diventi una seconda
   verità:
   - **stessi pin**: entrambi i percorsi leggono `stack/` e nient'altro; il
     file di mise si *genera* dai pin, non si scrive a mano;
   - **stessa verifica**: dopo l'installazione le versioni sul `PATH` devono
     essere i pin, qualunque percorso sia stato usato;
   - **mai silenzioso**: `auto` usa mise se c'è o si installa con verifica
     sha256; se no passa allo script **con un avviso** e lo scrive nel
     journal; `--backend mise` non ripiega mai (fallisce);
   - **provato in CI**: il benchmark `bench-install` misura entrambi; se lo
     script smette di superare A1–A4 si rimuove, non si ripara di nascosto.
   Se convivono, vince l'ordine del `PATH` fissato da `clients/shell-env.sh`
   (shim di mise prima di `~/.local/bin`). Nessuno dei due cancella i file
   dell'altro: la verifica stampa da dove arriva `node` e fallisce se le
   versioni sul `PATH` non sono i pin.

## Conseguenze
**Positive:** pin esatti e rollback quasi istantaneo, identici su Debian 13,
Fedora e Ubuntu; un solo file da revisionare; P3 (`stack.py`)
chiama `mise install` invece di tre installatori.

**Negative / costi accettati:**
- Un gestore in più nella catena di fiducia; scarica i runtime da GitHub e da
  nodejs.org.
- **Dependabot non conosce il formato di mise**: per questo il file di mise si
  genera dai pin di `stack/` (opencode tracciato da Dependabot via
  `package.json`; Node e mise a mano, col cooldown di ADR-0020).
- Due percorsi di installazione da mantenere: il costo del ripiego, accettato
  finché la CI lo prova.
- Bazzite non è stato misurato: G1 è un controllo sulla documentazione.
- I tempi a freddo dipendono dalla rete del runner; i rollback no.

**Da rivedere se:** mise cambia licenza o default di sicurezza; Dependabot
aggiunge l'ecosistema mise; un tool S3 non ha un backend mise affidabile;
il benchmark (`bench-install`, a mano) smette di dare A1–A4 pieni.
