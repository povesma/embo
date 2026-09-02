# 058: Release-hardening — remaining gaps after 0.2.9 fix

Status: seed. Captured 2026-09-02 from the post-0.2.9 audit.

## Context

The 0.2.9 install issue (`.claude-plugin/marketplace.json` at 0.2.5
while `plugin/.claude-plugin/plugin.json` was at 0.2.9) surfaced a
family of release-mechanism gaps. Four of the highest-leverage were
closed the same day:

- **G1** — `plugin/bin/embo-deliver` extended to check both top-level
  `.version` and every `.plugins[].version` field across the plugin
  manifest and the marketplace manifest.
- **G2** — release refused when `CHANGELOG.md` has no heading matching
  the plan's `version:`.
- **G3** — tag-identity guard: if a `vX.Y.Z` tag already exists locally
  or on the remote at a different commit than `origin/$BASE`'s tip,
  refuse with exit 8 instead of silently accepting the mismatch.
- **G8** — test coverage extended for G1 and the new checks (114/114
  pass on the branch that shipped as the 0.2.9 retag).

Four gaps remain, all sitting in the same executor / release-mode
skill area. This seed groups them for one future PRD pass.

## Remaining gaps

### G4 — no semver-ordering check

`plugin/bin/embo-deliver` never compares plan.version against the
previous tag. A release plan with `version: 0.2.8` while
`origin/main` is at 0.2.9 currently ships. Proposed mechanism:
`git tag --sort=-v:refname | head -1` and refuse when the plan's
version is not strictly greater. Override flag for deliberate
re-tags (the 0.2.9 retag path).

### G5 — no refusal for uncommitted files not in `file:`

`plugin/commands/git.md` step 1 tells the maintainer to inspect
`git status --short` "so the file list is accurate and unrelated
dirty files are not swept in" — pure prose. Proposed mechanism: in
`embo-deliver`, when the plan is release/pr-merge, compare tracked
modified files against the plan's `file:` set; refuse if any
tracked modification is not covered by the plan.

### G6 — skill prose does not enumerate version-bearing files

`plugin/commands/git.md` release-mode says "confirm version is set
in the project's version files" but names none of them, and does
not note that `.claude-plugin/marketplace.json` carries two version
fields. Proposed doc fix: enumerate the files explicitly and point
at the executor's check so the maintainer can rely on it.

### G7 — release-notes body only checked for non-empty

Line 166 of `embo-deliver` accepts any non-empty `release-notes:`
block. Proposed mechanism (minor): require the body to mention
`$VERSION` or exceed a floor length; reject the obvious placeholder
cases.

### G9 — PR create fails on an already-open PR (observed 2026-09-02)

During the 0.2.10 delivery, a `pr-merge` plan exited 5 because a PR
for the branch already existed OPEN; the re-run then detected it and
merged. The create step should treat an existing open PR as success
and proceed to merge in the same run, as the re-run path already
does.

### G10 — release checks validate the pre-reconcile tree (observed 2026-09-02)

The G2 CHANGELOG check ran against the checked-out branch (a stale
one) before the executor reconciled onto `plan.branch`, refusing a
release that was valid on the target state. Validation should run
after the branch reconcile, against the tree that will actually be
committed.

## Related files

- `plugin/bin/embo-deliver` — executor with the release-mode checks.
- `plugin/bin/embo-deliver.test.sh` — extend for each new check.
- `plugin/commands/git.md` — deliver/release-mode instructions.
