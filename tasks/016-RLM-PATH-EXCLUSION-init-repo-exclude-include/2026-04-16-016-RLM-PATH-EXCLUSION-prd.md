# 016-RLM-PATH-EXCLUSION: `init-repo` Path Exclusion & Inclusion — PRD

**Status**: Draft
**Created**: 2026-04-16
**Author**: Claude (via dev workflow analysis)
**Target file**: `.claude/rlm_scripts/rlm_repl.py`

---

## Introduction / Overview

`rlm_repl.py init-repo` discovers files via `git ls-files` (and falls back
to a manual walk when git is unavailable). In mixed repositories where
vendored or generated third-party trees are committed on purpose — e.g. a
Drupal/Opigno takeover where 17,009 of 17,113 tracked files are a vendored
CMS — the vendor portion dwarfs the project's own code. `.gitignore` is not
a solution because those files must stay tracked. The result is:

- Wasted indexing time on files the user will never analyse.
- Bloated `repo_index` (and `state.pkl`) making `grep`/search noisier.
- Inflated language statistics that mis-represent the "real" codebase.

This feature adds opt-in path filtering to `init-repo` so users can exclude
vendor/generated trees (and optionally restrict indexing to an allowlist)
without changing `.gitignore`. It is strictly additive: with no new flags
and no `.rlmignore` file, behaviour is identical to today.

---

## Objectives & Success Metrics

**Objectives**:

1. Allow excluding paths by glob pattern from CLI and from a config file.
2. Allow optionally restricting indexing to an allowlist of glob patterns.
3. Surface what was filtered, per pattern, so the user can verify.
4. Keep the change small, dependency-free, and backward compatible.
5. Apply uniformly to both git-aware discovery and the fallback walker.

**Success metrics**:

- Running `init-repo` with `--exclude 'html/**' --exclude 'vendor/**'` on
  the takeover repo drops the indexed count from ~17,113 to ~104 and
  completes in roughly the same wall-clock time as the current code on
  the remaining files.
- A repo with `.rlmignore` at root (discovered by walking up from cwd)
  auto-applies its patterns with no extra flags.
- `--include 'scripts/**' --include 'tests/**'` alone yields only files
  under those trees, regardless of what else is tracked.
- The summary block prints a per-pattern breakdown so a first-time user
  can confirm the expected directories were dropped.
- Running `init-repo` without any of the new flags, and without a
  `.rlmignore` anywhere up the tree, produces byte-identical output to
  the current code path.

---

## User Personas & Use Cases

**Takeover maintainer** — inherits a project that vendored a CMS/framework
into the repo. Wants RLM to analyse *their* scripts, tests, and terraform
without the vendor noise. Writes a two-line `.rlmignore` and stops
thinking about it.

**Polyglot monorepo developer** — has `apps/`, `libs/`, and `packages/`
where only a couple of trees are interesting for the current task. Uses
`--include 'apps/web/**' --include 'libs/shared/**'` ad hoc.

**Generated-artefact sufferer** — checks in `dist/`, `build/`, or
`generated/` per company policy. Uses `--exclude 'dist/**'` to keep the
index focused on source.

**CI / automation script** — runs `init-repo` headlessly and needs
deterministic, flag-driven behaviour with no interactive discovery.

---

## User Stories

### Epic

As a developer working on a repo with committed vendor or generated code,
I want `init-repo` to skip those paths, so RLM indexes only what I care
about, and every downstream query is faster and quieter.

### Story 1 — CLI exclusion

**As a** developer with vendored code in `html/`
**I want** to pass `--exclude 'html/**'` to `init-repo`
**So that** 17k vendor files are not indexed

**Acceptance Criteria**:
- [ ] `--exclude PATTERN` is accepted by `init-repo` and is repeatable.
- [ ] A gitignore-style matcher interprets the pattern; `html/**` matches
      any file at any depth under `html/`.
- [ ] Files matching any exclude pattern are removed from the file list
      before `_build_repo_index` stats them.
- [ ] With no `--exclude` flag present and no `.rlmignore` discovered,
      the indexed file set is identical to current behaviour.

### Story 2 — Exclude-from file / `.rlmignore`

**As a** developer who doesn't want to re-type the same flags
**I want** `init-repo` to read patterns from a file
**So that** the exclusion list lives in version control next to my code

**Acceptance Criteria**:
- [ ] `--exclude-from FILE` reads one pattern per line; lines beginning
      with `#` and blank lines are ignored.
- [ ] If no `--exclude-from` is given, `init-repo` walks upward from
      `cwd` looking for a file named `.rlmignore`, stopping at the first
      hit or at the filesystem root. If nothing is found on the upward
      walk, it then checks `repo_root/.rlmignore` as a fallback.
- [ ] A discovered `.rlmignore` is loaded silently unless
      `--no-rlmignore` is passed, which suppresses auto-discovery.
- [ ] Explicit `--exclude-from` wins over auto-discovered `.rlmignore`:
      only the explicit file is used. Patterns from `--exclude` on the
      command line are unioned with whichever file is chosen.

### Story 3 — Inclusion allowlist

**As a** developer who wants to index only a few trees
**I want** `--include PATTERN` as an allowlist
**So that** I don't have to list every vendor/generated directory

**Acceptance Criteria**:
- [ ] `--include PATTERN` is accepted by `init-repo` and is repeatable.
- [ ] When at least one `--include` is present, a file is kept only if
      it matches at least one include pattern **and** no exclude pattern.
- [ ] With no `--include` present, the allowlist is treated as "match
      everything" (current behaviour).

### Story 4 — Fallback walker parity

**As a** user initialising a non-git directory
**I want** the same `--exclude` / `--include` behaviour
**So that** the flag set is consistent regardless of git presence

**Acceptance Criteria**:
- [ ] When `_discover_git_files` falls back to `_discover_files_fallback`,
      the exclude/include filter is applied to the fallback result.
- [ ] The fallback walker's existing hardcoded `skip_dirs` is preserved
      (venv/node_modules/etc. still skipped), and the new patterns
      filter on top of that set.

### Story 5 — Visibility in summary

**As a** first-time user of the flag
**I want** the summary to show what was excluded, per pattern
**So that** I can confirm the expected directories were dropped, and
spot accidental over-exclusion

**Acceptance Criteria**:
- [ ] The summary block (after the "Primary languages" listing) prints
      a section like:
      ```
      - Excluded: 17,009 files via 2 patterns
        • html/** : 17,009 files
        • vendor/** : 0 files
      ```
- [ ] If no patterns are active, the section is omitted entirely (no
      "Excluded: 0 files" line, to keep existing output stable).
- [ ] Include patterns, if any, are reported similarly:
      ```
      - Included (allowlist): 2 patterns, kept 104 files
        • scripts/** : 40 files
        • tests/** : 64 files
      ```

### Story 6 — Backward compatibility

**As an** existing user upgrading `rlm_repl.py`
**I want** no behaviour change unless I opt in
**So that** my existing scripts, CI, and muscle memory keep working

**Acceptance Criteria**:
- [ ] No new flags on an invocation with no `.rlmignore` anywhere in the
      ancestry → byte-identical stdout and state file contents.
- [ ] `--help` output lists the new flags with short examples.
- [ ] `.rlmignore` auto-discovery can be globally disabled by
      `--no-rlmignore` for users who want to guarantee legacy behaviour.

---

## Functional Requirements

1. **FR-1 — CLI flags on `init-repo` subparser**
   - Add `--exclude PATTERN` (`action='append'`, repeatable, default `[]`).
   - Add `--include PATTERN` (`action='append'`, repeatable, default `[]`).
   - Add `--exclude-from FILE` (single path; default `None`).
   - Add `--no-rlmignore` (`action='store_true'`, default `False`).
   - Priority: **High**
   - Dependencies: none (stdlib `argparse`).

2. **FR-2 — Gitignore-lite matcher** *(no PurePath.match, no Python 3.13)*
   - Implement a small in-file helper `_match_gitignore(rel_path, pattern)`
     supporting:
     - `**` → zero or more path segments.
     - `*` → any chars within a single segment (no `/`).
     - `?` → any single char within a segment.
     - `[abc]` / `[a-z]` → character class (bracket expression,
       single-segment).
     - Trailing `/` on pattern → directory-only match (applies to the
       directory component at that position; a file under it still
       matches because its parent segment matches).
     - Leading `/` on pattern → anchored to repo root.
     - Plain names without `/` → match at any depth.
     - Patterns containing `/` without leading `/` → anchored to repo
       root (e.g. `html/vendor` only matches `html/vendor` at root).
     - `!pattern` → negation in the **exclude list only**. A file
       matched by a non-negation exclude is dropped; a later
       negation match re-includes it. Negation in the include list
       is treated as a literal `!`.
     - `\` → escape for literal `*`, `?`, `!`, `[`, `\`.
   - Rationale: `PurePath.match` is single-segment on Python ≤ 3.12, and
     `Path.full_match` (3.13+) is not available on all target systems
     (claude-mem constraint). `fnmatch` does not handle `**`. A small
     custom matcher is the only option that makes `html/**` recurse on
     the versions we support.
   - Priority: **High**
   - Dependencies: none (stdlib only).

3. **FR-3 — `.rlmignore` auto-discovery**
   - Starting from `cwd` (not `repo_path`), walk up the directory tree
     looking for a file named `.rlmignore`. Stop at the first hit, or at
     the filesystem root. Cache the discovered path for use in summary.
   - Skipped entirely if `--no-rlmignore` is given or if `--exclude-from`
     is given (explicit file wins over implicit discovery).
   - Priority: **High**

4. **FR-4 — Filter application**
   - Inside `_build_repo_index` (or immediately after file discovery),
     apply include+exclude filtering to the file list. Relative paths
     are computed against `repo_root` and normalised with forward
     slashes before matching.
   - Priority: **High**

5. **FR-5 — Fallback walker parity**
   - The same filter is applied to the result of
     `_discover_files_fallback`. Existing `skip_dirs` behaviour is
     preserved (the new filter runs *after* skip_dirs).
   - Priority: **High**

6. **FR-6 — Per-pattern summary reporting**
   - Track, per pattern, how many files it matched. Print the exclusion
     section and include section as specified in Story 5.
   - When both `--exclude` and `--exclude-from` / `.rlmignore` contribute
     patterns, the summary groups patterns by source (e.g. a `(from
     .rlmignore)` suffix) so users can tell where a pattern came from.
   - Priority: **Medium**

7. **FR-7 — Help text and examples**
   - `--help` for `init-repo` documents each flag with one-line examples
     (`--exclude 'html/**'`, `--exclude-from .rlmignore`,
     `--include 'scripts/**'`).
   - Priority: **Medium**

8. **FR-8 — README & CLAUDE.md updates**
   - README's "Add Language Support" section (or a new subsection) gains
     a short "Excluding vendor paths" note with a `.rlmignore` example.
   - CLAUDE.md's "File Structure" comment on `rlm_scripts/rlm_repl.py`
     updates the line count if it grows meaningfully.
   - Priority: **Medium**

---

## Non-Functional Requirements

1. **NFR-1 — Performance**: filtering must be O(files × patterns) with a
   constant-factor matcher; for 20k files × 5 patterns this should add
   < 100 ms on a modern laptop. No pre-compilation to regex is required
   but is allowed as an internal optimisation.
2. **NFR-2 — Zero dependencies**: must remain stdlib-only. Must not
   introduce `pathspec`, `gitignore-parser`, or any third-party package.
3. **NFR-3 — Python compatibility**: must work on the same Python
   versions the rest of `rlm_repl.py` targets — **no reliance on
   `Path.full_match` (3.13+)**. The claude-mem runtime pins an earlier
   version.
4. **NFR-4 — Determinism**: file ordering in the index must remain
   sorted after filtering, matching today's behaviour.
5. **NFR-5 — Safety**: invalid patterns (unreadable `--exclude-from`
   file, malformed line) must produce a clear error message that names
   the file and line number and exit non-zero, not silently skip.

---

## Technical Constraints

- Target file is the tracked source at
  `.claude/rlm_scripts/rlm_repl.py` (87 files indexed, 1 Python file).
  `install.sh` copies it into `~/.claude/rlm_scripts/`.
- Functions to touch (verified by reading the current source):
  - `_discover_git_files` (ends at line 344)
  - `_discover_files_fallback` (lines 351–368)
  - `_build_repo_index` (line 371)
  - `cmd_init_repo` (line 524) — wiring & summary output at lines 554–578
  - `build_parser` / `p_init_repo` subparser (lines 767–781) — new flags
- No state-file format change. `repo_index` dict stays the same; the
  exclusion report is print-only, not persisted.
- Must degrade gracefully: if `.rlmignore` exists but is unreadable, the
  command fails loud (NFR-5).
- Install path: change lands in this repo's tracked copy; users pick it
  up via `install.sh` on next install. This is consistent with existing
  workflow (see CLAUDE.md "Installation Flow").
- `_build_repo_index` will gain an optional `files: Optional[List[Path]]`
  parameter so filtering can happen after discovery without duplicating
  discovery code. Default preserves current behaviour
  (pre-filtered list is passed in by `cmd_init_repo` when present,
  otherwise the function discovers files itself as today).

---

## Out of Scope

- Rewriting the index format or adding per-file exclude reasons.
- Re-indexing on file change / watch mode.
- Negation (`!pattern`) inside the **include** list — a leading `!`
  there is treated as a literal character. Exclude-list negation is
  supported (see FR-2).
- Full gitignore compatibility (e.g. subtle `/**/` collapsing rules,
  `# ` handling mid-line, whitespace quoting). We ship a documented
  subset only.
- GUI/TUI for pattern entry.
- Making filtering available to `init` (context-file mode); this PRD
  only addresses `init-repo`.
- Upstream contribution to `brainqub3/claude_code_RLM`. The user
  confirmed the target is this repo's tracked `rlm_repl.py`; upstream
  sync, if any, is a separate task.

---

## Success Metrics (measurable)

1. **Vendor-heavy repo**: on a repo with 17,113 tracked files where 17,009
   are under `html/`, running `init-repo . --exclude 'html/**'` indexes
   exactly 104 files.
2. **Backward-compat**: on any repo with no flags and no `.rlmignore`
   anywhere in the ancestry, `init-repo` output is byte-for-byte
   identical to the current implementation (verified by snapshot test).
3. **Reporting**: the summary shows non-zero counts for every pattern
   that matched something, and the sum of per-pattern counts equals
   the `Excluded: N` total.
4. **Help discoverability**: `python3 rlm_repl.py init-repo --help`
   documents all four new flags with inline examples.

---

## Open Questions

*(None — resolved during scoping:*
*`PurePath.match` rejected in favour of a custom gitignore-lite matcher*
*due to `**` limitation on Python ≤ 3.12 and the claude-mem version*
*constraint; `.rlmignore` is discovered by walking up from cwd with*
*`repo_root/.rlmignore` as a fallback; `--include` is in scope;*
*exclude-list negation `!pattern` is in scope (include-list negation*
*is not); per-pattern reporting is verbose; fallback walker is covered;*
*target is this repo's `rlm_repl.py`.)*

---

## References

### From Codebase (RLM)

- `.claude/rlm_scripts/rlm_repl.py`:
  - `_discover_git_files` — lines ~320–348
  - `_discover_files_fallback` — lines 351–368
  - `_build_repo_index` — line 371
  - `cmd_init_repo` — line 524, summary block lines 554–578
  - `p_init_repo` subparser — lines 767–781

### From History (Claude-Mem)

- Obs #6251 (RLM state and MCP integration), #10010 (recent re-index)
  provide background on how `repo_index` is consumed. No prior PRD
  has modified `init-repo` file discovery.

---

## Next Steps

1. Review and approve this PRD.
2. Run `/dev:tech-design` to detail the gitignore-lite matcher and the
   filter pipeline wiring.
3. Run `/dev:tasks` to break into implementation + verification subtasks.
