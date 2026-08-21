# ============================================================
#  Immagine LiteLLM + callback di compressione Headroom.
#
#  ATTENZIONE all'installer: l'immagine upstream e' Wolfi con un venv
#  creato da `uv sync` in /app/.venv (PATH="/app/.venv/bin:$PATH").
#  NON contiene pip -- ne' il binario ne' il modulo -- ne' uv a runtime.
#  Per questo `RUN pip install ...` falliva con "pip: not found" e la CI
#  non e' mai passata: si porta uv da un'immagine dedicata e si installa
#  esplicitamente DENTRO il venv, che e' l'unico python che il proxy usa.
# ============================================================
ARG LITELLM_IMAGE_TAG=main-stable
# Stessa versione che usa il Dockerfile upstream di LiteLLM.
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.11.7

FROM ${UV_IMAGE} AS uvbin

FROM ghcr.io/berriai/litellm-database:${LITELLM_IMAGE_TAG}

# Extra di headroom-ai. Default: vuoto = solo il core.
# Il callback importa litellm, httpx e moduli interni di headroom: il core basta.
# NON usare "[all]" alla leggera: su linux/x86_64 gli extra 'ml' e 'voice'
# tirano dentro torch + transformers (~3 GB) in una VM da 20 GB con 2 GB di
# limite RAM. Se serve un extra, dichiaralo esplicitamente (es. "[relevance]").
ARG HEADROOM_EXTRAS=""

COPY --from=uvbin /uv /usr/local/bin/uv
RUN uv pip install --no-cache --python /app/.venv/bin/python "headroom-ai${HEADROOM_EXTRAS}"

# Gate fail-fast: se il callback non importa, la build fallisce QUI, non in produzione.
RUN /app/.venv/bin/python -c "from headroom.integrations.litellm_callback import HeadroomCallback; print('HeadroomCallback OK')"
