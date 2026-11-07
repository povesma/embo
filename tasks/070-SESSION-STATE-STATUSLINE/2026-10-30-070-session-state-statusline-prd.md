# 070: Session State and Statusline Indicator — PRD

**Status**: Draft
**Created**: 2026-10-30
**Author**: Claude (via embo workflow)

---

## Wider Context / Higher Goal

The statusline is always visible; the conversation scroll is not. Without
a session-state segment, the user can't tell at a glance whether
`/embo:start` ran, where they are mid-session, or whether `/embo:wrapup`
already ran — so they double-start or forget wrapup. This feature adds a
segment that answers "where am I?" without opening the conversation.

The state file is also read by the fast path: a HEAD SHA stored at start
lets a second `/embo:start` show an exact `git log <sha>..HEAD` delta
instead of a bare stat.

## Context

### Current State (observed)

- `plugin/statusline.sh` displays: cwd | git branch | model | token
  usage / cost | context % | mem indicator | time. No session-state
  segment exists. — verified via: `plugin/statusline.sh:4`, 2026-10-30
- `plugin/hooks/session-identity.sh` is a SessionStart hook that
  appends one JSON line per session start to `.claude/session-identity.jsonl`
  in the main working tree. Fields: `ts`, `observer`, `event`, `source`,
  `session_id`. — verified via: `plugin/hooks/session-identity.sh:65–72`,
  2026-10-30
- `plugin/statusline.sh` also appends one line to `session-identity.jsonl`
  (observer: statusline) on first call per session id, for diagnostic
  comparison with the hook's value. — verified via:
  `plugin/statusline.sh:28–40`, 2026-10-30
- The `session-identity.sh` hook IS registered on SessionStart. —
  verified via: `plugin/hooks/hooks.json:17`, 2026-11-06
- The hook's `session_id` and the statusline's `session_id` are the
  **same value** for one session, and `session_id` **survives `claude
  --resume`** — the Story 1 probe PASSED. So `session_id` is the
  confirmed state-file key. — verified via: SEED.md §Probe result,
  2026-11-06
- `plugin/statusline.sh`'s diagnostic `record_session_identity()` runs a
  `grep` and a `git rev-parse` on every render. Now the probe has
  passed, this conflicts with NFR-1 ("no git call in the hot path") and
  should be removed in implementation. — verified via:
  `plugin/statusline.sh:28–40`, 2026-11-06
- `plugin/commands/start.md` currently uses an in-context HTML comment
  marker (`<!-- embo-start: complete -->`) for the FR-5 fast path.
  — verified via: `plugin/commands/start.md` (shipped in commit
  e4b26cc), 2026-10-30

### Past Similar Features (from claude-mem)

- Task 047 (CONCLUSION-HARNESS): on-disk hook output used as the
  enforcement mechanism for behavioral rules. Same pattern: a shell
  script that the harness calls, writing to a gitignored file the
  statusline or health command reads.
- Task 020 (STATUSLINE-MEM-FRESHNESS): added a memory-freshness
  indicator segment to the statusline. That implementation is the
  reference for adding a new segment.

## Problem Statement

**Who**: An embo user running an active Claude Code session.
**What**: They cannot tell from the statusline whether `/embo:start`
has run, what stage the session is at, or whether `/embo:wrapup` has
already been called — so they sometimes run start twice, or forget
wrapup entirely.
**Why**: The statusline is always visible; the conversation scroll is
not. An ambient indicator removes a class of "did I already do this?"
mistakes.
**When**: Any time the user glances at the statusline mid-session or
before starting a new one.

## Goals

**Primary**: a statusline segment showing the session's embo lifecycle
state (not started / started / wrapped up).

**Secondary**:
- Leave schema room for richer detail (task, stage, peers) later without
  a breaking change.
- Give the fast path a disk file for an exact git delta, replacing the
  in-context marker.
- (Done) Confirm `session_id` is a safe file key via the Story 1 probe.

## User Stories

### Story 1 — session_id probe

**As an** embo maintainer,
**I want** confirmed data on whether the hook's `session_id` and the
statusline's `session_id` are the same value for the same session,
**so that** I can safely use `session_id` as the key for per-session
state files without guessing.

**Acceptance Criteria** — **PASSED 2026-11-06** (see SEED §Probe result):
- [X] `session-identity.sh` hook and `statusline.sh` diagnostic exist and
  the plugin points at them (`hooks.json:17`).
- [X] A live session produced a `session-identity.jsonl` with a hook line
  and a statusline line carrying the **same** `session_id`
  (`ecc8d58d-…`), and a `resume` hook line under that same id.
- [X] They match → `session_id` is the state-file key. No fallback to
  `transcript_path` needed. Stories 2–4 unblocked.

### Story 2 — on-disk session state file

**As an** embo user,
**I want** `/embo:start` and `/embo:wrapup` to write a small state
record to disk keyed by session id,
**so that** external tools (statusline, health command) can read the
current session's lifecycle phase without accessing the conversation.

**Acceptance Criteria**:
- [ ] The state file is written to the user-global, git-free path
  `${XDG_STATE_HOME:-~/.local/state}/embo/session-state/<session_id>.json`
  with at least `phase`, `started_at`, `head_sha`, `branch`, `repo_root`
  (home-relative), `updated_at`, and a `schema` version.
- [ ] A SessionStart hook writes a `new` baseline (not `started`);
  `/embo:start` sets `started`; `/embo:wrapup` sets `wrapped_up`.
- [ ] No file, and `phase: new`, both mean "not started".
- [ ] Every writer does a **merge** that preserves keys it does not own
  (`ext` and any unrecognised key); an unreadable file is treated as
  absent, never partially merged.
- [ ] Prune removes files by **mtime** past a configurable threshold
  (default 14 days) on `/embo:start`; every write touches the file so a
  live session is never pruned.
- [ ] Forward-compat: `schema` version + readers ignore unknown keys and
  tolerate missing ones. New state lands under `ext`; no fields are
  predeclared.

### Story 3 — statusline indicator

**As an** embo user,
**I want** the statusline to show a brief indicator of my session's
embo lifecycle state,
**so that** I can confirm at a glance whether I have started or wrapped
up without scrolling the conversation.

**Acceptance Criteria**:
- [ ] When no state file exists, or `phase` is `new`: the segment shows a
  "not started" hint (e.g. `embo:?` or similar brief text).
- [ ] When `phase` is `"started"`: the segment shows a positive
  indicator (e.g. `embo:▶` or `embo:on`). The exact symbol is
  decided in tech-design.
- [ ] When `phase` is `"wrapped_up"`: the segment shows a distinct
  completion indicator (e.g. `embo:✓` or `embo:done`).
- [ ] The statusline does not fail or delay if the state file is absent
  or unreadable; it degrades to the "not started" display.
- [ ] The segment is positioned consistently with the existing statusline
  segments and does not exceed a reasonable width (exact limit in
  tech-design).

### Story 4 — FR-5 fast path migration

**As an** embo user,
**I want** the `/embo:start` fast path (skip Batch A/B on a second
invocation in the same session) to use the disk state file rather than
the in-context HTML comment marker,
**so that** the fast path can show an exact `git log <sha>..HEAD`
delta rather than a bare `git diff --stat HEAD`.

**Acceptance Criteria**:
- [ ] `start.md` fast-path logic reads `phase` and `head_sha` from the
  session state file instead of checking for an in-context marker.
- [ ] On the fast path, the delta shown is `git log <head_sha>..HEAD
  --oneline` and `git diff --stat <head_sha>`, not just the diff against
  HEAD.
- [ ] **FR-9 fallback**: if `git cat-file -e <head_sha>` fails
  (rebase/amend/pruned), fall back to the plain delta against HEAD.
- [ ] The in-context marker (`<!-- embo-start: complete -->`) is removed
  from `start.md`; the Summary section no longer emits it.
- [ ] Absent/unreadable state file → full Batch A/B run, as before.

## Requirements

### Functional Requirements

1. **FR-1 (High)** — Write a per-session state file when `/embo:start`
   and `/embo:wrapup` complete. Disk is the only channel the statusline
   (a script outside the conversation) can read.

2. **FR-2 (High)** — The statusline displays a three-state indicator
   (not started / started / wrapped up) from the file. The `started`
   state must leave room for richer content (task, stage) later without
   a breaking change. Depends on FR-1.

3. **FR-3 (Medium)** — Migrate the `/embo:start` fast path off the
   in-context marker to the file, producing an exact git delta (commits +
   diff since start), not a bare stat. Depends on FR-1.

4. **FR-4 — DONE** — `session_id` equality (hook == statusline) confirmed;
   it is the file key (Story 1 PASSED 2026-11-06). Kept for traceability.

5. **FR-5 (Low)** — `/embo:start` prunes files by **mtime** past a
   threshold (default 14 days, configurable); every write touches the
   file so a live session is never pruned. Prune only deletes, so it
   can't race the writer.

6. **FR-6 (High)** — The file lives at a **user-global, git-free** path
   keyed by the globally-unique `session_id`
   (`${XDG_STATE_HOME:-~/.local/state}/embo/session-state/<id>.json`).
   Both writer and statusline compute it from `$HOME` + `session_id` with
   **no `git` call** (NFR-1), it survives worktree removal, and it works
   for non-repo sessions. A main-tree path was rejected: it forced the
   statusline to resolve the main tree (a per-render `git` call it does
   not have and cannot cache), and broke for worktrees and non-repo
   sessions.

7. **FR-7 (High)** — Enforce the write via **hooks**, not a command step
   the model may skip (the marker's weakness). A SessionStart hook writes
   a **`new`** baseline from the real stdin `session_id` (it cannot know
   whether `/embo:start` ran, so it must NOT write `started`). The
   `/embo:start` command step is the only writer that sets `started` — it
   supplies `head_sha`/`branch`/`repo_root`, which a hook cannot (no git
   in a hook). A UserPromptSubmit hook flips `wrapped_up`→`started` when
   work resumes. All writers call a `bin/` wrapper that **rejects an empty
   id, the literal `${CLAUDE_SESSION_ID}`, or an id with `/`/`..` — exit
   non-zero** (since `${CLAUDE_SESSION_ID}` substitutes in a command body
   but is NOT in the Bash env — verified: code.claude.com/docs/en/plugins/
   manifest-reference, 2026-11-06). The statusline reader applies the same
   id check. `/embo:health` flags a live session with no file.

8. **FR-8 (High)** — The phase vocabulary is **`new` → `started` →
   `wrapped_up`**; **no file and `new` both render as "not started"**
   (`embo:?`). Define the lifecycle by the transition table (below):
   SessionStart writes `new` (and preserves the phase on a
   `resume`/`compact` re-fire — never resets); `/embo:start` sets
   `started`; `/embo:wrapup` sets `wrapped_up` (no prior file required);
   first prompt after wrapup flips back to `started`; a later start
   resets to `started`; final-write-wins; `/clear`/fork get a new id and
   a fresh `new` baseline.

9. **FR-9 (Medium)** — The fast path tolerates an unreachable `head_sha`:
   if `git cat-file -e <sha>` fails (rebase/amend/pruned), fall back to the
   plain delta against HEAD. The file also records `branch` and
   `repo_root`.

### State machine (FR-8)

Phase is `started` or `wrapped_up`; **no file = not started**.

| Event | Action on the file |
|---|---|
| `/embo:start` | Write `phase: started` (overwrite any existing). |
| `/embo:wrapup` | Set `phase: wrapped_up`; create a minimal file (null `started_at`) if none. |
| start after wrapup, or work resumes | Next `/embo:start` resets to `started`; final-write-wins. |
| `claude --resume` | id preserved → keep the file as-is. |
| compaction | id preserved → keep (a strength: the in-context marker was lost here). |
| `/clear` | new id → no file → "not started" (correct; context is empty). |
| fork | new id → no file by default; optional SessionStart `source=fork` hook copies the parent's file. |

### Non-Functional Requirements

1. **NFR-1**: The statusline must not introduce a perceptible delay.
   Reading the state file must be a single `jq` call on a small JSON
   file; no shell loop, no network, no `git` call in the statusline's
   hot path.
2. **NFR-2**: `.gitignore` must explicitly list `.claude/session-state/`
   and `.claude/session-identity.jsonl`. `.claude/` is **not** ignored
   wholesale today (it lists individual entries like `rlm_state/`), so
   these paths are committable until added. A test must assert they are
   ignored. — verified via: `.gitignore`, 2026-11-06
3. **NFR-3**: All hooks and shell scripts must degrade silently on error
   — never kill the statusline or the harness. Every error path exits 0.
4. **NFR-4**: Writes must be atomic: write to a `.tmp` file in the same
   directory, then `mv` into place. The reader treats an empty or
   unparseable file as a neutral state (not "not started"). Prune and
   reads ignore `*.tmp`.

### Technical Constraints

- `jq` is the only JSON tool in scope; Python is not available in hook
  context. — verified via: existing hooks, 2026-10-30
- `${CLAUDE_SESSION_ID}` substitutes in a command's Markdown body but is
  NOT exported to the Bash process environment (drives FR-1/FR-7). —
  verified via: code.claude.com/docs/en/plugins/manifest-reference,
  2026-11-06
- The statusline receives `session_id` on stdin. — verified via:
  code.claude.com/docs/en/statusline + the live probe, 2026-11-06

## Out of Scope

- Showing the current task name or stage in the statusline (Story 3
  reserves the design space, but the actual rich display is a future
  task).
- Multi-user or shared state: each session has its own file; no
  cross-session aggregation.
- Windows support: state file paths assume POSIX; Windows is out of
  scope for this task.
- Surfacing session state through any channel other than the statusline
  and `/embo:health`.

## Success Metrics

1. **Probe result**: `session_id` equality confirmed (or design updated
   if not) before Stories 2–4 begin.
2. **Statusline accuracy**: after running `/embo:start` and
   `/embo:wrapup` in a live session, the statusline reflects each phase
   correctly within one refresh cycle.
3. **FR-5 delta quality**: the fast path on a second `/embo:start`
   invocation shows the exact commits and files changed since session
   start, not just a stat against HEAD.
4. **No regressions**: existing statusline segments, hook events, and
   the embo-capture / behavioral-reminder hooks all continue to pass
   their existing tests.

## References

### From Codebase

- `plugin/hooks/session-identity.sh` — per-session id recorder (hook)
- `plugin/statusline.sh` — statusline script; current segment list and
  the diagnostic `record_session_identity()` function
- `plugin/hooks/capture-correction.sh` — reference for
  `resolve_claude_dir()` pattern
- `plugin/hooks/hooks.json` — hook registration (`session-identity.sh`
  registered on SessionStart at line 17)
- `plugin/commands/start.md` — FR-5 fast path target (in-context
  marker to be replaced)

### From History (claude-mem)

- Task 020 (STATUSLINE-MEM-FRESHNESS): pattern for adding a new
  statusline segment.
- Task 047 (CONCLUSION-HARNESS): hook-written disk files read by the
  statusline — same architectural pattern.

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/embo:tech-design` to produce the technical design
3. Run `/embo:tasks` to break this into an ordered task list
