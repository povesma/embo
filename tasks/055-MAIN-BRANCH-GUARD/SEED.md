# 055: Guard against working directly on a protected branch

**Status**: Not started (seed). Deferred to a future release 2026-08-16;
documented now.
**Origin**: surfaced 2026-08-16 — during a session Claude committed a
changelog fix directly onto local `main` and attempted to push it, on a
repo whose `main` is protected. A CLAUDE.md rule was considered but, per
the "Enforce, Don't Ask" principle, a repeated/again-likely violation
needs a mechanism, not more prose.
**Priority**: medium — protects against lost work / rejected pushes;
no user-facing feature.

## Problem

Nothing stops the agent from editing, committing, or pushing while a
protected branch (`main`/`master`, or a repo-configured set) is checked
out. Prose rules in CLAUDE.md are unreliable under load (the agent did
exactly this after being reminded). The correct fix is a deterministic
guard.

The blindness is wider than protected branches: no step of the workflow
checks that the checked-out branch corresponds to the work being done.
Branch rules exist only at delivery time (`/embo:git deliver`
destination rules + the `embo-deliver` reconcile); during the work
phase, edits land on whatever branch is checked out — observed
2026-08-27: task-036 changes made on `feat/052-start-slim-and-tooling`,
the branch of an already-completed task.

## Proposed direction (validate in a design pass)

- **A PreToolUse guard hook** that inspects the current branch and blocks
  the action when it is protected:
  - Block `Edit`/`Write` to tracked files while on a protected branch
    (the agent must branch first).
  - Block `git commit` / `git push` targeting a protected branch.
  - Fail loudly with guidance ("create a feature branch; main is
    protected"), never silently.
- **The protected-branch behavior is CONFIGURABLE IN THE PROFILE**
  (user request 2026-08-16). Add a profile field — e.g.
  `rules.workflow.protected_branches: [main, master]` and a mode
  (`block` | `warn` | `off`) — so the guard reads its policy from the
  active profile via `embo-profile get`, rather than hardcoding the
  branch list. Default: block `main`/`master`.
  - This depends on task 053's `embo-profile` (shipped) for reading the
    field, and interacts with the profile schema — coordinate with the
    profile work.
- **Work-phase branch awareness**: check that the current branch matches
  the task being worked — report a mismatch at session start
  (`/embo:start` already displays the branch but acts on nothing) and
  suggest creating/switching to the task's branch before the first edit
  of an `/embo:impl` run. Policy lives in the profile alongside the
  protected-branch mode.
- **A terse CLAUDE.md note** stating the rule for humans, pointing at the
  hook as the enforcement.

## Scope (to refine)

- New PreToolUse hook (+ fixture tests, per the hook test convention:
  `plugin/hooks/*.test.sh`).
- Register it in `plugin/hooks/hooks.json`.
- New profile field for protected-branch policy; add to `default.yaml`
  and document in the profile field explanations.
- Terse CLAUDE.md Safety Rules note.

## Related

- CLAUDE.md § Safety Rules (where the human-facing note lands).
- `plugin/hooks/` — existing hook + `.test.sh` conventions
  (behavioral-reminder, capture-correction, approve-compound).
- `plugin/bin/embo-profile` (task 053) — reads the profile policy field.
- The "Enforce, Don't Ask" principle in CLAUDE.md — the rationale for a
  hook over prose.
