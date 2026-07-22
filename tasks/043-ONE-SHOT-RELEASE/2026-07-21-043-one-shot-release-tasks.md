# One-Shot Release — Task List

## Relevant Files

- [2026-07-21-043-one-shot-release.md](2026-07-21-043-one-shot-release.md)
  :: One-Shot Delivery with Inferred Mode — combined spec (problem,
  decisions, acceptance criteria). Normative source for the decision
  table and plan fields.
- plugin/bin/embo-deliver :: the executor — add `mode: release`,
  `version:`, release-notes handling; manifest bump; CHANGELOG prepend;
  tag + `gh release create` after the existing pr-merge path (modify)
- plugin/bin/embo-deliver.test.sh :: dry-run release cases + the
  halt-on-failure case (modify)
- plugin/commands/git.md :: `deliver` section — mode inference from the
  decision table, semver + CHANGELOG derivation for a release, plan
  build (modify)
- plugin/.claude-plugin/plugin.json :: `version` field bumped by the
  release executor (touched at release time, not edited by this task)
- .claude-plugin/marketplace.json :: `version` field bumped by the
  release executor (touched at release time)
- CHANGELOG.md :: entry prepended by the release executor
- README.md, CLAUDE.md :: document the one-shot delivery/release
  procedure (modify)

## Notes

- `embo-deliver` makes NO decisions — the skill's inference fills the
  plan; the executor only runs what the plan says. This holds for
  `release` exactly as for the existing modes.
- `release` is a new mode of the SAME executor, not a new binary — one
  plan format, one allow rule (`Bash(embo-deliver *)`).
- **DESIGN CHANGE (2026-07-22, user):** `release` is a general capability
  for ANY repo, not embo-specific — so the executor must not know or edit
  any version manifest. The maintainer sets the version in the manifests
  AND edits the CHANGELOG *before* releasing; those files are delivered as
  ordinary `file:` entries. **The executor writes NOTHING to source
  files.** The deliver *skill* verifies the version is set (asking the
  maintainer explicitly if it can't confirm) but never writes it. This
  removes the manifest-bump / CHANGELOG-prepend / jq work from scope.
- A `release` is therefore `pr-merge` plus a TAIL only: after merge, tag
  vX.Y.Z on the base tip + publish a GA Release. It inherits the branch
  reconcile from BUG-2026-07-22 (038): the plan's head `branch:` is
  authoritative, reconciled before staging.
- Plan fields for release: `version:` (the vX.Y.Z to tag) and a
  `release-notes:` block (the GitHub Release body). No `changelog:` field
  — the CHANGELOG is a maintainer-edited `file:`.
- New exit codes: 8 = tag create/push failed (merged); 9 = Release publish
  failed (merged + tagged).
- Tests use `--dry-run`, which must print bump/tag/publish steps WITHOUT
  running git/gh — the existing dry-run convention. `gh` is absent in
  the test env, so release-mode tests assert on printed step order and
  on the manifest/CHANGELOG edits that happen before any `gh` call.
- Story 5.0's live release (5.2) is the terminal step; it cuts the real
  next embo version and is the AC-1/AC-4 proof.

## Tasks

- [~] 1.0 **User Story:** As the maintainer, `embo-deliver` executes a
  full release from a plan with no decisions of its own — `mode: release`
  runs the pr-merge path over the maintainer-prepared files, then tags
  `vX.Y.Z` on the base tip and publishes the GA Release. The executor
  writes NO source files.
  - [X] 1.1 Write `embo-deliver.test.sh` `--dry-run` cases for
    `mode: release`: assert the printed step order (stage maintainer
    files → commit → push → PR → merge → `git fetch` → `git tag vX.Y.Z`
    → push tag → `gh release create`); plans missing `version:`,
    `base:`, or the `release-notes:` block each fail rc 2; the executor
    runs no `jq` [verify: auto-test]
    → 13 release cases added; red-first confirmed (mode rejected), green
      after 1.2/1.4 (2026-07-22)
  - [X] 1.2 Add `version:` and a `release-notes:` block to the plan
    parser (multi-block: `message:`/`release-notes:` run to the next
    header or EOF; scalar keys only before the first block); validate
    that `mode: release` requires `version:`, `base:`, and a
    `release-notes:` block [verify: auto-test]
    → parser reworked to a cur_block model; release validation added
      (2026-07-22)
  - [X] 1.4 Implement the `mode: release` post-merge tail: `git fetch
    origin <base>`, `git tag vX.Y.Z origin/<base>`, push the tag, then
    `gh release create` non-draft/non-prerelease with the release-notes
    body; new exit codes 8 (tag) and 9 (publish) documented in the
    header [verify: auto-test]
    → tail implemented; full dry-run prints the correct sequence
      (2026-07-22)
  - [X] 1.5 Full dry-run release plan runs end-to-end (rc 0) printing
    every step in order; the existing tests still pass [verify: auto-test]
    → 93 passed, 0 failed; full release dry-run verified by hand: stage
      → commit → push → PR → merge → fetch → tag → push tag → publish
      (2026-07-22)
  - Subtask 1.3 (jq manifest bump + CHANGELOG prepend) REMOVED by the
    2026-07-22 design change — the executor writes no source files.

- [X] 2.0 **User Story:** As the maintainer, a release-mode step failure
  halts cleanly — clear per-step status, nothing undone
  - [X] 2.1 Write a test simulating a mid-chain release failure (the PR
    step fails via a deterministic failing `gh` stub injected on PATH —
    never a real API call): the executor stops at that step with its
    documented exit code (5) and status message, and does NOT revert the
    commit already made [verify: auto-test]
    → release-halt test: commit made+kept, exit 5 at PR step, no reset,
      status shows "committed, pushed" (2026-07-22)
  - [X] 2.2 Confirm the release tail (tag + publish) never runs when an
    earlier step fails — no v-tag is created, tail status absent; the
    halt contract (AC-6) holds for release mode [verify: auto-test]
    → same test asserts no "tagged v9.9.9" status and refs/tags/v9.9.9
      absent after the halt (2026-07-22)

- [ ] 3.0 **User Story:** As the maintainer, `/embo:git deliver` picks
  the delivery mode from repo state via the fixed decision table, never
  a judgement call, defaulting to the safer mode when signals are
  ambiguous
  - [ ] 3.1 Write the mode-inference decision table into the `deliver`
    section of `git.md`: the three rows (feature-branch/no-version-change
    → push; destined-for-main/no-version-change → pr-merge;
    version-would-change or capability-cut → release), each signal
    checkable from repo state, and the explicit ambiguous→safer-default
    rule (never auto-`release` when unsure) [verify: code-only]
  - [ ] 3.2 State that the chosen mode + the signals that produced it are
    written into the plan file, and that the plan-file Write is the only
    confirmation — no separate "confirm the mode?" prompt; remove any
    remaining text implying the user names the mode [verify: code-only]

- [ ] 4.0 **User Story:** As the maintainer, an inferred `release` plan
  shows the derived version and drafted notes, so the single approval is
  informed
  - [ ] 4.1 Document in `git.md` how the skill derives the next semver
    (from the latest `vX.Y.Z` tag + the change class) and drafts the
    CHANGELOG entry + release body (per RULE:RELEASE-BODY-AUTHORING) INTO
    the plan — neither guessed silently nor asked separately
    [verify: code-only]
  - [ ] 4.2 Document the mandatory leading irreversibility comment for a
    `release` plan (merge AND public tag+Release are irreversible) so the
    Write-approval is informed; show a complete `release` plan example
    [verify: code-only]

- [ ] 5.0 **User Story:** As the maintainer, the feature is documented
  and proven on a real release
  - [ ] 5.1 Document the one-shot delivery/release procedure in README
    (user-facing: what `deliver` infers, the one approval) and CLAUDE.md
    (maintainer: release is a `deliver` mode, not manual steps)
    [verify: code-only]
  - [ ] 5.2 Live: cut the real next embo release (0.2.3) via
    `/embo:git deliver`; confirm inferred `release` → one plan approval →
    published GA. `gh release view v0.2.3` reports `isDraft:false,
    isPrerelease:false`; the tag points at the merge commit (AC-1, AC-4)
    [verify: manual-run-claude]

