# 030: Hook-Health Statusline Indicator — Seed

**Status**: Not started (seed only; run /dev:prd to begin)
**Origin**: user request 2026-06-10, during task 029 planning
**Priority**: low — "not top priority, but not to be forgotten"

## Problem

The approve-compound + embo-capture hook pair is core infrastructure:
it auto-approves compounds and captures output in every session. It
can break silently (unregistered hook, Claude Code hook-API change,
missing/broken wrapper). Today breakage is only discoverable by
noticing a missing `[embo-capture]` marker (the FR-1 fallback clause
in task 029). Health should be visible proactively.

## Sketch (from 029 discussion, to validate in PRD/tech-design)

- Hook touches a heartbeat file on every invocation.
- Statusline segment (`.claude/statusline.sh`) shows capture health,
  e.g. `cap✓` / `cap✗`, from: hook registered in settings + wrapper
  present/executable + heartbeat freshness.

## Related

- Task 029 (FR-1 fallback clause = reactive detection; this task =
  proactive visibility)
- Statusline lineage: tasks 008, 020
