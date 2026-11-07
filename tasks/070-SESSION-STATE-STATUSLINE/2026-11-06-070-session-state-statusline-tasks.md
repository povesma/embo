# Session State and Statusline Indicator - Task List

## Relevant Files

- [tasks/070-SESSION-STATE-STATUSLINE/2026-11-06-070-session-state-statusline-tech-design.md](2026-11-06-070-session-state-statusline-tech-design.md)
  :: Tech design (reviewed twice + task-list critique).
- [tasks/070-SESSION-STATE-STATUSLINE/2026-10-30-070-session-state-statusline-prd.md](2026-10-30-070-session-state-statusline-prd.md)
  :: PRD (reviewed twice).
- `plugin/bin/embo-session-state` :: NEW. Shared writer: subcommands
  `path`/`baseline`/`start`/`wrapup`/`resume`; schema, atomic write,
  merge-preserve, id safety, prune. (`delta` cut 2026-11-06 as
  convenience-only.)
- `plugin/bin/embo-session-state.test.sh` :: NEW. Writer unit tests.
- `plugin/hooks/session-identity.sh` :: MODIFY. SessionStart calls
  `baseline` in place of the old jsonl append; preserve-on-refire.
- `plugin/hooks/session-identity.test.sh` :: MODIFY. Assert the state
  write, not the jsonl append.
- `plugin/hooks/session-prompt-state.sh` :: NEW. UserPromptSubmit hook:
  flip `wrapped_up`→`started` on resumed work.
- `plugin/hooks/hooks.json` :: MODIFY. Register the UserPromptSubmit hook.
- `plugin/statusline.sh` :: MODIFY. Add `embo_state_segment()`; remove
  `record_session_identity()`.
- `plugin/commands/start.md` :: MODIFY. Call `start`; fast path keys on
  `phase: started` (not the marker) and shows the plain HEAD delta;
  remove the marker line.
- `plugin/commands/wrapup.md` :: MODIFY. Call `wrapup`.
- `plugin/commands/health.md` :: MODIFY. Read the state file instead of
  the jsonl; flag a live session with no file.

## Notes

- Shell tests follow the repo pattern: a sibling `*.test.sh` with
  fixtures, run directly. No jest.
- The state file is user-global and git-free:
  `${XDG_STATE_HOME:-~/.local/state}/embo/session-state/<session_id>.json`.
  Tests point `XDG_STATE_HOME` at a temp dir.
- Phase vocabulary: `new` → `started` → `wrapped_up`. No file and `new`
  both render as `embo:?`.
- All hooks/scripts exit 0 on any error; never print to stdout from a
  hook (corrupts the harness channel).

## TDD Planning Guidelines

Writer and statusline reader carry the logic → test-first. Hook glue,
`hooks.json`, command-body edits are config/scaffold → `code-only` or a
run check, no test-first pair.

## Tasks

- [X] 1.0 **User Story:** As an embo user, I want a tested state-file
  writer so baseline/start/wrapup/resume states are recorded reliably.
  [12/12]
  - [X] 1.1 Write tests for path resolution: `$HOME` + `session_id`,
    honouring `XDG_STATE_HOME`, no `git` invoked [verify: auto-test]
    → 4 path tests written and run; red as expected (no binary yet), 4 failed [live] (2026-11-06)
  - [X] 1.2 Implement path resolution + the `baseline`/`start`/`wrapup`/
    `resume`/`delta` subcommand skeleton [verify: auto-test]
    → full suite green: 47 passed, 0 failed [live] (2026-11-06)
  - [X] 1.3 Write tests for id safety: empty id, the literal
    `${CLAUDE_SESSION_ID}`, and an id with `/` or `..` each exit non-zero;
    a clean id exits 0 [verify: auto-test]
    → 6 id-safety + path-escape cases cover each rejection and a clean id [live] (2026-11-06)
  - [X] 1.4 Implement id safety (`^[A-Za-z0-9._-]+$`, reject `..`)
    [verify: auto-test]
    → charset + `..` check in valid_id, applied by every form and `path` [live] (2026-11-06)
  - [X] 1.5 Write tests for atomic write (`.tmp`+`mv`, no partial read)
    and unreadable-file-treated-as-absent [verify: auto-test]
    → tests assert no .tmp left, valid JSON, and a corrupt file rebuilt not merged [live] (2026-11-06)
  - [X] 1.6 Implement atomic write + read-modify-write merge of the
    `schema`/`phase`/`source`/`started_at`/`wrapped_up_at`/`head_sha`/
    `branch`/`repo_root`(home-relative)/`updated_at`/`ext` fields
    [verify: auto-test]
    → merge_write normalises the envelope, preserves ext + unknown keys, atomic mv [live] (2026-11-06)
  - [X] 1.7 Write per-subcommand tests: `baseline` writes `new` and
    preserves an existing phase on re-fire; `start` sets `started` +
    sha/branch/root, a second start resets; `wrapup` sets `wrapped_up`,
    wrapup-without-start → minimal (null `started_at`); `resume` flips
    `wrapped_up`→`started` else no-op, no-file → no-op; each preserves
    `ext`/unknown keys [verify: auto-test]
    → baseline/start/wrapup/resume + merge-preserve cases all pass [live] (2026-11-06)
  - [X] 1.8 Implement `baseline` [verify: auto-test]
  - [X] 1.9 Implement `start` [verify: auto-test]
    → started_at set once (sentinel), reset on second start keeps original started_at [live] (2026-11-06)
  - [X] 1.10 Implement `wrapup` + `resume` [verify: auto-test]
  - [X] 1.11 Write prune tests: deletes by mtime past threshold, never a
    just-touched file, ignores `*.tmp`, skips when <50 files; runs on
    `start` only (not `baseline`) [verify: auto-test]
    → prune cases cover mtime delete, fresh-keep, .tmp-ignore, <50 skip, baseline-no-prune [live] (2026-11-06)
  - [X] 1.12 Implement mtime prune (default 14 days) on `start`
    [verify: auto-test]
    → find -mtime +14 -delete, guarded by the 50-file floor, start-only [live] (2026-11-06)
- [X] 2.0 **User Story:** As an embo user, I want the baseline/resume
  writes driven by hooks so lifecycle state is recorded without the model
  remembering. [5/5]
  - [X] 2.1 Write tests: the SessionStart hook writes a `new` baseline
    with `session_id`+`source`; a re-fire (`resume`/`compact`) with an
    existing file **preserves** the phase, never resets to `new`
    [verify: auto-test]
    → session-identity.test.sh: 5 passed, 0 failed [live] (2026-11-06)
  - [X] 2.2 Change `session-identity.sh` to call `embo-session-state
    baseline` **in place of** the old `session-identity.jsonl` append, and
    update `session-identity.test.sh` to assert the state write
    [verify: auto-test]
    → hook now calls the writer; test asserts baseline write and no jsonl [live] (2026-11-06)
  - [X] 2.3 Write tests for the UserPromptSubmit hook: any prompt while
    `wrapped_up` flips to `started`; other prompts touch `updated_at`
    only; no file → no-op [verify: auto-test]
    → session-prompt-state.test.sh covers flip/touch/no-op/unsafe-id/no-stdout [live] (2026-11-06)
  - [X] 2.4 Implement `session-prompt-state.sh` (fast `jq`+`mv`, exit 0 on
    any error, no stdout) [verify: auto-test]
    → 8 passed, 0 failed [live] (2026-11-06)
  - [X] 2.5 Register the UserPromptSubmit hook in `hooks.json`, with a
    `jq` test asserting the entry is present and well-formed
    [verify: auto-test]
    → registered after behavioral-reminder; jq assertion green, hooks.json valid [live] (2026-11-06)
- [ ] 3.0 **User Story:** As an embo user, I want `/embo:start`,
  `/embo:wrapup` and `/embo:health` wired to the state file. [1/5]
  (NOTE 2026-11-07: the tech-design assumed `health.md` "currently reads
  the jsonl" — it does not; there was no jsonl reader to switch. 3.4 is
  reframed as ADDING a session-state check that flags a live session with
  no state file, which is the design's actual intent.)
  - [X] 3.1 Add a test asserting `start.md` and `wrapup.md` contain their
    wrapper calls [verify: auto-test]
    → commands/wiring.test.sh: start/wrapup/health wiring assertions pass (3/3) [live] (2026-11-07)
  - [~] 3.2 `/embo:start` calls `embo-session-state start
    ${CLAUDE_SESSION_ID} <sha> <branch> <root>` with the Batch A values
    (the only writer that sets `started`) [verify: manual-run-claude]
    → Batch A call added to start.md; needs a live /embo:start to verify substitution + write [simulated: awaiting live run] (2026-11-07)
  - [~] 3.3 `/embo:wrapup` calls `embo-session-state wrapup
    ${CLAUDE_SESSION_ID}` on completion [verify: manual-run-claude]
    → Step 6 added to wrapup.md; needs a live /embo:wrapup to verify [simulated: awaiting live run] (2026-11-07)
  - [~] 3.4 ADD a `/embo:health` session-state check that reads the file
    and flags a live session with no file (no prior jsonl reader existed)
    [verify: manual-run-claude]
    → Check 6 added to health.md; needs a live /embo:health to verify [simulated: awaiting live run] (2026-11-07)
  - [~] 3.5 Confirm the full start→wrapup→resume cycle updates the file
    live [verify: manual-run-claude]
    → requires live /embo:start → /embo:wrapup → prompt cycle [simulated: awaiting live run] (2026-11-07)
- [ ] 4.0 **User Story:** As an embo user, I want the statusline to show
  my session stage (`embo:?`/`▶`/`✓`) git-free. [3/4]
  - [X] 4.1 Write tests for `embo_state_segment()`: `embo:?` for no-file
    and `phase: new`; `embo:▶` started; `embo:✓` wrapped_up; `embo:?` for
    empty/corrupt and for a missing or unsafe stdin `session_id`; no
    `git` called [verify: auto-test]
    → statusline.test.sh: 8 passed, 0 failed, incl. a no-git stub assertion [live] (2026-11-07)
  - [X] 4.2 Implement `embo_state_segment()` (one `jq` read, path from
    `$HOME`+stdin `session_id`, same id-safety check) by the `mem:`
    segment [verify: auto-test]
    → segment added before mem:; now on statusline row 2 after the 2-row split (task 061); full render verified live [live] (2026-11-07)
  - [X] 4.3 Remove `record_session_identity()` from `statusline.sh`
    [verify: code-only]
    → removed; the diagnostic's only --git-common-dir call is gone (NFR-1) [live] (2026-11-07)
  - [~] 4.4 Confirm the states render live in the statusline
    [verify: manual-run-user]
    → needs user to confirm ▶/✓/? glyphs render in their terminal (tech-design open question) [simulated: awaiting user] (2026-11-07)
- [ ] 5.0 **User Story:** As an embo user, I want the `/embo:start` fast
  path to key on the state file instead of the in-context marker. [0/2]
  (SCOPE TRIMMED 2026-11-06: the `delta` subcommand and the git-delta
  fast path are cut as convenience-only complexity. The fast path now
  keys on `phase: started` and shows the existing plain HEAD delta that
  Batch A already runs. No new `delta` wrapper.)
  - [~] 5.1 `/embo:start` fast path takes effect only on `phase: started`
    (`new` is not a repeat start); on the fast path, show the existing
    `git log --oneline -10` + `git diff --stat HEAD` delta note
    [verify: manual-run-claude]
    → fast-path prose rewritten to read phase from the state file; needs a live repeat /embo:start to verify [simulated: awaiting live run] (2026-11-07)
  - [X] 5.2 Remove the marker line (`start.md`) and its marker-based
    fast-path prose, including the mention near the top of the file;
    grep test: the marker string appears nowhere in `plugin/`
    [verify: auto-test]
    → marker removed from start.md; wiring.test.sh marker-grep green (4/4) [live] (2026-11-07)
- [X] 6.0 **User Story:** As an embo maintainer, I want no stale identity
  log left behind. [1/1]
  - [X] 6.1 Confirm no `session-identity.jsonl` write remains after 2.2;
    if any does, add `.claude/session-identity.jsonl` to `.gitignore` and
    test with `git check-ignore` in a temp repo; otherwise remove stale
    references to it [verify: auto-test]
    → no jsonl write remains (hook + statusline both cleared); gitignore entry added defensively; git check-ignore test green [live] (2026-11-07)
