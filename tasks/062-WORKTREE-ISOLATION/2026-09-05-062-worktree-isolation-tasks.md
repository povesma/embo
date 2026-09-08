# worktree-isolation (v1) - Task List

## Relevant Files
- [2026-09-04-062-worktree-isolation-tech-design.md](2026-09-04-062-worktree-isolation-tech-design.md)
  :: Worktree Sessions with Shared Memory - Technical Design (v1)
- [2026-09-04-062-worktree-isolation-prd.md](2026-09-04-062-worktree-isolation-prd.md)
  :: Worktree Sessions with Shared Memory - Product Requirements
- [plugin/rlm_scripts/rlm_repl.py](../../plugin/rlm_scripts/rlm_repl.py)
  :: State-path resolver + write lock added here (state path at :56;
  `_save_state` sites at :944, :994, :1158).
- [plugin/bin/embo-worktree-start](../../plugin/bin/embo-worktree-start)
  :: NEW bare wrapper — create a worktree with a derived name; `--list`.
- [plugin/bin/embo-worktree-remove](../../plugin/bin/embo-worktree-remove)
  :: NEW bare wrapper — safe cleanup (dirty-guard, optional `--branch`).
- [plugin/hooks/capture-correction.sh](../../plugin/hooks/capture-correction.sh)
  :: MODIFIED — resolves `.claude` to the main tree so corrections from
  a worktree are shared, not stranded.
- [plugin/rlm_scripts/rlm_repl.test.sh](../../plugin/rlm_scripts/rlm_repl.test.sh)
  :: NEW fixture test for resolver + lock concurrency + fcntl-absent +
  state-survival.
- [.gitignore](../../.gitignore)
  :: Add `.worktrees/` so repo-adjacent worktrees are never staged.

Note: `embo-worktree-finish` (+ test) was created then removed — see the
Scope correction under story 4.0.

## Notes
- Tests follow the repo's `*.test.sh` fixture pattern (see
  `embo-deliver.test.sh`, `subagent-rules.test.sh`): build a temp git
  repo, `git worktree add` into a repo-adjacent path, assert, tear down.
- Run a test script directly: `bash plugin/bin/embo-worktree-remove.test.sh`.
- The lock-concurrency test MUST hold the lock in a backgrounded
  process before launching the second writer (a sequential test passes
  vacuously — see tech-design Testing Strategy).
- The state resolver behavior change is worktree-only: the main tree
  keeps today's exact CWD-relative path (regression guard is a test).

## Tasks

- [X] 0.0 **User Story:** As the implementer, I want the test files
  scaffolded first, so that every later TDD subtask has a file to write
  into.
  - [X] 0.1 Create the worktree test files with the repo's standard
    fixture boilerplate (shebang, assert helpers, temp-repo setup/
    teardown) as used by `embo-deliver.test.sh` [verify: code-only]
    (note: the initial `embo-worktree-finish.test.sh` scaffolded here
    was later removed with its script — see story 4.0)
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

- [X] 4.0 **User Story:** As a developer done with a worktree (work
  already merged via my normal PR/merge flow), I want one command to
  clean it up safely, so that I never hand-manage worktree removal,
  prune, and branch deletion, or risk losing uncommitted work.
  - [X] 4.1 Write remove tests: clean removal succeeds; non-worktree
    path rejected (exit 2) [verify: auto-test]
    → covered in embo-worktree-remove.test.sh [live] (2026-09-08)
  - [X] 4.2 Write DIRTY-guard test: worktree with uncommitted tracked
    changes → abort (exit 3), files surfaced, nothing removed
    [verify: auto-test]
    → dirty worktree refused, not removed [live] (2026-09-08)
  - [X] 4.3 Write `--branch` tests: deletes a merged branch; keeps an
    unmerged one with a note (no `--force-branch`) [verify: auto-test]
    → merged branch deleted; unmerged kept [live] (2026-09-08)
  - [X] 4.4 Implement `embo-worktree-remove` as a bare wrapper (validate
    registered worktree, dirty-guard, remove+prune, optional `--branch`/
    `--force-branch`) [verify: auto-test]
    → 13 passed, 0 failed [live] (2026-09-08)
  - [X] 4.5 Document the `Bash(embo-worktree-remove *)` allow opt-in in
    README [verify: code-only]

  > **Scope correction (2026-09-08):** an auto-merging
  > `embo-worktree-finish` (test → merge into a local base → re-test →
  > cleanup, modes merge/pr/keep) was built and tested first, then CUT
  > after live testing showed interactive worktree work merges via the
  > normal PR/merge flow — the automation solved a problem the user
  > does not have. It was replaced by the remove-only helper above.

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
    README alongside the remove opt-in [verify: code-only]

- [X] 8.0 **User Story:** As a developer emitting a correction from
  inside a worktree, I want it recorded in the main tree, so that
  removing the worktree does not lose it (part of FR-4, found in live
  testing when a session's corrections landed in `.worktrees/.claude/`).
  - [X] 8.1 Resolve `.claude` in `capture-correction.sh` to the main
    tree via `--path-format=absolute --git-common-dir` + parent, with a
    CWD fallback outside git [verify: auto-test]
    → 43 passed, 0 failed; verified live that a worktree resolves to the
    main tree's .claude [live] (2026-09-08)
