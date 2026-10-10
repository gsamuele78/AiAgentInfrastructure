# P2b — Come si installano e si annullano i tool utente (S3): pre-registrazione

Protocollo di [ADR-0021](../../docs/adr/0021-misurare-prima-di-adottare-e-oh-my-openagent.md).
Questo file è scritto **prima** di vedere i numeri; le soglie non si cambiano
dopo. L'esito va in ADR-0024.

## Domanda
Per lo strato S3 di ADR-0018 (Node, opencode, tool Python come graphify, in
`$HOME`), quale metodo dà l'installazione e il rollback più puliti?

## Candidati
| Metodo | Cosa gestisce | Rollback dichiarato |
|---|---|---|
| `baseline` (script nostro, nessun gestore nuovo) | tarball Node in `~/.local/opt`, `npm --prefix ~/.local`, `uv tool` | reinstallare il pin precedente |
| `mise` (MIT) | Node, opencode (`npm:`), graphify (`pipx:` via uv) in **un** `config.toml` | ripristinare il file + `mise install` |
| `brew` (BSD-2) | `node@24`, `opencode`; graphify via `uv tool` | nessuno nativo |
| `nix` (LGPL-2.1) | `nodejs_24`, `opencode` da una revisione di nixpkgs; graphify via `uv tool` | `nix profile rollback` |
| `distrobox` (GPL-3.0) | contenitore da immagine pinnata; dentro, lo stesso script della baseline | ricreare il contenitore + reinstallare |

`uv` non è un candidato a sé: gestisce solo Python ed è già la scelta per i
tool Python (ADR-0022). Compare dentro gli altri metodi.

## Pin di prova (cooldown ≥ 7 giorni al 2026-10-10, ADR-0020)
| Tool | A (installazione) | B (aggiornamento) |
|---|---|---|
| Node | 24.20.0 | 24.21.0 |
| opencode (`opencode-ai`) | 1.18.33 | 1.18.34 |
| graphify (`graphifyy`) | 0.9.73 | 0.9.74 |

Sequenza per ogni metodo: installa A → rilancia A (×10) → aggiorna a B →
**rollback** ad A (×5, ogni volta da B). Ogni metodo ha una `$HOME` sua.

## Metriche e soglie
**Accuratezza** (devono valere tutte, altrimenti il metodo è escluso):
| ID | Metrica | Soglia |
|---|---|---|
| A1 | dopo l'installazione, le versioni sono **esattamente** i pin A | 3/3 tool |
| A2 | il secondo run non modifica file nelle directory gestite | 0 file |
| A3 | dopo il rollback, le versioni tornano quelle di dopo l'installazione A | 3/3 tool, 5/5 ripetizioni |
| A4 | dopo il rollback, lo stato dichiarato del metodo (file di config / manifest) ha lo stesso sha256 di dopo A | uguale, 5/5 |

Un metodo che non sa esprimere "installa B" o "torna ad A" fallisce A3/A4
(registrato come `n/a` con il motivo).

**Prestazioni** (guardie; mediana, tempo reale):
| ID | Metrica | Soglia |
|---|---|---|
| P1 | installazione a freddo dei 3 tool (gestore escluso) | ≤ 300 s |
| P2 | rilancio idempotente (10 run) | ≤ 3 s |
| P3 | rollback da B ad A (5 run, cache calda) | ≤ 60 s |

**Pulizia e vincoli** (riportati; G1 è un gate):
| ID | Metrica | Soglia |
|---|---|---|
| G1 | funziona su Bazzite scrivendo **solo** in `$HOME` (nessun cambio S1) | sì — verificato sulla documentazione, non in CI |
| R1 | file lasciati in `$HOME` dopo la disinstallazione del metodo | riportato, non soglia |
| R2 | spazio su disco occupato | riportato, non soglia |

## Regola di decisione
1. Si escludono i metodi che falliscono A1–A4 o G1.
2. Tra i rimasti, si sceglie quello con **meno strumenti e meno file da
   mantenere** (un gestore vale meno di due).
3. A parità, vince il P3 più basso.
4. Se nessuno supera, resta la `baseline`.

## Limiti dichiarati
- Si misura in container Debian 13 e Fedora 44 e sul runner Ubuntu (per
  `brew`, `nix`, `distrobox`, che lì sono già presenti o installabili), **non
  su Bazzite**: G1 resta un controllo di documentazione.
- Le prestazioni a runtime dei tool non cambiano col metodo (stessi binari):
  non si misurano.
- Rete e cache dei mirror pesano su P1; P1 è una guardia larga per questo.
