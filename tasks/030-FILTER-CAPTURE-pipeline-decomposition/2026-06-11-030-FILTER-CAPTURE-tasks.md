# 030-FILTER-CAPTURE-pipeline-decomposition - Task List

## Relevant Files
- [2026-06-11-030-FILTER-CAPTURE-tech-design.md](2026-06-11-030-FILTER-CAPTURE-tech-design.md)
  :: Tech design (detection, --filter-b64 mode, exclusions, marker)
- [../../bash-output-capture-problem-map.md](../../bash-output-capture-problem-map.md)
  :: PRD (problem map P1-P5, chosen direction, NotebookLM review)
- `.claude/hooks/approve-compound.sh` :: FILTER_HEADS,
  split_filter_tail, rewrite branch in main
- `.claude/hooks/approve-compound.test.sh` :: detection cases
- `.claude/hooks/embo-capture.sh` :: --filter-b64 mode, stderr
  separation, dual-exit-code marker
- `.claude/hooks/embo-capture.test.sh` :: filter-mode cases
- `.claude/commands/dev/start.md` :: REDIRECT-CMD-OUTPUT clause
- `README.md` :: marker contract documentation

## Notes
- Run suites: `bash .claude/hooks/approve-compound.test.sh`,
  `bash .claude/hooks/embo-capture.test.sh`.
- TDD for Stories 1.0-3.0 (hook/wrapper logic); doc stories are
  code-only.
- Hooks are installed globally — Story 6.0 re-syncs `~/.claude/hooks/`
  via ./install.sh and verifies live before the task closes.
- Fail-safe stance: any ambiguous parse → no decomposition, fall back
  to existing whole-compound wrap. Tests must pin this.

## Session State (2026-06-17, COMPLETE)
- All stories 1.0-6.0 done. Suites green (approve-compound 164,
  embo-capture 60), start.md rule restructured, README documented.
- Story 6.0 verified live 2026-06-17: installed hooks byte-identical
  to repo (6.1), FR-5 filtered-view marker + unfiltered capture file
  (6.2), FR-6 upstream-failure marker (6.3), grep -q exclusion (6.4).
- Task changes still uncommitted on main (alongside other untracked
  work) — commit pending.
- Follow-up seed recorded in `bash-output-capture-problem-map.md`:
  voluntary runner / pure-stdin filter for the non-allowlisted path;
  priority ranking — no-re-run is the goal, exit code a bonus.
- Nothing committed to git yet (all changes uncommitted on main).

## Tasks
- [X] 1.0 **User Story:** As a developer, I want the hook to detect
  pipelines ending in a filter chain, so that only genuine
  filter-shaped commands are decomposed [3/3]
  - [X] 1.1 Write failing tests for filter-tail detection positives:
    `cmd | head -20`, `cmd | grep x | head -5` (multi-filter tail),
    every FILTER_HEADS member in tail position; and negatives: no
    pipe, `&&`/`;`/`||` compound (scope guard), non-filter tail
    (`a | grep x | xargs rm` → no decomposition)
    [verify: auto-test]
    → red phase: 22 cases added; 14 positives fail as expected
      (function absent), 8 negatives pass trivially (empty output),
      112 pre-existing pass. Contract pinned: two lines
      (upstream, filter chain) on detection, empty on none;
      all-filter pipeline → no decomposition (empty upstream,
      fail-safe) [live] (2026-06-11)
  - [X] 1.2 Write failing tests for opt-outs: `tail -f`/`tail -F`,
    `grep -q`, `sed -i`, filter segment containing a redirect;
    upstream exclusions: streaming heads (`yes`, `watch`,
    `journalctl -f`, upstream `tail -f`), existing should_wrap
    opt-outs hold; quoted-`|` ambiguity → no decomposition
    (fail-safe) [verify: auto-test]
    → red phase: 19 cases added (18 fail-safe negatives + 1 boundary
      positive: bounded `journalctl -n` stays eligible); suite now
      138 passed, 15 failed (14 from 1.1 + the new positive) [live]
      (2026-06-11)
  - [X] 1.3 Implement `FILTER_HEADS`, `split_filter_tail`, and the
    upstream exclusion list in approve-compound.sh until 1.1-1.2
    pass; full suite green (112 pre-existing) [verify: auto-test]
    → approve-compound.test.sh: 153 passed, 0 failed (112
      pre-existing + 41 new). Added is_filter_segment +
      split_filter_tail + CAPTURE_STREAM_HEADS; per-segment
      odd-quote fail-safe handles quoted pipes [live] (2026-06-11)
- [X] 2.0 **User Story:** As a developer, I want embo-capture to run
  upstream and filter separately, so that the full output is on disk
  and both true exit codes are visible [3/3]
  - [X] 2.1 Write failing tests for `--filter-b64` happy path: full
    upstream stdout in capture file, filtered view inline, marker
    carries path + lines/bytes + `upstream exit=` + `filter exit=`,
    wrapper exit code equals filter's [verify: auto-test]
    → red phase: happy-path + multi-segment chain cases added, fail
      as expected (mode absent → usage error) [live] (2026-06-11)
  - [X] 2.2 Write failing tests for edge semantics: stderr kept out
    of the filter path and emitted separately; failing upstream →
    nonzero `upstream exit=` in marker; `grep` no-match → marker
    `filter exit=1`, wrapper exits 1; large filtered view → existing
    preview thresholds apply; plain `--b64` mode behavior unchanged
    [verify: auto-test]
    → red phase: combined 2.1+2.2 suite run: 38 passed (33
      pre-existing --b64 cases unchanged + 5 trivial), 21 failed as
      expected [live] (2026-06-11)
  - [X] 2.3 Implement the `--filter-b64` mode in embo-capture.sh
    until 2.1-2.2 pass; full suite green (33 pre-existing)
    [verify: auto-test]
    → embo-capture.test.sh: 60 passed, 0 failed (33 pre-existing
      unchanged). Filter mode: stdout/stderr split, view thresholds
      reused, dual-exit marker, wrapper exits with filter's code
      [live] (2026-06-11)
- [X] 3.0 **User Story:** As a session model, I want the hook to
  rewrite detected filter pipelines into the new wrapper mode, so
  that filtered commands are captured end-to-end with zero prompts
  [2/2]
  - [X] 3.1 Write failing main/decide-level tests: allowlisted filter
    pipeline → emitted `updatedInput` command is
    `embo-capture.sh --filter-b64 <b64> --b64 <b64>`; non-allowlisted
    upstream → fallthrough (no rewrite); detected-but-ineligible
    shapes → existing whole-compound wrap; re-entrancy guard holds
    [verify: auto-test]
    → red phase: 11 cases added (8 final_command fail as expected,
      3 decide-gate pins pass: per-segment allowlist gating incl.
      filter segments confirmed pre-existing) [live] (2026-06-11)
  - [X] 3.2 Implement the rewrite branch in approve-compound.sh main
    until 3.1 passes; both suites fully green [verify: auto-test]
    → final_command + wrap_filter_command added; main rewire is one
      line. approve-compound: 164 passed, embo-capture: 60 passed,
      0 failed [live] (2026-06-11)
- [X] 4.0 **User Story:** As a session model, I want the
  REDIRECT-CMD-OUTPUT rule to cover the filtered-view marker, so that
  I re-read the capture file instead of re-running commands [1/1]
  - [X] 4.1 Add the filtered-view clause to RULE:REDIRECT-CMD-OUTPUT
    in start.md: marker semantics, Read/Grep the capture file, never
    re-run, `upstream exit=` vs `filter exit=` interpretation
    [verify: code-only]
    → REVISED per user: full rule restructure, not just a clause.
      New shape: problems first (context flood, masked exit code,
      lost output → re-run, approval dialog), then install summary,
      chain of events with per-step purpose, both markers, behavior
      list incl. auto-approval preference and qualified never-re-run
      (2026-06-11)
- [X] 5.0 **User Story:** As an end user installing embo, I want the
  marker contract documented in the README, so that I understand the
  filtered-view behavior and can disable or tune it [1/1]
  - [X] 5.1 Document in README Hooks section: filtered-view marker
    format, when decomposition triggers, exclusion list, tuning env
    vars (EMBO_CAPTURE_*), manual steps alongside install.sh
    [verify: code-only]
    → embo-capture table row extended; "Filtered pipelines" section
      added after allowlist-ownership paragraph (marker, exclusions,
      EMBO_CAPTURE_* tuning). Existing manual setup steps unchanged
      (no new registration needed — filter mode rides the same
      wrapper allow-rule) (2026-06-11)
- [X] 6.0 **User Story:** As the maintainer, I want the updated hooks
  deployed and verified live, so that filter capture is proven in a
  real session before the task closes [4/4]
  - [X] 6.1 User runs ./install.sh to sync updated hooks to
    ~/.claude/hooks/ (state intent; harness gates)
    [verify: manual-run-user]
    → installed hooks confirmed byte-identical to repo copies
      (`diff -q` clean for both embo-capture.sh and approve-compound.sh)
      and demonstrably active — capture markers appear live this
      session. Sync already in place; no re-run needed [live]
      (2026-06-17)
  - [X] 6.2 Live FR-5: allowlisted `cmd | grep X` with bulky upstream
    → filtered view inline, marker with both exit codes, Read of the
    capture file shows UNFILTERED content [verify: manual-run-claude]
    → `git log --oneline -40 | grep feat`: filtered view inline (5
      lines), marker `40 lines, 3160 bytes, upstream exit=0,
      filter exit=0`; capture file held all 40 unfiltered lines
      (`wc -l` = 40) [live] (2026-06-17)
  - [X] 6.3 Live FR-6: failing upstream piped into a filter → marker
    shows `upstream exit=<nonzero>` despite clean filtered view
    [verify: manual-run-claude]
    → `git log --oneline /nonexistent-ref | grep feat`: marker
      `0 lines, 0 bytes, upstream exit=128, filter exit=1`; git's
      fatal error surfaced separately on stderr, true upstream
      failure visible in marker [live] (2026-06-17)
  - [X] 6.4 Live exclusion check: `grep -q` or `tail -f` shape → not
    decomposed (existing behavior observed)
    [verify: manual-run-claude]
    → `git log --oneline -5 | grep -q feat`: no filtered-view marker
      emitted — `grep -q` correctly excluded, falls back to
      whole-compound wrap [live] (2026-06-17)
