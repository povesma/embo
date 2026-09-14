# 066: Branch↔Task Correspondence — PRD

**Status**: Draft
**Created**: 2026-09-10
**Revised**: 2026-09-11 (scope reduced — see §Design choice below)

---

## Problem

An agent starts a new task while HEAD is on a branch belonging to
other work — `main`, another task's branch, a docs branch, a release
branch. Git raises no objection. Every subsequent edit and commit
lands on the wrong branch, silently, until someone tries to describe
or ship what's on that branch.

**Observed twice in this repo:**
- Task 065 (telemetry) was branched off `feat/062-worktree-isolation`.
  The PR mixed both features; the release test plan wrongly described
  worktree commands as part of the telemetry release and made four
  cascading errors from it. Fix: cherry-pick onto a clean branch.
- Task 036 edits landed on `feat/052-start-slim-and-tooling` (a
  completed task's branch). Same failure, different branch.

---

## Negative consequences

1. **The wrong branch collects work it doesn't own.** The resulting
   PR mixes two features; the diff is no longer a record of what the
   branch was for.
2. **Release scope descriptions are wrong.** Anything downstream that
   summarises the branch (CHANGELOG, test plan, release notes)
   inherits and multiplies the mistake.
3. **The new task can't merge independently.** It's hostage to the
   base branch's review cycle even without any functional dependency.
4. **Untangling is expensive** — cherry-pick, re-point the PR, delete
   the polluted branch — for a mistake that was one `git switch`
   away from being prevented.

---

## Higher goal

Mitigate the negative consequences with the least intrusive
intervention that fits the failure profile: rare (2 in ~66 tasks),
recoverable (cherry-pick, no data loss), invisible at the moment it
happens (agent has all the context needed to notice, but no reason
to look). Reduce the incident rate; do not aim to eliminate it. Do
not tax the workflow on the ~97% of tasks where nothing is wrong.

---

## Design choice

"Enforce, Don't Ask" is embo's default principle for behavioural
rules, but it's a heuristic tuned for high-frequency,
context-expensive failures. Task 066's failure profile (rare,
bounded cost, cheap to notice at the exact moment the mistake would
happen) is the wrong shape for the mechanical-gate treatment.
Initial implementation proved this empirically — a gate with an
`AskUserQuestion` fork, an `--allow-mismatch` flag, and a
7-fixture test matrix imposed ceremony on every task in exchange
for eliminating a rare failure.

The shipped shape has three lightweight layers, each firing at a
distinct workflow moment. All three are warn-only, fail-open, and
silent on the common (branch matches) case:

- **Session start** (`branch-task-check.sh` `SessionStart` hook):
  when a session opens, look at the recently-modified `tasks/NNN-*`
  folders, pick the highest task number, compare against the current
  branch. One line to stderr on mismatch, silent on match. Covers
  the free-form editing case: the agent is deep in a task, editing
  files without going through `/embo:impl`, and would otherwise
  never see a branch↔task check. Added after empirical evidence
  from this feature's own development session: both observed
  failures (task 065, task 036) fit this pattern, and the initial
  two layers did not catch either one.
- **Task start** (`/embo:impl`, one bullet inside the existing
  step 2 "Load and Understand Current Task"): the agent notices
  whether the current branch references the task ID it just read,
  and — if not — suggests switching to any existing local branch
  that does. No gate, no fork, no new step. Zero output on match.
- **Delivery** (`embo-deliver`, warn-only): the same check runs
  before staging, deriving the task from `plan.files`. Warns to
  stderr and continues. No flag, no gate.

The three cover complementary moments: session start (before any
edit), task start (when a task is explicitly named), delivery
(before a commit is written). Each is cheap in the common case;
each surfaces the mismatch at a different natural attention point.

---

## Requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-1 | `SessionStart` hook prints a one-line stderr warning when the current branch does not reference the recently-active task (highest-numbered `tasks/NNN-*` folder modified in the last 7 days); suggests an existing matching local branch when one is present | High |
| FR-2 | `/embo:impl` step 2 includes a one-line note prompting the agent to compare HEAD against the task ID from the task folder; on mismatch, look for an existing matching branch or mention the mismatch and continue | High |
| FR-3 | `embo-deliver` derives the current task from `plan.files` and prints a warn-only stderr message when the plan's branch does not reference the task; exit code unchanged; no flag, no gate | High |
| FR-4 | All three mitigations fail open — no false-positive noise when the current task cannot be determined (no `tasks/NNN-*` files, ambiguous derivation, detached HEAD, stale task folder, not a git repo) | Medium |

---

## Out of scope

- **`AskUserQuestion` gate / interactive fork on mismatch**: rejected
  during initial implementation — imposes ceremony on every task; the
  failure profile does not warrant it.
- **`--allow-mismatch` flag on `embo-deliver`**: rejected — the check
  is warn-only, so there is nothing to suppress.
- **Pre-creation hook** (intercept `git checkout -b`): not needed —
  the two shipped layers catch the failure without hooking git
  commands.
- **Automatic cherry-pick / branch switching**: mentioned as a
  suggestion in the warning; not performed automatically.
- **Task 055 (protected-branch guard)** — a distinct failure (editing
  while HEAD is on a protected branch); remains separate.

---

**Next steps**: lessons-learned document, then close.
