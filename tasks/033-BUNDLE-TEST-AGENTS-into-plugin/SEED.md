# 033: Bundle Test Subagents into the Plugin — Seed

**Status**: Not started (seed only; run /dev:prd to begin)
**Origin**: split out of task 032 (plugin packaging), 2026-06-18
**Priority**: medium — `/embo:impl`'s test steps are incomplete for
plugin users until this lands.

## Problem

The 5 test subagents (`test-backend`, `test-review`,
`test-e2e-planner`, `test-e2e-generator`, `test-e2e-healer`) are
documented in CLAUDE.md and exist in the maintainer's `~/.claude/agents/`,
but are NOT in this repo. Task 032 ships the embo plugin without them
(deferred by decision), so `/embo:impl`'s testing workflow does not work
out-of-box for plugin users.

## Scope (validate in PRD/tech-design)

- Source the 5 `test-*.md` from `~/.claude/agents/` into the repo's
  `agents/`.
- Preserve upstream/license attribution: per CLAUDE.md, the three e2e
  agents are forks of `microsoft/playwright` — keep their attribution
  intact.
- Rewrite any `/dev:` references inside them to `/embo:` (consistent
  with 032's namespace flatten).

## Related

- Task 032 (plugin packaging) — FR-7 deferred here.
- CLAUDE.md "Test Subagents" section describes the canonical roles.
