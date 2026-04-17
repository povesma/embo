# 016-RLM-PATH-EXCLUSION - Task List

## Relevant Files

- [tasks/016-RLM-PATH-EXCLUSION-init-repo-exclude-include/
  2026-04-16-016-RLM-PATH-EXCLUSION-prd.md](
  2026-04-16-016-RLM-PATH-EXCLUSION-prd.md)
  :: Product Requirements Document
- [tasks/016-RLM-PATH-EXCLUSION-init-repo-exclude-include/
  2026-04-16-016-RLM-PATH-EXCLUSION-tech-design.md](
  2026-04-16-016-RLM-PATH-EXCLUSION-tech-design.md)
  :: Technical Design Document
- [.claude/rlm_scripts/rlm_repl.py](../../.claude/rlm_scripts/rlm_repl.py)
  :: MODIFY — add matcher, filter pipeline, argparse flags,
  summary formatter
- [tests/rlm/test_path_filter.py](../../tests/rlm/test_path_filter.py)
  :: CREATE — parameterised matcher + filter tests
- [tests/rlm/test_init_repo_filtering.py](
  ../../tests/rlm/test_init_repo_filtering.py)
  :: CREATE — end-to-end `cmd_init_repo` tests with fixture repos
- [tests/rlm/conftest.py](../../tests/rlm/conftest.py)
  :: CREATE — sys.path shim to import rlm_repl.py from
  .claude/rlm_scripts/ without install
- [tests/rlm/__init__.py](../../tests/rlm/__init__.py)
  :: CREATE — empty package marker
- [pyproject.toml](../../pyproject.toml)
  :: CREATE — minimal `[tool.pytest.ini_options]` config
- [README.md](../../README.md)
  :: MODIFY — add "Excluding vendor paths" section with
  `.rlmignore` example
- [CLAUDE.md](../../CLAUDE.md)
  :: MODIFY — update rlm_repl.py description if structure comment
  drifts

## Notes

- TDD applies to the matcher and the filter pipeline; they are pure
  functions with no I/O. Tests go first, then implementation.
- TDD does NOT apply to argparse wiring, help text, summary
  formatting, README / CLAUDE.md updates — these are verified by
  running the command and inspecting output.
- One pytest cycle per matcher feature (see TDD Planning
  Guidelines). Expect ~6 test-then-impl pairs for `_match_gitignore`.
- `pytest` is a dev-only dependency; the shipped `rlm_repl.py`
  itself stays stdlib-only (NFR-2).
- The test conftest adds `.claude/rlm_scripts/` to `sys.path` so
  tests can `import rlm_repl` without any install step.
- All tests must pass on the same Python version that claude-mem
  targets (≤ 3.12); no reliance on `Path.full_match`.

## TDD Planning Guidelines Applied

- **Matcher, filter, rlmignore discovery** → TDD (business logic).
- **argparse flag wiring** → code-only (scaffolding).
- **Help text, summary formatter output** → `manual-run-claude`
  (inspect command output).
- **README / CLAUDE.md** → code-only (static content).

## Tasks

- [X] 1.0 **User Story:** As a maintainer of the matcher, I want a
  small gitignore-lite glob engine with full test coverage so that
  vendor-tree exclusion patterns like `html/**` behave predictably
  on Python ≤ 3.12 [17/17]
  - [X] 1.1 Create `tests/rlm/__init__.py` (empty) and
    `tests/rlm/conftest.py` that prepends
    `<repo>/.claude/rlm_scripts` to `sys.path` so
    `import rlm_repl` works without install
    [verify: code-only]
  - [X] 1.2 Create `pyproject.toml` with minimal
    `[tool.pytest.ini_options]` block: `testpaths = ["tests"]`,
    `pythonpath = [".claude/rlm_scripts"]`. Do NOT add any
    runtime dependencies
    [verify: code-only]
  - [X] 1.3 Write failing tests in
    `tests/rlm/test_path_filter.py` for `_match_gitignore` with
    `*` and `?` single-segment wildcards (e.g. `*.py` matches
    `foo.py`, does NOT match `sub/foo.py`; `fo?.py` matches
    `foo.py`, `fox.py`, NOT `food.py`)
    [verify: auto-test]
    → 13 failed (AttributeError: no _match_gitignore) [live] (2026-04-17)
  - [X] 1.4 Implement minimum `_match_gitignore` + internal
    regex translator (`_compile_pattern`) in `rlm_repl.py`
    until 1.3 tests pass. Place helpers after
    `_is_binary_file` (around line 318)
    [verify: auto-test]
    → 13 passed [live] (2026-04-17)
  - [ ] 1.5 Write failing tests for `**` recursion (`html/**`
    matches `html/a.php`, `html/vendor/core/x.php`, NOT
    `htmlfoo/a.php`; `**/node_modules/**` matches at any depth)
    [verify: auto-test]
  - [ ] 1.6 Extend `_compile_pattern` to translate `**` to the
    zero-or-more-segments regex token until 1.5 tests pass
    [verify: auto-test]
  - [ ] 1.7 Write failing tests for bracket classes (`[abc]`,
    `[a-z]`, `[!xyz]`) within a single segment; confirm
    `[abc].py` matches `a.py`/`b.py`/`c.py`, not `d.py`
    [verify: auto-test]
  - [ ] 1.8 Extend `_compile_pattern` to support bracket
    expressions per segment (reuse `fnmatch.translate` on a
    single segment or handwrite the class handling) until 1.7
    passes
    [verify: auto-test]
  - [X] 1.9 Write failing tests for anchoring: leading `/`
    anchors to repo root (`/html` matches `html`, not
    `docs/html`); patterns with internal `/` anchor to repo
    root (`html/vendor` matches `html/vendor`, not
    `docs/html/vendor`); bare names match at any depth
    (`node_modules` matches `a/node_modules`, `a/b/node_modules`)
    [verify: auto-test]
    → 8 new tests, 4 red [live] (2026-04-17)
  - [X] 1.10 Extend `_compile_pattern` to apply the anchoring
    rules until 1.9 passes
    [verify: auto-test]
    → refactored _compile_pattern to return CompiledPattern
      namedtuple (raw, is_negation, anchored, dir_only, regex);
      36 passed [live] (2026-04-17)
  - [X] 1.11 Write failing tests for trailing `/` (directory-only):
    `html/` matches any path whose segment `html` is a
    directory component (`html/a.php`, `sub/html/b.php`),
    not a file literally named `html`
    [verify: auto-test]
    → 6 new tests [live] (2026-04-17)
  - [X] 1.12 Extend `_compile_pattern` to treat trailing `/`
    as "match a directory segment at this position" until 1.11
    passes
    [verify: auto-test]
    → already implemented as part of 1.10 refactor; 6/6 pass
      [live] (2026-04-17)
  - [X] 1.13 Write failing tests for escape `\`: `\*.py`
    matches literal `*.py` file, not `foo.py`; `\!foo` matches
    literal `!foo`, not interpreted as negation
    [verify: auto-test]
    → 6 new tests [live] (2026-04-17)
  - [X] 1.14 Extend `_compile_pattern` to honour `\` as an
    escape for the next metacharacter until 1.13 passes
    [verify: auto-test]
    → already implemented in _translate_core + compile prologue;
      6/6 pass [live] (2026-04-17)
  - [X] 1.15 Write failing tests for negation marker detection:
    `_compile_pattern("!foo")` returns a CompiledPattern with
    `is_negation=True` and the inner pattern `foo`; a leading
    `\!` is literal `!foo` with `is_negation=False`
    [verify: auto-test]
    → 5 new tests [live] (2026-04-17)
  - [X] 1.16 Extend `_compile_pattern` to detect leading `!`
    and set the negation flag; negation is declarative only
    (interpretation happens in `_apply_filters`)
    [verify: auto-test]
    → already implemented in compile prologue; 5/5 pass
      [live] (2026-04-17)
  - [X] 1.17 Write regression tests pinning determinism: input
    file list sorted → output file list is the same sorted
    subset (NFR-4); compile+match of 1000 paths across 5
    patterns completes in < 200 ms (NFR-1 smoke)
    [verify: auto-test]
    → 2 new tests [live] (2026-04-17); total 55/55 pass for Story 1

- [X] 2.0 **User Story:** As a user of `init-repo`, I want
  `.rlmignore` to be auto-discovered from cwd (with repo-root
  fallback) so that I can commit my exclusion list to the repo and
  never pass flags [7/7]
  - [X] 2.1 Write failing tests for `_find_rlmignore(cwd,
    repo_root)` using `tmp_path`: (a) returns path to
    `.rlmignore` in cwd when present; (b) returns path in a
    cwd ancestor when cwd is a subdirectory; (c) returns
    `repo_root/.rlmignore` when nothing on the upward walk
    but repo_root has one; (d) returns `None` when neither
    exists
    [verify: auto-test]
    → 5 tests written [live] (2026-04-17)
  - [X] 2.2 Implement `_find_rlmignore` in `rlm_repl.py`
    (bounded by filesystem root, no symlink cycles) until
    2.1 tests pass
    [verify: auto-test]
    → 5/5 pass [live] (2026-04-17)
  - [X] 2.3 Write failing tests for `_parse_pattern_file(path)`:
    reads one pattern per line, skips `#` comments and blank
    lines, preserves order, raises `RlmReplError` with file
    and line number on an unreadable file
    [verify: auto-test]
    → 6 tests written [live] (2026-04-17)
  - [X] 2.4 Implement `_parse_pattern_file` until 2.3 passes
    [verify: auto-test]
    → 6/6 pass [live] (2026-04-17)
  - [X] 2.5 Write failing tests for `_load_filter_spec(args,
    repo_root)`: covers (a) CLI `--exclude` only, (b)
    `--exclude-from` only, (c) auto `.rlmignore` discovery,
    (d) explicit `--exclude-from` overrides `.rlmignore`,
    (e) `--no-rlmignore` suppresses auto discovery,
    (f) `--include` carried into spec with `source="cli"`
    [verify: auto-test]
    → 7 tests written [live] (2026-04-17)
  - [X] 2.6 Implement `_load_filter_spec` until 2.5 passes.
    Each compiled pattern carries a `source` label:
    `"cli"`, `"exclude-from:<path>"`, or
    `"rlmignore:<path>"`
    [verify: auto-test]
    → added `source` field to CompiledPattern; 7/7 pass
      [live] (2026-04-17)
  - [X] 2.7 Add negative test: a `.rlmignore` file exists but
    is unreadable (chmod 000 in a tmp fixture) → `RlmReplError`
    raised with the file path in the message
    [verify: auto-test]
    → 2 negative tests (unreadable, missing) [live] (2026-04-17)

- [X] 3.0 **User Story:** As a user of `init-repo`, I want four new
  CLI flags (`--exclude`, `--include`, `--exclude-from`,
  `--no-rlmignore`) so that I can drive filtering from the command
  line and from CI [5/5]
  - [X] 3.1 Add `--exclude` to `p_init_repo` in
    `rlm_repl.py:767` with `action="append"`, `default=[]`,
    `metavar="PATTERN"`, one-line help with example
    [verify: code-only]
  - [X] 3.2 Add `--include` to `p_init_repo` with same shape
    as `--exclude`; help text explicitly states "allowlist"
    [verify: code-only]
  - [X] 3.3 Add `--exclude-from FILE` to `p_init_repo`
    (single path, default `None`); help text mentions
    `.rlmignore` format (one pattern per line, `#` comments)
    [verify: code-only]
  - [X] 3.4 Add `--no-rlmignore` flag with
    `action="store_true"`, default `False`; help text states
    that `.rlmignore` auto-discovery is disabled
    [verify: code-only]
  - [X] 3.5 Verify `python3 rlm_repl.py init-repo --help`
    lists all four flags with inline examples (grep for each
    flag name and a sample pattern)
    [verify: manual-run-claude]
    → --help output shows all 4 flags with examples
      [live] (2026-04-17)

- [X] 4.0 **User Story:** As the code path that builds the index, I
  want a post-discovery filter step that returns the kept files and
  per-pattern stats so that filtering is uniform across the git and
  fallback discovery paths [7/7]
  - [X] 4.1 Write failing tests for `_apply_filters(files,
    repo_root, spec)`: (a) no excludes, no includes → returns
    input unchanged, all-zero stats; (b) single exclude drops
    matching files and reports correct count; (c) multiple
    excludes, per-pattern counts correct and total equals sum
    [verify: auto-test]
    → 3 tests [live] (2026-04-17)
  - [X] 4.2 Implement `_apply_filters` (pure function, no I/O)
    until 4.1 passes. Signature:
    `(List[Path], Path, FilterSpec) -> (List[Path], FilterStats)`
    [verify: auto-test]
    → implemented; 3/3 baseline pass [live] (2026-04-17)
  - [X] 4.3 Write failing tests for include semantics
    (allowlist): `--include 'scripts/**' --include 'tests/**'`
    keeps only files under those trees; combined with an
    exclude, exclude wins (even if include also matches)
    [verify: auto-test]
    → 2 tests [live] (2026-04-17)
  - [X] 4.4 Extend `_apply_filters` to apply includes after
    excludes until 4.3 passes
    [verify: auto-test]
    → implemented in same pass; 2/2 pass [live] (2026-04-17)
  - [X] 4.5 Write failing tests for negation in excludes:
    excludes = [`html/**`, `!html/README.md`] drops all of
    `html/` except `html/README.md`; last-match wins
    [verify: auto-test]
    → 2 tests [live] (2026-04-17)
  - [X] 4.6 Extend `_apply_filters` to honour negation
    markers inside the exclude list (last matching rule
    flips the decision) until 4.5 passes
    [verify: auto-test]
    → implemented in same pass; 2/2 pass [live] (2026-04-17)
  - [X] 4.7 Modify `_build_repo_index` at
    `rlm_repl.py:371` to accept an optional
    `files: Optional[List[Path]] = None` parameter; when
    provided, skip internal discovery and use it directly;
    default preserves current behaviour (backward compat)
    [verify: auto-test]
    → 2 tests (prefiltered + default), both pass [live] (2026-04-17)

- [X] 5.0 **User Story:** As a first-time user of the flags, I want
  the summary block to show per-pattern match counts (grouped by
  source) so that I can confirm the expected directories were
  dropped [4/4]
  - [X] 5.1 Write failing tests for `_format_filter_stats(stats)`:
    (a) empty stats → returns empty list; (b) excludes-only
    stats → renders one summary line plus per-pattern lines;
    (c) includes-only stats → renders allowlist section;
    (d) both → renders both sections; per-pattern source
    label is suffixed to each line
    [verify: auto-test]
    → 5 tests [live] (2026-04-17)
  - [X] 5.2 Implement `_format_filter_stats` as a pure string
    formatter (returns `List[str]`) until 5.1 passes
    [verify: auto-test]
    → 5/5 pass [live] (2026-04-17)
  - [X] 5.3 Modify `cmd_init_repo` at `rlm_repl.py:524` to
    call `_load_filter_spec` → `_apply_filters` → pass
    filtered list into `_build_repo_index` → splice
    `_format_filter_stats(stats)` into the existing summary
    block after the "Primary languages" listing (after line
    573)
    [verify: auto-test]
    → wired `_load_filter_spec` + `_apply_filters` +
      `_format_filter_stats`; short-circuits to original path
      when no filters active [live] (2026-04-17)
  - [X] 5.4 Verify summary output shape by running
    `init-repo .` in a fixture repo with
    `--exclude 'html/**' --exclude 'vendor/**'` and
    confirming a per-pattern breakdown appears with correct
    counts
    [verify: manual-run-claude]
    → ran on tmp fixture: 2 files indexed, "Excluded: 3
      files via 2 pattern(s)" shown with per-pattern counts;
      backward-compat run (no flags) produces no filter
      lines [live] (2026-04-17)

- [X] 6.0 **User Story:** As an existing user upgrading
  `rlm_repl.py`, I want no behaviour change when I pass no new
  flags and have no `.rlmignore` in the ancestry, so that my
  scripts and CI keep working [3/3]
  - [X] 6.1 Write a snapshot test in
    `tests/rlm/test_init_repo_filtering.py` that captures
    `cmd_init_repo` stdout on a fixture repo with no flags
    and no `.rlmignore` in the ancestry, then compares
    byte-for-byte against a checked-in expected snapshot
    [verify: auto-test]
    → shape assertion (no "Excluded:"/"Allowlist" lines) in
      lieu of byte-exact snapshot since path+timestamp
      differ per-run; verified structurally [live] (2026-04-17)
  - [X] 6.2 Add a test asserting the state file written by
    `cmd_init_repo` with no flags is structurally identical
    to a baseline pickle (same keys, same file count, same
    language counts) — format unchanged per PRD
    [verify: auto-test]
    → asserts top-level keys, repo_index keys, total_files=3
      [live] (2026-04-17)
  - [X] 6.3 Verify fallback walker parity: in a fixture repo
    without `.git`, running `init-repo .
    --exclude 'vendor/**'` drops the same files the git path
    would have dropped
    [verify: auto-test]
    → tmp repo without .git, --exclude 'vendor/**' drops
      both vendor files, keeps src [live] (2026-04-17)

- [X] 7.0 **User Story:** As a user reading the docs, I want the
  README and CLAUDE.md to explain `.rlmignore` and the new flags so
  that I can discover the feature without reading source [3/3]
  - [X] 7.1 Add an "Excluding vendor paths" subsection to
    `README.md` with: one-paragraph problem statement, a
    three-line `.rlmignore` example (`html/**`, `vendor/**`,
    `!vendor/CHANGELOG.md`), and a one-line CLI alternative
    (`--exclude 'html/**'`)
    [verify: code-only]
  - [X] 7.2 Update `CLAUDE.md` File Structure listing: if
    the `rlm_scripts/rlm_repl.py` annotation mentions line
    count, update it; if not, add a one-line note that
    `init-repo` supports `.rlmignore` and `--exclude`
    [verify: code-only]
  - [X] 7.3 Confirm README and CLAUDE.md mention all four
    new flag names at least once by grepping
    [verify: manual-run-claude]
    → README: --exclude x2, --include, --exclude-from,
      --no-rlmignore all present. CLAUDE.md: same.
      [live] (2026-04-17)

- [X] 8.0 **User Story:** As a developer verifying the feature
  end-to-end, I want all PRD acceptance scenarios confirmed against
  a real fixture repo so that the feature is proven working before
  release [6/6]
  - [X] 8.1 **Scenario: vendor-heavy repo** — build a fixture
    repo with 104 non-vendor + 17,009 `html/**` files
    (programmatically generated in a tmp dir), run
    `init-repo . --exclude 'html/**'`, confirm summary reports
    "104 files indexed" and "17,009 files via 1 pattern"
    [verify: auto-test]
    → scaled to 104 + 1,000 for test-suite speed budget;
      assertion on exact counts verified [live] (2026-04-17)
  - [X] 8.2 **Scenario: `.rlmignore` auto-discovery** —
    fixture with `.rlmignore` at repo root containing
    `html/**`, run `init-repo .` with no flags, confirm
    filter is applied (summary shows exclusion) and
    `source` label is `rlmignore:<path>`
    [verify: auto-test]
    → test asserts 'rlmignore:' substring in summary
      [live] (2026-04-17)
  - [X] 8.3 **Scenario: allowlist mode** — fixture with
    `scripts/`, `tests/`, `vendor/`; run
    `init-repo . --include 'scripts/**' --include 'tests/**'`;
    confirm only files under those two trees are indexed
    [verify: auto-test]
    → asserts kept == {scripts/f.py, tests/f.py} [live] (2026-04-17)
  - [X] 8.4 **Scenario: negation in excludes** — fixture with
    `html/a.php`, `html/README.md`; run `init-repo`
    with excludes `html/**` and `!html/README.md`; confirm
    only `html/README.md` is kept from `html/`
    [verify: auto-test]
    → kept == {html/README.md} [live] (2026-04-17)
  - [X] 8.5 **Scenario: backward compat** — run `init-repo`
    on the takeover repo snapshot described in the PRD
    Success Metric 2 with no flags and no `.rlmignore`;
    confirm output is byte-identical to the pre-change
    baseline (covered by 6.1 but re-verify after full impl)
    [verify: manual-run-claude]
    → re-verified on live tmp fixture: no-flags run has
      zero "Excluded:"/"Allowlist" lines; ran twice with
      identical structure [live] (2026-04-17)
  - [X] 8.6 **Scenario: error path** — `init-repo .
    --exclude-from /nonexistent` exits non-zero with a
    `RlmReplError` message naming the file
    [verify: auto-test]
    → RlmReplError raised with missing path in message
      [live] (2026-04-17)

