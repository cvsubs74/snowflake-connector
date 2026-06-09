# tools/ — in-repo code-execution helpers (filesystem-as-tool-registry)

From the [code-execution-with-MCP post](https://www.anthropic.com/engineering/code-execution-with-mcp): present tools as a code-API filesystem rather than direct tool calls. Agents `ls`/`cat` only the schemas they need, filter data before it hits the context (~98.7% token reduction in the post's example).

## When to put a tool here vs. in an MCP server

| Put here | Put in `mcp/servers/<name>/` |
|---|---|
| One-off helper for this product | Reusable across products |
| Wraps shell / filesystem / local code | Wraps an external API |
| Used by a single agent | Used by multiple agents |
| Cheap to invoke (no auth, no I/O) | Has auth, secrets, rate limits |

In other words: `tools/` is for the project's *idiomatic* helpers; `mcp/servers/` is for the project's *external surfaces*.

## Shape

Each tool is one file. The filename + a leading docstring is the schema.

```
tools/
├── README.md                 # this file
├── render_report.py          # docstring describes inputs/outputs
├── extract_pdf_text.py
└── ...
```

The agent reads `tools/README.md` first (catalog), then `head -50 tools/<name>.py` for the docstring, then invokes via Bash.

## Tool design rules

Apply [`tool-design` skill](../.claude/skills/tool-design/SKILL.md) — the seven rules apply equally to in-repo helpers as to MCP tools.

## Filter at the tool, not in context

The whole point of the code-execution pattern is that **the tool returns the small thing the agent needs, not the large thing the agent has to filter**.

- ❌ Tool returns 50KB of CSV; agent grep/filters in the next turn.
- ✅ Tool takes a filter param; returns the 20 rows that matched.

## Sandbox

In-repo tools run in the project's working directory under the project's `sandbox.json` (when sandboxing is enabled). They should never require network access unless explicitly declared in the sandbox's domain allowlist.

## Related

- `docs/tool-design.md` — the seven rules
- `mcp/README.md` — when to escalate to an MCP server
- `sandbox.json` — what the tool can touch
