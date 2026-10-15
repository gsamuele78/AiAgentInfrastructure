"""Callback LiteLLM che toglie i segreti noti dal prompt PRIMA che lasci il gateway.

Idea importata da OpenHands (software-agent-sdk conversation/secret_registry.py e
utils/masking.py, MIT; ADR-0025 §6): i valori dei segreti si mascherano ricorsivamente
in tutto cio' che va al modello. Qui il punto giusto e' il gateway (un solo punto per
tutti i client, ADR-0001): un agente sull'host che fa `cat .env` manda l'output al cloud
alla richiesta successiva. L'invariante 6 copre i file versionati, non questo.

Segreti noti:
  - i valori delle variabili d'ambiente del gateway elencate in SECRET_MASK_ENV
    (default: le chiavi dei provider e la master key);
  - una riga per valore in SECRET_MASK_FILE (file 600 montato :ro), per i segreti
    dell'host che il gateway non vede.
Valori sotto 8 caratteri ignorati (troppi falsi positivi). Il valore diventa
<redacted:NOME>. NON e' ancora collegato al gateway: lo si collega solo se la misura
di bench/secret-canary/PREREG.md lo giustifica.
"""
import os

try:
    from litellm.integrations.custom_logger import CustomLogger
except ImportError:  # i test unitari girano senza litellm
    CustomLogger = object

DEFAULT_ENV = "ANTHROPIC_API_KEY,OPENROUTER_API_KEY,LITELLM_MASTER_KEY,VLLM_API_KEY,DATABASE_URL,POSTGRES_PASSWORD"
MIN_LEN = 8


def load_secrets(env=None):
    env = os.environ if env is None else env
    out = {}
    for name in env.get("SECRET_MASK_ENV", DEFAULT_ENV).split(","):
        v = env.get(name.strip(), "")
        if len(v) >= MIN_LEN:
            out[v] = name.strip()
    f = env.get("SECRET_MASK_FILE")
    if f and os.path.exists(f):
        for i, line in enumerate(open(f).read().splitlines(), 1):
            line = line.strip()
            if len(line) >= MIN_LEN and not line.startswith("#"):
                out[line] = f"file:{i}"
    return out


def mask(obj, secrets):
    """maschera ricorsivamente stringhe in dict/list; restituisce (nuovo_oggetto, n_sostituzioni)"""
    if not secrets:
        return obj, 0
    if isinstance(obj, str):
        n = 0
        for v in sorted(secrets, key=len, reverse=True):  # il piu' lungo prima: niente maschere parziali
            if v in obj:
                n += obj.count(v)
                obj = obj.replace(v, f"<redacted:{secrets[v]}>")
        return obj, n
    if isinstance(obj, list):
        res = [mask(x, secrets) for x in obj]
        return [r[0] for r in res], sum(r[1] for r in res)
    if isinstance(obj, dict):
        res = {k: mask(v, secrets) for k, v in obj.items()}
        return {k: r[0] for k, r in res.items()}, sum(r[1] for r in res.values())
    return obj, 0


class SecretMask(CustomLogger):
    def __init__(self):
        super().__init__() if CustomLogger is not object else None
        self.secrets = load_secrets()

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        if "messages" in data:
            data["messages"], n = mask(data["messages"], self.secrets)
            if n:
                data.setdefault("metadata", {})["secret_mask_hits"] = n
        return data


handler = SecretMask()
