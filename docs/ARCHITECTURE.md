# Architecture

> Update this file and append a Change Log row whenever a change touches module shape, data flow, schema, or constraints.

## System overview

This repository is the **claude-workflow** project: a Claude Code agent team that agents iterate on itself. The "system" is not a deployed web service — it is a set of shell hooks, agent role contracts, SDLC conventions, eval scaffolding, MCP wiring, layered-safety configs, and test suites that govern how a multi-agent engineering team coordinates work via GitHub Issues and Pull Requests.

The team is **8 always-on agents** (Team Lead + 7 specialists: PM, Triage, Dev, QA, Code Reviewer, DevOps, Designer) plus **2 on-demand specialists** (research-agent, citation-agent) spawned via `/research` for breadth-first discovery. There is no data store, no SPA, and no cloud deployment; the runtime is Claude Code running locally or in CI, driven by `.claude/settings.json`, `.mcp.json`, `auto-mode.yaml`, and `sandbox.json`. The primary external dependency is the GitHub API (accessed via `gh` CLI plus the GitHub MCP server). The Playwright MCP is wired by default for browser-based verification.

The architecture is derived from the full [Anthropic engineering blog corpus](https://www.anthropic.com/engineering) — every directory and skill below cites the post that motivated it.

## Module map

```
.
├── .claude/
│   ├── agents/             # 10 role contracts (8 always-on + 2 on-demand)
│   ├── commands/           # 10 slash commands
│   ├── hooks/              # 12 enforcement hooks + README.md
│   ├── skills/             # 14 cross-agent skills (procedural knowledge)
│   ├── audit/              # System-prompt change audit log (created on first edit)
│   └── settings.json       # Hook registrations, permission allowlist, env flags
├── .mcp.json               # Default MCP wiring (Playwright + GitHub)
├── auto-mode.yaml          # Semantic classifier policy (environment, block_rules, allow_exceptions)
├── sandbox.json            # OS-level isolation policy (FS allowlist, network allowlist, scoped git creds)
├── docs/
│   ├── ARCHITECTURE.md     # this file
│   ├── prd/                # Product requirement docs (PRD-<topic>.md)
│   ├── design/             # Design docs (DESIGN-<topic>.md)
│   ├── contracts/          # Generator ↔ Evaluator sprint contracts
│   ├── playbooks/          # Per-agent scratchpads (gotchas, env quirks)
│   ├── tool-design.md      # 7 rules from "Writing tools for agents"
│   └── HEARTBEAT.md        # Liveness canary target
├── memory/                 # Durable agent state (PROGRESS / DECISIONS / NOTES)
├── evals/
│   ├── tasks/              # YAML eval definitions, one per task; OOD-tagged
│   ├── graders/            # Code / LLM / state-based graders
│   ├── rubrics/            # Markdown rubrics + calibration set
│   ├── harness/            # eval_runner.py + anomaly.py (eval-awareness detector)
│   ├── results/            # Per-run transcripts + metrics.json
│   └── prod_monitor/       # Continuous quality, cross-platform equivalence, cohort segmentation
├── mcp/
│   ├── servers/            # Project-local MCP servers (one dir each, shippable as .mcpb)
│   ├── Makefile            # mcpb init / mcpb pack helpers
│   └── README.md
├── tools/                  # In-repo code-execution helpers (filesystem-as-tool-registry)
├── tests/
│   ├── run.sh              # Entry point: bash tests/run.sh
│   ├── lib.sh              # Shared helpers (emit_payload, run_case, assert_eq, ...)
│   ├── test_hooks.sh       # Per-hook behavioral tests
│   ├── test_consistency.sh # Cross-doc drift detection
│   ├── test_repo.sh        # Repo structure sanity
│   ├── test_e2e_*.sh       # End-to-end archetype flows
│   └── fixtures/           # Stubs for hook test isolation
├── bin/                    # Operational scripts (init-project.sh, gh-scoped-cred.sh, merge-pr.sh, ...)
├── CLAUDE.md               # Agent operating instructions + coding discipline
├── ETHOS.md                # Boil the Lake · Search Before Building · User Sovereignty
└── SDLC.md                 # Branch naming, PR workflow, label scheme, commit conventions
```

## Hook layout

Twelve enforcement hooks run inside Claude Code's hook lifecycle. All scripts live under `.claude/hooks/` and are registered in `.claude/settings.json`. Full detail (behavior, test cases, known limitations) is in `.claude/hooks/README.md`.

The 12 hooks fall into three families:

- **PR discipline (1–7)** — pre-existing enforcement of the SDLC.md rules.
- **Postmortem-prevention (8–12)** — added in PR #93, encoding defenses from the Anthropic [Apr 23](https://www.anthropic.com/engineering/april-23-postmortem) and [Sept 2025](https://www.anthropic.com/engineering/a-postmortem-of-three-recent-issues) postmortems.

| # | Script | Event type | What it enforces |
|---|--------|------------|------------------|
| 1 | `no-direct-push-main.sh` | `PreToolUse/Bash` | Blocks `git commit` on `main` and all push forms targeting a protected branch. Forces feature-branch + PR workflow (SDLC Step 2). |
| 2 | `restricted-label-ownership.sh` | `PreToolUse/Bash` | Blocks `gh issue edit`/`gh pr edit` calls that apply or remove owner-restricted labels (`prioritized`, `priority:*`, `resolved`, `in-review`, etc.) from unauthorized agents. |
| 3 | `pr-merge-requires-in-review.sh` | `PreToolUse/Bash` | Blocks `gh pr merge` when the PR does not carry the `in-review` label. Prevents Dev self-merge and premature merges before Code Reviewer sign-off. |
| 4 | `session-start-doc-check.sh` | `SessionStart` | Warns (never blocks) when required cold-start docs (`CLAUDE.md`, `ETHOS.md`, `SDLC.md`) are missing, and emits an INFO note when `docs/ARCHITECTURE.md` is absent. |
| 5 | `pr-body-closes-check.sh` | `PreToolUse/Bash` | Warns (never blocks) when `gh pr create` is called without a GitHub auto-close keyword (`Closes #N`, `Fixes #N`, `Resolves #N`) in the PR body. |
| 6 | `pr-merge-requires-delete-branch.sh` | `PreToolUse/Bash` | Blocks `gh pr merge` calls that omit `--delete-branch` (or `-d`). Enforces branch-deletion at merge time (SDLC Step 5). |
| 7 | `auto-clean-worktree.sh` | `PostToolUse/Bash` | After a successful `gh pr merge`, removes the matching `.worktrees/` entry and deletes the local branch. Closes the post-merge cleanup gap (SDLC Step 7). |
| 8 | `workaround-audit.sh` | `PostToolUse/Edit\|Write` | Warns when an edit adds or removes `WORKAROUND`/`HACK`/`FIXME` comments. Defends against the Sept 2025 postmortem failure mode (silently removing a workaround re-introduces the underlying bug). |
| 9 | `system-prompt-audit.sh` | `PostToolUse/Edit\|Write` | Appends a line to `.claude/audit/system-prompt-changes.log` whenever a file under `.claude/agents/`, `.claude/skills/*/SKILL.md`, or `.claude/commands/` is changed. Defends against the Apr 23 postmortem failure mode (untraceable prompt-line changes with outsized quality impact). |
| 10 | `verification-gate.sh` | `Stop` | Warns when the assistant is about to stop with "done"/"fixed"/"complete" language but the recent transcript shows no test/lint/verify calls. Advisory by default; set `CLAUDE_HOOK_GATE_STOP=block` to enforce. |
| 11 | `session-opener.sh` | `SessionStart` | Emits the 3-step opener (read `memory/`, `pwd`, run `bin/init.sh` smoke) per [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents). |
| 12 | `deploy-reminder.sh` | `UserPromptSubmit` | When the operator's prompt mentions deploy/release/rollout, injects a cohort-rollout + soak-period reminder. |

**Registration pattern in `.claude/settings.json`:** PR-discipline hooks register on `PreToolUse/Bash`; postmortem-prevention hooks register variously on `PostToolUse/Edit|Write`, `SessionStart`, `Stop`, and `UserPromptSubmit`. `PreToolUse` and `Stop` hooks can exit 2 to block; the rest are advisory (always exit 0). See `.claude/hooks/README.md` for the full event-type comparison table.

## Agent topology

The team has **10 agent role contracts** total: 8 always-on (Team Lead + 7 specialists) plus 2 on-demand (research-agent, citation-agent) spawned via `/research`.

### Always-on team (8 agents)

```
Human Operator
     │ "ship X by Friday" / "drain the backlog" / "investigate flaky scenario Y"
     ▼
┌────────────────────────────────────────┐
│  team-lead-agent  (the lead)           │
│  Plans · Delegates · Tracks · Reports  │
└────────────────────────────────────────┘
     │
     ├──────┬──────┬──────┬──────┬─────────┬──────────┐
     ▼      ▼      ▼      ▼      ▼         ▼          ▼
  ┌────┐ ┌──────┐ ┌────┐ ┌────┐ ┌────┐ ┌────────┐ ┌──────────┐
  │ PM │ │Triage│ │Dev │ │ QA │ │ CR │ │ DevOps │ │ Designer │
  └────┘ └──────┘ └────┘ └────┘ └────┘ └────────┘ └──────────┘
```

| Agent | Primary responsibility |
|-------|----------------------|
| `team-lead-agent` | Goal decomposition, cross-agent coordination, status synthesis, escalation. Router/budget allocator (not a manager). |
| `pm-agent` | Backlog triage, PRDs, slicing, `prioritized` + `priority:*` label ownership. Planner role in the harness. |
| `triage-agent` | Bug intake, 60–90s root-cause hypothesis, enriched bug filing, post-merge operator-verification. |
| `dev-agent` | Code, branches, PRs, design docs; picks up `bug` and `prioritized` issues. Generator role in the harness. |
| `qa-agent` | Bug discovery, post-merge verification, `resolved` label, test coverage. Evaluator role in the harness. |
| `code-reviewer-agent` | PR review, merge, cross-flow contract enforcement. Evaluator role in the harness. |
| `devops-agent` | Deploys, secrets, infrastructure health checks, rollback. |
| `designer-agent` | PRD UX review (mockups + open Qs), frontend PR visual quality gate. Planner role in the harness. |

### On-demand specialists (2 agents)

Spawned via `/research`. They do not own labels and are not part of the build chain. They inform Planner work.

| Agent | Primary responsibility |
|-------|----------------------|
| `research-agent` | Lead-worker orchestrator for breadth-first discovery. Decomposes the operator's question into 3–5 sub-questions, spawns parallel sub-agents, synthesizes findings with citations. Per the [multi-agent research post](https://www.anthropic.com/engineering/multi-agent-research-system). |
| `citation-agent` | Verifies that every claim in a draft document resolves to its cited source. Returns READY_TO_SHIP / NEEDS_REVISION. Last line of defense against confident-but-wrong synthesis. |

Full role contracts live in `.claude/agents/<role>-agent.md`. The canonical topology + label-ownership reference is `.claude/skills/system-role-boundaries/SKILL.md`. The Planner / Generator / Evaluator mapping is in `.claude/skills/harness-mapping/SKILL.md`.

## Skill layout

Fourteen skills under `.claude/skills/<name>/SKILL.md` — five pre-existing, nine new in PR #93. Every skill cites the Anthropic engineering post that motivated it (where applicable).

| Skill | Purpose |
|-------|---------|
| `label-discipline` | Canonical 12-label table + ownership rules |
| `file-bug-issue` | Bug filing protocol (no-backlog rule, title format, body template) |
| `worktree-management` | How specialists create/use/clean up git worktrees |
| `skill-maintenance` | How to update an agent's role file or a shared skill (agent-doc-PR pattern) |
| `system-role-boundaries` | Canonical agent topology + label ownership (single source of truth) |
| `harness-mapping` | 8-agent team → Planner / Generator / Evaluator harness mapping |
| `contract-negotiation` | Generator ↔ Evaluator sprint contract authoring |
| `think-tool-wiring` | Pause-to-reason discipline for policy-heavy specialists (54% gain on τ-Bench) |
| `tool-design` | 7 rules from "Writing tools for agents" |
| `safety-layering` | Sandbox + auto-mode classifier + hooks composition |
| `swarm-dispatch` | Partitionable bulk work via git lockfiles (C-compiler pattern) |
| `research-burst` | Lead-worker discovery pattern (multi-agent research post) |
| `eval-runner` | How to add and run agent/product evals |
| `quality-monitor` | Continuous prod quality + regression triage |

## Eval layer

`evals/` is the project's quality measurement substrate. Three grader types (code-based, LLM-based, state-based) combine per task into a `pass@k` + `pass^k` report with Wilson 95% CI. Every task declares `resources: {guaranteed, ceiling}` for infra-noise discipline ([Infra noise post](https://www.anthropic.com/engineering/infrastructure-noise)) and embeds a canary string for eval-awareness detection ([BrowseComp post](https://www.anthropic.com/engineering/eval-awareness-browsecomp)).

`evals/prod_monitor/` provides three additional surfaces:

- `continuous_quality.py` — runs the eval suite against the live system on a schedule (defense against the [Sept 2025 routing bug](https://www.anthropic.com/engineering/a-postmortem-of-three-recent-issues) which grew 0.8% → 16% before detection because monitoring only checked a canary).
- `cross_platform_eq.py` — cross-platform output equivalence + character-script anomaly detection (defense against the TPU corruption bug from the same postmortem).
- `cohort_segment.py` — per-cohort metric report (defense against the [Apr 23 postmortem](https://www.anthropic.com/engineering/april-23-postmortem) where three independent changes degraded different traffic slices and masked each other).

The `/eval` command runs the suite end-to-end and reports per-cohort regressions. The `quality-monitor` skill ties it together.

## MCP + tools layer

`.mcp.json` ships with two default servers:

- **Playwright MCP** — browser automation for UI verification (used by `verify`, the Evaluator role, and any eval task that grades UI behavior).
- **GitHub MCP** — typed access to issues / PRs / checks. Auth via `GITHUB_PERSONAL_ACCESS_TOKEN`. Replaces high-frequency `gh` shell-outs.

Project-local MCPs live under `mcp/servers/<name>/` and ship as `.mcpb` packages (one-click install via Claude Desktop). The `mcp/Makefile` wraps `npx @anthropic-ai/mcpb init` + `pack`. See [Desktop Extensions post](https://www.anthropic.com/engineering/desktop-extensions).

In-repo helpers — not full MCP servers — live under `tools/` per the filesystem-as-tool-registry pattern ([Code execution with MCP post](https://www.anthropic.com/engineering/code-execution-with-mcp)): each tool is one file whose docstring is its schema; agents `ls`/`cat` only what they need.

## Safety layer

Three composable mechanisms:

- **Sandbox** (`sandbox.json`) — OS-level FS + network isolation. cwd is read/write; everything else needs an explicit allowlist entry. All outbound traffic routed through a domain allowlist.
- **Auto-mode classifier** (`auto-mode.yaml`) — semantic Stage-1/Stage-2 classifier with project-specific `environment`, extended `block_rules`, and branch-scoped `allow_exceptions`. Escalates on 3 consecutive or 20 total denials.
- **Hooks** (`.claude/settings.json` + `.claude/hooks/*.sh`) — deterministic gates for things that MUST happen, not just MIGHT (PR discipline, lint, audit logging).

The `safety-layering` skill explains which layer owns which class of rule and how to decide where a new rule belongs. The `bin/gh-scoped-cred.sh` helper is the scoped git credential mechanism — SSH keys and signing keys never enter the sandbox.

## Memory layer

`memory/` holds durable agent state that survives context compaction and session resets:

- `PROGRESS.md` — active goals, in-flight tasks. Whichever agent is driving owns it.
- `DECISIONS.md` — architectural choices + why (mini-ADRs). Append-only; never edit, only supersede.
- `NOTES.md` — structured note-taking output. Bullet-and-prune.

Per the [Effective context engineering post](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents): file-based external memory outperforms in-context state for long-running work. The `session-opener` hook (Hook 11) reminds every fresh session to read these before acting.

## Test layers

All tests are plain Bash. Run everything with `bash tests/run.sh` from the repo root. See `tests/README.md` for full layout.

| File | What it catches |
|------|----------------|
| `tests/test_hooks.sh` | Per-hook behavioral correctness: allow/block decisions, edge cases (quoted args, URL forms, compound commands, refspec variants), and warn-only hooks that must always exit 0. Approximately 149 cases covering Hooks 1–7. |
| `tests/test_repo.sh` | Structural sanity: `.claude/settings.json` is valid JSON, every registered hook path resolves to an executable file, all expected agent files are present, all skill directories contain a `SKILL.md`, required cold-start docs exist, and `bin/*.sh` + `.claude/hooks/*.sh` pass `bash -n` syntax check. |
| `tests/test_consistency.sh` | Cross-doc drift detection: (1) label-set parity between `SDLC.md` and `label-discipline` SKILL.md; (2) hook inventory ↔ registration ↔ filesystem (hooks listed in README.md match scripts on disk and registrations in `settings.json`); (3) hook header count ("Hook N of 12") matches filesystem count; (4) agent topology (10-agent expected list matches agent `.md` filenames). |
| `tests/test_e2e_*.sh` | End-to-end SDLC archetype flows: smoke, bug fast-path, enhancement archetypes, umbrella + hotfix, Hook 7 worktree cleanup. |

## Constraints / invariants

- **No direct commits to `main`.** Every change goes through a feature branch + PR; Hook 1 enforces this mechanically.
- **PRs require `in-review` label before merge.** Hook 3 enforces this; Code Reviewer is the only role that merges.
- **Label ownership is role-locked.** Hook 2 enforces restricted labels; see `label-discipline` SKILL.md for the canonical table.
- **Branches deleted on merge.** Hook 6 enforces `--delete-branch` at command time; the GitHub repo setting is the server-side safety net.
- **Local worktrees auto-cleaned after merge.** Hook 7 fires after a successful `gh pr merge`, removes matching `.worktrees/` entries, and deletes the local branch (SDLC Step 7 invariant).
- **Evidence before assertions.** Hook 10 (verification-gate) warns when "done"/"fixed" language appears without recent test/lint/verify calls. Per superpowers:verification-before-completion and the Apr 23 postmortem.
- **System prompt changes are audit-logged.** Hook 9 appends every edit under `.claude/agents/`, `.claude/skills/*/SKILL.md`, or `.claude/commands/` to `.claude/audit/system-prompt-changes.log`.
- **WORKAROUND removal warns.** Hook 8 advises on removal of `WORKAROUND`/`HACK`/`FIXME` comments without a root-cause note.
- **Non-trivial work needs a contract.** New features and multi-file bug fixes get a Generator ↔ Evaluator sprint contract at `docs/contracts/<N>-<slug>.md`. See `contract-negotiation` skill.
- **Layered safety.** Sandbox + auto-mode + hooks compose; one rule per cheapest layer. See `safety-layering` skill.
- **ARCHITECTURE.md must stay current.** Append a Change Log row on any change that touches module shape, data flow, schema, or constraints.

## External dependencies

| Service | Purpose | Failure mode if down |
|---------|---------|----------------------|
| GitHub API (`gh` CLI + GitHub MCP) | Issue tracking, PR workflow, label enforcement | Hooks 2, 3, 5, 6 cannot make API calls; agents cannot open PRs or query labels. Work can continue locally; sync when restored. |
| Claude Code runtime | Agent execution, hook lifecycle, worktree management, auto-mode classifier, sandbox | All agent activity pauses; no fallback. |
| Playwright MCP (npm `@playwright/mcp`) | Browser automation for UI verification | `verify` skill and UI-grading eval tasks degrade to "cannot verify"; Code Reviewer is then the only quality gate. |
| Anthropic SDK (`anthropic` Python package) | LLM grader in `evals/graders/llm_grader.py` | LLM-based eval tasks skipped; code/state graders still run. |

## Change Log

> Most recent at the top.

| Date | PR | What changed | Why |
|------|----|----|-----|
| 2026-05-25 | #93 | Anthropic-engineering-derived system expansion. **Added**: `evals/`, `memory/`, `docs/contracts/`, `tools/`, `mcp/`, `.mcp.json`, `auto-mode.yaml`, `sandbox.json`; 9 skills (harness-mapping, contract-negotiation, think-tool-wiring, tool-design, safety-layering, swarm-dispatch, research-burst, eval-runner, quality-monitor); 2 on-demand agents (research-agent, citation-agent); 3 commands (/eval, /swarm, /research); 5 hooks (workaround-audit, system-prompt-audit, verification-gate, session-opener, deploy-reminder); `bin/gh-scoped-cred.sh`. **Modified**: dev-agent / qa-agent / code-reviewer-agent / triage-agent gain HARNESS ROLE + USING THE THINK TOOL sections; CLAUDE.md + README.md document the new structure; `bin/init-project.sh` scaffolds new dirs; `test_consistency.sh` updated to expect 10 agents + 12 hooks; existing 7 hooks renumbered "of 7" → "of 12"; `bin/merge-pr.sh` pre-existing dead vars removed (SC2034 CI fix) | Derive a comprehensive product-build system from the full Anthropic engineering blog corpus: evals + observability layer (was missing), file-based handoff contracts between Dev and QA, MCP wiring, sandboxing + auto-mode safety, burst-mode skills, postmortem-prevention hooks. All additive; existing 8-agent topology + ETHOS + SDLC + worktree discipline unchanged. |
| 2026-05-22 | #88 | `bin/merge-pr.sh` Section 3: add Tier 3 success-detection path — after banner-match and exit-0 both fail, call `gh pr view <N> --json state` and treat `MERGED` as success; add `CLAUDE_HOOK_TEST_PR_STATE_CMD` env override; `test_hooks.sh` +2 cases (Tests 17–18) | Fix #87: gh v2.89.0+ suppresses banner in non-TTY subshell AND exits 1 when head branch is checked out in sibling worktree — both initial guards defeated, cleanup was silently skipped even though remote merge succeeded |
| 2026-05-22 | #78 | Hook 7 (`auto-clean-worktree.sh`): PostToolUse hook auto-removes local worktree + branch after `gh pr merge` succeeds; all hook headers bumped "of 6" → "of 7"; `test_hooks.sh` +12 cases; `test_e2e_hook7_worktree_cleanup.sh` +10 E2E assertions | Closes recurring post-merge cleanup gap (resolves #72) |
| 2026-05-22 | #43 | Initial `docs/ARCHITECTURE.md` created from template | Eliminates session-start `[HOOK INFO]` noise; gives agents a live update surface as the system evolves (resolves #38) |
| 2026-05-22 | #42 | `SDLC.md` Step 5 + `code-reviewer-agent.md` document Designer-gate as convention-only | Honest docs about which gates are mechanical (hooks) vs convention (CR honor system) (resolves #37) |
| 2026-05-22 | #41 | Hook script headers updated "Hook N of 5" → "Hook N of 6"; Check 2b added to `tests/test_consistency.sh` | Doc rot from Hook 6 addition; new check prevents this class of drift from recurring silently (resolves #35) |
| 2026-05-22 | #40 | `label-discipline` + `system-role-boundaries` SKILLs clarify hook-enforced `in-review` vs convention-only `in-progress` | Honest about which labels are mechanically enforced vs convention-only (resolves #36) |
| 2026-05-22 | #39 | `team-lead-agent.md` inline label summary corrected: `bug` owned by QA / Triage / Dev / Operator (not Triage-only) | Drift fix; canonical owner table in `label-discipline` was right, inline summary was wrong (resolves #34) |
