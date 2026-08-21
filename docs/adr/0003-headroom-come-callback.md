# 0003 — Headroom come callback nel pre_call_hook
- **Status**: Accepted (supersedes [0002](0002-headroom-proxy-davanti.md))
- **Data**: 2026-06-25

## Contesto
[0002] metteva headroom come proxy. La integration guide ufficiale documenta il
callback dentro LiteLLM.

## Alternative considerate
| Opzione | Punti di compressione | Copre tutti i provider | Hop extra |
|---|---|---|---|
| Proxy davanti [0002] | 1, fuori dal gateway | solo l'upstream | sì |
| **Callback pre_call_hook** | 1, dentro il gateway | **sì** | no |

## Decisione
`litellm_settings.callbacks: ["headroom.integrations.litellm_callback.HeadroomCallback"]`
con `headroom-ai` nello stesso ambiente del proxy.

## Conseguenze
**Positive:** un solo punto di compressione per tutti i provider; nessun doppio
hop; il proxy :8787 diventa opzionale (utile solo per CLI che non puntano a LiteLLM).
**Negative:** dipendenza Python nell'immagine (mitigato: gate `import` a build-time).
**Da rivedere se:** Headroom cambia l'API, o serve comprimere traffico non-LiteLLM.
