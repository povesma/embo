# 057 — /embo:wrapup redesign for session idempotency

**Status: Superseded — folded into task 036.** Detection of untracked
session information, the docs sweep, rule discovery, and the
self-idempotency constraint are specified in
`tasks/036-TOKEN-EFFICIENCY-task-file-compaction/` (PRD delivery
piece 3, tech-design §Component 3, tasks story 6.0). This seed remains
as the problem record only.

## Problem

The wrapup command's stated purpose is to make sessions idempotent —
the docs at end-of-session should reflect what was decided, discovered,
and shipped, so a next session (or a different developer, or a future
maintainer) can resume from state, not from conversation memory.

The current implementation is git-centric:

1. Find modified `tasks/**/*-tasks.md`.
2. Compact `[X]` bodies in those files.
3. Surface uncommitted work.
4. Report.

That does part of the idempotency job (task-file compaction) but
misses most of it. Coverage gaps observed in sessions:

- Decisions made in conversation but never written to a task, tech-design,
  or CLAUDE.md never survive.
- Factual findings (broken assumptions, verified constraints, rejected
  approaches) exist only as claude-mem observations, which are noisy
  and hard to browse.
- Doc references introduced during a session (task pointers, tool
  names, file paths) are not verified against the working tree, so
  they can silently rot.
- New rules discovered during a session (like the "no internal task
  references in user-facing files" rule from 0.2.7) are added ad-hoc
  when the maintainer remembers, not systematically.

## Desired end state

Wrapup makes session state durable, not just git-clean. On invocation:

1. **Docs sweep** — scan CLAUDE.md, README, active task files, and the
   changed command bodies for references to files/paths/tasks/tools,
   flag any that don't resolve.
2. **Decision capture** — surface any decision made in the session
   that has no home in a task, tech-design, or CLAUDE.md rule, and
   offer to write it.
3. **Rule discovery** — flag any correction or steer captured this
   session that isn't yet a CLAUDE.md rule.
4. **Compaction** — as today, compact `[X]` bodies in modified tasks.
5. **Git** — as today, surface uncommitted work.
6. **Report** — one summary of what was made durable.

## Constraints

- Runs as one command; no per-file dialogs unless truly necessary.
- Every proposed doc edit is shown before write (via
  AskUserQuestion or Write dialog), not applied silently.
- Idempotent itself — running wrapup twice in a row does nothing on
  the second run.
- No dependency on claude-mem (its role stays: semantic search across
  sessions; wrapup does the durability part).

## Non-goals

- Automatic decision-mining without user confirmation.
- Overlap with `/embo:improve` (which reviews corrections for
  workflow-level rule additions, not per-session doc state).

## Open questions

- Which docs are in scope for the sweep? CLAUDE.md and active
  task files at minimum; README maybe.
- Where do "session-level" decisions live if they don't fit a task
  file? Options: a `SESSION-NOTES.md` per session, or fold into
  claude-mem with a specific `decision` type.
- Should wrapup edit CLAUDE.md, or only propose the edit and defer
  the write to the user?
