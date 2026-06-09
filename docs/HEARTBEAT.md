# Heartbeat Canary

This file is the canary target for `/heartbeat`. Each run of the command increments the counter below by 1, ships that increment through the full PM → Dev → CR pipeline, and verifies the four exit-state criteria.

The change is intentionally trivial — one digit — so the pipeline test is never confused with "real" work. Two consecutive `/heartbeat` runs always produce independent issues, branches, and PRs; they never collide.

<!-- DO NOT manually edit the counter line. /heartbeat owns it. -->

Run count: 4
