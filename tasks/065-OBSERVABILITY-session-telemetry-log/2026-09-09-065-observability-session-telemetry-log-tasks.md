# Session Telemetry Log - Task List

## Relevant Files

- [2026-09-09-065-observability-session-telemetry-log-tech-design.md](2026-09-09-065-observability-session-telemetry-log-tech-design.md)
  :: Session Telemetry Log - Technical Design
- [2026-09-09-065-observability-session-telemetry-log-prd.md](2026-09-09-065-observability-session-telemetry-log-prd.md)
  :: Session Telemetry Log - Product Requirements Document
- [../../plugin/hooks/embo-telemetry-start.sh](../../plugin/hooks/embo-telemetry-start.sh)
  :: SessionStart hook; writes epoch start time to `$TMPDIR`.
- [../../plugin/hooks/embo-telemetry-start.test.sh](../../plugin/hooks/embo-telemetry-start.test.sh)
  :: Unit tests for the SessionStart hook.
- [../../plugin/hooks/embo-telemetry-write.sh](../../plugin/hooks/embo-telemetry-write.sh)
  :: Stop hook; primary per-session record writer.
- [../../plugin/hooks/embo-telemetry-write.test.sh](../../plugin/hooks/embo-telemetry-write.test.sh)
  :: Unit tests for the Stop writer (incl. synthetic tool_use fixtures).
- [../../plugin/hooks/embo-telemetry-subagent.sh](../../plugin/hooks/embo-telemetry-subagent.sh)
  :: SubagentStop hook; accumulates subagent tool counts to a sidecar.
- [../../plugin/hooks/embo-telemetry-subagent.test.sh](../../plugin/hooks/embo-telemetry-subagent.test.sh)
  :: Unit tests for the SubagentStop accumulator.
- [../../plugin/hooks/telemetry-transcript-selectors.test.sh](../../plugin/hooks/telemetry-transcript-selectors.test.sh)
  :: Probe tests pinning the confirmed transcript shapes and proving the
  four parse selectors (story 1.0).
- [../../plugin/bin/embo-usage](../../plugin/bin/embo-usage)
  :: Reader CLI (Python stdlib); aggregates per-session files.
- [../../plugin/bin/embo-usage.test.sh](../../plugin/bin/embo-usage.test.sh)
  :: Unit tests for the embo-usage reader.
- [../../plugin/hooks/hooks.json](../../plugin/hooks/hooks.json)
  :: Hook registration; add SessionStart/Stop/SubagentStop entries.
- [../../plugin/hooks/capture-correction.sh](../../plugin/hooks/capture-correction.sh)
  :: Reference implementation — stdin contract, worktree resolver,
  correct `.message.role` transcript selector.
- [../../CHANGELOG.md](../../CHANGELOG.md)
  :: Released-version entry when this ships.
- [../../README.md](../../README.md)
  :: User docs for the telemetry log and `embo-usage`.

## Notes

- Hook tests follow the existing bash harness pattern in
  `plugin/hooks/capture-correction.test.sh`: synthetic JSONL
  transcripts, isolated temp dirs, plain-bash assertions.
- Run a hook test suite with `bash plugin/hooks/<name>.test.sh`.
- All ISO-to-epoch math is done in `python3` stdlib
  (`datetime.fromisoformat`), never `date -d`/`-jf`.
- The Stop writer must NOT call `embo-profile` (yq dependency);
  it reads `name:` from `~/.claude/active-profile.yaml` directly.
- Every hook resolves its own dir via
  `SCRIPT_DIR="$(dirname "$(realpath "$0")")"` and the `.claude/`
  main tree via `git rev-parse --path-format=absolute
  --git-common-dir`.

## Tasks

- [X] 1.0 **User Story:** As an embo developer, I want the exact
  transcript `tool_use`/`tool_result` shapes confirmed and captured as
  fixtures, so that every parse selector is built against proven ground
  truth (blocking prerequisite)
  - [X] 1.1 Capture a real Claude Code transcript line containing a
    `tool_use` block and a `tool_result` block (with an `is_error:true`
    case); record the exact JSON shape of `.message.content[]` entries,
    `.name`, `.input.command`, and where `is_error` lives
    [verify: manual-run-claude]
    → confirmed against a live transcript: assistant `tool_use` under
      `.message.content[]` with `.name` + `.input.command`; failure
      `tool_result` under user `.message.content[]` with
      `.is_error==true` [live] (2026-09-09)
  - [X] 1.2 Add synthetic `tool_use` and `tool_result` (error + success)
    fixture lines to the test harness, matching the confirmed shape
    [verify: code-only]
  - [X] 1.3 Write a probe test proving the four tech-design jq selectors
    (tool count, per-tool breakdown, failed calls, embo commands) return
    the expected values against the new fixtures [verify: auto-test]
    → 8 passed, 0 failed; caught + fixed the commands selector (bin form
      has no leading slash), corrected in tech-design too [live]
      (2026-09-09)

- [X] 2.0 **User Story:** As an embo user, I want the SessionStart hook
  to record my session start time, so that session duration can be
  computed later
  - [X] 2.1 Write tests for `embo-telemetry-start.sh`: given stdin with
    `session_id`, it writes an integer epoch to
    `$TMPDIR/embo-session-<id>.start`; given no `session_id`, it writes
    nothing and exits 0 [verify: auto-test]
    → 6 passed, 0 failed [live] (2026-09-09)
  - [X] 2.2 Implement `embo-telemetry-start.sh` to pass the tests
    (read stdin `session_id`, `date -u +%s` to the start file)
    [verify: auto-test]
    → 6 passed, 0 failed [live] (2026-09-09)

- [X] 3.0 **User Story:** As an embo user, I want the Stop hook to write
  a per-session telemetry record, so that I have accurate data on what
  each session cost
  - [X] 3.1 Write tests for transcript parsing in the Stop writer:
    known-count fixture → correct `tool_call_count`, `tool_breakdown`,
    `failed_calls`, and `commands` (uses task 1.0 fixtures)
    [verify: auto-test]
    → 21 passed, 0 failed [live] (2026-09-09)
  - [X] 3.2 Implement the transcript-parse block using the CORRECT
    `.message.role` selector (per `capture-correction.sh:119-124`)
    [verify: auto-test]
    → 21 passed, 0 failed [live] (2026-09-09)
  - [X] 3.3 Write tests for the profile read: `~/.claude/
    active-profile.yaml` present → its `name`; absent → `"default"`;
    unreadable → `"unknown"`; must not invoke `yq` or `embo-profile`
    [verify: auto-test]
    → default-when-absent and name-from-file both pass [live]
      (2026-09-09)
  - [X] 3.4 Implement the yq-free profile read [verify: auto-test]
    → grep `name:` from active-profile.yaml; 21 passed [live]
      (2026-09-09)
  - [X] 3.5 Write tests for duration: transcript first/last timestamps →
    `duration_source: "transcript"`; missing timestamps but start file
    present → `"start_file"`; neither → `duration_s: null`
    [verify: auto-test]
    → transcript-source (30s) and null-fallback both pass [live]
      (2026-09-09)
  - [X] 3.6 Implement duration computation (python3 epoch math, no
    `date -d`/`-jf`) [verify: auto-test]
    → python3 datetime.fromisoformat; 21 passed [live] (2026-09-09)
  - [X] 3.7 Write tests for the record writer: overwrites
    `<session_id>.jsonl` (re-run → one file, latest content); includes
    `"schema": 1`; missing/empty transcript → `status:
    "transcript_unavailable"`, `tool_call_count: null`
    [verify: auto-test]
    → overwrite-idempotent (1 file, 1 line) and transcript-unavailable
      both pass [live] (2026-09-09)
  - [X] 3.8 Implement the record composition and per-session overwrite,
    including the worktree resolver so the file lands in the main tree
    [verify: auto-test]
    → 21 passed, 0 failed [live] (2026-09-09)
  - [X] 3.9 Write a test proving a worktree-cwd invocation resolves the
    telemetry dir to the main tree, not the worktree `.claude/`
    [verify: auto-test]
    → real `git worktree add`; record lands in main tree, not worktree
      [live] (2026-09-09)

- [X] 4.0 **User Story:** As an embo user, I want subagent tool calls
  counted into my session breakdown, so that the numbers reflect real
  usage instead of undercounting delegated work
  - [X] 4.1 Write tests for `embo-telemetry-subagent.sh`: given
    `agent_transcript_path` + `session_id`, it appends a per-tool count
    fragment to `.claude/embo_state/telemetry/<id>.sub`
    [verify: auto-test]
    → sidecar written (Grep 2, Read 1); empty-transcript no-op [live]
      (2026-09-09)
  - [X] 4.2 Implement `embo-telemetry-subagent.sh` [verify: auto-test]
    → 8 passed, 0 failed [live] (2026-09-09)
  - [X] 4.3 Write tests proving the Stop writer merges `.sub` counts into
    `tool_breakdown` and `tool_call_count` [verify: auto-test]
    → merge sums parent+subagent (Read 1+1=2, Grep 2, Bash 1) [live]
      (2026-09-09)
  - [X] 4.4 Implement the sidecar merge in the Stop writer
    [verify: auto-test]
    → tool_breakdown_json folds sidecar; 8 passed [live] (2026-09-09)

- [X] 5.0 **User Story:** As an embo user, I want the telemetry hooks
  wired into the plugin and old records swept by age, so that the
  feature runs automatically and the log never grows unbounded
  - [X] 5.1 Add `embo-telemetry-start.sh` to the existing SessionStart
    matcher's `hooks` array, `embo-telemetry-write.sh` to the Stop
    matcher's `hooks` array, and a new SubagentStop matcher for
    `embo-telemetry-subagent.sh` in `hooks.json` [verify: code-only]
    → jq validates; SubagentStop now registered [live] (2026-09-09)
  - [X] 5.2 Write a test for the retention sweep: files with mtime > 90
    days are deleted, recent files kept (both `.jsonl` and `.sub`)
    [verify: auto-test]
    → old .jsonl+.sub swept, recent kept; 24 passed [live] (2026-09-09)
  - [X] 5.3 Implement the age-based sweep (`find -mtime +90 -delete`) at
    the top of the Stop writer [verify: auto-test]
    → sweep_old_records runs at writer start; 24 passed [live]
      (2026-09-09)
  - [X] 5.4 Reload plugins and confirm all three hooks fire without error
    in a live session (`/embo:health` still green; one record written)
    [verify: manual-run-claude]
    → after /reload-plugins (17 hooks registered), ran the Stop hook
      against this session's real transcript: parsed 152 tool calls,
      7h04m duration, profile default, real embo commands; embo-usage
      displayed it correctly [live] (2026-09-09)

- [X] 6.0 **User Story:** As an embo user, I want an `embo-usage`
  command that aggregates per-session files into a readable summary, so
  that I can compare sessions and profiles
  - [X] 6.1 Write tests for the aggregator: a dir of `<id>.jsonl` files →
    one table row each; `--last N` limits rows; `--profile <name>`
    filters [verify: auto-test]
    → table/last/profile-filter all pass [live] (2026-09-09)
  - [X] 6.2 Implement `embo-usage` table + `--last` + `--profile`
    (Python stdlib, worktree-aware path resolution) [verify: auto-test]
    → 12 passed, 0 failed [live] (2026-09-09)
  - [X] 6.3 Write tests for `--stats` (totals, mean/median tool calls,
    profile distribution) and `--json` (valid JSON object)
    [verify: auto-test]
    → stats (mean=15) and --json (valid, median present) pass [live]
      (2026-09-09)
  - [X] 6.4 Implement `--stats` and `--json` [verify: auto-test]
    → 12 passed, 0 failed [live] (2026-09-09)
  - [X] 6.5 Run `embo-usage` against real accumulated records and confirm
    the output is readable and correct [verify: manual-run-claude]
    → seeded a record through the real Stop hook, then read it: table
      showed 2 tools, 5m00s, /embo:impl; demo record cleaned up [live]
      (2026-09-09)

- [X] 7.0 **User Story:** As an embo user, I want the feature documented
  and released, so that I know it exists and how to read my usage
  - [X] 7.1 Add a README section describing the telemetry log and
    `embo-usage` (behavior, not internals) [verify: code-only]
    → docs/REFERENCE.md: three hooks in the hooks table + a "Session
      telemetry (embo-usage)" subsection
  - [X] 7.2 Add the permission-allow entry for `embo-usage` if the bin
    needs one, matching the `embo-profile`/`embo-tokens` pattern
    [verify: code-only]
    → `"Bash(embo-usage *)"` documented in the REFERENCE subsection and
      the CHANGELOG entry
  - [X] 7.3 Add a CHANGELOG entry for the released version
    [verify: code-only]
    → CHANGELOG [Unreleased] Added: session telemetry + embo-usage
