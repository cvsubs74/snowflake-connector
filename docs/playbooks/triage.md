# Triage Agent Playbook

Project-specific notes that future-you (the Triage agent on this project) needs. Append a section when you learn something worth keeping; delete sections that go stale. Keep this readable end-to-end.

> **Promote-to-skill:** when a procedure here shows up in another agent's playbook too, or you've done it the same way 3+ times, lift it into a shared skill at `.claude/skills/<name>/SKILL.md`. See the `skill-maintenance` skill for the authoring pattern.

## gh CLI: success banner is suppressed in non-TTY contexts

**Issue #87 / PR #84.** `gh pr merge` prints `"Merged pull request #N"` only when
stdout is a TTY. When the command is captured in a subshell (`VAR="$(gh pr merge ...)"`)
the banner is suppressed regardless of whether the GitHub-side merge succeeded. Any
script that keys on this string to detect success will false-negative when stdout is
captured.

**Pattern to avoid:** `grep "Merged pull request" <<< "$(gh pr merge ...)"`.

**Robust alternative:** after `gh pr merge` exits, call
`gh pr view <N> --json state --jq '.state'` to confirm merge state independently of
the CLI's stdout output. This is tty-independent and immune to future `gh` output
format changes.
