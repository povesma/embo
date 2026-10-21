# 067-WORKTREE-HOOK — Mechanical enforcement of worktree safety rules

## Problem

The `/embo:worktree` command's safety rules — no `discard_changes: true`
on `ExitWorktree`, no `git branch -D`, and no opening a worktree from
inside another worktree — are prose that the agent follows by instruction.
They are not enforced by any external mechanism. A model under load, or a
subagent without the full command context, can violate them silently.

The original shell wrappers (`embo-worktree-start`, `embo-worktree-remove`)
enforced these as script exit codes. When those wrappers were deleted and
replaced by the native-tool command (task 062, story 9.0), the mechanical
enforcement was removed as a side effect. That downgrade was recorded in
`plugin/commands/worktree.md §Enforcement note`.

## Goal

Add a PreToolUse hook that intercepts the two most dangerous calls and
refuses them before the tool runs, regardless of which agent or session
issues them:

1. `ExitWorktree` with `discard_changes: true` — permanent data loss.
2. `git branch -D <name>` — deletes an unmerged branch without warning.

The nest check (refusing to open from inside a worktree) is lower priority:
the command's prose check runs first and is a recoverable miss (the user
just lands in a nested worktree, no data loss).

## Acceptance criteria

- A PreToolUse hook (Bash) intercepts `ExitWorktree(discard_changes: true)`
  and exits non-zero with a clear message; the tool is never called.
- The same hook (or a companion rule) intercepts `Bash(git branch -D …)`
  and exits non-zero, directing the agent to use `-d` and surface the
  result to the user instead.
- The hook is registered in `plugin/hooks/hooks.json`.
- The hook has a fixture test (`*.test.sh`) that confirms both intercepts.
- `plugin/commands/worktree.md §Enforcement note` is updated to reflect
  that the hook now provides mechanical enforcement.

## Out of scope

- The nest check (recoverable; prose is sufficient for now).
- Intercepting `git worktree remove --force` (this is the raw git command
  path, not the native-tool path; lower priority).
