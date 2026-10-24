# worktree-isolation (v1) - Task List

## Relevant Files
- [2026-09-04-062-worktree-isolation-tech-design.md](2026-09-04-062-worktree-isolation-tech-design.md)
  :: Worktree Sessions with Shared Memory - Technical Design (v1)
- [2026-09-04-062-worktree-isolation-prd.md](2026-09-04-062-worktree-isolation-prd.md)
  :: Worktree Sessions with Shared Memory - Product Requirements
- [plugin/rlm_scripts/rlm_repl.py](../../plugin/rlm_scripts/rlm_repl.py)
  :: State-path resolver + write lock added here (state path at :56;
  `_save_state` sites at :944, :994, :1158).
- [plugin/commands/worktree.md](../../plugin/commands/worktree.md)
  :: NEW command — `/embo:worktree` with three modes: `<branch>`
  (open via native `EnterWorktree`, derived name, nest-refusal,
  base-ref warning), `list`, `remove [path]` (native `ExitWorktree`,
  never forced). Supersedes both bin wrappers below.
- ~~`plugin/bin/embo-worktree-start` (+ `.test.sh`)~~
  :: REMOVED — superseded by `/embo:worktree <branch>` / `list`.
- ~~`plugin/bin/embo-worktree-remove` (+ `.test.sh`)~~
  :: REMOVED — superseded by `/embo:worktree remove [path]`.
- [plugin/hooks/capture-correction.sh](../../plugin/hooks/capture-correction.sh)
  :: MODIFIED — resolves `.claude` to the main tree so corrections from
  a worktree are shared, not stranded.
- [plugin/rlm_scripts/rlm_repl.test.sh](../../plugin/rlm_scripts/rlm_repl.test.sh)
  :: NEW fixture test for resolver + lock concurrency + fcntl-absent +
  state-survival.
- [.gitignore](../../.gitignore)
  :: Add `.worktrees/` so repo-adjacent worktrees are never staged.

Note: `embo-worktree-finish` (+ test) was created then removed — see the
Scope correction under story 4.0. The two remaining wrappers
(`embo-worktree-start`, `embo-worktree-remove`) were later removed too,
replaced by one command file — see the Scope correction under story 9.0.

## Notes
- Tests follow the repo's `*.test.sh` fixture pattern (see
  `embo-deliver.test.sh`, `subagent-rules.test.sh`): build a temp git
  repo, `git worktree add` into a repo-adjacent path, assert, tear down.
- Run a test script directly: `bash plugin/rlm_scripts/rlm_repl.test.sh`.
  (The two `embo-worktree-*.test.sh` suites are gone with their
  scripts; `/embo:worktree` is prose and is verified by
  `manual-run-claude`, not by a fixture.)
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
    was later removed with its script — see story 4.0; the
    `embo-worktree-start`/`-remove` scaffolds went the same way in
    2026-10 — see story 9.0)
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
  > **The story (FR-2) still stands; its delivery moved.** All subtasks
  > below are SUPERSEDED — they built `embo-worktree-remove`, which was
  > deleted in 2026-10. FR-2 is now delivered by `/embo:worktree
  > remove` (story 9.0). History kept below, not deleted.
  - [X] ~~4.1 Write remove tests: clean removal succeeds; non-worktree
    path rejected (exit 2) [verify: auto-test]~~
    → SUPERSEDED (2026-10): script + its 13 tests deleted; FR-2 is now
    `/embo:worktree remove` — see story 9.0.
    → (historical) covered in embo-worktree-remove.test.sh [live] (2026-09-08)
  - [X] ~~4.2 Write DIRTY-guard test: worktree with uncommitted tracked
    changes → abort (exit 3), files surfaced, nothing removed
    [verify: auto-test]~~
    → SUPERSEDED (2026-10): the refusal now comes from native
    `ExitWorktree`; the command surfaces the files instead.
    → (historical) dirty worktree refused, not removed [live] (2026-09-08)
  - [X] ~~4.3 Write `--branch` tests: deletes a merged branch; keeps an
    unmerged one with a note (no `--force-branch`) [verify: auto-test]~~
    → SUPERSEDED (2026-10): branch deletion is a separate explicit
    `git branch -d` step in the command, not a script flag.
    → (historical) merged branch deleted; unmerged kept [live] (2026-09-08)
  - [X] ~~4.4 Implement `embo-worktree-remove` as a bare wrapper (validate
    registered worktree, dirty-guard, remove+prune, optional `--branch`/
    `--force-branch`) [verify: auto-test]~~
    → SUPERSEDED (2026-10): script deleted; replaced by the `remove`
    mode of `/embo:worktree` — see story 9.0.
    → (historical) 13 passed, 0 failed [live] (2026-09-08)
  - [X] ~~4.5 Document the `Bash(embo-worktree-remove *)` allow opt-in in
    README [verify: code-only]~~
    → SUPERSEDED (2026-10): no script, so no Bash allow-rule to
    document; the command needs no permission opt-in.

  > **Scope correction (2026-09-08):** an auto-merging
  > `embo-worktree-finish` (test → merge into a local base → re-test →
  > cleanup, modes merge/pr/keep) was built and tested first, then CUT
  > after live testing showed interactive worktree work merges via the
  > normal PR/merge flow — the automation solved a problem the user
  > does not have. It was replaced by the remove-only helper above.

- [X] 5.0 **User Story:** As a developer using worktrees, I want their
  checkout directories gitignored, so that worktree contents are never
  accidentally staged.
  - [X] 5.1 Add `.worktrees/` to `.gitignore` [verify: code-only]
  - [X] 5.2 Assert `git check-ignore .worktrees/probe` exits 0 in a
    fixture test [verify: auto-test]
    → check-ignore reports it ignored (was NOT-IGNORED before) [live]
    (2026-09-05)
  - [X] 5.3 Add `.claude/worktrees/` to `.gitignore` — the native
    `EnterWorktree` tool puts worktrees there, and only `.worktrees/`
    (the deleted scripts' location) was covered, so a native worktree
    showed as untracked and could be staged [verify: code-only]
    → both paths now ignored (2026-10-20)

- [X] 6.0 **User Story:** As a maintainer verifying the feature, I want
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
  - [X] 6.4 Manual end-to-end: `claude --worktree` a branch, confirm the
    session sees the main-tree RLM index (no re-index) and claude-mem
    history [verify: manual-run-user]
    → VERIFIED live via `claude --worktree feat/064-e2e` (2026-10-24):
      from inside the native worktree (`.claude/worktrees/feat+064-e2e`,
      branch `worktree-feat+064-e2e`), `rlm_repl status` resolved the
      MAIN-tree state file (267 files, no re-index), AND a claude-mem
      search returned this project's shared history (0.3.0, task 062/068,
      the worktree follow-up commits). Both halves proven through the
      CLI entry point, not a fixture.
    → Note: the native `claude --worktree` CLI derives the directory name
      with slash→`+` (`feat+064-e2e`), distinct from `/embo:worktree`'s
      slash→`-`; both are valid, different entry points.
    → (earlier, 2026-09-05) resolver verified through the bin wrapper
      from a real worktree [live]

- [X] 7.0 **User Story:** As a developer starting a parallel session, I
  want embo to create and name the worktree and let me list existing
  ones, so that I don't invent names or hand-track worktrees.
  > **The story (FR-7) still stands; its delivery moved.** All subtasks
  > below are SUPERSEDED — they built `embo-worktree-start`, deleted in
  > 2026-10. FR-7 is now delivered by `/embo:worktree <branch>` and
  > `/embo:worktree list` (story 9.0). History kept below.
  - [X] ~~7.1 Write tests for `embo-worktree-start <branch>`: creates
    `.worktrees/<derived-name>` on `<branch>` (slashes → `-`); refuses
    to nest when already inside a worktree; prints the path
    [verify: auto-test]~~
    → SUPERSEDED (2026-10): the derived name and the nest-refusal are
    now steps in `/embo:worktree <branch>`; the native `EnterWorktree`
    tool chooses the directory, so `.worktrees/` is not embo's to pick.
    → (historical) derived name, nest-guard, path-conflict all pass
    [live] (2026-09-05)
  - [X] ~~7.2 Write tests for `embo-worktree-start --list`: prints existing
    worktrees + their branches [verify: auto-test]~~
    → SUPERSEDED (2026-10): listing is now `/embo:worktree list`.
    → (historical) list shows main tree + created worktree [live] (2026-09-05)
  - [X] ~~7.3 Implement `embo-worktree-start` as a bare wrapper (create +
    derived name + nest-guard + list) [verify: auto-test]~~
    → SUPERSEDED (2026-10): script deleted — it called `git worktree
    add` directly, creating worktrees the harness cannot see.
    → (historical) 11 passed, 0 failed; nest-guard compares
    --git-dir/--git-common-dir both in absolute form
    (relative-vs-absolute would false-positive) [live] (2026-09-05)
  - [X] ~~7.4 Document the `Bash(embo-worktree-start *)` allow opt-in in
    README alongside the remove opt-in [verify: code-only]~~
    → SUPERSEDED (2026-10): no script, so no Bash allow-rule to
    document.

- [X] 8.0 **User Story:** As a developer emitting a correction from
  inside a worktree, I want it recorded in the main tree, so that
  removing the worktree does not lose it (part of FR-4, found in live
  testing when a session's corrections landed in `.worktrees/.claude/`).
  - [X] 8.1 Resolve `.claude` in `capture-correction.sh` to the main
    tree via `--path-format=absolute --git-common-dir` + parent, with a
    CWD fallback outside git [verify: auto-test]
    → 43 passed, 0 failed; verified live that a worktree resolves to the
    main tree's .claude [live] (2026-09-08)

- [~] 9.0 **User Story:** As a developer who wants parallel worktree
  sessions without phantom state, I want one `/embo:worktree` command
  that drives Claude Code's own worktree tools, so that every worktree
  embo opens is one the harness can see, track, and clean up.

  > **Scope correction (2026-10):** stories 4.0 and 7.0 shipped two
  > bare wrappers (`embo-worktree-start`, `embo-worktree-remove`) that
  > called `git worktree add` / `remove` themselves. Research into
  > comparable projects found nobody ships a standalone shell script
  > for worktrees: Superpowers uses a skill, Oh-My-ClaudeCode a
  > compiled TypeScript library for its agent swarm, and
  > claude-workflow-template a slash command wrapping the native
  > `EnterWorktree`/`ExitWorktree` tools; Spec-Kit has no worktree
  > support. Superpowers calls bypassing the native tool "the #1
  > mistake — it creates phantom state your harness can't see or
  > manage." The PRD already said v1 "must not rebuild" the native
  > lifecycle, and the scripts had drifted past that. Both scripts and
  > their 24 tests (11 + 13) were deleted and replaced by one command
  > file following the thin-wrapper approach. FR-2 and FR-7 are
  > unchanged as requirements; only their delivery moved. FR-3, FR-4
  > and FR-6 (shared index, shared memory, state survival) are
  > untouched.

  - [X] 9.1 Delete `plugin/bin/embo-worktree-start`,
    `plugin/bin/embo-worktree-remove` and both `.test.sh` suites
    [verify: code-only]
    → all four files removed from `plugin/bin/`
  - [~] 9.2 Write `plugin/commands/worktree.md` — `/embo:worktree` with
    three modes (`<branch>`, `list`, `remove [path]`): gate on
    `EnterWorktree` and refuse a raw-git fallback; refuse to nest
    (`--git-dir` vs `--git-common-dir`); warn that the native base ref
    is the remote default branch, not HEAD, and name
    `worktree.baseRef: "head"` as the user's remedy without setting it;
    derive the worktree name from the branch (slashes → hyphens);
    on remove never force, surface uncommitted files via
    `git -C <path> status --porcelain -uno` and put the choice to the
    user, with branch deletion a separate explicit `-d` step; state
    that it does not merge, does not install dependencies, and that
    subagents never call the worktree tools [verify: manual-run-claude]
    → written, NOT yet live-tested
    → CORRECTED 2026-10-20 against the loaded tool definitions (the
      first draft was written from the docs): `ExitWorktree` acts ONLY
      on a worktree the same session entered via `EnterWorktree` and is
      a no-op anywhere else, so "name the worktree to remove from the
      main tree" was wrong — the command now reports that it cannot and
      hands the user `git worktree remove`. The force path is
      `discard_changes: true`, named explicitly as forbidden. The
      native location `.claude/worktrees/<name>/` is now stated.
  - [X] 9.3b LIVE RUN 2026-10-20 — the whole command exercised end to
    end from the main tree on `feat/062-worktree-isolation`:
    - tool gate: `EnterWorktree` present; nest check `--git-dir` ==
      `--git-common-dir`, correctly read as the main tree
    - open: worktree created at `.claude/worktrees/wt-062-livetest` on
      branch `worktree-wt-062-livetest`, session switched into it
    - base ref: HEAD was `1c88b65` (the feature branch tip), NOT
      `origin/main` — `worktree.baseRef: "head"` took effect WITHOUT a
      session restart, contradicting the prediction that it needed one
    - **shared index (FR-3/FR-6): state file resolved to the MAIN tree**
      (`/Users/dnipro/home/AI/embo/.claude/rlm_state/state.pkl`), 267
      files, no re-index — the core feature proven on a real worktree,
      not a fixture
    - **shared corrections (FR-4): the worktree's `.claude/` held only
      tracked content; the main tree's `corrections.jsonl` was modified
      during the test** — nothing stranded in a deletable directory
    - list: both worktrees reported with paths and branches
    - gitignore: `.claude/worktrees/wt-062-livetest` matched
      `.gitignore:46` (without this session's fix it would have shown
      as untracked)
    - remove refusal: with one uncommitted file, `ExitWorktree
      action:"remove"` REFUSED, named the count, and pointed at
      `discard_changes: true`; the command's no-force rule held and the
      choice went to the user
    - remove: after the probe was deleted, removal succeeded; session
      back in the main tree, directory gone, branch deleted, no stray
      state [verify: manual-run-claude]
  - [X] 9.3 Live-test the open path: `/embo:worktree <branch>` from the
    main tree — derived name used, base-ref consequence stated before
    entering, landing branch confirmed [verify: manual-run-claude]
    → covered by the 9.3b live run (2026-10-20)
  - [X] 9.4 Live-test the nest refusal and the tool gate: invoke from
    inside a linked worktree (must stop); confirm the command does not
    fall back to `git worktree add` when `EnterWorktree` is absent
    [verify: manual-run-claude]
    → NEST REFUSAL verified live (2026-10-24): opened
      `.claude/worktrees/feat-test-nest`; from inside it `--git-dir`
      (`.git/worktrees/feat-test-nest`) != `--git-common-dir` (`.git`),
      command REFUSED and pointed back to the main tree. Correct.
    → TOOL GATE (the "Test B" absent-tool branch) — CLOSED, no live run
      needed. The "EnterWorktree genuinely absent" branch is NOT
      reachable on current Claude Code (checked 2.1.310, 2026-10-24):
      the worktree tools ship as DEFERRED tools — listed by name, schema
      loaded on demand via tool-search — in every reachable context
      (main session and subagent alike). A probe confirmed a subagent
      fetches `EnterWorktree` via `ToolSearch(select:...)` and calls it.
      So no in-session test can make the refusal fire; it would require
      an older build that never had the tools. The refusal path is
      instead verified by LOGIC + PROBE: a second probe ran the amended
      gate and confirmed it loads the deferred tool and proceeds, and
      that a tool-search on a non-existent name returns no schema, which
      the "conclude unavailable only once that load fails" clause routes
      to the refusal. Live-untriggerable, logically proven.
    → FINDING + FIX: the original gate ("if EnterWorktree is not
      available") misread a deferred-but-unfetched tool as absent, which
      would wrongly trigger the refusal on current builds. The gate now
      loads the deferred tool first and refuses only if that load fails.
      (worktree.md §tool gate, 2026-10-24)
  - [X] 9.5 Live-test the remove path: clean worktree removed via
    `ExitWorktree`; a dirty one is NOT forced — files surfaced, choice
    put to the user, nothing removed [verify: manual-run-claude]
    → covered by the 9.3b live run: refusal with one uncommitted file,
      then clean removal after it was deleted (2026-10-20)
  - [~] 9.8 Offer the base-ref fix instead of only naming it. Shipped
    0.3.0 warned that a worktree branches from the remote default
    branch and named `worktree.baseRef`, leaving the user to find out
    where a setting lives — too thin to act on. The command now shows
    the JSON, names both settings files, and offers to merge it in
    (once per session, user approves the write); README matches
    [verify: manual-run-claude]
    → written, NOT live-tested: the offer path has not been exercised
  - [X] 9.6 Record the enforcement downgrade in the docs: the no-force
    / no-`-D` / no-nest rules are now agent-followed prose, not a
    script's exit code — and open a follow-up for a PreToolUse hook
    that would restore mechanical enforcement [verify: code-only]
    → `plugin/commands/worktree.md` §Enforcement note added; task 067
      seed created for the PreToolUse hook (2026-10-21)
  - [X] 9.7 Update README and CHANGELOG for `/embo:worktree`, removing
    the two `Bash(embo-worktree-* *)` allow opt-ins that no longer
    apply [verify: code-only]
    → README worktree section rewritten around the command and the
      base-ref caveat; command table row added; CHANGELOG Unreleased
      bullet replaced; CLAUDE.md command counts 19 -> 20 (2026-10-20)
