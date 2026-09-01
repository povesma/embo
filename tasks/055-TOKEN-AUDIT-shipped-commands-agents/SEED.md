# 055-TOKEN-AUDIT: Token-cost audit of every shipped command and agent

Seed for a future `/embo:prd` run. Work MUST proceed on a dedicated
feature branch — never straight to `main`. This task produces a
prioritized slim-down backlog, not a rewrite; each item it
recommends becomes its own follow-up task on its own branch.

## Why now

Task 052 revealed a large gap between "lines cut" and "tokens saved"
(48.3% lines vs 27.6% tokens for the same edit). The measurement
tool `plugin/bin/embo-tokens` now exists; running it across the
whole shipped surface tells us where the leverage actually is.

## Budget principle (from user, 2026-09-01)

The total token size of shipped commands and agents is a budget to
hold constant or reduce: an addition to any shipped prompt must name
the saving that offsets it. Snapshot at 0.2.9 time (~tok = chars/4):
~56k total; top consumers visual-impl 9.2k (rare load), start 8.8k
(every session, checklists re-injected every prompt), git 7.5k (every
delivery; ~50 lines are dormant commented-out blocks that still load).
Cost = size × load frequency — rank targets by that product.

## Deliverable

A single audit report at
`tasks/055-TOKEN-AUDIT-shipped-commands-agents/2026-XX-XX-055-token-audit-report.md`
containing:

1. Full `embo-tokens` output for every file under `plugin/commands/`
   and `plugin/agents/`.
2. For each file: injection frequency (per session / per prompt /
   per invocation), yielding a per-session or per-prompt cost.
3. A ranked list of the top ~10 highest-leverage tightening targets,
   with a rough per-target estimate of realistic reduction (10-30%
   is normal; more than 40% usually implies content is being cut,
   not tightened).
4. A suggested task order.

## Verification method

`manual-run-claude` — the audit script is idempotent; running
`embo-tokens plugin/commands/*.md plugin/agents/*.md` reproduces
the numbers.

## Out of scope

- Doing the tightening (each item becomes its own task).
- Hooks, bin wrappers, or `.claude-plugin/*` manifests — those are
  code and configuration, not per-session prompt cost.

## Delivery constraint (from user, 2026-08-22)

Dedicated feature branch. Report file only — no shipped-prompt
edits in this task.
