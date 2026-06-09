---
name: tool-design
description: Use when adding a tool to an MCP server, defining a code-exec helper, designing a product surface an agent will call, or reviewing whether an existing tool is well-shaped for agent use. Encodes the seven rules from Writing tools for agents (Sep 2025).
---

# tool-design — agent-friendly tool authoring

The seven rules from [Writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents). See `docs/tool-design.md` for the long form with examples.

## Checklist before shipping a tool

1. **Name namespaced?** `<service>_<verb>_<object>` (e.g., `asana_search_tasks`).
2. **Params unambiguous?** `user_id` not `user`. `due_iso8601` not `due`.
3. **Description "explain to a new hire" quality?** Inputs, output shape, domain terms, resource relationships.
4. **Return shape documented?** All fields + types + enum values.
5. **Pagination/truncation defaults on?** And the truncation message tells the agent how to narrow.
6. **`response_format: DETAILED | CONCISE` toggle?** Required when output size varies widely.
7. **Consolidated, search > list, workflow-shaped?** No `list_*` tools; `search_*` instead. Ship the workflow tool, not the endpoint.

Every "no" is a deferred bug — the agent will misuse the tool in some way you can't anticipate.

## Tool Search Tool threshold

If the project ships >10 tools or its tool definitions cross 10K tokens, enable Tool Search Tool. From the [advanced tool use post](https://www.anthropic.com/engineering/advanced-tool-use): 85% token reduction, 49%→74% accuracy on Opus 4. Until then, plain tool listing is fine.

## Programmatic tool calling threshold

If a workflow involves 3+ dependent tool calls, large intermediate results, or natural parallelism, mark callable tools with `"allowed_callers": ["code_execution_20250825"]` and let Claude orchestrate them in code. 37% token reduction.

## Eval

Every new tool ships with **at least one realistic transcript** that proves an agent uses it correctly. Drop the transcript at `evals/tools/<tool-name>/transcript-1.txt` and register an eval task at `evals/tasks/tools/<tool-name>.yaml` so the rule "tool design discipline is verified, not asserted" stays true.

## Anti-patterns

- **`list_*` tools.** Wrong default — the agent does scan-and-filter that `search_*` would do for it.
- **Opaque returns.** `{"id": "abc", "ref": "..."}` without doc.
- **Lazy descriptions.** "Execute X query." Tells the agent nothing.
- **Tool proliferation.** "More tools don't always lead to better outcomes." Consolidate.
- **No eval.** A tool without an eval is a tool you don't know works.

## Related

- `docs/tool-design.md` — long-form with examples
- `eval-runner` — how to add the per-tool eval
- `.mcp.json` — where to wire the tool's MCP server
