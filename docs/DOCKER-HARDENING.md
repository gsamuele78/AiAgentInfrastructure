# Docker hardening

## Sequenza per la VM Debian
```bash
# Repo ufficiale DEBIAN (non ubuntu: il codename trixie non esiste lì)
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo groupadd docker 2>/dev/null || true      # il pacchetto lo crea già
sudo usermod -aG docker "$USER" && newgrp docker
docker run --rm hello-world

# daemon.json
sudo mkdir -p /opt/docker/data /etc/docker    # -p: /opt/docker non esiste
sudo tee /etc/docker/daemon.json > /dev/null <<'JSON'
{
  "data-root": "/opt/docker/data",
  "log-driver": "local",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "live-restore": true
}
JSON

# Migrazione data-root, con validazione PRIMA del restart
sudo systemctl stop docker.socket docker.service
sudo rsync -avP /var/lib/docker/ /opt/docker/data/
sudo dockerd --validate --config-file=/etc/docker/daemon.json   # gate
sudo systemctl start docker.socket docker.service
docker info | grep -E "Docker Root Dir|Logging Driver"

# Solo DOPO la verifica: rinomina (non cancellare) il vecchio path
# sudo mv /var/lib/docker /var/lib/docker.old
```

## `local` vs `json-file` — la scelta
| Scenario | Driver |
|---|---|
| Log letti solo con `docker logs` | **`local`** (compresso, rotazione nativa) |
| Log shipper che legge i `*-json.log` (Promtail, Fluentd) | `json-file` |

Il `daemon.json` copre **tutti** i container, anche quelli lanciati a mano: è il
posto giusto (DRY). I blocchi per-servizio servono solo per eccezioni. Nel
compose sono espliciti e allineati a `local`, così lo stack è autoconsistente.

## journald — dimensionato sulla VM
```bash
sudo tee /etc/systemd/journald.conf.d/99-vm.conf > /dev/null <<'CONF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=500M       # NON 8G: il disco della VM è 20 GB
SystemKeepFree=2G       # NON 20G: renderebbe il journal inutilizzabile
MaxRetentionSec=1month
CONF
sudo systemctl restart systemd-journald && journalctl --disk-usage
```
Un drop-in in `journald.conf.d/` non viene sovrascritto dagli aggiornamenti.
Valori 8G/20G sono giusti **sul server BIOME**, non su una VM da 20 GB.

## `data-root` su /opt: quando serve
Ha senso se `/opt` è un **disco o LV separato**. Se nella VM è tutto sulla stessa
partizione, è solo organizzazione: il disco si riempie comunque.

## `live-restore: true`
I container continuano a girare durante un riavvio del daemon: un `apt upgrade`
di docker non butta giù il gateway. Non funziona con swarm (qui non lo usi).
