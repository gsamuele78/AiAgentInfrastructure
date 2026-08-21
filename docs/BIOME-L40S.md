# BIOME L40S — vLLM self-hosted, esposto in sicurezza

Deploy su **una** L40S (48 GB), raggiungibile dal gateway senza esporre nulla
alla rete di ateneo.

```
[VM] LiteLLM → stunnel sidecar (mTLS) ──VPN──► nginx :8443 (mTLS, step-ca)
                                                    │ 127.0.0.1
                                                    ▼  vLLM :8000 → L40S #0
```
Quattro livelli indipendenti: vLLM su loopback · firewall sulla subnet VPN ·
mTLS (rifiuto in handshake) · API key vLLM.

## Modello
`Qwen3-Coder-Next 80B-A3B` — MoE 80B con 3B attivi, ~35-40 GB Q4/FP8, 256K
contesto. Il MoE è il punto: ragiona come un grande, gira come un piccolo.
L'L40S è Ada → **FP8 nativo**, meglio del Q4 a pari velocità. Apache-2.0.

## Compose (server BIOME)
```yaml
services:
  vllm:
    image: vllm/vllm-openai:latest      # PSE: pinna un digest
    restart: unless-stopped
    ports: ["127.0.0.1:8000:8000"]      # MAI fuori da loopback
    environment:
      HUGGING_FACE_HUB_TOKEN: ${HF_TOKEN}
      VLLM_API_KEY: ${VLLM_API_KEY}
    volumes: ["hf-cache:/root/.cache/huggingface"]
    shm_size: "16gb"                     # senza, vLLM crasha in modo oscuro
    deploy:
      resources:
        reservations:
          devices: [{ driver: nvidia, device_ids: ["0"], capabilities: [gpu] }]
    command:
      - --model=Qwen/Qwen3-Coder-Next
      - --served-model-name=biome-coder
      - --quantization=fp8
      - --kv-cache-dtype=fp8
      - --max-model-len=131072
      - --gpu-memory-utilization=0.90    # mai 1.0: OOM
      - --host=0.0.0.0
      - --port=8000
      - --api-key=${VLLM_API_KEY}
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8000/health || exit 1"]
      start_period: 600s                 # il primo caricamento è lungo
volumes: { hf-cache: {} }
```
**`device_ids: ["0"]`**: l'L40S **non ha NVLink**. Un modello per GPU; la #1 resta
alla ricerca. Tensor-parallel solo se un modello non entra in 48 GB.

## Certificati (step-ca)
```bash
# server
step ca certificate "biome-llm.<dominio-interno>" /etc/nginx/certs/server.crt /etc/nginx/certs/server.key
step ca root /etc/nginx/certs/step-root.crt
# client (sul laptop)
step ca certificate "litellm-gateway.$(hostname -s)" ~/.config/litellm/client.crt ~/.config/litellm/client.key
chmod 600 ~/.config/litellm/client.key
# rinnovo automatico (cert a vita breve per design)
step ca renew --daemon --exec "systemctl reload nginx" /etc/nginx/certs/server.crt /etc/nginx/certs/server.key
```

## nginx (mTLS)
```nginx
limit_req_zone $ssl_client_s_dn zone=llm:10m rate=30r/m;
server {
    listen 10.x.x.x:8443 ssl;  http2 on;
    server_name biome-llm.<dominio-interno>;
    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;
    ssl_protocols TLSv1.3;
    ssl_client_certificate /etc/nginx/certs/step-root.crt;
    ssl_verify_client on;
    location /v1/ {
        limit_req zone=llm burst=10 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header X-Client-DN $ssl_client_s_dn;
        proxy_buffering off;               # senza: SSE arriva in blocco
        proxy_read_timeout 600s;
    }
}
```

## Lato client — sidecar stunnel
Non dipendere dal supporto client-cert di LiteLLM (varia tra versioni): un
sidecar termina l'mTLS in uscita, LiteLLM parla HTTP in locale.
```ini
# stunnel.conf
[biome-llm]
client = yes
accept  = 0.0.0.0:8443
connect = biome-llm.<dominio-interno>:8443
cert = /certs/client.crt
key  = /certs/client.key
CAfile = /certs/step-root.crt
verifyChain = yes
```
```yaml
  - model_name: biome-coder
    litellm_params:
      model: openai/biome-coder
      api_base: http://biome-tls:8443/v1
      api_key: os.environ/VLLM_API_KEY
      timeout: 600
```

## Verifica
```bash
curl -sk https://biome-llm.<dominio-interno>:8443/v1/models                    # SENZA cert: DEVE fallire
curl -s --cert client.crt --key client.key --cacert step-root.crt \
     https://biome-llm.<dominio-interno>:8443/v1/models                        # 200
```
⚠️ **Gotcha VM→VPN:** la VM è dietro NAT libvirt, la VPN gira sull'host. Alcuni
client VPN bloccano il forwarding da `virbr0`. Verifica `ip route get <IP>` e
`sysctl net.ipv4.ip_forward`.

## Autenticazione per livello (ADR-0009)
agente → LiteLLM: virtual key · LiteLLM → vLLM: mTLS · umano → UI: Keycloak OIDC.

## Governance — prima del deploy
Un servizio LLM **occupa la VRAM in modo residente**, a differenza dei job batch.
Da concordare: la GPU 0 è dedicabile? Chi sono gli utenti? L'argomento da portare
non è il costo ma la **sovranità del dato** — ricerca non pubblicata che non
lascia l'ateneo.
