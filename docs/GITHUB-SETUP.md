# GitHub — setup del repo `AiAgentInfrastructure`

Repo: `https://github.com/gsamuele78/AiAgentInfrastructure`

## 1. Primo push

Il pacchetto è **già un repo git** con commit iniziale. Serve solo il remote:

```bash
cd AiAgentInfrastructure
git remote add origin git@github.com:gsamuele78/AiAgentInfrastructure.git
#  (HTTPS:  https://github.com/gsamuele78/AiAgentInfrastructure.git)
git branch -M main
git push -u origin main
```

⚠️ **Prima di pushare**, verifica di non avere segreti reali:
```bash
git ls-files | xargs grep -lE 'sk-ant-[A-Za-z0-9]{20,}|sk-or-v1-[A-Za-z0-9]{20,}' || echo "pulito"
./scripts/devops-audit.sh
```

## 2. Impostazioni consigliate del repo

**Visibilità: il repo è PUBBLICO.** È una scelta, non una dimenticanza, e ha due
conseguenze operative che vanno tenute vive:

1. **Niente identificatori interni nei file versionati.** I template usano
   `$USER`, `$VM_USER`, `<dominio-interno>` e `CHANGEME-*`. La subnet
   `192.168.122.0/24` resta in chiaro apposta: è il default di libvirt, uguale
   su ogni macchina, e gli script la usano davvero. FQDN reali, IP di ateneo,
   nomi macchina e path personali no: non rientrano.
2. **Il runner self-hosted diventa la superficie di attacco principale** — vedi
   §4, dove il vincolo è stretto.

**Settings → General**
- Disabilita Wiki e Projects (non servono a un repo single-maintainer)
- Abilita "Automatically delete head branches"

**Settings → Branches → Add rule** su `main`:
- ✅ Require a pull request before merging (anche da solo: forza la checklist del PR)
- ✅ Require status checks to pass → seleziona `syntax`, `secrets`, `docs`
- ✅ Require branches to be up to date before merging
- ❌ Require approvals (sei solo: bloccheresti te stesso)
- ✅ Include administrators — opzionale: onesto, ma ti costringe al PR anche per un typo

> Se il PR obbligatorio ti rallenta troppo, un compromesso sensato: nessuna
> restrizione sul push, ma **status check obbligatori**. Ottieni la protezione
> dagli errori senza la cerimonia.

**Settings → Secrets and variables → Actions** (servono al workflow functional):
| Secret | Contenuto |
|--------|-----------|
| `LITELLM_MASTER_KEY` | la master key del gateway |
| `VM_SSH_TARGET` | es. `$VM_USER@192.168.122.50` |

## 3. Etichette utili
```bash
gh label create security --color d93f0b --description "Sicurezza / segreti"
gh label create adr --color 0e8a16 --description "Richiede una decisione architetturale"
gh label create debt --color fbca04 --description "Debito riconosciuto"
```

## 4. Runner self-hosted (per `functional.yml`)

I test funzionali non possono girare sui runner GitHub: la VM, il gateway e
Ollama vivono sulla tua macchina. Serve un runner locale.

```bash
# Settings → Actions → Runners → New self-hosted runner (Linux x64)
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner.tar.gz -L <URL_DALLA_PAGINA_GITHUB>
tar xzf actions-runner.tar.gz
./config.sh --url https://github.com/gsamuele78/AiAgentInfrastructure \
            --token <TOKEN_DALLA_PAGINA> \
            --labels self-hosted,linux,llm-gateway \
            --name "$(hostname -s)" --unattended
sudo ./svc.sh install && sudo ./svc.sh start     # oppure: ./run.sh
```

Le label `self-hosted,linux,llm-gateway` devono corrispondere a `runs-on` in
`functional.yml`.

⚠️ **Sicurezza del runner — il repo è pubblico, quindi leggi tutto.**
Un self-hosted runner esegue il codice del repo sulla tua macchina. Su un repo
pubblico questo è pericoloso *se* un workflow può essere innescato da un
estraneo.

Oggi **non lo è**, e per una ragione precisa: `functional.yml` gira solo su
`workflow_dispatch` e `schedule`, mai su `pull_request`. Una PR da un fork non
lo avvia, e i secret del repo non sono esposti ai fork. Il vincolo da non
violare è quindi uno solo:

> **Non aggiungere `pull_request` (né `pull_request_target`) ai trigger di
> `functional.yml`, e non aggiungere trigger a un workflow che gira su
> `runs-on: [self-hosted, ...]`.** Farlo significa dare esecuzione di codice
> arbitrario sull'host a chiunque apra una PR.

In più, per difesa in profondità:
- **Settings → Actions → General → Fork pull request workflows**: richiedi
  l'approvazione per tutti gli outside collaborator.
- Se il runner non ti serve, **rimuovilo**: è l'opzione più sicura, e la CI
  statica su runner GitHub resta comunque l'unico gate reale (vedi
  `TEST-PLAN.md`).

Il workflow ha `continue-on-error: true`: se il laptop è spento il job non fa
fallire il repo.

## 5. Flusso di lavoro

```bash
git switch -c feat/lane-biome
# ...modifiche...
./scripts/devops-audit.sh && ./scripts/audit-integration.py
git add -A && git commit -m "feat(gateway): lane BIOME via mTLS"
git push -u origin feat/lane-biome
gh pr create --fill        # la CI valida; la checklist del PR fa il resto
```

Per una modifica architetturale: **prima l'ADR**, poi il codice. La CI verifica
che gli ADR indicizzati esistano e abbiano uno Status.

## 6. Cosa NON versionare
Già coperto da `.gitignore`: `.env`, `*.key`, `*.crt` (tranne la root CA),
`forward.env`, `master.key`, `*.bak-*`, `audit-*.txt`, `.serena/`, `graph.json`.
Vedi `SECURITY.md` per la procedura se un segreto finisce in history.

Su un repo pubblico vale anche per ciò che segreto non è ma è identificante:
FQDN interni, IP di ateneo, nomi macchina, path personali. Se ne aggiungi uno
per sbaglio, sostituiscilo con un placeholder — non serve riscrivere la history
per un hostname, ma serve smettere di aggiungerne.
