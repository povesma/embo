# 070: Session state and statusline indicator — Tech Design

**Status**: Draft
**Created**: 2026-11-06
**PRD**: `2026-10-30-070-session-state-statusline-prd.md`
**Depends on**: Story 1 probe gate — **PASSED 2026-11-06** (see SEED).
`session_id` is the confirmed state-file key.

---

## Summary

Replace the in-context `<!-- embo-start: complete -->` marker with a
per-session JSON file on disk. `/embo:start` and `/embo:wrapup` write it;
the statusline reads it and shows a three-state indicator. Because the
file is on disk and keyed by `session_id`, the statusline (a shell script
outside the conversation) can read session state, and the `/embo:start`
fast path can compute a real git delta.

## Key platform fact (verified 2026-11-06)

`${CLAUDE_SESSION_ID}` substitutes inline **in a command's Markdown body**
when Claude Code loads it, but is **NOT exported** to the Bash tool's
process environment (code.claude.com/docs/en/plugins/manifest-reference,
"Where each variable resolves"). Consequence: a command cannot read
`$CLAUDE_SESSION_ID` as a shell variable inside a Bash step. The command
body must embed the literal `${CLAUDE_SESSION_ID}` token into the argument
it tells Claude to run, so Claude Code expands it before the Bash call.

## State file

- **Path (FR-6)** — **user-global, git-free**:
  `${XDG_STATE_HOME:-$HOME/.local/state}/embo/session-state/<session_id>.json`
  (fall back to `$HOME/.claude/embo/session-state/` if `$HOME` only).
  `session_id` is globally unique, so no project key is needed, and both
  the writer and the statusline reader compute the path from `$HOME` +
  `session_id` alone — **no `git` call in either**. This is the key fix
  from review: a main-tree path forced the statusline to resolve the main
  tree (a per-render `git` call it does not actually have, and cannot
  cache across fresh processes), and broke for non-repo sessions and
  worktrees. A global path removes all three at once and still survives
  worktree removal.
- **Gitignore**: not needed for the state file (it lives outside any
  repo). NFR-2 still applies to `session-identity.jsonl` if that stays
  in-tree.
- **Writer (FR-7)** — a hook is the **primary** writer; the command step
  is secondary:
  - A `SessionStart` hook already runs (`session-identity.sh`). Extend it
    (or add one) to write `phase: "started"` from the real stdin
    `session_id` — so the id can never be empty or unsubstituted, and the
    model cannot forget the write.
  - A `UserPromptSubmit` hook flips `wrapped_up` → `started` on the first
    real prompt after a wrapup (closes the "work resumes after wrapup"
    gap — otherwise the indicator shows `✓` while work continues).
  - The command step (`/embo:wrapup` → `wrapped_up`; `/embo:start`
    refreshing `head_sha`) calls the shared `bin/embo-session-state`
    wrapper, which **rejects an empty id or the literal
    `${CLAUDE_SESSION_ID}` with a non-zero exit**. `/embo:health` flags a
    live session that has no state file, catching a missed write.

### Schema

A **versioned envelope**. The point is not to predeclare future fields —
it is that the structure absorbs additions without rework. Two rules give
that: **readers ignore unknown keys and tolerate missing ones**, and a
**`schema` version** bumps only on a breaking change. New state (whatever
it turns out to be — current task, peer sessions, flags) lands under the
open `ext` bag when a concrete feature needs it; it is not guessed now.

```json
{
  "schema": 1,                   // bump ONLY on a breaking change
  "session_id": "ecc8d58d-…",
  "phase": "started",            // "new" | "started" | "wrapped_up"
  "source": "startup",           // last SessionStart source (startup/resume/…)
  "started_at": "2026-11-06T18:39:12Z",
  "wrapped_up_at": null,
  "head_sha": "e4b26cc…",        // HEAD at /embo:start
  "branch": "feat/…",            // FR-9
  "repo_root": "~/…",            // FR-9; home-relative, never an absolute path
  "updated_at": "2026-11-06T18:39:12Z",  // touched every write (FR-5 prune)
  "ext": {}                      // open bag: any future key lands here
}
```

Forward-compat contract:
- **Additive only.** New data goes under `ext`; an existing field's
  meaning never changes without a `schema` bump.
- **Readers ignore unknowns, tolerate absence.** This — not a list of
  predeclared fields — is what makes the structure future-proof. The
  statusline reads only `phase`.
- **Writers merge, never clobber.** Every write (v1 and any future
  writer, `start` and `wrapup` alike) does a read-modify-write that
  **preserves all keys it does not own**, including `ext` and any
  top-level key it does not recognise. An unreadable existing file is
  treated as absent (start fresh); it is never partially merged.

### Writer interface (`embo-session-state`)

All forms resolve the path from `$HOME` + `session_id` (no git), do a
read-modify-write that **preserves every key the form does not own**
(including `ext` and any unrecognised top-level key), and write
atomically (NFR-4: `.tmp` in the same dir, then `mv`). An unreadable
existing file is treated as absent, never partially merged.

**Id safety (every form, and the reader):** reject an empty id, the
literal `${CLAUDE_SESSION_ID}`, or any id not matching `^[A-Za-z0-9._-]+$`
or containing `..` — exit non-zero, so a hostile or missing id can never
build a path outside `session-state/` (FR-7). The statusline reader
applies the same charset check before touching a path.

- `embo-session-state baseline <session_id> <source>` — SessionStart
  only. If no file: create `phase: new`. If a file exists
  (`resume`/`compact` re-fire): **preserve the current phase**, record
  `source`, touch `updated_at`. Never prunes (avoids a stat storm on
  every session start).
- `embo-session-state start <session_id> <head_sha> <branch> <repo_root>`
  — set `phase: started`, `started_at` (first time) / `updated_at` = now,
  `head_sha`/`branch`/`repo_root`; **then prune**.
- `embo-session-state wrapup <session_id>` — set `phase: wrapped_up`,
  `wrapped_up_at`/`updated_at` = now; minimal file (null `started_at`,
  `phase: wrapped_up`) if none; preserves `ext`/unknown keys.
- `embo-session-state resume <session_id>` — UserPromptSubmit: if `phase`
  is `wrapped_up`, flip to `started`; else touch `updated_at` only. No
  file → no-op (baseline should have created one).

**Scope note (2026-11-06):** the originally-designed `delta` subcommand
(a `git cat-file -e <head_sha>` fast-path helper) was **cut** as
convenience-only complexity. The `/embo:start` fast path now keys on
`phase: started` and reuses the plain `git log --oneline -10` +
`git diff --stat HEAD` that Batch A already runs — no dedicated delta
wrapper, no `head_sha`-based git branch. `head_sha`/`branch`/`repo_root`
are still recorded for forward use but are not consumed by a fast path.

### Writers (hook-primary)

**Phase vocabulary:** `new` (session exists, `/embo:start` has not run) →
`started` → `wrapped_up`. **No file and `new` both render as `embo:?`**;
only `started`/`wrapped_up` show ▶/✓. This matters: the SessionStart hook
cannot know whether `/embo:start` ran, so it must NOT write `started` — it
writes `new`. Writing `started` from SessionStart would show ▶ for every
session and make the fast path fire on the first `/embo:start`.

- **SessionStart hook** (`session-identity.sh`): `embo-session-state
  baseline <id> <source>` — writes `phase: new` with `session_id` from
  the real stdin id. On a re-fire (`resume`/`compact`) with an existing
  file it **preserves** the current phase, never resets to `new`. The id
  is never empty/unsubstituted and the model cannot skip it. This write
  also **replaces** the old `session-identity.jsonl` append (see below).
- **`/embo:start` command step** (the only writer that sets `started`):
  `embo-session-state start <id> <head_sha> <branch> <repo_root>` with the
  Batch A values. A second `/embo:start` resets to `started`
  (final-write-wins). The hook cannot supply sha/branch/root (no git in a
  hook), so this step is required — it is not optional polish.
- **UserPromptSubmit hook**: `embo-session-state resume <id>` — flips
  `wrapped_up`→`started` on the first prompt after a wrapup; otherwise
  touches `updated_at` only. Never creates a file (no file → the
  SessionStart baseline already made one).
- **`/embo:wrapup` command step**: `embo-session-state wrapup <id>` →
  `wrapped_up`. `/embo:health` flags a live session with no state file.

## Statusline segment

Add `embo_state_segment()` to `plugin/statusline.sh`, modelled on
`cmem_segment()` (task 020). It computes the path from `$HOME` +
the stdin `session_id` and does **one `jq` read** — no `git`, no loop,
no network (NFR-1). This is why FR-6 chose a global path: the reader
needs no main-tree resolution.

The diagnostic `record_session_identity()` is **removed** now the probe
has passed (it ran `grep`+`git` every render — an NFR-1 violation, and it
held the only `--git-common-dir` call).

| Reader result | Display | Colour |
|---|---|---|
| no file, or `phase: new` | `embo:?` | dim |
| `phase: started` | `embo:▶` | green |
| `phase: wrapped_up` | `embo:✓` | cyan |
| empty / unparseable / unsafe id | `embo:?` | dim (degrade, NFR-3/NFR-4) |

Next to the `mem:` segment; width ≤ ~7 chars.

## FR-3 fast-path migration (`start.md`)

- Remove the `<!-- embo-start: complete -->` line and the fast-path prose
  that keys on it. The marker string must not survive anywhere in
  `plugin/` (grep check).
- New check: read the state file for `${CLAUDE_SESSION_ID}`; `phase:
  started` → repeat start → fast path. (`phase: new` is not a repeat
  start — the baseline hook set it; run the full Batch A/B.)
- Delta on the fast path: the existing plain `git log --oneline -10` +
  `git diff --stat HEAD` note (the commands Batch A already runs). The
  `delta` subcommand and its `git cat-file -e <head_sha>` branch were cut
  (see Writer interface scope note) as convenience-only.
- Absent/unreadable file, or `phase: new` → full Batch A/B, as before.

## FR-5 prune

`embo-session-state start` deletes `session-state/*.json` by **mtime**
older than the threshold (default 14 days; profile key overrides). Every
write touches the file, so a live/recent session is never pruned. Prune
only deletes, never rewrites — no race with the writer. `*.tmp` ignored.
Skip the pass when the directory holds few files (<50) to avoid a stat
storm on every start.

## Retiring `session-identity.jsonl`

The identity log was the one-off probe; it has passed. The SessionStart
hook's **`baseline` write replaces** the old `jsonl` append (same hook,
one change — not a separate "stop" step). Two dependents must move with
it, or they break:
- `plugin/hooks/session-identity.test.sh` — currently asserts the append;
  update it to assert the `baseline` state write.
- `plugin/commands/health.md` — has NO jsonl reader (verified 2026-11-07;
  the design's "currently reads the jsonl" was wrong). Instead ADD a
  session-state check (Check 6) that reads the state file for the live
  session and flags its absence.
`record_session_identity()` in `statusline.sh` is removed (its only job
was the diagnostic). If any `session-identity.jsonl` write remains after
this, add `.claude/session-identity.jsonl` to `.gitignore`; if the append
is fully removed, no gitignore entry is needed (the state file is
out-of-tree).

## State machine (FR-8)

Phase is `new` → `started` → `wrapped_up`. **No file and `new` both =
not started** (statusline `?`).

| Event | Action |
|---|---|
| SessionStart (first) | baseline hook writes `phase: new`. |
| SessionStart re-fire (`resume`/`compact`) | preserve current phase; record `source`; touch `updated_at`. |
| `/embo:start` | command step → `phase: started` (merge-preserve other keys). |
| `/embo:wrapup` | `phase: wrapped_up`; minimal file if none. |
| first prompt after wrapup | UserPromptSubmit hook flips `wrapped_up`→`started` (no stale `✓` while work continues). |
| second `/embo:start` | resets to `started`; final-write-wins. |
| `/clear` | new id → fresh baseline → `new` → `?` (correct). |
| fork | new id → fresh baseline; optional `source=fork` hook copies parent's. |

## Testing

- `embo-session-state.test.sh` —
  - **baseline**: no file → `phase: new`; re-fire with an existing
    `started`/`wrapped_up` file **preserves** the phase (never resets to
    `new`); records `source`.
  - **start**: `phase: started`, populates sha/branch/root; second start
    resets to `started`; prunes.
  - **wrapup**: `wrapped_up`; wrapup-without-start → minimal file (null
    `started_at`); preserves `ext`/unknown keys.
  - **resume**: flips `wrapped_up`→`started`; no-op otherwise; no file →
    no-op.
  - **merge-preserve**: each of start/wrapup/resume keeps `ext` and an
    unknown top-level key; an unreadable file is treated as absent.
  - **id safety**: empty id, the literal `${CLAUDE_SESSION_ID}`, a `/` or
    `..` id each exit non-zero.
  - **atomic**: `.tmp`+`mv`, no partial read.
  - **prune**: removes only stale-by-mtime, never a just-touched file,
    ignores `*.tmp`, skips when <50 files.
- Statusline test: `new`/no-file→`?`, `started`→`▶`, `wrapped_up`→`✓`,
  empty/corrupt→`?`, unsafe or missing stdin `session_id`→`?`; no `git`
  invoked.
- `hooks.json`: a `jq` assertion that the UserPromptSubmit entry is
  present and well-formed.
- `session-identity.test.sh`: updated to assert the `baseline` state
  write (not the old jsonl append).
- Migration grep: the marker string appears nowhere in `plugin/` or
  `~/.claude/` after the change.
- `.gitignore` test: `session-state/` and `session-identity.jsonl` are
  ignored.

## Open questions

- Prune threshold config: a dedicated profile key, or reuse an existing
  one? Default 14 days either way.
- Symbols (`▶`/`✓`/`?`): confirm they render; else fall back to
  `on`/`done`/`?`.
