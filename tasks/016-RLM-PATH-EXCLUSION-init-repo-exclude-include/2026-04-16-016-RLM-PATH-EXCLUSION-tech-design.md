# 016-RLM-PATH-EXCLUSION: `init-repo` Path Filtering — Technical Design

**Status**: Draft
**PRD**: [2026-04-16-016-RLM-PATH-EXCLUSION-prd.md](2026-04-16-016-RLM-PATH-EXCLUSION-prd.md)
**Created**: 2026-04-16
**Target file**: `.claude/rlm_scripts/rlm_repl.py`

---

## Overview

Add a dependency-free path filter between file discovery and index
building in `init-repo`. Filtering uses a small gitignore-lite matcher
implemented in-module, wired via two new helpers (`_match_gitignore`,
`_apply_filters`) and four new `argparse` flags on the `init-repo`
subparser. Stats per pattern are returned as a plain dict and rendered
in the existing summary block. Both the git-aware and fallback
discovery paths feed the same filter. State-file format is unchanged.

## Current Architecture (RLM-verified)

**Relevant module**: `.claude/rlm_scripts/rlm_repl.py` (single file, stdlib only, ~820 lines).

**Conventions observed**:
- Private helpers are module-level `_snake_case` functions
  (e.g., `_discover_git_files`, `_discover_files_fallback`,
  `_build_repo_index`, `_detect_language`, `_is_binary_file`).
- No classes for data pipelines. `RlmReplError` is the only class.
- Command handlers are `cmd_<verb>` functions wired by `build_parser()`.
- Error surface: raise `RlmReplError` with a human-readable message;
  `main()` catches and prints to stderr, exits non-zero.
- Summary print is plain `print()` in `cmd_init_repo`
  (lines 558–578). No logger.

**Relevant call path today**:
```
cmd_init_repo
  └─ _build_repo_index
       └─ _discover_git_files
            └─ _discover_files_fallback  (on git failure)
```
Discovery returns `List[Path]`; `_build_repo_index` stats each and
populates `index['files']`, `index['languages']`.

## Proposed Design

### New call path

```
cmd_init_repo
  ├─ _load_filter_spec            (new) — reads CLI + --exclude-from + .rlmignore
  ├─ discovery (unchanged)
  ├─ _apply_filters               (new) — returns (kept_files, filter_stats)
  ├─ _build_repo_index(files=kept) (signature gains optional pre-discovered list)
  └─ prints summary incl. _format_filter_stats(filter_stats)
```

Rationale:
- Filtering sits **after** discovery so both git and fallback paths are
  covered without duplication, and `_build_repo_index` gains a trivial
  signature tweak (`files: Optional[List[Path]] = None` — when provided,
  skip internal discovery).
- `filter_spec` is a read-only dict; `filter_stats` is a write-once dict
  produced by `_apply_filters`. Neither is persisted.

### Components (all free functions, matching module style)

1. **`_match_gitignore(rel_path: str, pattern: str) -> bool`**
   - Pure function. No I/O, no state.
   - Converts a gitignore-dialect pattern to a regex **once per call**
     (callers should cache in a small LRU-style dict when iterating,
     see `_compile_pattern`). Wildcards supported:
     - `**` → zero or more full path segments
     - `*`  → any chars within a single segment (no `/`)
     - `?`  → any single char within a segment
     - `[abc]` / `[a-z]` → character class (reuse `fnmatch.translate`
       for bracket expressions; we call it per segment)
     - `!pattern` → negation (returns a *negation marker*, handled by
       the caller — see "Precedence" below)
     - Trailing `/` → directory-only semantics; since our file list
       never contains directory entries, a trailing `/` pattern matches
       any file whose path contains a matching directory segment.
     - Leading `/` → anchored to repo root (no cross-depth match).
     - Pattern without `/` (bare name) → match at any depth.
     - Pattern with `/` but no leading `/` → anchored to repo root.
     - `\` escapes next wildcard character.
   - Returns `True` / `False`. Negation is a property of the pattern
     text, not the return value; the matcher reports "pattern matched",
     and `_apply_filters` interprets the leading `!` to flip the
     decision.

2. **`_compile_pattern(pattern: str) -> CompiledPattern`**
   - Dataclass-free tuple wrapper: `(is_negation: bool, anchored: bool,
     dir_only: bool, regex: re.Pattern)`.
   - Built once per pattern during `_load_filter_spec`, reused for
     every file. Keeps filtering O(files × patterns) with a cheap
     per-check `regex.fullmatch` on the normalised relative path.

3. **`_load_filter_spec(args, repo_root) -> FilterSpec`**
   - Assembles the filter inputs:
     - `excludes = args.exclude + from_file(args.exclude_from)` *or*
       `args.exclude + from_file(_find_rlmignore(cwd, repo_root))`
       when `args.exclude_from` is `None` and `--no-rlmignore` is
       `False`.
     - `includes = args.include`.
   - Each pattern carries its **source** (`"cli"`, `"exclude-from:<path>"`,
     `"rlmignore:<path>"`) so the summary can show where it came from.
   - Compiles patterns eagerly; raises `RlmReplError` with file+line
     on an unreadable `--exclude-from` or malformed pattern (NFR-5).

4. **`_find_rlmignore(cwd: Path, repo_root: Path) -> Optional[Path]`**
   - Walk up from `cwd`, returning the first `.rlmignore` found, or
     `None`. If none found on the walk, also check `repo_root /
     ".rlmignore"`. Returns `None` if neither exists.
   - Two-step order chosen to handle "run from subdirectory" and "run
     from outside repo" cleanly without surprising the user.

5. **`_apply_filters(files: List[Path], repo_root: Path, spec: FilterSpec)
    -> Tuple[List[Path], FilterStats]`**
   - Iterates files once. For each file:
     1. Compute `rel = file.relative_to(repo_root).as_posix()`.
     2. Walk `spec.excludes` in order. If a non-negation pattern matches,
        mark `excluded = True`. If a negation pattern matches later,
        flip back to `excluded = False`. (Gitignore-style last-match,
        scoped to excludes only.)
     3. If `spec.includes` is non-empty, a file must match at least one
        include to be kept. Excludes still win (negation inside includes
        is not supported — keeps semantics simple).
     4. Record a match count per-pattern in `stats`.
   - Returns the filtered list + stats dict.

6. **`_format_filter_stats(stats) -> List[str]`**
   - Pure string formatter for `cmd_init_repo` to splice into the
     summary block. No I/O.

### Data contracts

```python
FilterSpec = Dict[str, Any]
# {
#   "excludes": [CompiledPattern, ...],  # in input order
#   "includes": [CompiledPattern, ...],
# }

CompiledPattern = Tuple[str, str, bool, bool, bool, re.Pattern]
# (raw_pattern, source, is_negation, anchored, dir_only, regex)

FilterStats = Dict[str, Any]
# {
#   "excluded_total": int,
#   "per_exclude": [ (raw_pattern, source, count), ... ],
#   "included_total": int,          # 0 if no includes given
#   "per_include":  [ (raw_pattern, source, count), ... ],
# }
```

### Matcher semantics (precedence summary)

| Situation                                      | Result                  |
|-----------------------------------------------|-------------------------|
| No includes, no matching exclude              | Keep                    |
| No includes, matches exclude, no later `!`    | Drop                    |
| No includes, matches exclude then `!rule`     | Keep                    |
| Includes present, no include matches          | Drop                    |
| Includes present, include matches, no exclude | Keep                    |
| Includes present, both match                  | Drop (exclude wins)     |

Matching `!rule` inside the **includes** list is not interpreted; a
leading `!` in an include pattern is treated as a literal character
(document this in `--help`).

### Argparse additions (`p_init_repo`, lines 767–781)

```python
p_init_repo.add_argument(
    "--exclude",
    action="append",
    default=[],
    metavar="PATTERN",
    help="Gitignore-style pattern to exclude (repeatable). "
         "Example: --exclude 'html/**'",
)
p_init_repo.add_argument(
    "--include",
    action="append",
    default=[],
    metavar="PATTERN",
    help="Gitignore-style allowlist pattern (repeatable). "
         "When given, only matching files are kept.",
)
p_init_repo.add_argument(
    "--exclude-from",
    metavar="FILE",
    help="Read exclude patterns from file (one per line, # for comments).",
)
p_init_repo.add_argument(
    "--no-rlmignore",
    action="store_true",
    help="Disable automatic discovery of .rlmignore.",
)
```

### Summary block additions (after line 573)

```python
stats_lines = _format_filter_stats(filter_stats)
for line in stats_lines:
    print(line)
```

`_format_filter_stats` returns nothing when neither excludes nor
includes are active (preserves current output byte-for-byte for NFR
backward compat).

### Backward-compatibility guarantee

- No flags + no `.rlmignore` in cwd's ancestry + no `.rlmignore` at
  repo root → `_load_filter_spec` returns an empty `FilterSpec`;
  `_apply_filters` short-circuits and returns `(files, None)`;
  `_format_filter_stats(None)` returns `[]`. Control flow past
  `_build_repo_index` is untouched.
- Snapshot test (see Verification below) pins this.

### Error handling

Aligns with existing `RlmReplError` convention:

| Condition                                  | Behaviour                                   |
|-------------------------------------------|---------------------------------------------|
| `--exclude-from` points at missing file   | Raise `RlmReplError("exclude-from file not found: {path}")` |
| `--exclude-from` file is unreadable       | Raise `RlmReplError("cannot read exclude-from file: {path}: {e}")` |
| Malformed pattern (empty after `!`/escape)| Raise `RlmReplError("invalid pattern in {source} line {lineno}: {raw}")` |
| `.rlmignore` exists but unreadable        | Raise `RlmReplError("cannot read .rlmignore at {path}: {e}")` |
| Regex compilation fails internally         | Raise `RlmReplError("internal pattern compile failure for {raw}")` — indicates a matcher bug |

Exit code: non-zero (already the default for `RlmReplError` in `main()`).

### Performance

- Per-file check: one `regex.fullmatch` per pattern per file.
  For 17,113 files × ~5 patterns = ~86k regex matches; expected
  ≪ 100 ms on modern hardware.
- No I/O in the hot path (pre-computed rel path strings; no
  `Path.is_file()` re-check — discovery already vetted that).
- Pattern compilation happens once per run, up front.

## Trade-offs & Rejected Alternatives

1. **`pathlib.PurePath.match`** — rejected in PRD scoping because
   `**` is not recursive on Python ≤ 3.12, and `Path.full_match`
   (3.13+) is incompatible with claude-mem's Python version pin.

2. **`fnmatch.fnmatch` alone** — rejected: no `**` recursion. Would
   force users to write `html/*`, `html/*/*`, `html/*/*/*` … which
   defeats the vendor-exclusion use case.

3. **Third-party `pathspec`** — rejected: violates NFR-2 (stdlib
   only). Would add a real dependency to a file that has none.

4. **Class-based `PathFilter`** — rejected in scoping question:
   free functions match the rest of the module; no state to bundle.

5. **Filter inside discovery** — rejected: would duplicate filter
   logic into both `_discover_git_files` and `_discover_files_fallback`,
   or force passing stats via a global. Post-discovery is cleaner.

6. **Persist filter stats to state.pkl** — rejected: changes the
   state format; PRD explicitly keeps state unchanged.

7. **Full gitignore compatibility (all edge cases, e.g. `/**/`
   collapsing rules, `**/` with trailing-slash interactions, octothorpe
   handling mid-line)** — rejected: we advertise "gitignore-lite".
   Documented subset only.

## Files to Create / Modify

**Modify**:
- `.claude/rlm_scripts/rlm_repl.py`
  - ~line 371 (`_build_repo_index`): accept optional pre-filtered
    `files` parameter; default preserves current behaviour.
  - ~line 524 (`cmd_init_repo`): call `_load_filter_spec` →
    `_apply_filters` → pass to `_build_repo_index` → splice formatted
    stats lines into summary.
  - Insert new helpers (`_match_gitignore`, `_compile_pattern`,
    `_load_filter_spec`, `_find_rlmignore`, `_apply_filters`,
    `_format_filter_stats`) above `_discover_git_files` or grouped
    after the existing discovery helpers — developer choice during
    implementation; tasks file will pick one.
  - ~line 767 (`p_init_repo`): add the four new arguments shown above.

**Create**:
- `tests/rlm/test_path_filter.py` — pytest parameterised matcher
  tests (see Verification).
- `tests/rlm/__init__.py` — empty.
- `tests/rlm/fixtures/snapshot_repo/.gitkeep` — minimal fixture for
  the end-to-end snapshot.
- `tests/rlm/conftest.py` — sys.path shim to import `rlm_repl.py`
  from the tracked `.claude/rlm_scripts/` without install.
- `pyproject.toml` *(if not already present)* — minimal
  `[tool.pytest.ini_options]` with `testpaths = ["tests"]`. If a
  project already pins pytest config elsewhere, extend that instead.
  (The repo currently has no Python tests; confirm during impl.)

**Documentation updates** (per FR-8):
- `README.md` — add "Excluding vendor paths" section with a
  one-paragraph example and a three-line `.rlmignore`.
- `CLAUDE.md` — update the `rlm_scripts/rlm_repl.py` line-count
  comment if it drifts meaningfully.

## Dependencies

**External**: none (NFR-2).
**Internal**: `re`, `argparse`, `pathlib`, `fnmatch` (already imported
or easy to add — `fnmatch` is stdlib and used only for bracket
expressions inside `_match_gitignore`).
**Test-time**: `pytest` (already assumed present per the test-backend
agent's conventions; install if missing — does not ship with the
package).

## Verification Approach

Maps each functional requirement to its verification method. Feeds
directly into `/dev:test-plan`.

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1 CLI flags accepted, repeatable | `auto-test` | unit | `argparse.parse_args` exposes `args.exclude`, `args.include`, `args.exclude_from`, `args.no_rlmignore` with correct types/defaults |
| FR-2 gitignore-lite semantics | `auto-test` | unit | `test_path_filter.py` parametrised table covers: `**`, `*`, `?`, `[a-z]`, leading `/`, trailing `/`, bare-name any-depth, `path/with/slash` root-anchored, `!negation`, `\` escape |
| FR-3 `.rlmignore` discovery (cwd walk → repo root fallback → `--no-rlmignore` override → explicit `--exclude-from` override) | `auto-test` | unit | tmp_path fixtures build each layout; `_find_rlmignore` returns the right file or `None` |
| FR-4 filter applied post-discovery | `auto-test` | integration | monkeypatch `_discover_git_files` to return a fixed list; assert kept set equals spec |
| FR-5 fallback walker parity | `auto-test` | integration | force git to fail (delete `.git`); assert identical filtered output as the git path |
| FR-6 per-pattern stats | `auto-test` | unit | `_apply_filters` returns per-pattern counts equal to the number of matched files for each pattern |
| FR-7 `--help` text | `code-only` | — | `--help` output contains the four new flag names and one-line examples |
| FR-8 README / CLAUDE.md updates | `code-only` | — | grep confirms new section exists with `.rlmignore` example |
| NFR-1 performance | `manual-run-claude` | smoke | time `init-repo .` on a seeded 17k-file fixture; < 1 s total |
| NFR-2 stdlib-only | `code-only` | — | no new `import` of non-stdlib packages |
| NFR-3 Python ≤ 3.12 compat | `code-only` | — | no `Path.full_match` use; `re` + stdlib only |
| NFR-4 determinism | `auto-test` | unit | sorted order preserved after filtering (input-sorted list → output sorted) |
| NFR-5 safety on bad inputs | `auto-test` | unit | each error row in the "Error handling" table raises `RlmReplError` with expected substring |
| Backward compat (Story 6) | `auto-test` + `manual-run-user` | integration | snapshot test: stdout of `init-repo .` on fixture with no flags and no `.rlmignore` is byte-identical before/after |
| Story 1 (17k → 104 indexed) | `manual-run-claude` | e2e | seed fixture with `html/**` containing N files; run `--exclude 'html/**'`; assert summary count = expected |

Methods map: `code-only` | `auto-test` | `manual-run-claude` |
`manual-run-user` | `docker` | `e2e` | `observation`.

## Security Considerations

- `_load_filter_spec` reads files from paths supplied by the user
  (`--exclude-from`, `.rlmignore`). Use `Path.resolve()` and read
  via stdlib `open()`; do not evaluate their contents as code.
  Patterns go through `re.escape` for literal segments so no regex
  injection is possible from user input.
- No network, no subprocess beyond the existing `git ls-files` calls.
- `.rlmignore` walk-up bounded by the filesystem root; no symlink
  cycles because we only call `Path.parent` on absolute paths.

## Performance Considerations

Already captured above. Main guard rail: compile each pattern once;
avoid per-file string normalisation cost by calling `.as_posix()`
once per file and caching.

## Rollback Plan

Single-file change. Revert the commit that touches
`.claude/rlm_scripts/rlm_repl.py` and delete `tests/rlm/`. No state
migration is needed because `state.pkl` format is unchanged.

## Constraints Carried from PRD

- NFR-2 stdlib-only → no `pathspec`, no `gitignore-parser`.
- NFR-3 Python ≤ 3.12 compat → no `Path.full_match`.
- State-file format unchanged → filter stats are print-only.
- Backward compat → no-flag invocations produce byte-identical output.

## PRD Deltas (update the PRD after this design is approved)

1. **Negation (`!pattern`) was moved from Out of Scope into
   FR-2 scope** — limited to the exclude list only; includes do not
   interpret `!`.
2. **`.rlmignore` discovery clarified** — walk up from cwd; if none
   found, check `repo_root / ".rlmignore"`. Update Story 2 AC and
   FR-3 to reflect the two-step search.
3. **`_build_repo_index` signature gains** an optional pre-filtered
   `files` parameter. Internal refactor only, but worth noting in
   the "Technical Constraints" section.

---

## Next Steps

1. Review and approve this technical design.
2. Apply the three PRD deltas above (small edit).
3. Run `/dev:tasks` to produce the implementation + verification
   task list, driven by the Verification table.
