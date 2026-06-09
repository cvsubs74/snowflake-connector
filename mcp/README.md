# mcp/ — project-local MCP servers (packaged as .mcpb)

When the project ships its own typed API for agent use — beyond the in-repo helpers in `tools/` — that API lives here as an MCP server.

## Layout

```
mcp/
├── README.md                 # this file
├── Makefile                  # mcpb init / mcpb pack
└── servers/
    └── <product-name>/
        ├── manifest.json     # MCPB manifest (required)
        ├── server/           # source
        └── README.md         # what this server provides
```

## Packaging discipline

From the [Desktop Extensions / MCPB post](https://www.anthropic.com/engineering/desktop-extensions): ship project MCPs as `.mcpb` from day 1 so contributors install with one click instead of manually editing `~/.claude/settings.json`.

```bash
# Initialize a new MCP server (in mcp/servers/<name>/)
npx @anthropic-ai/mcpb init

# Package for distribution
make pack NAME=<server-name>       # → mcp/dist/<server-name>.mcpb
```

## Secrets

Never hardcode secrets in `manifest.json` or `server/`. Declare them in `user_config`:

```json
{
  "user_config": {
    "api_key": {
      "type": "secret",
      "label": "Project API key",
      "required": true
    }
  }
}
```

Claude Desktop stores secrets in the OS keychain. Code in `server/` reads via `${user_config.api_key}` template literal.

## Tool design

Every tool exposed by your MCP server follows [`tool-design` skill](../.claude/skills/tool-design/SKILL.md). Each tool ships with at least one realistic transcript eval at `evals/tools/<tool-name>/`.

## Sandbox + auto-mode interaction

The MCP server runs *outside* the Claude Code sandbox (it's a separate process), so it can do network/auth work. But its actions are auto-mode-classifier-gated when the agent calls them — declare the server's domain in `auto-mode.yaml` under `environment.trusted_services` so common calls don't trigger Stage 2 reasoning.

## Related

- `docs/tool-design.md` — the seven rules
- `.mcp.json` — root-level MCP wiring (Playwright, GitHub MCP, your local servers)
- `auto-mode.yaml` — classifier rules that govern when an MCP call needs approval
