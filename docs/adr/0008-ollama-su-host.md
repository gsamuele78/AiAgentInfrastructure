# 0008 — Ollama sull'host, niente GPU passthrough
- **Status**: Accepted
- **Data**: 2026-07-27

## Contesto
Inferenza locale sulla RTX A2000 Laptop (4 GB). I servizi girano in VM.
Opzione teorica: passthrough VFIO alla VM.

## Alternative considerate
| Opzione | GPU per l'host | Complessità | Su laptop |
|---|---|---|---|
| Passthrough VFIO | ❌ esclusiva alla VM | alta | fragile (Optimus) |
| **Ollama su host** | ✅ | minima | nessun problema |
| vGPU | ✅ condivisa | licenza NVIDIA | non applicabile |

## Decisione
Ollama sull'host, bindato su `192.168.122.1:11434` (bridge libvirt).

## Conseguenze
**Positive:** GPU disponibile per Blender/CUDA; lane realmente privata.
**Negative:** bind su interfaccia non-loopback (mitigato: solo virbr0, mai
`0.0.0.0`; Ollama non ha autenticazione).
**Da rivedere se:** si passa a due GPU o a un server dedicato.
