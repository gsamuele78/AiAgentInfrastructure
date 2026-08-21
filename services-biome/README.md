# services-biome — vLLM su L40S, esposto in mTLS

File **deployabili** (non snippet). Il razionale è in `docs/BIOME-L40S.md`,
la decisione in `docs/adr/0009-mtls-per-biome.md`.

```
[VM gateway] LiteLLM → stunnel (mTLS client) ──VPN──► nginx :8443 ──► vLLM :8000 (loopback) ──► L40S #0
```

## Deploy sul server BIOME

```bash
# 1. certificati step-ca
sudo install -d certs
step ca certificate "biome-llm.<dominio-interno>" certs/server.crt certs/server.key
step ca root certs/step-root.crt
sudo chmod 600 certs/server.key

# 2. configurazione
cp .env.example .env && chmod 600 .env && $EDITOR .env   # BIND_IP, HF_TOKEN, VLLM_API_KEY

# 3. avvio (il primo caricamento del modello richiede diversi minuti)
docker compose up -d
docker compose logs -f vllm | grep -i "started\|error"
curl -s localhost:8000/health

# 4. firewall: solo la subnet VPN
sudo ufw allow from <SUBNET_VPN> to any port 8443 proto tcp

# 5. rinnovo automatico dei certificati (step-ca usa cert a vita breve)
step ca renew --daemon --exec "docker compose restart nginx" certs/server.crt certs/server.key
```

## Lato client (nella VM del gateway)

```bash
step ca certificate "litellm-gateway.$(hostname -s)" certs/client.crt certs/client.key
chmod 600 certs/client.key
```
Il sidecar e la lane **sono gia' nel repo**, non piu' snippet da incollare:
- servizio `biome-tls` in `services/docker-compose.yml`, dietro il profilo
  `biome` (non parte, e non pretende certificati, per chi non usa BIOME);
- config del sidecar in `services/stunnel-biome.conf` — sta in `services/`
  perche' e' il lato CLIENT e gira nella VM del gateway, non qui;
- modello `biome-coder` in `services/litellm_config.yaml`.

Nella VM:
```bash
# certificati client in ~/llm-services/certs/
docker compose --profile biome up -d
```

## Verifica — il test che conta
```bash
# SENZA certificato client: DEVE fallire
curl -sk https://biome-llm.<dominio-interno>:8443/v1/models        # atteso: errore handshake
# CON certificato: 200
curl -s --cert certs/client.crt --key certs/client.key \
     --cacert certs/step-root.crt https://biome-llm.<dominio-interno>:8443/v1/models
# dal gateway
./scripts/test-all.sh biome
```

## Failure modes
| # | Sintomo | Causa | Fix |
|---|---|---|---|
| 1 | vLLM crasha all'avvio senza messaggi chiari | shared memory | `shm_size: 16gb` |
| 2 | OOM al caricamento | `gpu-memory-utilization` troppo alto | 0.90, mai 1.0; riduci `MAX_LEN` |
| 3 | risposte in blocco invece che streaming | buffering nginx | `proxy_buffering off` |
| 4 | handshake rifiutato con cert valido | root CA sbagliata | `step ca root` aggiornata |
| 5 | gateway "giù" senza motivo | cert scaduto | `step ca renew --daemon` |
| 6 | la VM non raggiunge BIOME | VPN blocca il forwarding da virbr0 | `ip route get`, `ip_forward` |
| 7 | ricercatori senza GPU | il servizio la occupa in modo residente | **governance**, non tecnica |

## Governance — prima di accendere
Un servizio LLM **occupa la VRAM in modo residente**, a differenza dei job batch.
Da concordare con Chiarucci e il gruppo: la GPU 0 è dedicabile stabilmente? chi
sono gli utenti? L'argomento non è il costo ma la **sovranità del dato** —
ricerca non pubblicata che non lascia l'infrastruttura di ateneo.
