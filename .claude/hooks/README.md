# .claude/hooks — Claude Code Enforcement Hooks

Hooks are short scripts that Claude Code runs at specific lifecycle points to enforce workflow rules **mechanically**, before any PR is opened. They are the floor — not the ceiling. Agent docs explain the WHY; hooks enforce the WHAT for the mechanical subset.

See the [Claude Code hooks reference](https://docs.anthropic.com/en/docs/claude-code/hooks) for the full contract.

---

## Hook inventory

| # | File | Type | Trigger | Status |
|---|------|------|---------|--------|
| 1 | `no-direct-push-main.sh` | `PreToolUse/Bash` | `git commit` or `git push origin main` while on `main` | **Done — #9** |
| 2 | `restricted-label-ownership.sh` | `PreToolUse/Bash` | `gh issue edit --add-label` / `--remove-label` for protected labels | **Done — #10** |
| 3 | `pr-merge-requires-in-review.sh` | `PreToolUse/Bash` | `gh pr merge` without `in-review` label | **Done — #11** |
| 4 | `session-start-doc-check.sh` | `SessionStart` | Session begin | **Done — #12** |
| 5 | `pr-body-closes-check.sh` | `PreToolUse/Bash` | `gh pr create` with missing `Closes #N` | **Done — #13** |
| 6 | `pr-merge-requires-delete-branch.sh` | `PreToolUse/Bash` | `gh pr merge` without `--delete-branch` / `-d` | **Done** |
| 7 | `auto-clean-worktree.sh` | `PostToolUse/Bash` | after `gh pr merge` succeeds: remove matching `.worktrees/` entry and delete local branch | **Done — #72** |
| 8 | `workaround-audit.sh` | `PostToolUse/Edit\|Write` | edits that add/remove `WORKAROUND\|HACK\|FIXME` comments — warn (Sept 2025 postmortem defense) | **Done** |
| 9 | `system-prompt-audit.sh` | `PostToolUse/Edit\|Write` | edits to `.claude/agents/*`, `.claude/skills/*/SKILL.md`, `.claude/commands/*` — append to audit log (Apr 23 postmortem defense) | **Done** |
| 10 | `verification-gate.sh` | `Stop` | assistant about to claim "done"/"fixed" without recent test/lint/verify calls — warn (`CLAUDE_HOOK_GATE_STOP=block` to enforce) | **Done** |
| 11 | `session-opener.sh` | `SessionStart` | emit the 3-step opener (read `memory/`, `pwd`, run `bin/init.sh`) per Effective harnesses for long-running agents | **Done** |
| 12 | `deploy-reminder.sh` | `UserPromptSubmit` | prompts mentioning deploy/release/rollout get a cohort+soak reminder (Apr 23 postmortem defense) | **Done** |

---

## Running tests

All hook tests live in `tests/test_hooks.sh` (migrated from the per-hook `--self-test` blocks). Run the full suite from the repo root:

```bash
bash tests/run.sh
```

Run just the hook tests (skipping consistency + repo-structure checks):

```bash
bash tests/run.sh test_hooks.sh
```

See `tests/README.md` for the full layout (`tests/lib.sh` helpers, `tests/test_consistency.sh` cross-doc checks, `tests/test_repo.sh` structure sanity).

---

## Hook 1: `no-direct-push-main.sh`

**Purpose:** Block direct `git commit` on `main` and all push forms that target a protected remote branch (`main`, `master`, or whatever `CLAUDE_HOOK_PROTECTED_BRANCHES` lists). Forces all changes through a feature branch + PR, per the SDLC branch-naming rule.

**Trigger:** `PreToolUse` on tool `Bash`

**What it blocks — all forms including refspec bypasses:**
- `git push origin main` (simple)
- `git push origin master`
- `git push --force origin main` / `git push -f origin main`
- `git push -u origin main`
- `git push origin HEAD:main` (refspec — pushes current HEAD to remote main)
- `git push origin refs/heads/main` (full refname)
- `git push origin main:main` (explicit local:remote refspec)
- `git push origin +main` (force-push shorthand via leading `+`)
- `git push origin :main` (delete remote branch)
- `git push origin +main:main` / `git push origin +refs/heads/main` (combined force + refspec)
- `git push 'origin' 'main'` / `git push "origin" "main"` (shell-quoted args — both forms)
- `git push 'origin' 'HEAD:main'` / `git push "origin" "HEAD:refs/heads/main"` (quoted + refspec combined)
- `git commit` when the current branch is `main` or `master`

**What it allows:**
- Any `git push origin <other-branch>` — e.g. `feat/9-my-branch`
- `git push origin mainline` — no false positive on branch names that contain `main`
- `git push upstream main` — different remote, out of scope per issue #9 non-goals
- `git commit` on any branch other than `main`/`master`

**Exit codes:**
- `0` — allow (silent)
- `2` — block (Claude Code will surface the stderr message to the user)

**Rule this enforces:** SDLC.md Step 2 — "No direct commits to the default branch. Every change goes through a PR."

---

### Configuring protected branches

The hook reads the `CLAUDE_HOOK_PROTECTED_BRANCHES` environment variable (space-separated list of branch names). If the variable is not set, it defaults to `main master`.

```bash
# Example: also protect 'develop' and 'release'
export CLAUDE_HOOK_PROTECTED_BRANCHES="main master develop release"
```

Add the export to your shell profile or to the `env` block in `.claude/settings.json` for project-wide enforcement.

---

### Test-branch override (for tests and CI)

The commit-guard check (Check 2) calls `git symbolic-ref --short HEAD` to read the real current branch. This makes the "allow commit on feature branch" test flaky when the test runner is checked out on `main`.

Set `CLAUDE_HOOK_TEST_BRANCH=<branch>` to override the branch lookup with a fixed value:

```bash
# Simulate being on a feature branch (commit allowed)
CLAUDE_HOOK_TEST_BRANCH=feat/test run_case "$HOOK" "..." "git commit -m fix" "allow"

# Simulate being on main (commit blocked)
CLAUDE_HOOK_TEST_BRANCH=main run_case "$HOOK" "..." "git commit -m fix" "block"
```

The `tests/test_hooks.sh` Hook 1 section uses this pattern so the suite is hermetic regardless of the checkout branch.

---

## Hook 2: `restricted-label-ownership.sh`

**Purpose:** Block `gh issue edit` and `gh pr edit` calls that apply or remove owner-restricted labels unless the calling agent is the declared owner per `label-discipline`.

**Trigger:** `PreToolUse` on tool `Bash`

**Restricted label → authorised agents:**

| Label | Authorised agents |
|-------|------------------|
| `prioritized` | `pm-agent` |
| `priority:high` | `pm-agent` |
| `priority:medium` | `pm-agent` |
| `priority:low` | `pm-agent` |
| `pm` | `pm-agent` |
| `resolved` | `qa-agent` |
| `qa` | `qa-agent` |
| `in-review` | `dev-agent` |

All other labels (`bug`, `enhancement`, `backlog`, `in-progress`, etc.) are unrestricted — any agent may apply them.

**What it blocks:**
- `gh issue edit <n> --add-label prioritized` from any non-PM agent
- `gh pr edit <n> --remove-label in-review` from any agent other than dev-agent
- Any combination of the above

**What it allows:**
- Owner applying their own label
- Non-restricted labels (no check performed)
- Operator direct sessions where `agent_type` is absent in hook stdin (fail-open with WARNING — see §Limitation below)
- `CLAUDE_HOOK_BYPASS=1` emergency override

**Exit codes:**
- `0` — allow (silent, or WARNING to stderr when agent identity is absent)
- `2` — block (Claude Code surfaces stderr to the user)

**Rule this enforces:** `label-discipline` SKILL.md hard rules 2, 3, and 4.

---

### Limitation: agent identity

Claude Code sets `agent_type` in the hook stdin JSON **only when running inside a subagent context** (spawned via `--agent` flag or the `Agent` tool). When an operator runs Claude Code directly (no agent wrapper), `agent_type` is absent and the hook **fails open** — it emits a stderr WARNING but allows the label operation through.

This is intentional: operators are trusted principals and can apply any label per the Operator Override Clause in `label-discipline`. The WARNING is a signal to the operator that enforcement was skipped.

**Follow-up:** If full enforcement for all interactive sessions is needed, a separate mechanism (e.g. reading the active agent name from a session env var or settings override) would be required. File an enhancement issue with label `enhancement,backlog` if this gap needs to be closed.

---

## Hook 3: `pr-merge-requires-in-review.sh`

**Purpose:** Block `gh pr merge` if the PR does not carry the `in-review` label. Prevents Dev agents from self-merging and premature merges before the Code Reviewer has signed off.

**Trigger:** `PreToolUse` on tool `Bash`

**What it blocks — all forms including flags and compound commands:**
- `gh pr merge 5` (simple)
- `gh pr merge --squash 5` (flag before number)
- `gh pr merge 5 --squash` (flag after number)
- `gh pr merge 5 --squash --delete-branch` (multiple flags)
- `gh pr merge '5'` / `gh pr merge "5"` (quoted number — both forms)
- `gh pr merge https://github.com/owner/repo/pull/5` (URL form)
- `cd /tmp && gh pr merge 5` (compound command)

**What it allows:**
- `gh pr merge <N>` when PR `<N>` carries the `in-review` label — passes through silently
- `gh pr view`, `gh pr create`, `gh issue close`, and all other non-merge `gh` subcommands
- Any non-`gh` command (`git`, `ls`, etc.)

**Exit codes:**
- `0` — allow (silent)
- `2` — block (Claude Code surfaces the stderr message to the user)

**Rule this enforces:** SDLC.md Step 5 — "Code Reviewer merges. Always."

---

## Hook 4: `session-start-doc-check.sh` — Done (#12, extended #45)

**Purpose:** Sanity-check that required cold-start docs exist in the repo root at session start, and that the local branch is not behind `origin/<default-branch>`. Surfaces informational notes (never blocks) for missing docs or stale local state so the agent knows the situation before acting.

**Trigger:** `SessionStart` event — fires once per Claude Code session, before the agent takes any action.

**Event type: SessionStart**

`SessionStart` is a different hook event type from `PreToolUse`. It fires once when Claude Code starts a new session, not on each tool call. Its JSON stdin payload contains session metadata (e.g. `session_id`, `transcript_path`) rather than tool input. It is registered under the top-level `SessionStart` key in `.claude/settings.json` (NOT inside `PreToolUse`), and does not use a `matcher` field.

```json
"hooks": {
  "SessionStart": [
    {
      "hooks": [
        { "type": "command", "command": ".claude/hooks/session-start-doc-check.sh" }
      ]
    }
  ]
}
```

**Required docs checked:**
- `CLAUDE.md` — agent operating instructions (required)
- `ETHOS.md` — the three principles that override all defaults (required)
- `SDLC.md` — branch naming, PR workflow, label scheme (required)
- `docs/ARCHITECTURE.md` — system shape + change log (optional; informational note if absent)

**Local-vs-origin sync check:**

After the doc checks, the hook runs `git fetch origin --quiet` and then checks whether local is behind `origin/<default-branch>` using `git rev-list --count HEAD..origin/<default-branch>`.

- If local is N commits behind: emits `[HOOK INFO] local is behind origin/<branch> by N commit(s) — run 'git pull' before reading repo state.`
- If up to date: silent (no noise for the common case).
- If `git fetch` fails (no network / offline): emits `[HOOK INFO] git fetch failed (offline?) — could not verify local-vs-origin sync.`

The default branch is detected via `git rev-parse --abbrev-ref origin/HEAD`; falls back to `main` if that command fails (e.g. no remote configured).

**Why this matters:** All 8 agent cold-start protocols run `git log origin/<branch>` without a preceding `git fetch`. A stale local silently sees old state and reports it as current. This hook catches the staleness at the point where it can still be corrected — before the agent acts on bad data. (Audit finding: a session 5 commits behind origin reported 0 in-flight PRs and missing `docs/ARCHITECTURE.md` — both wrong.)

**This hook NEVER BLOCKS.** Exit code is always 0. Blocking `SessionStart` would brick every session. The hook is an advisory surface only.

**Exit codes:**
- `0` — always

**Test-root override (for tests and CI):**
- `--test-root <dir>` flag, or `CLAUDE_HOOK_TEST_ROOT=<dir>` env var — use `<dir>` as the repo root instead of `$PWD`. Flag takes precedence over env var.

**Sync check override (for tests and CI — prevents real git remote calls):**
- `CLAUDE_HOOK_TEST_SYNC=behind:N` — simulate local being N commits behind origin
- `CLAUDE_HOOK_TEST_SYNC=ok` — simulate local being up to date (no output)
- `CLAUDE_HOOK_TEST_SYNC=fetch-failed` — simulate `git fetch` failure (offline)

---

## Hook 5: `pr-body-closes-check.sh` — Done (#13)

**Purpose:** Warn (never block) when `gh pr create` is called without a GitHub auto-close keyword in the PR body. Reduces orphaned PRs that silently fail to close their tracking issues on merge.

**Rationale:** dev-agent.md §5 establishes that `Closes #N` is mandatory for any PR that fully resolves a tracking issue. This hook makes accidental omission visible rather than silent.

**Trigger:** `PreToolUse` on tool `Bash`

**What it warns on:**
- `gh pr create --body "some text"` where the body lacks any auto-close keyword
- `gh pr create --body-file path/to/file` where the file content lacks any auto-close keyword

**What it allows silently:**
- `gh pr create --body "Closes #5"` (or any GitHub auto-close keyword — see below)
- `gh pr create` (no `--body` or `--body-file` — interactive edit, can't check)
- `gh pr create --body-file <path>` where the file does not exist or is not readable
- Any non-`gh pr create` command

**Accepted auto-close keywords (case-insensitive):**
- `Closes #N` / `Close #N`
- `Fixes #N` / `Fix #N`
- `Resolves #N` / `Resolve #N`

`Refs #N` is intentionally NOT in the accepted list — it does not auto-close the issue, so the warning is appropriate.

**Exit codes:**
- `0` — always (warn-only hook; never blocks)

---

## Hook 6: `pr-merge-requires-delete-branch.sh` — Done

**Purpose:** Block `gh pr merge <N>` calls that don't include `--delete-branch` (or its short form `-d`). Enforces the SDLC Step 5 branch-deletion convention at command time so the agent learns the rule.

**Trigger:** `PreToolUse` on tool `Bash`

**What it blocks:**
- `gh pr merge 5` (no flags)
- `gh pr merge 5 --squash` (other flags, no `--delete-branch`)
- `gh pr merge --squash 5 --admin`
- `gh pr merge '5'` / `gh pr merge "5"` (quoted PR number)
- `cd /tmp && gh pr merge 5` (compound)
- `gh pr merge https://github.com/owner/repo/pull/5` (URL form)

**What it allows:**
- `gh pr merge <N> --squash --delete-branch` (required form)
- `gh pr merge <N> --delete-branch --squash` (flag order doesn't matter)
- `gh pr merge <N> -d` (short form)
- `gh pr view`, `gh pr create`, `gh issue close`, and all other non-merge `gh` subcommands
- Any non-`gh` command

**Why both this hook AND the GitHub repo setting?**

- **Server-side:** `gh api -X PATCH repos/{owner}/{repo} -f delete_branch_on_merge=true` deletes the remote branch automatically on merge. Catches everything but is invisible to the agent — silent fix, no learning.
- **This hook:** catches the missing flag at command time, prints an actionable message naming the convention, and ensures `gh pr merge` also cleans up the local tracking ref (which the server setting can't do).

Both are wired up. The hook is the teaching surface; the setting is the safety net.

**Exit codes:**
- `0` — allow (silent)
- `2` — block (Claude Code surfaces the stderr message to the user)

**Rule this enforces:** SDLC.md Step 5 — "branches are deleted on merge to keep `origin` clean."

---

## Operator override (emergency escape hatch)

Every hook checks for the environment variable `CLAUDE_HOOK_BYPASS=1`. Set it in your shell before invoking Claude Code to disable all hook guards for that session:

```bash
CLAUDE_HOOK_BYPASS=1 claude
```

This is an **ops-emergency escape hatch only** — for security hotfixes, post-incident recovery, or cases where the hook fires incorrectly. Normal workflow violations are not emergencies. Document why you used the bypass in the commit message or PR body.

---

## Verifying a hook outside its self-test

### The self-firing recursion problem

When you try to drive a `PreToolUse/Bash` hook manually from inside a live Claude Code session — by piping a JSON payload to the hook script — Claude Code itself fires on the outer `Bash` tool call. If the payload string contains the blocked text (e.g. `"git push origin main"`), the PreToolUse hook finds it inside the echo'd argument and blocks the test before the script ever runs.

**Repro — this fails inside Claude Code:**

```bash
# Claude Code fires Hook 1 on this outer Bash call because
# "git push origin main" appears in the echo'd string.
echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
  | bash .claude/hooks/no-direct-push-main.sh
```

The hooks are working exactly as designed — they fire on every Bash call. The problem is that the test payload leaks the blocked string into the outer command.

### Workarounds

**Option 1 — Stage the payload in a file (recommended)**

Write the JSON to a temp file outside the `Bash` call, then pipe from the file. The outer command no longer contains the blocked string.

```bash
# Step 1: write payload — no blocked text in this command
cat > /tmp/hook-test-payload.json << 'EOF'
{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}
EOF

# Step 2: drive the hook — outer command has no blocked text
bash .claude/hooks/no-direct-push-main.sh < /tmp/hook-test-payload.json
# Expected: exit 2 + stderr block message
echo "Exit code: $?"
```

This is the recommended path for ad-hoc e2e spot-checks from inside a Claude Code session. The two-step split keeps the blocked string inside the file (opaque to the hook scanner) while the outer Bash command remains clean.

**Option 2 — Run from a plain terminal (no hook registered)**

Open a regular terminal (not a Claude Code session). PreToolUse hooks are only registered when Claude Code is running, so the outer Bash call is not intercepted.

```bash
# In a plain terminal:
echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
  | bash .claude/hooks/no-direct-push-main.sh
```

This is the cleanest path for full e2e coverage. The automated test suite (`bash tests/run.sh`) uses this environment by design.

**Option 3 — `CLAUDE_HOOK_BYPASS=1` (ops-emergency only)**

Setting `CLAUDE_HOOK_BYPASS=1` disables all hook guards for the session. This silences the recursion but also defeats the hooks you are trying to test. Reserve this for the ops-emergency scenarios described in §Operator override — do not use it as a testing workaround.

### Summary

| Approach | Works inside Claude Code? | Hooks still active for test? | Recommended? |
|----------|--------------------------|------------------------------|--------------|
| File-staged payload | Yes | Yes | **Yes** |
| Plain terminal | N/A (outside Claude Code) | Yes | Yes — for full e2e |
| `CLAUDE_HOOK_BYPASS=1` | Yes | No | No — defeats the test |

The automated suite in `tests/` already runs in a plain-terminal CI context and covers the canonical cases. Use the file-staged-payload approach for quick one-off spot-checks without leaving your Claude Code session.

---

## How hooks are registered

Hooks are registered in `.claude/settings.json` under a `hooks` key. Different event types use different top-level keys. Example showing both `PreToolUse` and `SessionStart`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/no-direct-push-main.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": ".claude/hooks/session-start-doc-check.sh" }
        ]
      }
    ]
  }
}
```

**Key differences by event type:**

| Event | `matcher` field | stdin payload | Exit 2 = block? |
|-------|----------------|---------------|-----------------|
| `PreToolUse` | Required — matches the tool name (e.g. `"Bash"`) | `{"tool_name":"...","tool_input":{...}}` | Yes — blocks the tool call |
| `SessionStart` | Not used | `{"session_id":"...","transcript_path":"..."}` | No — must always exit 0 |

Claude Code passes a JSON object to the hook's stdin. For `PreToolUse`, the hook reads the command, decides allow/block, and exits with 0 or 2. For `SessionStart`, the hook must always exit 0 — blocking would brick the session.

---

## Adding a new hook

1. Write the script in this directory. Follow the pattern in `no-direct-push-main.sh`.
2. `chmod +x` the script.
3. Register it in `.claude/settings.json`.
4. Add a row to the inventory table above.
5. Append a section to `tests/test_hooks.sh` covering the new hook's cases (use `run_case` for exit-code hooks, `run_case_warn` for warn-only hooks).
6. Run `bash tests/run.sh` and ensure all cases pass.
7. The `test_consistency.sh` "hook inventory" check will fail until steps 3 and 4 are done — that's the safety net catching incomplete registration.

---

## Hook 7: `auto-clean-worktree.sh` — Done (#72, fixed #81)

**Purpose:** After a successful `gh pr merge` (in the operator's main session), automatically remove the matching `.worktrees/` entry and delete the local branch.

**Trigger:** `PostToolUse` on tool `Bash` (fires after the Bash tool returns, not before)

**IMPORTANT LIMITATION (issue #81):** `PostToolUse` hooks registered in `settings.json` do NOT fire for Bash tool calls made inside agent sub-sessions (anthropics/claude-code #34692, open March 2026). This means Hook 7 is silent for every CR-agent merge — which is 99% of real-world merges. The primary fix for issue #81 is `bin/merge-pr.sh`, which CR agents call instead of `gh pr merge` directly. Hook 7 remains registered and still runs cleanup for main-session merges.

**PostToolUse stdin payload (real runtime fields — issue #81 fix):**

The Claude Code runtime sends `stdout`, `stderr`, and `exit_code` — NOT `output` and `error`:

```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "<bash command string>" },
  "tool_response": { "stdout": "<stdout>", "stderr": "<stderr>", "exit_code": 0 }
}
```

The original implementation read `.tool_response.error` and `.tool_response.output` (wrong field names). The corrected hook reads `.tool_response.stderr // .tool_response.error` (with fallback for backward compat) and `.tool_response.stdout // .tool_response.output`.

**Exit-code-1 non-suppression (issue #81, Hypothesis 2 fix):**

`gh pr merge` may return exit code 1 when the local branch deletion fails because a worktree still has it checked out ("Cannot delete branch '...' checked out at '...'"). The merge on GitHub already succeeded in this case. The hook does NOT bail on non-zero exit code alone — it only skips cleanup when a known merge-failure phrase is present in stderr AND exit code is non-zero.

**Ordering constraint:** `git branch -D <branch>` fails if a worktree still has the branch checked out. This hook always removes the worktree first, then deletes the local branch.

**What it does — happy path:**
1. Detects a `gh pr merge` command in `tool_input.command`
2. Checks for merge-failure phrase in stderr + non-zero exit_code — if both, skip cleanup
3. Extracts the PR number from the command (same token-walking logic as Hook 3)
4. Calls `gh pr view <N> --json headRefName` to get the merged branch name
5. Scans `git worktree list --porcelain` for entries under `.worktrees/` on that branch
6. For each match: checks for uncommitted changes (safety guard), then runs `git worktree remove <path>` followed by `git branch -D <branch>`
7. Logs each action to stderr so the user sees confirmation

**What it does — no-match path:**
- No matching worktree found (Dev already cleaned up manually) → exits silently (0). This is valid state.

**Safety guard:**
- If `git status --porcelain` shows uncommitted changes in a worktree, the hook logs a WARNING and skips that worktree. The Dev session must clean up manually.

**Scope guard:**
- Only removes worktrees under `<repo-root>/.worktrees/`. Worktrees in other locations are left untouched.

**This hook ALWAYS exits 0.** It is a cleanup helper, not an enforcement gate. Cleanup failure is logged as a WARNING, never as a blocking error.

**Exit codes:**
- `0` — always

**Environment overrides (for test isolation):**
- `CLAUDE_HOOK_BYPASS=1` — skip all checks (ops emergency)
- `CLAUDE_HOOK_TEST_REPO_ROOT=<dir>` — override repo root instead of using `git rev-parse --show-toplevel`
- `CLAUDE_HOOK_TEST_GH_BRANCH_CMD=<cmd>` — override the `gh pr view` call; the stub receives the PR number as `$1` and must print the branch name to stdout

**Registration in `.claude/settings.json`:**
```json
"PostToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      { "type": "command", "command": ".claude/hooks/auto-clean-worktree.sh" }
    ]
  }
]
```

**Rule this enforces:** SDLC.md Step 7 — "After the PR merges: `git worktree remove .worktrees/<task-id>` and `git branch -D <branch>`."

---

## bin/merge-pr.sh — Issue #81 primary fix

This is not a hook script — it lives in `bin/` and is called explicitly by CR agents.

**Purpose:** Wrap `gh pr merge` with guaranteed post-merge worktree cleanup that works in all contexts including agent sub-sessions.

**Why it exists:** `PostToolUse` hooks do not fire for agent sub-session tool calls (see Hook 7 IMPORTANT LIMITATION above). `bin/merge-pr.sh` runs the cleanup logic directly after the merge, bypassing the hook dispatch limitation.

**Usage (CR agent only):**
```bash
bin/merge-pr.sh <PR-NUMBER> --squash
```

**Environment overrides (for test isolation):**
- `CLAUDE_HOOK_BYPASS=1` — falls through to plain `gh pr merge` (no cleanup)
- `CLAUDE_HOOK_TEST_REPO_ROOT=<dir>` — same as Hook 7
- `CLAUDE_HOOK_TEST_GH_BRANCH_CMD=<cmd>` — same as Hook 7
- `CLAUDE_HOOK_TEST_MERGE_CMD=<cmd>` — override the `gh pr merge` call itself; stub receives `<pr_num> --delete-branch <extra-flags>` and must print merge output to stdout
