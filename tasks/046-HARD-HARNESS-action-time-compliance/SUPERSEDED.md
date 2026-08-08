# Task 046 — Superseded by Task 047

**Date:** 2026-07-24  
**Superseded by:** `tasks/047-CONCLUSION-HARNESS-emit-then-enforce/`

## What 046 built

Task 046 delivered a full CLASS 1/CLASS 2 regex harness:
- `harness-lib.sh` — rule loader + signal-shape dispatch
- `approve-compound.sh` — PreToolUse CLASS 1 deny+substitute gate
- `custodian-halt.sh` — PostToolUse CLASS 2 halt marker + flap guard
- `harness-rules.json` — shipped default rules
- `embo-custodian` — human-gated halt-clear binary
- 262 passing unit tests across four suites

## Why it was cut

Task 047 found a simpler mechanism (per-rule conclusion checklists +
`behavioral-reminder.sh` verbatim injection) that:
1. Requires no regex pattern authoring per rule
2. Has no "unknown signal shape" failure mode
3. Proved reliable in real sessions via Stop-hook measurement
4. Needs zero hook changes to add a new rule

The regex harness adds complexity (signal shapes, the flap guard, halt
markers, a clearing command) that is only justified if the simpler
approach fails. It did not fail.

## Status of the code

Both gates remain **disabled by default** on the branch:
- `hooks.json` registers both hooks but the PreToolUse entry targets `Bash`
  (not `*`), and the PostToolUse entry was not added to the shipped file
- `EMBO_HARNESS_046` / `SUBSTITUTE_SUPPLY_DISABLED` / `CUSTODIAN_HALT_DISABLED`
  disable switches are present but not set by default

The code is preserved as infrastructure. If the simpler mechanism shows
gaps (measured via `conclusion-probe.log`), the harness is the next escalation.
