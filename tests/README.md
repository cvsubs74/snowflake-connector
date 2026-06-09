# tests/

All repo tests live here. Plain bash, no framework — `bash tests/run.sh` runs everything.

## Layout

```
tests/
├── run.sh                # entry point: bash tests/run.sh
├── lib.sh                # shared helpers (emit_payload, run_case, assert_eq, assert_set_eq, print_summary)
├── test_hooks.sh         # all 5 (soon 6) hooks' migrated cases — replaces the per-hook --self-test blocks
├── test_consistency.sh   # cross-document consistency checks (label-table parity, hook inventory, agent topology)
├── test_repo.sh          # repo structure sanity (settings.json valid, required docs/agents/skills present)
├── fixtures/
│   └── gh-labels-stub.sh # script-file stub for Hook 3's CLAUDE_HOOK_GH_LABELS_CMD
└── README.md             # this file
```

## Running locally

```bash
bash tests/run.sh                  # all files
bash tests/run.sh test_hooks.sh    # one file by name
```

Prerequisites: `jq` (already used by every hook).

## What each test file covers

- **`test_hooks.sh`** — Every case from the old `--self-test` blocks, one section per hook. ~99 cases today. New cases added here when hooks are added or extended.
- **`test_consistency.sh`** — Cross-document consistency:
  1. Label set parity: `SDLC.md` § "Label scheme" ↔ `.claude/skills/label-discipline/SKILL.md` canonical table.
  2. Hook inventory ↔ registration ↔ filesystem: `.claude/hooks/*.sh` ↔ inventory in `.claude/hooks/README.md` ↔ `.claude/settings.json` registrations.
  3. Agent topology: `.claude/skills/system-role-boundaries/SKILL.md` 8-agent list ↔ `.claude/agents/*.md` filenames.
- **`test_repo.sh`** — Structural sanity:
  - `.claude/settings.json` is valid JSON; every registered hook path resolves to an executable file.
  - All 8 expected agent files present.
  - All 5 skill directories contain a `SKILL.md`.
  - Required cold-start docs (`CLAUDE.md`, `ETHOS.md`, `SDLC.md`) present.
  - `bin/*.sh` pass `bash -n` syntax check.

## Adding a new hook test

1. Append a section to `tests/test_hooks.sh`:
   ```bash
   echo ""
   echo "--- HOOK N: <name> ---"
   HOOK="$HOOKS_DIR/<name>.sh"
   run_case "$HOOK" "label" "command string" "block"
   ```
2. Run `bash tests/run.sh` locally; ensure green.
3. If the hook uses a stub mechanism (like Hook 3's `CLAUDE_HOOK_GH_LABELS_CMD`), `export` it before the `run_case` calls and `unset` after.

## CI

`.github/workflows/ci.yml` includes a `hook-tests` job that installs `jq` and runs `bash tests/run.sh` on every PR. The job is required; PRs cannot merge if it fails.

## Why not bats / shellspec?

Considered. The existing `--self-test` blocks already work; adopting a framework trades familiar working code for a vendoring step + assertion DSL + load-path management. Net code shrinks more from removing the inline self-test blocks than it would from adding bats.
