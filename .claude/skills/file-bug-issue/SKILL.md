---
name: file-bug-issue
description: "Canonical protocol for filing a new bug issue — title format, body template, duplicate check, no-backlog rule."
---

# File a Bug — Canonical Protocol

Use this whenever you (Triage, QA, Dev, or operator) need to file a new `bug` issue. The protocol exists to keep bug reports actionable and to enforce the fast-path discipline (bugs skip the backlog).

---

## Checklist

1. **Duplicate check first.**
2. **Repro steps must be in the body.**
3. **Label `bug` — never `backlog`.**
4. **Include a hypothesis if you have one.**
5. **Document scope (blast radius).**

---

## Step 1 — Duplicate check

```bash
gh issue list --label bug --search "<keyword>" --state all --limit 5
```

If you find a duplicate:

- Comment on the existing issue with the new evidence.
- Re-open if closed and the regression is back.
- Do NOT file a new issue.

If no duplicate:

- Proceed to filing.

---

## Step 2 — File with this template

```bash
gh issue create \
  --title "[BUG] <crisp imperative title — what's broken>" \
  --label "bug" \
  --body "$(cat <<'EOF'
## Repro steps
1. <step>
2. <step>
3. <step>

## Expected
<what should happen>

## Actual
<what does happen — paste error message, attach screenshot link>

## Hypothesis (optional)
<your guess at root cause — name files / functions / commits if you can.
omit if you don't have one>

## Scope
- Blast radius: <one user / tenant / all users / feature-flagged subset>
- First broken: <commit / deploy / date if known, else "unknown">
- Last working: <similar, else "unknown">
- Environment: <prod / staging / dev / local>

## Evidence
<links to logs, screenshots, failed test runs, monitoring dashboards>

## Operator
@<operator-handle>
EOF
)"
```

Add `qa` label if you (QA Agent) filed it. Add no other label.

---

## Hard rules

1. **Never label `backlog`.** Bugs skip the backlog. If you find yourself wanting to add `backlog`, the issue is probably an enhancement, not a bug — re-file accordingly.
2. **Never label `prioritized` or `priority:*`.** Those are PM-exclusive, and bugs don't go through PM anyway.
3. **Never label `resolved`.** That's QA's terminal label, applied only after the §TWO-PASS verification rule.
4. **Repro steps are mandatory.** If you can't reproduce, file with "Repro: currently not reproducing — flagging for visibility" and the evidence you do have. Don't skip the section.
5. **One issue per regression.** If you find two unrelated bugs, file two issues.

---

## Edge cases

### "It might be a regression but I'm not sure"

File anyway. The cost of a misfiled bug is much lower than the cost of a real regression sitting unreported. Note your uncertainty in the body.

### Security-sensitive bug in a public repo

Don't file in the public issue tracker. Surface to operator via direct channel. Use the repo's private security advisory feature if available.

### Performance regression with no clear repro

File with whatever quantitative evidence you have (latency graphs, slow query logs). Mark scope as "all users" or "users with X data shape" based on what the metrics show.

### Bug discovered during a feature implementation

Don't bundle the fix into the feature PR. File a separate bug issue, link from the feature PR ("noticed during implementation of #N"), and let Dev pick it up via the bug fast-path. Keeps PRs reviewable and bisect-friendly.
