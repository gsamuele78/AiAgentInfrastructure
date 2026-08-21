# DevOps best practices — assessment onesto

Verifica automatica: `scripts/devops-audit.sh`. Qui il quadro e **cosa manca**.

| Area | Stato | Note |
|---|---|---|
| IaC / config dichiarative | ✅ | compose, YAML, unit file, tutti in repo |
| Build riproducibile | ✅ | Dockerfile + gate `import HeadroomCallback` |
| Pin versioni | ⚠️ | `main-stable` è mobile → **pinna un digest sha256** |
| Config immutabile | ✅ | `litellm_config.yaml:ro` |
| Segreti fuori dai config | ✅ | solo `os.environ/` |
| Permessi ristretti | ✅ | `.env` 600 |
| Rotazione segreti | ⚠️ | manuale; le vecchie credenziali erano esposte → **ruotale** |
| Secret manager | ❌ | scelta: sproporzionato per single-host |
| Least privilege | ✅ | postgres non esposto, `no-new-privileges`, NAT |
| Container non-root | ⚠️ | limite dell'immagine upstream |
| Healthcheck / restart / limiti | ✅ | entrambi i servizi |
| Log rotation | ✅ | driver `local`, 15m × 5 |
| Metriche | ⚠️ | Prometheus disponibile, non attivo |
| Alerting | ❌ | **debito reale** se il gateway diventa critico |
| Backup DB | ✅ | `backup-db.sh` + retention 14 |
| **Restore testato** | ✅ | `restore-test.sh` (TC-05) + CI functional |
| Snapshot VM | ✅ | `virsh snapshot-create-as` |
| ADR / decisioni | ✅ | `docs/adr/` 10 ADR, con superseded |
| PRD / requisiti | ✅ | `docs/PRD.md` |
| Test plan | ✅ | `docs/TEST-PLAN.md` |
| CI | ✅ | `validate.yml` + `functional.yml` |
| CD | ❌ | **per scelta** (ADR-0010) |
| Scan CVE immagini | ⚠️ | non implementato |

## Debito riconosciuto (priorità)
1. **Immagine su tag mobile** → pinna `main-stable@sha256:...`
2. **Nessun alerting** → minimo utile: `callbacks: ["prometheus"]` + scrape
3. **Rotazione credenziali** → le vecchie erano in un file 664: rigenerale
4. **Nessuno scan CVE** → valuta `trivy` nella CI

## Non implementato *per scelta* (non è debito)
Secret manager (Vault/SOPS) · CD automatico · HA/replica · container non-root
(dipende dall'upstream). Motivazioni in `PRD.md` §3 e `adr/0010`.

## Manutenzione
```bash
./scripts/devops-audit.sh        # prima di ogni deploy
./scripts/audit-integration.py   # dopo ogni modifica ai config
./scripts/backup-db.sh           # settimanale
./scripts/restore-test.sh        # a ogni cambio di schema
virsh snapshot-create-as llm-vm pre-upgrade   # prima degli aggiornamenti
```
