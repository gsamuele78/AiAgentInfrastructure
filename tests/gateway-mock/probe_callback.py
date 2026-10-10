"""Callback di test: registra ogni chiamata (riuscita o fallita) in un file JSONL.

Prende il posto del callback headroom nella config mock (gen-config.py): il
test verifica che il gateway INVOCHI i callback configurati, e su quale lane.
"""
import json
import os

from litellm.integrations.custom_logger import CustomLogger

LOG = os.environ.get("PROBE_CALLBACK_LOG", "/tmp/probe-callback.jsonl")


class Probe(CustomLogger):
    def _w(self, kind, kwargs):
        with open(LOG, "a") as f:
            f.write(json.dumps({"event": kind, "model_group": (kwargs.get("litellm_params") or {}).get("metadata", {}).get("model_group"),
                                "model": kwargs.get("model")}) + "\n")

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._w("success", kwargs)

    async def async_log_failure_event(self, kwargs, response_obj, start_time, end_time):
        self._w("failure", kwargs)


handler = Probe()
