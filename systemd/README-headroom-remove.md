# headroom.service — rimuovere (diventa callback, ADR-0003)

Il tuo unit puntava `--openai-api-url https://openrouter.ai/api`: andava dritto a
OpenRouter **bypassando litellm**.
```bash
systemctl --user disable --now headroom.service
mv ~/.config/systemd/user/headroom.service ~/headroom.service.bak 2>/dev/null || true
rm -f ~/.config/systemd/user/.#headroom.service*     # temp di nano
systemctl --user daemon-reload
headroom unwrap opencode; headroom unwrap codex
```
Il binario `headroom` **resta**: serve per l'MCP `headroom_retrieve` e il
pacchetto `headroom-ai` finisce nell'immagine litellm.

**Eccezione:** se usi la variante B di `DUAL-AUTH.md` (Claude Code + compressione),
tieni il proxy con upstream verso Anthropic.
