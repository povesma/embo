# worktree-isolation (v1) - Task List

## Relevant Files
- [2026-09-04-062-worktree-isolation-tech-design.md](2026-09-04-062-worktree-isolation-tech-design.md)
  :: Worktree Sessions with Shared Memory - Technical Design (v1)
- [2026-09-04-062-worktree-isolation-prd.md](2026-09-04-062-worktree-isolation-prd.md)
  :: Worktree Sessions with Shared Memory - Product Requirements
- [plugin/rlm_scripts/rlm_repl.py](../../plugin/rlm_scripts/rlm_repl.py)
  :: State-path resolver + write lock added here (state path at :56;
  `_save_state` sites at :944, :994, :1158).
- [plugin/bin/embo-worktree-finish](../../plugin/bin/embo-worktree-finish)
  :: NEW bare wrapper — one-command local merge-back finish flow.
- [plugin/bin/embo-worktree-finish.test.sh](../../plugin/bin/embo-worktree-finish.test.sh)
  :: NEW fixture test for the finish flow.
- [plugin/rlm_scripts/rlm_repl.test.sh](../../plugin/rlm_scripts/rlm_repl.test.sh)
  :: NEW/extended fixture test for resolver + lock concurrency +
  state-survival.
- [plugin/bin/embo-deliver](../../plugin/bin/embo-deliver)
  :: Reused reconcile/idempotency patterns (:205-266) for the finish
  flow.
- [.gitignore](../../.gitignore)
  :: Add `.worktrees/` so repo-adjacent worktrees are never staged.

## Notes
- Tests follow the repo's `*.test.sh` fixture pattern (see
  `embo-deliver.test.sh`, `subagent-rules.test.sh`): build a temp git
  repo, `git worktree add` into a repo-adjacent path, assert, tear down.
- Run a test script directly: `bash plugin/bin/embo-worktree-finish.test.sh`.
- The lock-concurrency test MUST hold the lock in a backgrounded
  process before launching the second writer (a sequential test passes
  vacuously — see tech-design Testing Strategy).
- The state resolver behavior change is worktree-only: the main tree
  keeps today's exact CWD-relative path (regression guard is a test).

## Tasks

- [X] 0.0 **User Story:** As the implementer, I want the test files
  scaffolded first, so that every later TDD subtask has a file to write
  into.
  - [X] 0.1 Create `plugin/rlm_scripts/rlm_repl.test.sh` and
    `plugin/bin/embo-worktree-finish.test.sh` with the repo's standard
    fixture boilerplate (shebang, assert helpers, temp-repo setup/
    teardown) as used by `embo-deliver.test.sh` [verify: code-only]
    → both scaffolds run clean (0 passed, 0 failed, exit 0) [live]
    (2026-09-05)

- [X] 1.0 **User Story:** As a developer whose RLM state lives in the
  main tree, I want a state-path resolver in `rlm_repl.py` that finds
  the main tree from inside a worktree, so that a worktree session
  reads/writes the shared index, not a stray worktree-local one.
  - [X] 1.1 Write tests for `resolve_state_path`: main tree →
    CWD-relative default; explicit `--state` → passthrough; git
    absent/not-a-repo → CWD default [verify: auto-test]
    → covered in rlm_repl.test.sh; 12 passed, 0 failed [live] (2026-09-05)
  - [X] 1.2 Write tests for the worktree case: from a linked worktree,
    resolver returns the MAIN tree's
    `.claude/rlm_state/state.pkl` [verify: auto-test]
    → CORRECTION: main root comes from `--git-common-dir` (absolute),
    parent — NOT `--show-toplevel`, which returns the worktree's own
    root (proven wrong live 2026-09-05); test asserts main-tree path
    [live] (2026-09-05)
  - [X] 1.3 Write tests for the bare-repo guard: bare repo falls back to
    CWD default, no crash [verify: auto-test]
    → covered; falls back to default [live] (2026-09-05)
  - [X] 1.4 Implement `resolve_state_path`: detect worktree via
    `git rev-parse --git-dir --git-common-dir` (differ ⇒ worktree);
    main-tree root via `git rev-parse --path-format=absolute
    --git-common-dir` then `.parent` (NOT `--show-toplevel`, which
    returns the worktree root); bare-repo + git-absent fallbacks
    [verify: auto-test]
    → 12 passed, 0 failed [live] (2026-09-05)
  - [X] 1.5 Wire `resolve_state_path` into every current use of
    `DEFAULT_STATE_PATH` (rlm_repl.py:56 and its call sites); `--state`
    still overrides [verify: auto-test]
    → `--state` default now sentinel None, resolved in main(); `rlm_repl
    status` still finds the main-tree 267-file index [live] (2026-09-05)

- [X] 2.0 **User Story:** As a developer running parallel worktree
  sessions, I want every RLM index write serialized by a crash-safe
  lock, so that concurrent `exec`/`init` calls cannot silently
  overwrite each other's index.
  - [X] 2.1 Write a genuinely-concurrent lock test: hold the lock in a
    background process BEFORE launching the second writer; assert the
    second writer exits non-zero with "index busy"; kill holder after;
    first index left intact [verify: auto-test]
    → backgrounded fcntl holder; second writer exits 2, "index busy"
    [live] (2026-09-05)
  - [X] 2.2 Write a test proving the lock wraps `cmd_exec`, not just
    init — a held lock blocks an `exec` write [verify: auto-test]
    → held lock blocks exec write (exit 2) [live] (2026-09-05)
  - [X] 2.3 Implement `index_write_lock` (fcntl advisory, non-blocking,
    lockfile in the resolved state root) [verify: auto-test]
    → 21 passed, 0 failed [live] (2026-09-05)
  - [X] 2.4 Guard all `_save_state` writes with the lock; on contention
    exit non-zero without writing [verify: auto-test]
    → DECISION: lock placed INSIDE `_save_state` (one guard covers all
    three call sites) rather than wrapping each — simpler, same
    guarantee; "index busy" → RlmReplError → exit 2 (repo convention)
    [live] (2026-09-05)

- [X] 3.0 **User Story:** As a Windows user, I want RLM to degrade
  gracefully when `fcntl` is unavailable, so that using a worktree
  never crashes `rlm_repl`.
  - [X] 3.1 Write a test simulating `fcntl` absent: place a `fcntl.py`
    shim (raising ImportError) ahead of stdlib on `PYTHONPATH`; assert
    the one-time warning prints, the write succeeds, no `ImportError`
    [verify: auto-test]
    → shim on PYTHONPATH; exec exits 0, warns, no ImportError [live]
    (2026-09-05)
  - [X] 3.2 Implement the conditional import (`try: import fcntl`) and
    the no-op lock fallback with a single warning [verify: auto-test]
    → conditional import + one-time warning; 21 passed, 0 failed [live]
    (2026-09-05)

- [X] 4.0 **User Story:** As a developer finishing a feature, I want a
  one-command local merge-back (`embo-worktree-finish`) that tests,
  merges into the local base, and cleans up safely, so that I never
  hand-manage git worktree bookkeeping.
  - [X] 4.1 Write finish-flow tests (happy path): green worktree tests →
    merge into a clean base → re-test merged → remove worktree → prune →
    delete branch [verify: auto-test]
    → happy path merges + cleans up, exit 0 [live] (2026-09-05)
  - [X] 4.2 Write tests for the DIRTY guard: base dirty → abort (exit 4),
    no merge; dirty worktree at cleanup → abort (exit 7) + surface files,
    no `--force` [verify: auto-test]
    → both guards abort as specified [live] (2026-09-05)
  - [X] 4.3 Write tests for base ownership: unheld base + main tree on
    another branch → temp worktree, main tree untouched; (dirty-abort and
    owned-elsewhere paths covered by the script's branches) [verify: auto-test]
    → temp-worktree path merges to dev, main stays on main [live]
    (2026-09-05)
  - [X] 4.4 Write tests for the abort-on-red-merge case: merged result
    fails tests → exit 6, worktree + branch preserved [verify: auto-test]
    → poison-on-base marker: step 1 passes, step 5 fails, exit 6, kept
    [live] (2026-09-05)
  - [X] 4.5 Implement `embo-worktree-finish` as a bare wrapper (self-
    resolving, no `${...}`/`$(...)`), reusing `embo-deliver` reconcile
    patterns; steps 1-7 per tech-design [verify: auto-test]
    → 20 passed, 0 failed [live] (2026-09-05)
  - [X] 4.6 Implement the finish menu dispatch: `merge` (steps 6-7),
    `pr` (embo-deliver hand-off), `keep` (merge, no cleanup)
    [verify: auto-test]
    → keep merges + preserves worktree; pr hands off; both exit 0 [live]
    (2026-09-05)
  - [X] 4.7 Document the `Bash(embo-worktree-finish *)` allow opt-in in
    README (mirroring embo-deliver's opt-in) [verify: code-only]

- [X] 5.0 **User Story:** As a developer using repo-adjacent worktrees,
  I want `.worktrees/` gitignored, so that worktree checkouts are never
  accidentally staged.
  - [X] 5.1 Add `.worktrees/` to `.gitignore` [verify: code-only]
  - [X] 5.2 Assert `git check-ignore .worktrees/probe` exits 0 in a
    fixture test [verify: auto-test]
    → check-ignore reports it ignored (was NOT-IGNORED before) [live]
    (2026-09-05)

- [~] 6.0 **User Story:** As a maintainer verifying the feature, I want
  the full suite green and the shared-state guarantees proven, so that
  v1 is release-ready.
  - [X] 6.1 Write a state-survival test: create worktree, session
    resolves shared state, `git worktree remove` → main-tree
    `state.pkl` intact and usable [verify: auto-test]
    → state survives worktree remove; status still loads it [live]
    (2026-09-05)
  - [X] 6.2 Run the full RLM + finish-flow suite; all green
    [verify: auto-test]
    → rlm 24 + finish 20 = 44 passed; embo-deliver 114 no regression
    [live] (2026-09-05)
  - [X] 6.3 Update CHANGELOG with the user-facing capability (gate for
    story completion, before E2E) [verify: code-only]
  - [ ] 6.4 Manual end-to-end: `claude --worktree` a branch, confirm the
    session sees the main-tree RLM index (no re-index) and claude-mem
    history [verify: manual-run-user]
    → partial: resolver verified live through the bin wrapper from a real
    worktree (State file → main tree, 267 files, no re-index); the new
    interactive `claude --worktree` session check remains for the user
    [live] (2026-09-05)

- [X] 7.0 **User Story:** As a developer starting a parallel session, I
  want embo to create and name the worktree and let me list existing
  ones, so that I don't invent names or hand-track worktrees.
  - [X] 7.1 Write tests for `embo-worktree-start <branch>`: creates
    `.worktrees/<derived-name>` on `<branch>` (slashes → `-`); refuses
    to nest when already inside a worktree; prints the path
    [verify: auto-test]
    → derived name, nest-guard, path-conflict all pass [live] (2026-09-05)
  - [X] 7.2 Write tests for `embo-worktree-start --list`: prints existing
    worktrees + their branches [verify: auto-test]
    → list shows main tree + created worktree [live] (2026-09-05)
  - [X] 7.3 Implement `embo-worktree-start` as a bare wrapper (create +
    derived name + nest-guard + list) [verify: auto-test]
    → 11 passed, 0 failed; nest-guard compares --git-dir/--git-common-dir
    both in absolute form (relative-vs-absolute would false-positive)
    [live] (2026-09-05)
  - [X] 7.4 Document the `Bash(embo-worktree-start *)` allow opt-in in
    README alongside the finish opt-in [verify: code-only]
