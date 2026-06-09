# Tool design rules

From [Writing tools for agents — with agents](https://www.anthropic.com/engineering/writing-tools-for-agents). Apply these when adding a tool to an MCP server, defining an in-repo helper exposed via code-execution-MCP, or designing the surface of a product feature an agent will call.

## The seven rules

### 1. Namespace by prefix

Tools live in a flat namespace from the agent's perspective. Prefix related tools so the agent can group them mentally and so two tools named `search` from different domains don't collide.

- ✅ `asana_search_tasks`, `asana_create_task`, `asana_update_task`
- ❌ `search_tasks`, `create_task`, `update_task`

### 2. Use unambiguous parameter names

The agent guesses at parameter intent from the name alone. Be explicit.

- ✅ `user_id: str`, `project_id: str`, `due_iso8601: str`
- ❌ `user: str`, `project: str`, `due: str`

### 3. Describe the tool like you'd describe it to a new hire

The description is the agent's only window into the tool's semantics. Include: what it does, what kinds of inputs make sense, what comes back, terminology specific to your domain, relationships between resources.

- ✅ "Search for customer orders by date range, status, or total amount. Returns up to 50 order objects with `id`, `customer_id`, `status` (one of pending|paid|refunded|cancelled), `total_cents`, `created_at`. Use `search_customer` first to resolve customer names to IDs."
- ❌ "Execute order query."

### 4. Document the return value's shape

The agent has no other way to know. Always include field names, types, and the enum values for any string field that's secretly an enum.

### 5. Default-on truncation + pagination, with steering errors

Large responses pollute the agent's context (per the [code-execution-with-MCP post](https://www.anthropic.com/engineering/code-execution-with-mcp), this is the second biggest context leak). Default to paginated/truncated returns. When you truncate, tell the agent **how to narrow** next time, not just that you truncated.

- ✅ "Returned 50 of 1,247 matching orders (truncated). To narrow: add `status=`, `customer_id=`, or `since_iso8601=`."
- ❌ "Results truncated."

### 6. Offer a DETAILED | CONCISE toggle for variable-cost tools

When a tool's response is sometimes a one-liner and sometimes a wall of text, expose `response_format: "DETAILED" | "CONCISE"` so the agent can ask for the size it needs.

### 7. Consolidate; prefer search over list; ship the workflow tool

"More tools don't always lead to better outcomes." Replace `list_users` + `list_events` + `create_event` with `schedule_event`. Prefer `search_contacts` over `list_contacts`. Ship the tool that completes the workflow, not the tool that exposes the endpoint.

## Anti-patterns

- **`list_*` tools.** Almost always wrong. The agent has to scan + filter; `search_*` does that for it.
- **Opaque return values.** `{ "id": "u_abc123", "ref": "..." }` with no doc on what fields mean.
- **`Execute X query` descriptions.** Tells the agent nothing it didn't already know from the name.
- **Returning raw JSON blobs on success and empty on failure.** Pick one shape; always include success/error markers.
- **More than ~10 tools without Tool Search Tool.** Per the [advanced tool use post](https://www.anthropic.com/engineering/advanced-tool-use), turn on `tool_search` once you cross that threshold or 10K tokens of tool definitions — 85% token reduction.

## Eval discipline

Every tool ships with at least one realistic transcript that exercises it. The transcript proves: the description suffices for the agent to use the tool correctly, the params are unambiguous, the return shape is consumable.

A tool without an eval is a tool you don't know works.

## Related

- `tool-design` skill — actionable checklist version of these rules
- `.mcp.json` — where the project's MCP servers are wired
- `mcp/servers/` — where your project's own MCP server lives
- `tools/` — where in-repo code-execution helpers live
