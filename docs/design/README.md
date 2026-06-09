# Design Docs

This directory holds engineering design docs. One file per non-trivial feature or refactor.

Filename convention: `DESIGN-<topic>.md` (kebab-case, descriptive). Examples:

- `DESIGN-bulk-import.md`
- `DESIGN-payment-failure-recovery.md`
- `DESIGN-event-sourcing-migration.md`

Design docs are owned by **Dev Agent** (for engineering shape) or **Designer Agent** (for UX shape, typically as a separate doc or section). See `.claude/agents/dev-agent.md` for the canonical design-doc shape and authoring workflow.

When in doubt: write the design doc. The cost of writing one is small; the cost of skipping one and discovering the design was wrong mid-implementation is large.
