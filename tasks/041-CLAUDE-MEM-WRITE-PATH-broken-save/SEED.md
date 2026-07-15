# 041: claude-mem write path is broken — `save_memory` no longer exists

**Status**: Not started (seed). **Origin**: discovered 2026-07-15 while
verifying visual-impl; split out so it gets a proper fix rather than a
bundled wording patch.
**Priority**: medium-high — `/embo:improve` is silently non-functional
in the worker runtime.

## Problem

The worker-runtime write tool `save_memory` **is no longer exposed by
the claude-mem MCP server** (verified 2026-07-15: `ToolSearch
select:...save_memory` → "No matching deferred tools found"). The
server-beta write tools (`observation_add`, `observation_record_event`,
`memory_add`) exist but are **"Server runtime only"** and refuse to run
under the worker runtime this project uses. So there is currently **no
callable write path to claude-mem in the worker runtime.**

Observations are still captured automatically by the PostToolUse /
SessionStart hooks — that path works (this very finding was auto-
captured). The gap is only the *manual/programmatic* save that some
commands call.

## Impact

- **`/embo:improve` is broken** (the real bug). Its Step 4 calls
  `save_memory` to persist `CORRECTION-STATUS` observations, which Step
  1 reads back to filter out already-curated corrections. With no write
  tool, curation status never persists → every run re-surfaces the same
  corrections. The command cannot complete its documented purpose.
- Fixed in a separate PR (not this task): `impl.md` had a dead "save to
  claude-mem" instruction and `wrapup.md` described/offered a manual
  save that cannot happen — both removed as honest wording fixes.
- CLAUDE.md (§Runtime) still lists `save_memory` as a worker tool; that
  claim is now stale and should be corrected.

## Scope (validate in a short design pass)

- Decide the replacement write path for `/embo:improve`'s curation
  status. Options to weigh: (a) a local file (e.g.
  `.claude/curation-log.json`) that Step 1 reads and Step 4 writes —
  no MCP dependency; (b) block on the server-beta migration (task 037)
  and use `observation_add`/`memory_add`; (c) drop persistent curation
  and re-review every time (worst UX). Lean (a): simplest, no moving
  target, works today.
- Audit ALL `save_memory` / manual-save references across shipped files
  and rules; ensure none instructs or offers a non-functional save.
- Correct CLAUDE.md §Runtime so it no longer claims `save_memory` is an
  available worker tool.
- Decide whether the "offer to save to claude-mem" closing-menu option
  (seen in other sessions) originates from a shipped file or a general
  default, and remove it at the source.

## Related

- Task 037 (CLAUDE-MEM-SERVER-RUNTIME-migration) — if the project moves
  to server-beta, the write tools become available and this changes
  shape. Coordinate.
- CLAUDE.md §"Runtime: stay on worker tools" — documents the worker vs
  server-beta split and the migration trigger.
- claude-mem obs 28862 (save_memory tool no longer exists), 28861
  (stale: claims improve's save works — superseded by the live tool
  check).
