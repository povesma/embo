# 043: One-Shot Delivery with Inferred Mode (incl. Release)

Combined doc (problem + decisions + scope + tasks), compact style.
`/embo:git deliver` should read the repo state, pick the right delivery
mode (commit+push / pr+merge / release), and run it behind one approval
— the user never types a sub-command or babysits the steps.

## Problem

Cutting embo 0.2.2 took ~8 separate hand-driven actions (version bump,
CHANGELOG entry, commit, push, PR, merge, tag, publish Release), each a
tool call the user watched and corrected. That is the "please remember
the steps" prose-procedure failure the project's Core Design Principle
(CLAUDE.md, "Enforce, Don't Ask") says to replace with a mechanism. A
delivery should cost the user **one approval**, and the user should not
have to know which mode to ask for.

`embo-deliver` (task 038) already runs stage → commit → push → (PR) →
(merge) from a plan file, `mode: push|pr|pr-merge`, making no decisions.
A release is that pipeline plus two ends: before commit, bump the
version in both manifests + write the CHANGELOG entry; after merge,
create the `vX.Y.Z` tag on the merge commit + publish the GitHub
Release.

## Decisions

1. **Full GA in one shot (user, 2026-07-21).** One plan approval runs
   the whole chain up to a published, non-draft, non-prerelease Release.

2. **The skill derives version + CHANGELOG; the plan shows them (user,
   2026-07-21).** For a release, `/embo:git deliver` computes the next
   semver and drafts the CHANGELOG entry + release body, and they appear
   IN the plan the user approves — no separate question, no blind guess.

3. **No `release` sub-command — `/embo:git deliver` INFERS the mode
   (user, 2026-07-21).** The user runs plain `deliver`; the skill reads
   the repo state and picks the mode by a fixed decision table (below),
   not a judgement call. "Infer" here is deterministic: the same repo
   state always yields the same proposed mode.

   | Signal (all checkable from repo state) | → Mode |
   |---|---|
   | On a feature branch; ordinary local work; nothing indicates main is the target; no version change | `push` (commit+push, stay on branch) |
   | Change is destined for main/protected branch; ordinary work (fix/refactor/feature); manifest version unchanged vs latest tag | `pr-merge` |
   | Manifest version would change vs the latest tag, OR a user-facing capability is being cut as a version (a CHANGELOG entry is warranted) | `release` (pr-merge + tag + publish) |

   The chosen mode + the signals that produced it are written into the
   plan file. The single plan-file Write-approval is the confirmation —
   no separate "confirm the mode?" prompt (that would be the double-
   gate the deliver design forbids). **When signals are contradictory /
   genuinely ambiguous, the plan states so and defaults to the SAFER
   mode — never auto-`release` when unsure.**

4. **`release` is a new `embo-deliver` executor mode, not a new binary.**
   Keeps one executor, one plan format, one allow rule
   (`Bash(embo-deliver *)`). New plan fields: `version:` and the release
   body (via the existing `message:` convention or a `release-notes:`
   block). The executor still makes NO decisions — the skill's inference
   fills the plan.

5. **Tag on the merge commit; Release non-draft/non-prerelease = GA.**
   Fetch main first, tag the PR's merge commit, `gh release create`
   publishes immediately (the 0.2.2 GA state just shipped by hand).

6. **Irreversibility disclosed in the plan.** A `release` (and
   `pr-merge`) plan carries a mandatory leading comment: the merge AND
   the public tag+Release are irreversible, so the Write-approval is
   informed.

7. **Release body per RULE:RELEASE-BODY-AUTHORING** (`embo:git`):
   executive summary + Highlights + CHANGELOG link, hand-written.

## Acceptance criteria

- **AC-1 (one approval):** from a clean committed branch,
  `/embo:git deliver` reaches the correct end state (push, or merged, or
  published GA) with exactly one human gate — the plan-file Write.
- **AC-2 (mode inference deterministic):** given a fixed repo state, the
  skill selects the mode by the decision table; a unit/fixture check
  covers each row incl. the ambiguous→safer-default case.
- **AC-3 (derived + shown for release):** the plan contains the computed
  version and drafted CHANGELOG entry; neither guessed silently nor
  asked separately.
- **AC-4 (GA verified):** after a release run, `gh release view vX.Y.Z`
  reports `isDraft:false, isPrerelease:false`; the tag points at the
  merge commit.
- **AC-5 (faithful executor):** `embo-deliver` makes no decisions; every
  value comes from the plan. Release mode is fixture-tested via
  `--dry-run` (prints bump/tag/publish without running them).
- **AC-6 (halt on failure):** a mid-chain failure stops with a clear
  per-step status and does not undo prior steps — today's contract.

## Scope

- Extend `plugin/bin/embo-deliver`: `mode: release`, `version:`,
  release-notes block; bump both manifests, prepend the CHANGELOG entry,
  the existing pr-merge path, then tag + `gh release create`.
- Extend `embo-deliver.test.sh` with `--dry-run` release cases + the
  mode-inference decision-table cases.
- Rework the `embo:git` `deliver` section: infer the mode from the
  decision table, derive version + changelog for a release, build the
  plan, write it (the single gate), run the bare executor. Remove any
  implication that the user names the mode.
- Out of scope: multi-artifact/signed releases; changelog-from-
  conventional-commits automation (draft stays model-authored).

## Tasks

- [ ] 1.0 **User Story:** As the maintainer, `embo-deliver` executes a
  full release from a plan with no decisions of its own.
  - [ ] 1.1 Write `embo-deliver.test.sh` `--dry-run` cases for
    `mode: release`: printed step order (bump both manifests → prepend
    CHANGELOG → commit → push → PR → merge → tag vX.Y.Z → publish); a
    missing `version:` fails rc 2. [verify: auto-test]
  - [ ] 1.2 Implement `mode: release` to pass 1.1 (jq bump both
    manifests, CHANGELOG prepend, pr-merge path, `git tag` +
    `gh release create`). [verify: auto-test]
  - [ ] 1.3 Halt-on-failure + no-undo verified for a release-mode step
    failure (simulated tag-push reject). [verify: auto-test]

- [ ] 2.0 **User Story:** As the maintainer, `/embo:git deliver` picks
  the right mode from context behind one gate.
  - [ ] 2.1 Implement the mode-inference decision table in the skill;
    fixture-check each row + the ambiguous→safer-default. [verify: code-only]
  - [ ] 2.2 For an inferred `release`: derive next semver, draft the
    CHANGELOG entry + release body, write the plan (single approval);
    plan carries the mode, the signals, and the irreversibility comment.
    [verify: code-only]

- [ ] 3.0 **User Story:** As the maintainer, the feature is documented
  and proven on a real release.
  - [ ] 3.1 Document the one-shot delivery/release procedure in README +
    CLAUDE.md. [verify: code-only]
  - [ ] 3.2 Live: cut the next real embo release via `/embo:git deliver`;
    confirm inferred `release` → one approval → published GA (AC-1, AC-4).
    [verify: manual-run-claude]

## Related

- Task 038 (RAPID-DELIVER / `embo-deliver`) — the executor this extends.
- Task 040 (visual-impl ship) — its 4.3 tag+Release was the last
  hand-driven release; this replaces that procedure.
- CLAUDE.md "Core Design Principle — Enforce, Don't Ask" — the rationale.
