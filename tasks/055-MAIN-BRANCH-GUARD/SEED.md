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

## Findings (2026-10-21 session)

**The violation recurred, and worse than in August.** An agent session
pushed directly to `origin/main` twice, having read both the CLAUDE.md
rule and the `[RULES ACTIVE: … DEV-GIT …]` reminder injected on every
prompt. The reasoning path was: "docs-only change, and CLAUDE.md says no
PR for docs-only" → "therefore merge straight to main". The no-PR rule
is about skipping *review*, not about bypassing the branch; the two
rules read as contradictory in that case and the unsafe reading won.
`embo-deliver` would have refused the same action with exit 7, but raw
`git push` was used instead, bypassing the project's own enforcement.

Design consequences:

- The guard must cover the **raw git path**, not just `embo-deliver`.
  Enforcement living only inside the delivery wrapper is bypassed by
  the agent reaching for `git` directly, which is exactly what happened.
- CLAUDE.md's "no PR for docs-only" and DEV-GIT's "main only via PR"
  must be reconciled in wording, or the gap will be re-derived. State
  the precedence explicitly: protected-branch delivery wins over the
  no-PR preference.

**`permissions.deny` is a partial mechanism that already exists.**
`approve-compound.sh` `decide()` returns `deny` and emits
`permissionDecision: "deny"` when a subcommand matches a
`permissions.deny` rule, across all four settings layers. So a deny
rule is in principle a zero-code guard for this repo.

**Cause now verified: the rule was written in an unsupported shape.**
The `Bash(git push origin main*)` rule that "did not work" failed
because `matches_rule` supports exactly three rule shapes — exact
`Bash(cmd)`, space-star `Bash(cmd *)`, and colon-star `Bash(cmd:*)`. A
glued glob (`*` attached to a token, `main*`) is none of these: the `*`
is treated as a literal character to match, so the rule silently fails
to match `git push origin main`. Confirmed by executing the hook under
bash (not sourcing it from an interactive shell): `matches_rule 'git
push origin main' 'Bash(git push origin main*)'` returns `no`, while
`Bash(git push origin main *)` returns `yes`. The earlier zsh
`bad pattern: Bash(` message was a separate artifact of sourcing the
hook into an interactive zsh and is unrelated — the deny mechanism is
sound in the production (bash) runtime.

**The deny path is NOT broken in production.** Verified by the hook's
own test suite (`plugin/hooks/approve-compound.test.sh`, run under
bash): the deny decision fires end-to-end through the real stdin→JSON
hook I/O, and 173 assertions pass. New tests pin both the working
space-star guard and the glued-glob failure mode so the wrong shape is
not reintroduced.

**The zero-code guard, written correctly:** add to `permissions.deny`
the space-star shape
`Bash(git push origin main *)` (covers a bare push and any trailing
flags). Known limitation of this shape, for the design pass to weigh:
it matches only the literal `git push origin main[ ...]` prefix, so it
does not cover `git push -u origin main`, `git push origin HEAD:main`,
or a push whose remote/branch order differs. A complete protected-branch
guard still needs the branch-aware hook this task proposes; the deny
rule is a correct, tested stopgap for the common form.
