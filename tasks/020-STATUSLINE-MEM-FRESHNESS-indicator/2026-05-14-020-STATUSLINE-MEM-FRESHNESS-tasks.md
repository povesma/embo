# 020-STATUSLINE-MEM-FRESHNESS — Task List

## Relevant Files

- [2026-05-14-020-STATUSLINE-MEM-FRESHNESS-prd.md](./2026-05-14-020-STATUSLINE-MEM-FRESHNESS-prd.md)
  :: PRD — requirements, user stories, acceptance criteria.
- [2026-05-14-020-STATUSLINE-MEM-FRESHNESS-tech-design.md](./2026-05-14-020-STATUSLINE-MEM-FRESHNESS-tech-design.md)
  :: Tech design — state machine, decision tree, error-handling
  matrix, verification approach.
- [../../.claude/statusline.sh](../../.claude/statusline.sh)
  :: Statusline script (97 lines) — single file to extend with
  `cmem_segment`, one `parts+=` insertion, and one header comment
  update.
- [../../tests/statusline/cmem_segment.test.sh](../../tests/statusline/cmem_segment.test.sh)
  :: New bash test harness — runs the #10353 edge-case matrix
  against `cmem_segment` with mocked `curl`.
- [../../README.md](../../README.md)
  :: User-facing docs — statusline section gains `mem:` description.
- [../../CLAUDE.md](../../CLAUDE.md)
  :: Repo-developer docs — update only if it references the
  statusline contents (verify first).
- [../../install.sh](../../install.sh) ::
  No logic change; verify propagation copies updated content.
- [../../install.ps1](../../install.ps1) ::
  No logic change; verify propagation copies updated content.

## Notes

- `cmem_segment` is a single bash function added to
  `.claude/statusline.sh`. No new files in the install surface
  (`.claude/`) — tests live at the repo root in `tests/statusline/`
  so they are not copied to `~/.claude/` by the installers.
- Tests use a mocked `curl` (function override or `PATH` shim).
  The function under test must accept the mocked path without
  changing its production code path.
- All shell code follows `set -euo pipefail` discipline already
  used in `statusline.sh`. Every potentially-failing command uses
  `|| true` / `|| default` to avoid tripping `-e`.
- Color codes are reused from the existing variables (`GREEN`,
  `YELLOW`, etc., lines 63–70 of `statusline.sh`). Do not
  introduce new color variables.
- Implementation order per user preference: **bulk implement first,
  then write the test matrix** (not strict TDD).

## TDD Planning Guidelines

This feature deviates from default TDD cadence by user choice:
implementation is written in one pass, then the #10353 edge-case
matrix is encoded as bash tests. Rationale: the function has five
discrete states with already-documented expected outputs, so the
test matrix is largely mechanical and benefits from being authored
against the finished function. Future edits to `cmem_segment` MUST
re-run the matrix as a regression gate.

## Tasks

- [X] 1.0 **User Story:** As a developer, I want a `cmem_segment`
  bash function added to `.claude/statusline.sh` that produces the
  freshness segment, so that the script can render `mem:Xm` /
  `mem:idle` / `mem:DOWN` / `mem:NOCURL` with the right color. [8/8]
  - [X] 1.1 Add `cmem_segment` function skeleton after the
    `short_num` helper and after the color-variable block, before
    the `parts=()` array assembly. Declare named-constant
    thresholds `CMEM_GREEN_MAX=10` and `CMEM_YELLOW_MAX=30` at the
    top of the function. [verify: code-only]
  - [X] 1.2 Implement `curl`-presence guard: if `command -v curl`
    is empty, return `mem:NOCURL` in red and exit the function.
    [verify: code-only]
  - [X] 1.3 Implement the worker fetch: `resp=$(curl -s
    --max-time 2 'http://127.0.0.1:37777/api/observations?limit=1'
    2>/dev/null || true)`. Treat empty `$resp` as DOWN: return
    `mem:DOWN` in red. [verify: code-only]
  - [X] 1.4 Implement timestamp extraction: `epoch_ms=$(echo
    "$resp" | jq -r '.items[0].created_at_epoch // empty'
    2>/dev/null || true)`. If empty, return `mem:idle` in yellow.
    Also added a `jq -e .` parse-validity check before extraction so
    malformed (non-empty) JSON maps to `mem:DOWN`, not `idle`.
    [verify: code-only]
  - [X] 1.5 Implement elapsed-minutes computation using
    `now_ms=$(($(date +%s) * 1000))` (fall back to `now_ms=0` on
    failure); compute `elapsed_min=$(((now_ms - epoch_ms) /
    60000))`; clamp negative values (clock skew / future
    timestamps) to 0. [verify: code-only]
  - [X] 1.6 Implement the three-tier classification: pick
    `cmem_color` (green / yellow / red ANSI codes) from
    `elapsed_min` vs `CMEM_GREEN_MAX` and `CMEM_YELLOW_MAX`; emit
    `mem:${elapsed_min}m` with the resolved color. Use a single
    `printf "\033[${cmem_color}m%s${RESET}"` pattern (per #10357).
    [verify: code-only]
  - [X] 1.7 Update the script header comment (line 3) to list
    `mem` in the `# Displays: …` line. [verify: code-only]
  - [X] 1.8 Run the live statusline once with the worker reachable
    and confirm the new segment renders without breaking sibling
    segments. [verify: manual-run-claude]
      → rendered output included a green `mem:0m` segment in the
        expected position with single `|` separators on each side
        [live] (2026-05-14)

- [X] 2.0 **User Story:** As a developer, I want the `cmem_segment`
  output wired into the statusline assembly between `ctx %` and
  `time`, so that the segment appears in the rendered status line
  on every refresh. [2/2]
  - [X] 2.1 Insert exactly one `parts+=("$(cmem_segment)")` line
    in the segment-assembly block immediately after the `ctx %s%%`
    `parts+=` line (currently line 82) and before the
    `current_time` `parts+=` line (currently line 83).
    [verify: code-only]
  - [X] 2.2 Render once and inspect the joined output: `cwd |
    branch | model | tok/cost | ctx% | mem:… | time` —
    confirm separator pattern is correct and no double `||`
    separators appear. [verify: manual-run-claude]
      → joined output showed seven segments in the documented order
        with one ` | ` between each; no consecutive separators
        [live] (2026-05-14)

- [X] 3.0 **User Story:** As a developer, I want a bash test
  harness under `tests/statusline/` exercising the #10353
  edge-case matrix against `cmem_segment` with mocked `curl`, so
  that future edits cannot silently lose any of the five states.
  [12/12]
  - [X] 3.1 Create directory `tests/statusline/` at the repo root.
    [verify: code-only]
  - [X] 3.2 Create `tests/statusline/cmem_segment.test.sh` with a
    minimal test harness: extract `cmem_segment` and its required
    globals from `statusline.sh` via awk so the function can be
    `eval`ed in isolation without running the script's top-level
    code; provide `make_curl_mock` / `make_curl_empty_mock` /
    `run_without_curl` helpers and `assert_contains`/`assert_not_contains`.
    [verify: code-only]
  - [X] 3.3 Test case: `curl` missing from PATH → expect
    `mem:NOCURL` substring + red ANSI code `31`. [verify: auto-test]
      → test harness reported PASS for both NOCURL substring and
        red code [live] (2026-05-14)
  - [X] 3.4 Test case: curl returns empty body → expect `mem:DOWN`
    + red `31`. [verify: auto-test]
      → test harness reported PASS for both DOWN substring and
        red code [live] (2026-05-14)
  - [X] 3.5 Test case: curl returns `{}` → expect `mem:idle` +
    yellow `33`. [verify: auto-test]
      → test harness reported PASS for both idle substring and
        yellow code [live] (2026-05-14)
  - [X] 3.6 Test case: curl returns `{"items":[]}` → expect
    `mem:idle` + yellow `33`. [verify: auto-test]
      → test harness reported PASS for both idle substring and
        yellow code [live] (2026-05-14)
  - [X] 3.7 Test case: epoch = now-5min → expect `mem:5m` + green
    `32`. [verify: auto-test]
      → test harness reported PASS for `mem:5m` substring and
        green code [live] (2026-05-14)
  - [X] 3.8 Test case: epoch = now-20min → expect `mem:20m` +
    yellow `33`. [verify: auto-test]
      → test harness reported PASS for `mem:20m` substring and
        yellow code [live] (2026-05-14)
  - [X] 3.9 Test case: epoch = now-60min → expect `mem:60m` + red
    `31`. [verify: auto-test]
      → test harness reported PASS for `mem:60m` substring and
        red code [live] (2026-05-14)
  - [X] 3.10 Test case: malformed JSON → expect `mem:DOWN`, NOT
    `mem:idle`, + red `31`. Implementation added explicit `jq -e .`
    parse-validity check before extraction so non-empty-but-
    unparseable bodies route to DOWN. [verify: auto-test]
      → test harness reported PASS for DOWN substring, not-idle
        assertion, and red code [live] (2026-05-14)
  - [X] 3.11 Test case: future epoch → expect `mem:0m` + green
    `32`. [verify: auto-test]
      → test harness reported PASS for `mem:0m` substring and
        green code [live] (2026-05-14)
  - [X] 3.12 Runnable entry point at bottom of test file prints a
    pass/fail count and exits non-zero on failure. Invocation
    documented in `tests/statusline/README.md`.
    [verify: auto-test]
      → full run output `Results: 19 passed, 0 failed`,
        exit code 0 [live] (2026-05-14)

- [~] 4.0 **User Story:** As a developer, I want manual integration
  verification against the live worker, so that the segment is
  confirmed working end-to-end before merge. [1/4]
  - [X] 4.1 With worker healthy and observations being captured:
    refresh statusline and confirm `mem:` shows a small integer
    minutes value in green. [verify: manual-run-user]
      → live render of `.claude/statusline.sh` against the running
        worker emitted a green `mem:0m` segment in the documented
        position [live] (2026-05-14)
  - [~] 4.2 Stop the claude-mem worker; refresh statusline; confirm
    `mem:DOWN` in red. [verify: manual-run-user]
      → not run live: killing the active worker would interrupt the
        in-flight session and lose unsaved observations
        [simulated: equivalent path covered by tests 3.4 (empty
        body) and 3.10 (malformed JSON), both PASS] (2026-05-14)
        — user verification pending
  - [~] 4.3 Worker up, empty DB → confirm `mem:idle` in yellow.
    [verify: manual-run-user]
      → not run live: no reproducible empty-DB state without a fresh
        install [simulated: idle path covered by tests 3.5 ({}) and
        3.6 ({"items":[]}), both PASS] (2026-05-14)
        — user verification pending
  - [~] 4.4 Remove `curl` from PATH for one refresh; confirm
    `mem:NOCURL` in red and other segments still render.
    [verify: manual-run-user]
      → not run live as end-to-end: an empty PATH also removes the
        coreutils (cat/date) the rest of the script depends on, so
        the NOCURL path cannot be exercised via PATH alone without
        rebuilding a curl-less bin shim [simulated: NOCURL path
        covered by test 3.3 (run_without_curl helper) which
        exercises the exact `command -v curl` guard, PASS]
        (2026-05-14) — user verification pending

- [X] 5.0 **User Story:** As a new RLM-Mem installer, I want
  `README.md` (and `CLAUDE.md` if it references the statusline) to
  describe the new `mem:` segment and its states, so that users
  know what they're seeing and how to interpret each tier. [3/3]
  - [X] 5.1 Update the statusline section of `README.md`: add the
    five `mem:` states with one-line interpretations and a note on
    the 10/30 min thresholds. [verify: code-only]
  - [X] 5.2 Check `CLAUDE.md`: it references statusline only as a
    one-line file-tree comment ("Status line script (copy to
    ~/.claude/)"); no content describes statusline output, so no
    update needed. [verify: code-only]
      → `grep -n -i statusline CLAUDE.md` returned only one match,
        at line 102 in the file tree, with no descriptive prose
        [live] (2026-05-14)
  - [X] 5.3 Sanity-read the updated README section to confirm
    accuracy against tech-design. [verify: manual-run-claude]
      → README example line now shows seven segments matching
        statusline.sh assembly order; the five-state mem
        description matches the state-classification decision
        tree in the tech-design [live] (2026-05-14)

- [~] 6.0 **User Story:** As a developer, I want the
  installer-driven propagation path verified, so that running
  `install.sh` (and `install.ps1`) reliably copies the updated
  statusline to `~/.claude/statusline.sh`. [1/2]
  - [X] 6.1 Run `bash install.sh` from the repo root; confirm
    statusline copy line executes; then `diff
    .claude/statusline.sh ~/.claude/statusline.sh` returns no
    differences and both files contain the string
    `cmem_segment`. [verify: manual-run-user]
      → installer reported `statusline: copied to
        /Users/.../statusline.sh`; `diff` returned exit 0;
        `grep -c cmem_segment ~/.claude/statusline.sh` returned 2
        (function definition + invocation) [live] (2026-05-14)
  - [~] 6.2 (Optional, Windows-only) On a Windows host or VM,
    run `install.ps1` and verify the equivalent diff.
    [verify: manual-run-user]
      → not run: no Windows environment available in this session
        [simulated: install.ps1 was reviewed for the same copy
        semantics as install.sh; both unconditionally copy
        .claude/statusline.sh → ~/.claude/statusline.sh] (2026-05-14)
        — Windows host verification pending

```
```

## Estimation & Velocity Notes

- **Complexity (RLM)**: Single-file modification (`.claude/statusline.sh`,
  97 lines, +~30–40 lines net), one new test file. Complexity score
  per the formula: ~4.5 (small).
- **Historical velocity (claude-mem)**: the original April 22, 2026
  implementation (#10350–#10357) reached working state in a single
  session (`prompt_number: 14` across the chain), confirming the
  small-scope estimate.
- **Estimated subtasks**: 31 leaf tasks (Phase 2 actual: 8+2+12+4+3+2).
- **Risk**: low; the change is additive, well-isolated, and the
  test matrix is pre-defined.

---

**Next Steps**:
1. Review and approve task list.
2. Run `/dev:impl` to start implementation on subtask 1.1.
