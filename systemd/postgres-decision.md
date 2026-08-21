# postgres host — VERIFICATO: litellm-only, dismissione sicura

Check eseguiti sul sistema reale:
- `pg_stat_activity` → solo la sessione psql. **Zero client applicativi.**
- `\l` → solo `postgres/template0/template1`. Nessun db keycloak/altro.
- `grep` in opencode/openchamber → nessun riferimento a postgres/5432.
- `list-dependencies --reverse` → nessun servizio dipende da postgres.
- java su 1025/1110/1143/1389 = **DavMail**, non usa postgres.
- litellm pipx: `static` + `inactive (dead)` → non parte al boot.

```bash
# ORDINE PSE: prima la VM su e verificata, POI qui.
sudo -u postgres psql -c "ALTER SYSTEM RESET log_connections;"
systemctl --user stop litellm.service 2>/dev/null || true
sudo systemctl stop postgresql@17-main postgresql.service
sudo systemctl disable postgresql        # postgresql@.service 'indirect' segue
ss -tlnp | grep -E ':(4000|5432)' || echo "chiuse"
```
Dati NON cancellati (`/var/lib/postgresql/17/main`). Solo dopo settimane serene:
`sudo pg_dropcluster 17 main --stop`.

⚠️ La password del vecchio config era in chiaro (perm 664): **non riusarla**.
