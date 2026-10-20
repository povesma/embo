# 066: Branch↔Task Correspondence — Technical Design

**Status**: Complete (shipped)
**PRD**: `2026-09-10-066-branch-stacking-discipline-prd.md`
**Created**: 2026-09-10 | **Revised**: 2026-09-11

---

## Shipped shape

Three lightweight layers, all warn-only, all fail-open. No new
dependencies, no configuration. One new file (the SessionStart
hook + its test).

### Layer 1 — `SessionStart` hook (`branch-task-check.sh`)

Fires on session start. Reads the working directory, derives the
current task from the **uncommitted working-tree changes** (`git
status --porcelain`: counts `tasks/NNN-*` path prefixes, highest
count wins, tie or none → fail open), compares against the current
branch (whole-token match), and prints a one-line stderr warning on
mismatch. Silent on match. Fail-open on everything else (not a git
repo, detached HEAD, a clean tree, no task paths among the changes,
a tie, etc.).

**Why working-tree changes and not folder mtimes.** The first
implementation picked the highest-numbered `tasks/NNN-*` folder
modified in the last 7 days. Two failures made that unusable:

- Git does not preserve mtimes. A clone, a checkout, or any `git
  switch` that rewrites files stamps the touched folders with the
  current time, so after switching branches several task folders
  look equally "recent" and the highest number wins arbitrarily.
- "Highest-numbered" is not "active". Working on task 042 while
  066's folder was touched days ago made the hook name 066 and
  advise switching off a correct branch — a false warning that
  tells the user to do the wrong thing, from the one mechanism
  whose purpose is to be trusted about branches.

Deriving from uncommitted changes uses the same evidence as Layer 3
(what is actually being edited), so the two checks cannot give
contradictory answers about the same repo state.

Added after empirical evidence from this feature's own development
session: both observed failures (tasks 065, 036) happened while the
agent was in free-form editing mode, not going through `/embo:impl`
or `embo-deliver`. Neither of the other two layers fires in that
case. The `SessionStart` hook does.

**Location**: `plugin/hooks/branch-task-check.sh` +
`branch-task-check.test.sh`, registered in `hooks.json` alongside
`statusline-refresh.sh`.

### Layer 2 — `/embo:impl` awareness bullet

One bullet inside `plugin/commands/impl.md` step 2 ("Load and
Understand Current Task"):

> **Notice the current branch.** Compare `git symbolic-ref --short -q
> HEAD` against the task ID from the folder name. If the branch name
> does not reference the task, look for an existing local branch that
> does (`git branch --list '*<task-id>*'`) and suggest switching to
> it; if none exists, mention the mismatch and continue. One line to
> the user; no gate.

The agent already reads step 2 as its first action after loading the
task; the branch name and task ID are both already in context. The
bullet costs one shell comparison and one output line (only on
mismatch). No new step, no new heading, no `AskUserQuestion` gate.

### Shared rule — `plugin/lib/branch-task-lib.sh`

The match rule shipped as two byte-identical copies, one per layer,
each carrying a comment asking the next editor to keep them in sync.
A rule aligned by a comment is a rule that eventually diverges, and
two layers giving different answers about one branch teaches the user
to ignore both. The definition now lives in one sourced library:

- `branch_task_matches <branch> <task>` — the whole-token rule.
- `branch_task_derive_from_paths` — stdin paths → the task owning the
  most of them; empty on a tie or no match.
- `branch_task_paths_from_porcelain` — `git status --porcelain` →
  plain paths, renames attributed to their destination.

Both consumers resolve the library relative to their own location and
skip the check silently when it is absent, so a partial install never
breaks a delivery or a session.

### Layer 3 — `embo-deliver` safety-net check

Added to `plugin/bin/embo-deliver` after the branch reconcile block,
before `git add`:

- Task derivation and the match test come from the shared library
  (`branch_task_derive_from_paths` over `plan.files`, then
  `branch_task_matches`).
- `check_branch_task_match()` — the warning text; returns 0 either
  way.
- Wiring: called whenever the library loaded. No flag, no gate. Exit
  code contract unchanged (still 0 on success, 7 on reconcile
  refusal).

### What was rejected during implementation

- `AskUserQuestion` gate at task start — ceremony on every task
- `--allow-mismatch` flag — nothing to suppress in a warn-only design
- `/embo:start` branch-mismatch note — nice-to-have, deferred
- Automatic branch creation — would fail when the correct branch
  already exists (the common case in the observed failures)

---

## Files modified / added

| File | Change |
|---|---|
| `plugin/lib/branch-task-lib.sh` | NEW — shared match rule, sourced by both mechanical layers |
| `plugin/hooks/branch-task-check.sh` | NEW — SessionStart hook (~85 lines) |
| `plugin/hooks/branch-task-check.test.sh` | NEW — 16 test cases (~310 lines) |
| `plugin/hooks/hooks.json` | +1 command entry under SessionStart |
| `plugin/commands/impl.md` | +1 bullet inside step 2 |
| `plugin/bin/embo-deliver` | +~50 lines: two functions + unconditional wiring after reconcile |
| `plugin/bin/embo-deliver.test.sh` | +3 test blocks (T066 A/B/C: mismatch, match, exit-code regression) |

No profile fields, no `CLAUDE.md` changes.

---

## Verification

- `bash plugin/hooks/branch-task-check.test.sh` → 41 passed, 0
  failed (16 test cases: mismatch × 2, match × 3, whole-token
  rejection, fail-open × 5 incl. the tie case, most-changed
  selection, the reverse case where the lower task number is the
  active one, suggestion filtering, rename attribution).
  Mutation-checked: reverting the derivation to
  "highest-number-wins" fails tests 11, 13 and 14, confirming those
  cases discriminate rather than passing vacuously.
- `bash plugin/bin/embo-deliver.test.sh` → 120 passed, 0 failed
  (up from 114 baseline; +6 assertions for T066).
- The `/embo:impl` bullet is prose the model executes; verification
  is observational.

---

## Rollback

Additive. Revert = delete the two new hook files, remove the
`hooks.json` entry, remove the bullet from `impl.md`, remove the
two functions and their call from `embo-deliver`, delete the 3
test blocks. No state written; nothing depends on the new code.
