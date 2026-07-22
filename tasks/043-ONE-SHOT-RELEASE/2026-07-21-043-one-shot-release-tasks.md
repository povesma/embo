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

- [X] 1.0 **User Story:** As the maintainer, `embo-deliver` executes a
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

  DESIGN CHANGE (2026-07-22, user): stories 3.0/4.0 were originally a
  deterministic "mode-inference decision table" the skill would evaluate.
  That was rejected as overcomplication — the agent reading the repo and
  drafting a sensible plan IS the decision; it does not need a codified
  rules engine. Rewritten below to "the agent drafts the release plan."
  Both remain OPEN (skill-side git.md work); the executor (1.0/2.0) and
  the live release (5.2) do not depend on them.

- [X] 3.0 **User Story:** As the maintainer, `/embo:git deliver` builds a
  correct `release` plan from the situation — the agent picks the mode by
  judgment (no codified table), shows it in the plan, and the plan-file
  Write is the only confirmation
  - [X] 3.1 In the `deliver` section of `git.md`, state plainly when the
    agent should choose `release` (publishing a new version: version files
    + CHANGELOG changed) vs `pr-merge`; kept as one-line guidance, not a
    lookup engine [verify: code-only]
    → `release` added to the mode list with "choose only when publishing a
      new version; else prefer pr-merge" (2026-07-22)
  - [X] 3.2 State that the chosen mode is written into the plan and the
    plan-file Write is the sole confirmation [verify: code-only]
    → the existing "plan-file Write is the single gate" text already
      covers all modes incl. release; mode appears in the format block
      (2026-07-22)

- [X] 4.0 **User Story:** As the maintainer, a `release` plan the agent
  drafts shows the version and release notes, so the single approval is
  informed
  - [X] 4.1 Document in `git.md` that for a `release` the agent confirms
    the version is already set (asking if it can't confirm — never editing
    it), and drafts the `release-notes:` body per RULE:RELEASE-BODY-
    AUTHORING [verify: code-only]
    → `version` field note "confirm it is already set; never set or bump
      it yourself (ask if unclear)"; `release-notes` field points to
      RULE:RELEASE-BODY-AUTHORING (2026-07-22)
  - [X] 4.2 Document the mandatory leading irreversibility comment for a
    `release` plan; show a complete `release` plan example [verify: code-only]
    → format block shows mode/version/release-notes; irreversibility
      comment note extended to release (2026-07-22)

- [X] 5.0 **User Story:** As the maintainer, the feature is documented
  and proven on a real release
  - [X] 5.1 Document the one-shot delivery/release procedure in README
    (user-facing) and CLAUDE.md (maintainer) [verify: code-only]
    → README DONE: the `deliver` section lists the `mode` values incl.
      `release`, shipped to main via PR #34 (2026-07-22). CLAUDE.md DONE:
      the embo-deliver bin entry notes `release` mode adds tag+GitHub
      Release (2026-07-22).
  - [X] 5.2 Live: cut the real next embo release (0.2.3) via
    `/embo:git deliver`; confirm `release` → one plan approval →
    published GA [verify: manual-run-claude]
    → RELEASED v0.2.3 (2026-07-22) by dogfooding `mode: release`:
      plan tmp/git-release-0.2.3.txt → PR #33 → squash-merge into main →
      tag v0.2.3 → GitHub Release. Verified: `gh release view v0.2.3`
      = isDraft:false, isPrerelease:false; tag v0.2.3 == origin/main tip
      (799984f) (AC-1, AC-4). First attempt halted at PR step (exit 5,
      collaborator auth) with commit+push kept and nothing undone —
      halt-on-failure contract confirmed live; retry after auth fix
      completed the chain.

