# 0018 — Installazione idempotente e rollback su Debian 13 e Bazzite

- **Status**: Proposed — piano in [`PLAN-STACK-VALIDATION.md`](../PLAN-STACK-VALIDATION.md) (P2–P3)
- **Data**: 2026-10-10

## Contesto
Due famiglie di host con modelli opposti:

| | Debian 13 (trixie) | Bazzite (Fedora Atomic, Universal Blue) |
|---|---|---|
| `/usr` | scrivibile | **sola lettura** (ostree/composefs) |
| pacchetti | `apt`, nessun rollback transazionale | `rpm-ostree`, rollback nativo **con reboot** |
| GPU NVIDIA | driver da `apt` (non-free) | immagine `-nvidia` (rebase), non layering |
| tool utente | apt / tarball | `brew` (preinstallato), Flatpak, Distrobox |
| Node.js di sistema | 20.x — **EOL upstream da aprile 2026** (Debian lo patcha) | assente |

`scripts/lib/hw-detect.sh` già distingue atomico/ublue/sandbox, rileva la GPU dal
bus PCI e stampa il comando d'installazione giusto (`pkg_hint`). Manca il resto:
i fatti escono solo come testo per umani, gli installer non sono idempotenti, e
un rollback esiste solo per la VM (snapshot, TC-06).

## Alternative considerate
| Opzione | Pro | Contro |
|---|---|---|
| Tutto via pacchetti di sistema | un solo meccanismo | su Bazzite ogni modifica = layering + reboot; su Debian nessun rollback |
| Tutto in una Distrobox Debian 13 anche su Bazzite | un solo percorso di codice | Ollama, libvirt e firewall restano servizi dell'host: il problema non sparisce, si sposta |
| **Strati con regole per strato** | ogni strato usa il meccanismo di rollback che ha davvero | quattro regole da conoscere invece di una |

## Decisione
Ogni componente sta in **uno** di quattro strati, e lo strato decide come si
installa e come si torna indietro:

| Strato | Esempi | Debian 13 | Bazzite | Idempotenza | Rollback |
|---|---|---|---|---|---|
| **S1 sistema** | libvirt, qemu, driver, firewall | `apt` (versioni registrate) | `rpm-ostree install` solo se non già nell'immagine | probe prima di installare | Bazzite: `rpm-ostree rollback`. Debian: rimozione di ciò che *questo* run ha aggiunto (journal) + snapshot btrfs/snapper **se rilevato**, altrimenti dichiarato non disponibile |
| **S2 servizi host** | Ollama, `litellm-forward` | script + unit systemd in `/etc` | idem (`/etc` e `/var` scrivibili) | render → confronto sha256 → scrivi solo se diverso | ripristino dal journal + `daemon-reload` |
| **S3 tool utente** | opencode, Serena, graphify, uv, Node, MCP | in `$HOME` (`uv tool`, prefix npm utente), versione **pinnata** nel manifest | **identico** | versione installata = pin → skip | reinstallare il pin precedente (da git) |
| **S4 config** | `opencode.jsonc`, `~/.claude/*`, `.serena/` | render dal repo | identico | sha256 uguale → nessuna scrittura, **nessun `.bak`** | ripristino dal journal per run-id |

Regole trasversali:
1. **Journal di run**: `~/.local/state/aiagentinfra/runs/<run-id>/` con
   `manifest.json` (file toccati, sha256 prima/dopo, pacchetti aggiunti) e le
   copie precedenti. Sostituisce i `.bak-<ts>` sparsi.
2. **Decisioni automatiche solo se reversibili**: dai fatti hw/OS
   (`stack.py facts`) si sceglie da soli ciò che sta in S3/S4 (modello Ollama
   per la VRAM, `KEEP_ALIVE` da laptop, Node via brew su Bazzite). Ciò che
   richiede **reboot, rebase o driver** (S1) produce una raccomandazione e
   serve un flag esplicito — mai automatico.
3. **Sandbox**: invariato, `sandbox_guard` prima di qualunque strato S1/S2.
4. **VM**: prima di ogni azione che tocca la VM, snapshot automatico
   (`stack.py` riusa la logica di TC-06); una `validate --level 5` fallita dopo
   l'aggiornamento riporta la VM allo snapshot.
5. **Runtime**: Node LTS e Python sono pin del manifest, non "quello che ha la
   distro" — Node 20 di Debian è EOL upstream. Gestore candidato: `mise` (MIT);
   da confermare in P2 contro l'alternativa "brew su entrambi".

## Conseguenze
**Positive:** rilanciare l'installazione diventa sicuro (TC-10); ogni run è
annullabile per gli strati S2–S4 (TC-11/12); S3 è identico sui due OS, quindi la
maggior parte del codice si testa una volta sola.

**Negative — da non minimizzare:**
- **Su Debian lo strato S1 non ha un vero rollback** senza btrfs: rimuovere un
  pacchetto non ripristina le dipendenze aggiornate nel frattempo. Lo diciamo,
  non lo nascondiamo.
- Su Bazzite il rollback S1 **richiede un reboot** e annulla l'intero deployment
  ostree, non il solo pacchetto.
- **Bazzite non è testabile nei runner GitHub**: rpm-ostree in un container non
  ha senso. Serve una VM Bazzite sul runner self-hosted o una prova manuale
  registrata (come TC-05). Finché non esiste, "funziona su Bazzite" è
  un'affermazione su S3/S4, non su S1.
- Un gestore di runtime (mise) è un componente in più.

**Da rivedere se:** si adotta Ansible (ADR-0017 "da rivedere"), o Bazzite cambia
modello di aggiornamento (bootc al posto di rpm-ostree è già in corso in
Fedora: va seguito).
