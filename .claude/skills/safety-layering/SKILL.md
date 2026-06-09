---
name: safety-layering
description: Use when reasoning about the project's safety posture — when an operation should require approval, when a sandbox boundary is appropriate, how auto-mode and sandboxing compose, or why a hook (vs. auto-mode rule vs. sandbox rule) is the right enforcement layer. Reference before adding a new permission or block_rule.
---

# safety-layering — three layers that compose

The Claude Code platform layers three safety mechanisms. **Use the right tool for the right enforcement.** Doubling up wastes operator attention; layering correctly catches what each layer alone misses.

## The layers

| Layer | Granularity | What it stops | Where it lives | When to use |
|---|---|---|---|---|
| **Sandbox** | OS-level FS + network | Reads/writes outside CWD; calls to non-allowlisted domains | `sandbox.json` | Untrusted code execution, blast-radius reduction, prompt-injection containment |
| **Auto-mode classifier** | Per-tool-call semantic | "This looks like it would `destroy_or_exfiltrate_secrets`" | `auto-mode.yaml` | Approval fatigue → 84% fewer prompts (paired with sandbox) |
| **Hooks** | Pre/PostToolUse, Stop, SessionStart | Deterministic gates with custom logic | `.claude/hooks/*.sh` + `.claude/settings.json` | Things that MUST happen, not just MIGHT (lint after edit, block push --force) |

## Composition: which layer catches what

```
Operator types something
   ↓
Claude makes a tool call
   ↓
[Hook: PreToolUse] ─────────── deterministic block? STOP.
   ↓
[Auto-mode classifier] ────── semantic block? STOP (or ask operator).
   ↓
[Sandbox] ─────────────────── OS-enforced boundary? STOP at syscall.
   ↓
Tool runs
   ↓
[Hook: PostToolUse] ────────── lint / format / audit logging
   ↓
Result returned to Claude
   ↓
[Hook: Stop] ───────────────── refuse "done" without verification
```

A well-designed system catches each class of failure at the cheapest layer.

## Decision tree — which layer for a new rule?

```
Is the rule fundamentally deterministic (regex match, exit code, file existence)?
├─ Yes → HOOK
│         (e.g. block `git push --force` on main; run lint after edit)
└─ No → Is it about preventing a category of action regardless of context?
        ├─ Yes → SANDBOX or AUTO-MODE
        │         ├─ OS-enforceable (file path, network domain)? → SANDBOX
        │         └─ Semantic intent (e.g. "this looks like exfiltration")? → AUTO-MODE
        └─ No → Probably belongs in an agent's role .md file (policy, not safety)
```

## Anti-patterns

- **Doubling up.** Don't replicate the same rule in a hook AND auto-mode AND sandbox. Pick the cheapest layer; let it own the rule.
- **Hook-only thinking.** Hooks are bash; they can't see semantic intent. For "any operation that exfiltrates", auto-mode + sandbox catch it; a hook would need 200 lines of regex.
- **Sandbox without auto-mode.** Sandbox blocks bad ops at the syscall, but the agent burns turns hitting the wall. Auto-mode catches the intent earlier and explains why.
- **Auto-mode without sandbox.** Classifier has known 17% FN rate; sandbox is the OS-enforced backstop.
- **Adding a permission to settings.json instead of a sandbox/auto-mode rule.** Permissions are one-off allowlists; they don't enforce categorical rules.

## Files in this layer

- `sandbox.json` — OS-level filesystem + network policy
- `auto-mode.yaml` — semantic classifier rules + allow_exceptions
- `.claude/settings.json` — hook wiring + per-project permission allowlist
- `.claude/hooks/*.sh` — deterministic enforcement scripts

## Calibration

After every `/retro`, review `evals/results/.../cohort_segment.py` for `cohort: safety`. Compare against the platform's published 0.4% FP / 17% FN baseline. If project-local rules push FP above 1% or FN above 20%, the rule set is mis-tuned and producing approval fatigue or letting bad ops through.

## Related

- `update-config` skill — for editing settings.json hook wiring
- `eval-runner` — for adding a safety-cohort eval task
- `quality-monitor` — for the continuous safety metric
