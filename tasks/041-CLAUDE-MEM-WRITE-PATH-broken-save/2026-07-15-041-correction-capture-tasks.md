# Correction Capture — Task List

## Relevant Files
- [2026-07-15-041-correction-capture-tech-design.md](2026-07-15-041-correction-capture-tech-design.md)
  :: Correction Capture - Technical Design (reviewed by two clean-context passes)
- [2026-07-15-041-correction-capture-prd.md](2026-07-15-041-correction-capture-prd.md)
  :: Correction Capture - Product Requirements Document
- [FINDINGS-correction-capture.md](FINDINGS-correction-capture.md)
  :: Live evidence + working recipe (obs 29191 proof)
- [../../plugin/commands/enable-corrections.md](../../plugin/commands/enable-corrections.md)
  :: NEW — turn-on command
- [../../plugin/commands/disable-corrections.md](../../plugin/commands/disable-corrections.md)
  :: NEW — turn-off command (full undo)
- [../../plugin/commands/improve.md](../../plugin/commands/improve.md)
  :: MODIFY — rewrite search + curation persistence, drop dead save_memory
- [../../plugin/claude-mem/code-embo.build.jq](../../plugin/claude-mem/code-embo.build.jq)
  :: REUSE — jq mode-file transform (proven correct, no change)
- [../../plugin/claude-mem/code-embo-build.test.sh](../../plugin/claude-mem/code-embo-build.test.sh)
  :: NEW — fixture test for the jq transform
- [../../plugin/claude-mem/corrections-lib.sh](../../plugin/claude-mem/corrections-lib.sh)
  :: NEW — sourceable shell lib: settings merge, conflict guard,
  enable-record, removal guard, curation read/write (the testable core)
- [../../plugin/claude-mem/corrections-lib.test.sh](../../plugin/claude-mem/corrections-lib.test.sh)
  :: NEW — fixture tests for corrections-lib.sh
- [../../plugin/commands/health.md](../../plugin/commands/health.md)
  :: PATTERN — check/report/collect-all shape for enable's verification step
- [../../plugin/hooks/fix-hooks.sh](../../plugin/hooks/fix-hooks.sh)
  :: PATTERN — detect-then-repair + jq in-place edit convention
- [../../plugin/hooks/fix-hooks.test.sh](../../plugin/hooks/fix-hooks.test.sh)
  :: PATTERN — .test.sh fixture-test convention to follow
- [../../.gitignore](../../.gitignore)
  :: MODIFY — add .claude/correction-curation.json
- [../../CLAUDE.md](../../CLAUDE.md)
  :: MODIFY — document plugin/claude-mem/; correct save_memory claim

## Notes
- These are Claude Code command files (Markdown) + one shell test, not a
  compiled app. "Tests" here are fixture-based shell tests for the jq
  transform and for the file-write/idempotency logic, run against copies
  in a temp dir — never against the live claude-mem worker.
- The worker-restart + log-verification steps are environment-dependent
  and stay `manual-run-claude`, per the tech-design's Verification
  Approach.
- Run the jq/shell tests directly: `bash plugin/claude-mem/code-embo-build.test.sh`.
- claude-mem mechanism verified against 13.11.0, worker runtime. The
  mechanism relies on undocumented claude-mem internals (see tech-design
  §Implementation Constraints) — the version gate (1.x) and worker-log
  verification (1.x) make breakage visible rather than silent.

## TDD Planning Guidelines
- The jq transform (4.x) and the file-write/idempotency logic (1.x, 2.x,
  3.x curation) are pure, deterministic, fixture-testable → TDD applies:
  write the fixture test first, then the logic.
- Command orchestration prose, doc edits, and upstream issue filing are
  not unit-testable in isolation → verified by `manual-run-claude`,
  `code-only`, or `manual-run-user` as tagged, no test-first cycle.

## Tasks

- [X] 1.0 **User Story:** As an embo user, I want a one-command turn-on
  for correction capture, so that claude-mem starts saving my
  corrections with no manual file-editing.
  - [X] 1.1a Scaffold `plugin/claude-mem/corrections-lib.sh` as a
    sourceable function library (following `fix-hooks.sh`), with a
    path-override convention so tests target synthetic temp files, never
    real `~/.claude` config [verify: code-only]
  - [X] 1.1 Write fixture test (`corrections-lib.test.sh`) for
    `corrections_merge_modes_dir`: given a settings.json with no `env`
    block, an empty `env` block, and an unrelated key present, assert
    the merge adds `CLAUDE_MEM_MODES_DIR` without dropping existing keys;
    then implement the function to pass [verify: auto-test]
    → 5 passed, 0 failed [live] (2026-07-16)
  - [X] 1.2 Write fixture test for `corrections_modes_dir_conflict` +
    the enable-record write: `CLAUDE_MEM_MODES_DIR` set to a DIFFERENT
    path → conflict reported, no overwrite; set to the SAME value →
    `claude_mem_modes_dir_written=false` recorded; unset → written=true
    with the value recorded; then implement to pass [verify: auto-test]
    → 13 passed, 0 failed [live] (2026-07-16)
  - [X] 1.3 Write fixture test for enable idempotency: given a
    half-applied state (mode file written, env var not yet set),
    re-invoking the lib functions converges without double-writing or
    erroring; then implement to pass [verify: auto-test]
    → 17 passed, 0 failed; jq merge idempotent by construction, no new
    impl needed [live] (2026-07-16)
  - [X] 1.4 Author `plugin/commands/enable-corrections.md` Step 0:
    disclose the machine-wide effect (single shared worker, adds
    `correction` type to every project) and require explicit consent
    before proceeding [verify: manual-run-claude]
    → Step 0 consent gate authored; exercised via 1.10 live run
  - [X] 1.5 Author Step 1: detect installed claude-mem version, locate
    its shipped `modes/code.json`, and warn (require confirmation to
    continue) if the version differs from the verified 13.11.0
    [verify: manual-run-claude]
    → detected 13.11.0 (matched, no warning) in 1.10 live run
  - [X] 1.6 Author Step 2: rebuild `~/.claude-mem/modes/code-embo.json`
    from the installed `code.json` via
    `jq -f plugin/claude-mem/code-embo.build.jq` — always rebuild, even
    if the file exists (defeats stale mode after a claude-mem update)
    [verify: manual-run-claude]
    → built 9-type mode file in 1.10 live run [live] (2026-07-16)
  - [X] 1.7 Author Step 3 (env write + conflict guard) and Step 4
    (record prior `CLAUDE_MEM_MODE`, then set `code-embo`), writing the
    enable-record JSON (all fields per tech-design Data Models) using an
    atomic temp-file+rename write [verify: manual-run-claude]
    → conflict=absent → env written; record written with all 5 fields
    in 1.10 live run [live] (2026-07-16)
  - [X] 1.8 Author Step 5: stop the worker via `worker.pid`, then verify
    the day's log shows `Mode loaded: code-embo` with no `falling back`
    line; on fallback, report failure with the exact log path
    [verify: manual-run-claude]
    → worker restarted, log showed `Mode loaded: code-embo` in 1.10
    [live] (2026-07-16)
  - [X] 1.9 Add YAML frontmatter `description` matching the shipped
    command convention (see other `plugin/commands/*.md`)
    [verify: code-only]
  - [X] 1.10 Live end-to-end: run `/embo:enable-corrections` from a
    disabled state, confirm worker log shows `Mode loaded: code-embo`
    [verify: manual-run-claude]
    → ran Steps 1-5 live; worker log: `Mode loaded: code-embo`, no
    fallback; env var written to CC settings, 9-type mode built, record
    written [live] (2026-07-16); also fixed worker.pid JSON read bug in
    both commands

- [X] 2.0 **User Story:** As an embo user, I want a one-command turn-off,
  so that I can fully reverse correction capture and return claude-mem to
  its prior state.
  - [X] 2.1 Write fixture test for
    `corrections_should_remove_modes_dir`: returns true ONLY when
    `claude_mem_modes_dir_written=true` AND current value equals the
    recorded `claude_mem_modes_dir_value`; false otherwise; then
    implement to pass [verify: auto-test]
    → 20 passed, 0 failed [live] (2026-07-16)
  - [X] 2.2 Write fixture test for crash-safe re-run: enable-record
    present, simulate a crash after mode-restore but before record
    deletion; re-invoking disable functions converges (restore
    idempotent, record only deleted after all restore steps succeed);
    then implement to pass [verify: auto-test]
    → 25 passed, 0 failed; added corrections_restore_mode +
    corrections_remove_modes_dir, both idempotent [live] (2026-07-16)
  - [X] 2.3 Author `plugin/commands/disable-corrections.md` Step 1: read
    the enable-record; if absent, report "not enabled by this command"
    and stop (do not guess prior state) [verify: manual-run-claude]
    → no-record guard verified live (Test A) [live] (2026-07-16)
  - [X] 2.4 Author Steps 2-3: restore `CLAUDE_MEM_MODE` to the recorded
    prior value; conditionally remove the env var per the 2.1 guard
    [verify: manual-run-claude]
    → guard→remove, mode restored, env removed in 2.7 [live] (2026-07-16)
  - [X] 2.5 Author Steps 4-5: stop the worker and confirm the log no
    longer shows `code-embo`; delete the enable-record last, only after
    restore steps succeed [verify: manual-run-claude]
    → record deleted last in 2.7 [live] (2026-07-16)
  - [X] 2.6 Add YAML frontmatter `description` [verify: code-only]
  - [X] 2.7 Live round-trip: enable then disable, assert
    `~/.claude-mem/settings.json` `CLAUDE_MEM_MODE` matches its
    pre-enable value and the worker log shows no `code-embo`
    [verify: manual-run-claude]
    → ran disable live: removal guard→remove, mode restored to recorded
    prior, env var removed, record deleted last; env block back to
    baseline [live] (2026-07-16)

- [X] 3.0 **User Story:** As an embo user, I want `/embo:improve` to
  actually find my saved corrections and remember what I've already
  reviewed, so that it produces a useful proposal without resurfacing
  curated items.
  - [X] 3.1 Write fixture test for `corrections_curation_read` /
    `corrections_curation_write`: after a write, the file contains the
    reviewed IDs; a read after a second write excludes already-curated
    IDs; an unparseable file reads as "no state yet" (re-review), never
    a crash; then implement to pass [verify: auto-test]
    → 31 passed, 0 failed [live] (2026-07-16)
  - [X] 3.2 Write fixture test for the atomic curation write
    (temp-file+rename): a simulated crash mid-write leaves the prior
    file intact, not truncated; then implement to pass [verify: auto-test]
    → 31 passed, 0 failed; write via mktemp+mv, garbage base falls back
    to empty [live] (2026-07-16)
  - [X] 3.3 `improve.md` Step 1: read corrections via **direct SQL** on
    `claude-mem.db` (`WHERE type='correction' AND project=X`), NOT the
    MCP search tool [verify: manual-run-claude]
    → design revised after investigation: MCP free-text fallback is
    lossy (semantic rank + limit can miss corrections); the type= filter
    is broken (#3279) but corrections ARE stored+indexed (Chroma: 44
    rows), so SQL on the source table is complete + deterministic. Live:
    SQL returned all 3 embo corrections, exact scope [live] (2026-07-16)
  - [X] 3.4 Delete `improve.md` Step 1 second search call (lines 33-39,
    CORRECTION-STATUS read-back); replace with a read of the local
    curation file [verify: code-only]
  - [X] 3.5 Add the enabled/disabled pre-check: read
    `~/.claude-mem/settings.json` `CLAUDE_MEM_MODE`; if not `code-embo`,
    emit the "never turned on → run /embo:enable-corrections" message,
    distinct from "on but nothing to review" [verify: manual-run-claude]
    → live: pre-check read `code-embo` → proceeds; distinct messages
    authored for the not-enabled and empty cases [live] (2026-07-16)
  - [X] 3.6 Rewrite `improve.md` Step 4 (lines 85-103): replace both
    `save_memory` calls (lines 90, 99) with an atomic write of curated
    IDs to the local curation file [verify: code-only]
  - [X] 3.7 Add a code comment at the free-text-fallback site pointing at
    the filed upstream search-filter issue (link from 6.1), so the
    workaround is revisited on claude-mem upgrade [verify: code-only]
    → workaround marker added; issue link fills in when 6.1 files it
  - [X] 3.8 Live: with capture enabled and at least one correction
    present, run `/embo:improve`; confirm it surfaces the correction and
    a second run does not re-surface a curated item
    [verify: manual-run-claude]
    → full loop live: obs 29191 (type=correction) surfaced via free-text
    fallback; curation write persisted it; second-run read excluded it
    (does not resurface) [live] (2026-07-16)

- [X] 4.0 **User Story:** As a developer trusting the mode-file
  transform, I want the jq build script covered by a test, so that a
  claude-mem update changing `code.json` is caught before it silently
  breaks capture.
  - [X] 4.1 Create a minimal fixture `code.json` (the fields the jq
    program reads: `observation_types` with 6 entries,
    `prompts.type_guidance` containing "EXACTLY one of these 6 options",
    `prompts.recording_focus`, `prompts.skip_guidance`)
    [verify: auto-test]
    → fixture built (internally consistent 6-type mode) [live] (2026-07-16)
  - [X] 4.2 Write `plugin/claude-mem/code-embo-build.test.sh` asserting
    the transform output has 7 observation types including a
    `correction` entry, "7 options" in type_guidance, and the appended
    recording_focus / skip_guidance clauses [verify: auto-test]
    → 10 passed, 0 failed [live] (2026-07-16)
  - [X] 4.3 Run the test against the ACTUAL installed `code.json` (not
    just the fixture) and confirm it passes for 13.11.0 [verify: auto-test]
    → live test found real mismatch: installed code.json has 8 types
    (guidance text lists only 6); assertion changed to base+1 (8→9) and
    a guidance-sub-fired check added [live] (2026-07-16)

- [X] 5.0 **User Story:** As an embo maintainer, I want the repo's docs
  and ignore rules updated to match this feature, so that the plugin
  structure is documented and no state file is committed by accident.
  - [X] 5.1 Add `.claude/correction-curation.json` to `.gitignore`
    [verify: code-only]
  - [X] 5.2 Add `plugin/claude-mem/` (holding `code-embo.build.jq` +
    `code-embo-build.test.sh`) to the CLAUDE.md File Structure tree
    [verify: code-only]
    → added claude-mem/ subtree + the two new command entries
  - [X] 5.3 Correct CLAUDE.md §Claude-Mem Integration: state that
    `save_memory` is confirmed unavailable in the worker runtime
    [verify: code-only]
    → done by DELETION not annotation (per user: no prose about a
    nonexistent tool); removed the dead save_memory list entries,
    migration mapping kept
  - [X] 5.4 Add the two new commands to CLAUDE.md's command count/list
    (17 → 19 commands) [verify: code-only]
  - [X] 5.5 Confirm `plugin/claude-mem/correction-capture.md` is removed
    (done this session — verify absent, no stray references remain)
    [verify: manual-run-claude]
    → absent; fixed a dangling ref in code-embo.build.jq [live] (2026-07-16)

- [X] 6.0 **User Story:** As an embo maintainer, I want the two known
  claude-mem defects filed upstream, so that the free-text workaround and
  the version gate can eventually be retired.
  - [X] 6.1 Search the claude-mem GitHub for an existing issue on the
    broken `search(type=...)` custom-type filter; if none, open one with
    a minimal reproduction; record the link in the PRD's action item and
    the 3.7 code comment [verify: manual-run-user]
    → no existing issue found (searched issues+PRs); filed
    thedotmack/claude-mem#3279 with abstract-placeholder repro; link
    recorded in PRD + improve.md marker [live] (2026-07-16)
  - [X] 6.2 File a feature request for a documented mode-extension API
    (so the `code.json` patch stops being an unsupported-internals
    dependency); record the link in the tech-design [verify: manual-run-user]
    → NOT re-filed: already exists as #1640 → canonical #2009, which is
    CLOSED as NOT_PLANNED. Recorded in PRD upstream-action item; embo's
    approach does not depend on it landing [live] (2026-07-16)

## Summary
6 user stories, 35 subtasks. Stories 1-3 carry the implementation
(a sourceable `corrections-lib.sh`, two new commands, and the
improve.md rewrite); story 4 is the jq safety test; story 5 is
docs/ignore hygiene; story 6 is upstream follow-up.
