# PRD: Smoke Test Hello Script

## Problem
The 8-agent pipeline (PM, Designer, Dev, QA, Code Reviewer, DevOps, Triage, Team Lead) has no end-to-end exercise. Without a concrete deliverable flowing through every stage, there is no signal that the SDLC contract — backlog triage, PRD authoring, implementation, review, and post-merge verification — works as designed. A developer joining the project today cannot verify the pipeline by observation alone.

## Users
Agent-team operators and contributors who need confidence that the full workflow is wired correctly before routing real work through it.

## Success metrics
- `bin/hello.sh` exists in `main`, is executable, prints the project name, and exits 0.
- The script was delivered via the full SDLC cycle: prioritized issue → PRD → (Designer sign-off) → implementation PR → code review → merge → QA verification.
- Zero regressions introduced in adjacent files.

## Scope
- A single shell script at `bin/hello.sh`.
- The script prints the project name (hard-coded string or read from a config file) and exits 0.
- Executable bit set (`chmod +x`).

## Out of scope
- Dynamic project-name discovery (e.g., parsing `package.json` or `CLAUDE.md`).
- CI integration for the script.
- Any other scripts or tooling.

## Open questions
- None blocking implementation. Designer review can confirm no UX considerations apply to a CLI-only artifact (expected: immediate sign-off).

## Slicing plan
- Slice 1 (this issue): Implement `bin/hello.sh`, set executable bit, open PR. Closes #2.

## Risks
- None material. This is a low-risk smoke test with no production surface.
