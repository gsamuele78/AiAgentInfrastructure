# AGENTS SETUP — opencode + OpenChamber + MCP + VSCodium

Ordine: prerequisiti → opencode → MCP → OpenChamber → VSCodium.

## 1. Prerequisiti
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
nvm install --lts                       # Node >= 18 per gli MCP npx
curl -LsSf https://astral.sh/uv/install.sh | sh    # per Serena/graphify
sudo apt install -y ripgrep
```

## 2. opencode
```bash
curl -fsSL https://opencode.ai/install | bash      # → ~/.opencode/bin/opencode
# alt: npm i -g opencode-ai | brew install anomalyco/tap/opencode | pacman -S opencode
echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
opencode serve --port 3000 --hostname 127.0.0.1    # server che OpenChamber pilota
```
⚠️ Esiste una **beta 2.0** (`@opencode-ai/cli@next`, binario `opencode2`): la doc
avverte che può cancellare i dati e che config/API cambiano. **Resta sulla stable.**

## 3. Autenticazione: NON serve `opencode auth login`
Tutti i provider passano dal gateway. Un solo provider `litellm` con
`apiKey: "{env:LITELLM_MASTER_KEY}"`. Le API key stanno in **un posto solo**.
```bash
install -d ~/.config/litellm
echo "sk-..." > ~/.config/litellm/master.key && chmod 600 ~/.config/litellm/master.key
```

## 4. MCP server
| Alias | Pacchetto | Prerequisito | Chiave |
|---|---|---|---|
| `serena` | `serena-agent` (uv) | uv, Python 3.13 | — |
| `reason` | `@modelcontextprotocol/server-sequential-thinking` | Node | — |
| `mem` | `@modelcontextprotocol/server-memory` | Node | — |
| `fs` | `@modelcontextprotocol/server-filesystem` | Node | — |
| `ctx7` | `@upstash/context7-mcp` | Node | `CONTEXT7_API_KEY` |
| `crawl` | `firecrawl-mcp` | Node | `FIRECRAWL_API_KEY` |
| `fetch` | build locale `zcaceres/fetch-mcp` | Node + build | — |
| `tavily` | `tavily-mcp` | Node | `TAVILY_API_KEY` |

```bash
uv tool install -p 3.13 "serena-agent@latest" --prerelease=allow
uv tool install graphifyy && graphify install     # occasionale, è una skill
# fetch-mcp va compilato:
git clone https://github.com/zcaceres/fetch-mcp ~/Documents/Cline/MCP/github.com/zcaceres/fetch-mcp
cd ~/Documents/Cline/MCP/github.com/zcaceres/fetch-mcp && npm install && npm run build
```
Regole (già applicate in `clients/opencode.jsonc`): **alias corti** (i nomi tool
diventano `alias_toolname`; alias lunghi causano errori di tool-calling),
`enabled: false` su quelli non usati ogni sessione, Serena con
`--context ide-assistant`, **una sola** memory. Verifica con `/mcp` nella TUI.

## 5. OpenChamber
Prerequisito: opencode. Su Linux: **web/PWA** o estensione (il desktop è solo macOS).
```bash
curl -fsSL https://raw.githubusercontent.com/openchamber/openchamber/main/scripts/install.sh | bash
openchamber --ui-password <password-robusta> --port 3001
```
⚠️ **Conflitto di porta**: la web UI usa di default la **3000**, la stessa di
`opencode serve`. Sposta una delle due (sopra: OpenChamber su 3001).

OpenChamber **eredita provider, modelli e MCP dal server opencode**: il suo
`settings.json` contiene solo temi/skillCatalogs/responseStyle. Non toccarlo.

## 6. VSCodium
VSCodium usa **Open VSX**, non il Marketplace Microsoft.

**A — estensione opencode:** si installa da sola lanciando `opencode` nel
terminale **integrato** (Ctrl+~), non in uno esterno.

**B — estensione OpenChamber via VSIX:** se non è su Open VSX, scarica il `.vsix`
dalle release GitHub → `codium --install-extension file.vsix`. ⚠️ perdi gli
aggiornamenti automatici.

**C — PWA affiancata:** nessuna estensione, zero attrito. **Spesso la scelta più
pragmatica su VSCodium.**

MCP dentro VSCodium: possibile ma **si sommano** a quelli di opencode → rischi di
sforare il budget di contesto. Consiglio: gli MCP stanno in opencode.

## 7. Verifica
```bash
opencode --version && serena --version
curl -s http://127.0.0.1:3000/doc >/dev/null && echo "server ok"
./scripts/test-all.sh agents
# nella TUI:  /mcp   /models
```

## 8. Failure modes
| Sintomo | Causa | Fix |
|---|---|---|
| OpenChamber non trova opencode | conflitto :3000 | separa le porte |
| `opencode: command not found` | PATH | `export PATH="$HOME/.opencode/bin:$PATH"` |
| estensione non si installa | terminale esterno | usa Ctrl+~ |
| OpenChamber assente in VSCodium | Open VSX ≠ Marketplace | VSIX o PWA |
| "unavailable tool" | alias MCP lunghi | accorcia |
| contesto esaurito | troppi MCP | `enabled: false` |
| dati cancellati dopo update | beta 2.0 | resta sulla stable |
