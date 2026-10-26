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
# FROM letterali, tag + digest (debito #1, ADR-0020): Dependabot (docker) li legge
# e propone gli aggiornamenti; un ARG nel FROM non lo vedrebbe. Il digest e'
# l'indice multi-arch: lo stesso tag non puo' cambiare contenuto sotto i piedi.
# v1.104.2 e' cio' a cui puntava `main-stable` il 2026-10-10: il pin congela lo
# stato di oggi, il cooldown di 14 giorni vale per gli aggiornamenti successivi.
# uv: stessa versione che usa il Dockerfile upstream di LiteLLM.
FROM ghcr.io/astral-sh/uv:0.13.5@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff AS uvbin

FROM ghcr.io/berriai/litellm-database:v1.106.0@sha256:80a12a210e6626e39daaa31fb6ce70f4c4d97ee10e21d4584a9e87f45bf3a2f1

# Extra di headroom-ai. Default: vuoto = solo il core.
# Il callback importa litellm, httpx e moduli interni di headroom: il core basta.
# NON usare "[all]" alla leggera: su linux/x86_64 gli extra 'ml' e 'voice'
# tirano dentro torch + transformers (~3 GB) in una VM da 20 GB con 2 GB di
# limite RAM. Se serve un extra, dichiaralo esplicitamente (es. "[relevance]").
ARG HEADROOM_EXTRAS=""

COPY --from=uvbin /uv /usr/local/bin/uv
# La versione viene da requirements-callback.txt (vincolo, -c): gli extra restano
# scelti da HEADROOM_EXTRAS, ma headroom-ai non puo' salire da solo.
COPY requirements-callback.txt /tmp/requirements-callback.txt
RUN uv pip install --no-cache --python /app/.venv/bin/python \
      -c /tmp/requirements-callback.txt "headroom-ai${HEADROOM_EXTRAS}"

# Gate fail-fast: se il callback non importa, la build fallisce QUI, non in produzione.
RUN /app/.venv/bin/python -c "from headroom.integrations.litellm_callback import HeadroomCallback; print('HeadroomCallback OK')"
