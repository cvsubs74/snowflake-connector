---
description: Weekly retro — shipping streaks, test health, growth opportunities.
---

# Retro

Adapted from [garrytan/gstack](https://github.com/garrytan/gstack)'s `/retro` — used and credited under MIT license.

Produce a weekly retro for the engineering team. Focus on what shipped, what stalled, what's at risk, and one concrete growth opportunity. Targeted at the operator; should be readable in under 2 minutes.

## Time window

Default: last 7 days. Override with `$1` (e.g., `/retro 14d` for last 14 days, `/retro since-2026-05-01` for since a date).

## Data sources

Pull from GitHub:

```bash
# Merged PRs in window
gh pr list --state merged --search "merged:>=YYYY-MM-DD" --json number,title,author,mergedAt,labels --limit 50

# Closed issues in window
gh issue list --state closed --search "closed:>=YYYY-MM-DD" --json number,title,labels,closedAt --limit 50

# Open bugs (current state)
gh issue list --label bug --state open --json number,title,createdAt --limit 20

# Open in-flight PRs
gh pr list --state open --json number,title,createdAt,labels --limit 20

# Open prioritized work
gh issue list --label prioritized --state open --json number,title,labels --limit 20
```

## Retro shape

```markdown
# Retro: <week of YYYY-MM-DD>

## Shipped this week
- <N PRs merged> — <breakdown: bugs / features / chores>
- Notable: <#PR title> — <why it mattered>
- Notable: <#PR title> — <why it mattered>

## In flight
- <N open PRs>, oldest <X> days
- <Y> PRs awaiting review (in-review label)
- <Z> prioritized issues not yet picked up

## Test health
- <Tests added this week>
- <Open `bug` count vs last week — direction>
- <Any `qa-failure` or scenario regressions worth flagging>

## Blockers / risks
- <#issue or #PR>: <one-line description of blocker>
- <Deploy currency: any service shipped to main but not to prod?>

## Shipping streak
- <N consecutive days with at least one PR merged>
- <Best streak this month / year>

## One growth opportunity
<Pick ONE concrete improvement for next week. Examples:
 - "Our `qa` queue has grown by 3 issues — let's drain it next week."
 - "Three PRs sat `in-review` >48h. Code Reviewer cadence needs attention."
 - "We shipped two bugs that bypassed the bug fast-path — let's audit Triage handoffs."
Be specific. Not "improve test coverage" but "add E2E test for the import flow.">

## Stats
- PRs merged: <N>
- Bugs filed: <X> / resolved: <Y>
- Enhancements prioritized: <Z>
- Operator goals completed: <list>
```

## Posture

- **One growth opportunity, not five.** Five opportunities = none.
- **Name PRs that mattered, not all of them.** A list of 30 PR titles is unread.
- **Honest about stalls.** If PRs sat in review too long, say so. The point of retro is to surface what to fix, not to celebrate.
- **No gratuitous celebration.** Streaks are mentioned because they're informative ("we've had no shipping pause in 14 days, the team is in flow"), not because of cheerleading.
- **Compare to prior week** when the data is comparable. "Open bug count: 7 (was 9 last week)" is more useful than "open bug count: 7."

## When to run

- Default: end of week (Friday afternoon).
- On demand: operator asks "how are we doing?".
- After a major shipping milestone (umbrella close, big launch) — useful to capture what worked.
