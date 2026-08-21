ARG LITELLM_IMAGE_TAG=main-stable
FROM ghcr.io/berriai/litellm-database:${LITELLM_IMAGE_TAG}
RUN pip install --no-cache-dir "headroom-ai[all]"
# Gate fail-fast: se il callback non importa, la build fallisce QUI, non in produzione.
RUN python -c "from headroom.integrations.litellm_callback import HeadroomCallback; print('HeadroomCallback OK')"
