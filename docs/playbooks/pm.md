# PM Agent Playbook

Project-specific notes that future-you (the PM agent on this project) needs. Append a section when you learn something worth keeping; delete sections that go stale. Keep this readable end-to-end.

> **Promote-to-skill:** when a procedure here shows up in another agent's playbook too, or you've done it the same way 3+ times, lift it into a shared skill at `.claude/skills/<name>/SKILL.md`. See the `skill-maintenance` skill for the authoring pattern.

## Triage pass — 2026-05-21 (issues #6, #7, #8)

**Hook umbrella slicing pattern.** When a multi-hook issue lands (#7), slice by hook not by layer. Each hook has a different trigger type, intercept target, and acceptance test — they are independent units of work. File one child issue per hook; do NOT batch hooks into a single PR. First child creates the `.claude/hooks/` directory and README skeleton so subsequent children can build on it.

**Option C on doc-vs-hook splits.** When an issue asks "doc fix now or bundle into a bigger hook PR?" — Option C (both) is usually right. Doc fix ships in a tiny PR immediately (correctness now); the hook ships later as part of the infrastructure buildout (enforcement later). The two PRs are independent and can run in parallel.

**Label check before applying.** Always run `gh label list --repo <owner>/<repo>` before editing labels. Do not assume canonical labels exist on a fresh fork — `bin/bootstrap-labels.sh` may need to be run first.

**`priority:medium` is the right default for workflow-tightening issues.** Issues that enforce existing documented rules (CI, hooks, docs) but don't block active work today are medium. Reserve high for issues that make an existing workflow step vacuous or actively misleading in production.

**Umbrella issues get `pm` label.** When filing or promoting an issue that PM is actively tracking as an umbrella (multi-slice), add `pm` to the umbrella so it shows up in `gh issue list --label pm`. Children do not get `pm`.

## Triage pass — 2026-05-21 (umbrella #33 — /investigate audit findings)

**Doc-fix bundling judgment.** When two findings are both trivial doc/text fixes, the instinct is to bundle them into one PR. Prefer separate issues when the fixes touch different file layers (e.g., agent contract file vs. hook script headers) — cleaner diff history and easier bisect. Reserve bundling for fixes so small that the overhead of a second PR exceeds the fix itself.

**"Two paths" findings — pick one and note the override.** When an issue presents two remediation paths (e.g., extend hook enforcement vs. align docs to current enforcement), PM picks the recommended path and files the slice accordingly. Always note in the issue body that the operator can override to the other path — this documents the decision without blocking. Default bias: prefer the simpler path (doc alignment) over adding hook complexity unless the label/gate is truly consequential.

**Umbrellas track; slices are picked up — never `prioritized` an umbrella.** An umbrella issue carries `enhancement,pm` only (plus optionally `backlog` before PM triages it away). Never apply `prioritized` or `priority:*` to the umbrella itself — those labels signal "Dev can pick this up and start coding." Dev sorting the prioritized queue by priority would see the umbrella tied with real slices and waste cycles reading the body to realize it's a tracker. Only the slices get `prioritized,priority:*`. The umbrella stays open until the final slice merges with `Closes #<umbrella>`.

**Final-slice `Closes` pattern.** When slicing an umbrella, designate only the last slice to use `Closes #<umbrella>`. Earlier slices use `Refs #<umbrella>`. Explicitly call this out in the umbrella triage comment so Dev knows which issue to use `Closes` on.

## Triage pass — 2026-05-22 (umbrella #44 — /investigate audit findings, round 2)

**Fold-in instead of separate slice.** When two findings share a root cause and one fix covers both, fold the weaker one in rather than filing a redundant slice. Document the fold decision in the triage table (Decision = "Folded into A"; Issue = "—") so the audit trail is complete. Do not leave a dangling slice that Dev would pick up and find nothing to do.

**Out-of-scope findings still get a triage row.** Even when a finding is explicitly out of scope (documented limitation, design choice), give it a row in the triage table with Decision = "Out of scope" and a one-line rationale. This closes the loop for any future reader wondering why a finding wasn't acted on.

**Operator pre-approved umbrellas skip `backlog`.** When the operator drives the investigation directly and explicitly hands PM the findings to slice, open the umbrella with `enhancement,pm` (no `backlog`). The `backlog` label signals "PM hasn't looked at this yet" — operator-driven audits skip that queue by definition.

## PRD for E2E test suite — 2026-05-22 (umbrella #65)

**Search Before Building discipline when writing infrastructure PRDs.** Before scoping a test suite, read all existing test files, hook scripts, and playbooks end-to-end. The team-lead playbook contained a concrete gap (local worktree cleanup across PRs #56/#58/#59–#61) that became the operator's first-priority invariant. Reading the playbook first saved a round-trip.

**Three-option harness shape presentation.** When the PRD involves a significant infrastructure choice (test harness approach), present the three most realistic options with pros/cons and a recommendation rather than picking silently. This is User Sovereignty applied to technical direction — the operator may have context (e.g., a preference for live-GitHub fidelity) that the PM doesn't. Use the PRD's Open Questions section to surface these.

**Hook upgrade paths belong in child issues, not PRD prose.** The team has at least two documented "Hook N upgrade" paths (Hook 7 for label cleanup, Hook 7 for Designer gate — confusingly both numbered 7 in different docs). When a PRD references these, file them as separate `enhancement,backlog` child issues with the rationale in the body. This gives the operator a clean signal on each one rather than burying them in a PRD section.

**"What exists today" section is mandatory for any infra/tooling PRD.** A test-suite PRD without a gap table is either duplicating existing coverage or missing the real gaps. The gap table (existing tests vs. what's uncovered) is the most valuable artifact PM produces in these PRDs — it converts the operator's vague "more tests" request into a specific delta.
