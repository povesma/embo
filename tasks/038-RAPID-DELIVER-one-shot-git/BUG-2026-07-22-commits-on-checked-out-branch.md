# T038 BUG — embo-deliver commits on the checked-out branch, not the plan's

**Reported:** 2026-07-22 (found in a downstream project during a normal
`/embo:git deliver`; the commit landed on `main` while the push targeted
a stale feature branch, and the PR showed the wrong diff).
**Severity:** wrong-branch commits on every delivery run from a branch
other than the plan's target. Recoverable, but the operator must know
several manual git steps to untangle it — exactly what the deliver flow
exists to remove.
**Status:** FIXED — commits `559d254` (fix + docs + tests) and
`f071ead` (test hardening) on `feat/044-subagent-utilization`.

## Symptom

The plan file declared `branch: feat/x`, but the operator was standing
on `main` when `embo-deliver` ran (a `feat/x` branch already existed,
pointing at a stale commit). The script:

1. committed the change onto `main` (the checked-out branch), then
2. pushed the pre-existing `feat/x` (still at the old commit), then
3. opened a PR from that stale branch.

Result: the commit was on local `main`; the PR diff was wrong. Happened
twice in one session (once via a project build script, once via
`embo-deliver` itself).

## Root cause

`plugin/bin/embo-deliver` parsed `branch:` from the plan but used it
only for push/PR targeting. `git commit` ran on whatever branch `HEAD`
pointed at. The plan's declared intent (`branch: feat/x`) was ignored
at commit time — the tool trusted ambient shell state over the plan,
which is the source of truth.

## Fix

The plan's `branch:` is now authoritative. Before staging, the executor
reconciles the working tree onto it (spec adopted from the reporter's
recommendation, reconcile done carefully so it does not reintroduce the
bug):

1. **Refuse a protected base as a `push` commit target.** `branch:`
   `main`/`master` with `mode: push` aborts (exit 7). A protected branch
   stays valid as a `pr`/`pr-merge` `base:`.
2. **Reconcile onto `plan.branch`.** Switch to it if on a different
   branch; create from `base:` for pr modes; a `push` plan to an absent
   branch aborts (exit 7) rather than invent the branch point from
   `HEAD`; a pre-existing branch is switched to as-is and **never
   force-reset** (the stale-branch case that caused this bug).
3. **Re-assert `HEAD == plan.branch`** immediately before commit; any
   drift aborts (exit 7) with no commit made.

New exit code **7** = branch reconcile refused (no git changes made).
Documented in the script header and in `plugin/commands/git.md`
("Branch reconcile" subsection + the authoritative `branch` field note).

## Verify

`plugin/bin/embo-deliver.test.sh` (76 passed, 0 failed). Load-bearing
cases:

- **The reported bug:** operator on `main`, plan targets a pre-existing
  `feat/x` — commit lands on `feat/x`, `main` is unchanged, HEAD ends
  on `feat/x`.
- Protected base (`main`/`master`) as a `push` target -> exit 7, no
  `git add`.
- `main` as a PR `base:` -> allowed, exit 0.
- Absent branch + `push` (no base) -> exit 7, no commit.
- Absent branch + `pr` with base -> created **from base**, not ambient
  HEAD (fixture puts HEAD != base and asserts the new branch's parent
  is base's tip).
- `--dry-run` skips reconcile (mutates no git state).

An independent clean-context review traced all three guarantees and the
test coverage before delivery.
