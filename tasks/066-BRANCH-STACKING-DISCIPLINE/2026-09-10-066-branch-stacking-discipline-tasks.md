# branch-task-correspondence - Task List

## Relevant Files
- [2026-09-10-066-branch-stacking-discipline-prd.md](2026-09-10-066-branch-stacking-discipline-prd.md)
  :: Product Requirements Document (revised 2026-09-11: three-layer
  shape after empirical evidence added a SessionStart hook)
- [2026-09-10-066-branch-stacking-discipline-tech-design.md](2026-09-10-066-branch-stacking-discipline-tech-design.md)
  :: Technical Design (revised 2026-09-11 to match shipped shape)
- [LESSONS.md](LESSONS.md)
  :: Retrospective on the development arc, including the empirical
  0/2 datapoint that led to the SessionStart layer being added
- [plugin/lib/branch-task-lib.sh](../../plugin/lib/branch-task-lib.sh)
  :: NEW — the single definition of the branch↔task match rule and
  task derivation, sourced by the hook and by embo-deliver
- [plugin/hooks/branch-task-check.sh](../../plugin/hooks/branch-task-check.sh)
  :: NEW — SessionStart hook that warns on branch↔task mismatch
- [plugin/hooks/branch-task-check.test.sh](../../plugin/hooks/branch-task-check.test.sh)
  :: NEW — 16 test cases for the hook
- [plugin/hooks/hooks.json](../../plugin/hooks/hooks.json)
  :: +1 command entry registering the SessionStart hook alongside
  statusline-refresh.sh
- [plugin/commands/impl.md](../../plugin/commands/impl.md)
  :: `/embo:impl` step 2 — one bullet added for branch↔task awareness
- [plugin/bin/embo-deliver](../../plugin/bin/embo-deliver)
  :: Delivery executor — warn-only safety-net check added after
  reconcile, before staging
- [plugin/bin/embo-deliver.test.sh](../../plugin/bin/embo-deliver.test.sh)
  :: Test suite — three fixtures for the safety-net check

## Notes
- Warn-only: no exit-code change, no flag, no gate. The check fails
  open on any uncertainty.
- The `/embo:impl` step is prose the model executes; the
  SessionStart hook and the `embo-deliver` check are mechanical
  bash. All three do the same comparison (whole-token match on the
  task ID); they run at different moments in the workflow.
- The hook and `embo-deliver` share one implementation of the rule
  (`plugin/lib/branch-task-lib.sh`) and derive the task from the same
  kind of evidence — the files actually being changed (working tree
  for the hook, `plan.files` for the delivery). One definition plus
  aligned evidence is what stops the two layers giving contradictory
  advice about one repo state.

## Tasks

- [X] 0.0 **User Story:** As the embo agent opening a session on
  free-form edits (no `/embo:impl` entry point, no `embo-deliver`
  plan yet), I want a one-line stderr warning when the current
  branch does not reference the task my uncommitted changes belong
  to, so I notice the mismatch before any further edit happens.
  [6/6]

  Motivation: this session's own experience made the case. All
  task-066 work was authored on `feat/062-fake` (a test branch
  from earlier). Neither the `/embo:impl` bullet nor the
  `embo-deliver` check fired because free-form editing never
  invokes either. Empirical 0/2 result on the shipped mitigation
  drove the addition of this third layer.

  - [X] 0.1 Create `plugin/hooks/branch-task-check.sh`: read
    `git symbolic-ref --short -q HEAD`; derive the task from the
    uncommitted working-tree changes (`git status --porcelain`,
    most-changed `tasks/NNN-*` prefix wins, tie → fail open);
    whole-token match branch against task; warn to stderr on
    mismatch; suggest an existing matching branch if any exists;
    fail open on every uncertain state [verify: auto-test]
    → Derivation reworked 2026-09-14. Folder mtimes (highest number
      within 7 days) are unusable: git rewrites mtimes on checkout,
      and "highest-numbered" is not "active", so the hook warned on
      correct branches and could contradict `embo-deliver` on the
      same repo state. Both layers now read the same evidence.
  - [X] 0.5 Filter the suggested branches through the whole-token
    rule: `git branch --list '*NNN*'` glob-matches substrings, so it
    offered `feat/1066-x` for task `066` — the very match the hook
    rejects one line earlier [verify: auto-test]
    → GREEN: test 15 asserts `feat/1066-x` is never suggested
      (2026-09-14)
  - [X] 0.2 Register the hook in `plugin/hooks/hooks.json` under
    SessionStart, alongside `statusline-refresh.sh`
    [verify: code-only]
  - [X] 0.3 Create `plugin/hooks/branch-task-check.test.sh` with
    16 test cases: mismatch (with/without matching branch), match
    (3 whole-token positions), whole-token rejection of `1066`,
    fail-open cases (clean tree, not a repo, detached HEAD, no task
    paths dirty, tie), most-changed selection, the reverse case
    (lower task number is the active one), suggestion filtering,
    rename attribution [verify: auto-test]
    → GREEN: 41 passed, 0 failed (2026-09-14)
    → Mutation-checked: reverting the hook to the old
      "highest-number-wins" logic fails tests 11, 13 and 14, so
      those cases genuinely discriminate rather than passing
      vacuously. Test 13's failure output reproduces the original
      defect — on the correct branch `feat/042-fix`, the old logic
      advises switching away to 066.
  - [X] 0.6 Extract the match rule and task derivation into
    `plugin/lib/branch-task-lib.sh`, sourced by both the hook and
    `embo-deliver`; each skips its check silently when the library
    is absent (partial install) [verify: auto-test]
    → GREEN: 41 + 120 pass with the library; both degrade silently
      without it (2026-09-14)
    → Mutation-checked: one break in the shared
      `branch_task_matches` fails BOTH suites (5 hook + 1 deliver),
      proving a single definition is reached rather than two copies.
  - [X] 0.4 Live-test: current branch `docs/066-branch-stacking-seed`
    (matches — silent); `feat/062-fake` (mismatch — warns, suggests
    `docs/066-branch-stacking-seed`) [verify: manual-run-user]
    → GREEN (2026-09-14). Match case: silent, exit 0. Mismatch case,
      reproducing the original failure state (`feat/062-fake`, the
      same uncommitted task-066 files, the matching branch present):
      warns, names task 066, suggests `docs/066-branch-stacking-seed`.
      Verified in a clone, so no branch operation touched this
      working tree.

- [X] 1.0 **User Story:** As the embo agent starting a task in
  `/embo:impl`, I want to notice when my current branch does not
  reference the task, so I can course-correct before editing.
  [1/1]
  - [X] 1.1 Add one bullet to `plugin/commands/impl.md` step 2
    prompting the agent to compare HEAD against the task ID and
    suggest switching to an existing matching branch or mention
    the mismatch [verify: code-only]
    → shipped: one bullet inside existing step 2 bullet list
      (2026-09-11)

- [X] 2.0 **User Story:** As the embo agent running `embo-deliver`,
  I want a warn-only safety-net check that fires when the plan's
  branch does not reference the task derived from `plan.files`, so
  bypassed awareness is still surfaced before a PR opens. [3/3]
  - [X] 2.1 Add `derive_current_task()` and
    `check_branch_task_match()` to `embo-deliver`; call them
    unconditionally after the branch reconcile block, before
    `git add` [verify: auto-test]
    → GREEN: 120 passed, 0 failed (2026-09-11)
  - [X] 2.2 Add real-repo tests: (A) mismatch on
    `feat/062-worktree` → WARNING to stderr, exit 0; (B) match on
    `feat/066-x` → no WARNING, exit 0 [verify: auto-test]
    → GREEN: both fixtures pass (2026-09-11)
  - [X] 2.3 Add exit-code regression assertion — protected-branch
    push still exits 7 after the new code [verify: auto-test]
    → GREEN: reconcile guard intact (2026-09-11)

## Verification

- `bash plugin/hooks/branch-task-check.test.sh` → 41 passed, 0 failed.
- `bash plugin/bin/embo-deliver.test.sh` → 120 passed, 0 failed.
- Live run of the hook (0.4): silent on the matching branch, warns
  and names the matching branch on `feat/062-fake`.
- The `/embo:impl` bullet activates on the next task-start; no
  automated test covers command-file prose (verification is
  observational — the next `/embo:impl` run on a mismatched branch
  will exercise it).
