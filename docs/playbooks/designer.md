# Designer Agent Playbook

Project-specific notes that future-you (the Designer agent on this project) needs. Append a section when you learn something worth keeping; delete sections that go stale. Keep this readable end-to-end.

> **Promote-to-skill:** when a procedure here shows up in another agent's playbook too, or you've done it the same way 3+ times, lift it into a shared skill at `.claude/skills/<name>/SKILL.md`. See the `skill-maintenance` skill for the authoring pattern.

## Mermaid diagram review — learned from PR #95 (2026-05-28)

**Validation tool:** `npx @mermaid-js/mermaid-cli -i <file>.mmd -o <file>.svg` — a non-zero SVG output confirms render. A silent parse error produces a near-zero file. Run this for every diagram block before approving.

**GitHub-flavored Mermaid:** `graph TD`, `graph LR`, `stateDiagram-v2`, `sequenceDiagram` all work. `stroke-dasharray:5` in style directives works on GitHub. Dark fill colors with `color:#ffffff` (white text) render correctly.

**Topology accuracy footgun:** When showing on-demand agents (Research, Citation), anchor the spawn-edge from the level that actually triggers them — Team Lead or operator-level slash command — not from the PM node. `system-role-boundaries/SKILL.md` is the canonical reference. An edge from PM to Research implies PM manages Research as a subordinate; the canonical is that `/research` is an operator-invoked command.

**Bug pipeline completeness:** The canonical bug flow includes a Triage re-entry step after DevOps deploys: `Triage pings operator to verify`. Easy to omit in sequence diagrams. Always check `system-role-boundaries/SKILL.md` bug flow section before approving a bug-pipeline diagram.

**DevOps self-trigger:** DevOps watches main for merges (SDLC Step 7) — it is not explicitly delegated to by Code Reviewer. Sequence diagrams often show DO firing without an incoming arrow. This is correct behavior but confusing to newcomers; a `Note over` annotation helps.
