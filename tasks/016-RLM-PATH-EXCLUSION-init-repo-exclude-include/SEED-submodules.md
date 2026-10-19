# 016 follow-up: `init-repo` skips git submodule contents — Seed

**Status**: Fix applied in the working tree, not committed. No test,
no PRD/tech-design amendment yet.
**Origin**: raised 2026-10-07 while running `/embo:init` on
`app-astudio` (Artec Studio), a repo whose code lives mostly in 51 git
submodules.

## Problem

`_discover_git_files()` in `plugin/rlm_scripts/rlm_repl.py` listed
tracked files with plain `git ls-files`. Git reports a submodule as a
single gitlink entry (the submodule path), not its files, so
`rlm_repl init-repo .` indexed **none of the code inside submodules**
even when they were checked out.

Observed on `app-astudio`:

| | Files indexed | Size | Files under `core-astudio/` + `3dproc/` + `fusion/` |
|---|---|---|---|
| Before fix | 4,318 | 160.2 MB | 0 (each submodule = 1 gitlink entry) |
| After fix | 15,005 | 435.4 MB | 1,979 |

Nothing fails or warns — the index just looks plausible but small, so
the gap is easy to miss. Every later command that relies on RLM (prd,
tech-design, impl, check) then reasons about the codebase without the
submodule code.

## Fix applied

`rlm_repl.py`, `_discover_git_files()`, tracked-files call:

```python
['git', 'ls-files']                          # before
['git', 'ls-files', '--recurse-submodules']  # after
```

The untracked-files call (`git ls-files --others --exclude-standard`)
is unchanged: git rejects `--others` together with
`--recurse-submodules`. Consequence: untracked files *inside* a
submodule are not indexed (tracked ones are).

## Verified

- Re-index of `app-astudio` after the fix: all 51 submodules have files
  in `repo_index['files']` (smallest: `dnn-compiler`, 13 files); no
  gitlink-only entries remain.

## Not verified / open

- **No automated test.** `_discover_git_files` has no test coverage.
  Add one: a temp repo with a submodule (local `file://` remote),
  assert submodule files are discovered and the gitlink path is not.
- **Uninitialized submodules**: expected to contribute no entries
  (neither files nor gitlink) with `--recurse-submodules`; not tested.
  Before the fix they appeared as 1 gitlink entry each. Decide whether
  init should *report* uninitialized submodules so the user knows the
  index is partial (app-astudio had all 51 uninitialized at first).
- **Nested submodules** (submodules inside submodules): `ls-files
  --recurse-submodules` recurses, but this was not checked on a real
  nested layout.
- **`.rlmignore` / `--exclude` / `--include` interaction**: patterns
  now see submodule paths too (e.g. `colmap/**`). Expected to work the
  same as for normal paths; not tested.
- **Minimum git version** for `ls-files --recurse-submodules`: not
  checked against embo's supported platforms (Windows install, task 034).
- **Docs**: the 016 PRD/tech-design describe file discovery as
  git-aware via `git ls-files`; amend them to state submodule
  behaviour (fold into 016 rather than a new task).
- **Branch**: the edit was made in the working tree while the embo repo
  was on `docs/066-branch-stacking-seed` — move it to its own branch
  off `main` before committing (see task 066).

## Recommended next step

Move the change to a `fix/` branch off `main`, add the submodule test,
amend the 016 tech-design's file-discovery section, then deliver.
