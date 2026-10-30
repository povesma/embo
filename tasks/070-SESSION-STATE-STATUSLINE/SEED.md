# 070: Session state and statusline indicator — Seed

**Status**: Seed — partially built, uncommitted
**Created**: 2026-10-29
**Split from**: task 068 (decision: amend 068 for FR-5 only; the
statusline indicator becomes its own task)

---

## What the user asked for

A statusline segment showing the session's embo state:

- **not started** → hint the user to run `/embo:start`
- **started** → in progress
- **just wrapped up** → so `/embo:wrapup` is not run twice

## Why this needs a state file

The statusline is a shell script running outside the conversation. It
cannot read conversation context, so an in-context marker (such as task
068's `<!-- embo-start: complete -->`) cannot drive it. The state must
be on disk.

## Decisions already taken

| # | Question | Decision |
|---|---|---|
| D-1 | Per project or per session? | **Per session.** Several sessions routinely run in one directory. |
| D-2 | Where? | Project `.claude/`, gitignored, beside the existing `rlm_state/`. |
| D-3 | Does it also serve task 068's FR-5? | Yes — a disk file carries a timestamp and the HEAD commit SHA, so the fast path can compute a real delta (`git log <sha>..HEAD`) rather than guessing. It replaces FR-5's in-context marker. |

## What the session id research established

- The statusline's stdin JSON carries `session_id`
  (code.claude.com/docs/en/statusline).
- Every hook event carries `session_id` and `transcript_path`
  (code.claude.com/docs/en/hooks).
- A slash command body can expand `${CLAUDE_SESSION_ID}`
  (code.claude.com/docs/en/slash-commands).
- **Undocumented**: whether the statusline's `session_id` equals the
  hook's for the same session.
- **Undocumented**: whether `session_id` survives `claude --resume`.

## Already built, NOT committed

Four files, written and fixture-tested, to settle the two undocumented
facts above:

- `plugin/hooks/session-identity.sh` — SessionStart hook recording
  `session_id` and `source` (startup / resume / clear / compact / fork)
- `plugin/hooks/session-identity.test.sh` — 5 cases, all passing
- `plugin/statusline.sh` — records the statusline's own view once per
  session; only appends to a file the hook already created, never
  creates one itself
- `plugin/hooks/hooks.json` — hook registered on SessionStart

Records append to `.claude/session-identity.jsonl` in the **main**
working tree (via the `resolve_claude_dir()` pattern copied from
`capture-correction.sh`), so they survive a worktree being removed.

## Why the probe has not run

It needs the installed plugin to point at a tree containing the hook,
then a session exit and `claude --resume`. The user's plugin currently
loads from a different worktree.

## Open design questions

- Stale files accumulate one per session — needs a cleanup rule
  (simplest: `/embo:start` prunes entries older than a few days when it
  writes).
- A session that never runs `/embo:start` never creates a file, which is
  exactly the "not started" state — that works out.
- `/embo:wrapup` needs to write the `wrapped_up` field; it can use
  `${CLAUDE_SESSION_ID}` directly, no hook required.
