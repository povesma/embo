# 060: Separate "released" from "latest development" — Seed

**Status**: Not started (run /embo:prd to begin).
**Origin**: raised 2026-09-03 while deciding whether to merge PR #65.

## Problem

Today `main` doubles as both the integration branch (everything merges
here) and the release branch. There is no branch whose HEAD reliably
equals "the last GA release." A change is indistinguishable from a
released change the moment it merges.

Consequence: a consumer who tracks the default branch — installed via a
branch ref (`/plugin marketplace add povesma/embo#main`) or a directory
source — receives unreleased, potentially half-finished changes as soon
as they land. (Note the scope: a user who installed the normal pinned
way does NOT auto-update — third-party marketplaces have auto-update off
by default; see task 035. So the leak affects branch-tracking / preview
consumers, not the whole install base. Still worth closing, because
`main` being ambiguous is the root issue.)

## Goal

Establish a branch (or tag) discipline where **"released" is a distinct,
identifiable state** from "latest development", so:

- A consumer can point at "released only" and never see unreleased work.
- A consumer can opt into a "preview / staging" stream deliberately.
- `main`'s HEAD (or the latest tag) unambiguously means "the current GA
  release."

## Proposed direction (the raised idea)

A long-lived `staging` (or `develop`) branch:

- All feature PRs merge into `staging` first.
- A release is: merge `staging` → `main` **and** publish the release in
  the same step.
- `main` then means "released only."

## Options to weigh (rank by KISS / maintainability)

1. **Staging branch (the raised idea).** Git Flow-style. `main` =
   released, `staging` = integration. Clear separation; standard model.
   Cost: a second long-lived branch to maintain and keep in sync —
   overhead that pays off with a stream of contributor PRs, less so for
   a solo/small maintainer.
2. **Tag-based release, single branch.** Keep merging to `main` as the
   integration branch, but define **released = tagged** (`vX.Y.Z`).
   Tell users to install a tagged ref, not the branch. `main` moves
   freely; only tags are "official." Less machinery than a second
   branch; achieves the same "released is identifiable" property. The
   marketplace source would need to resolve to a tag/release, not the
   branch tip.
3. **Do nothing / docs only.** Document that users should pin to a
   released version and not track `main`. Cheapest; relies on user
   discipline; does not fix the ambiguity of `main` itself.

## Constraints (verified elsewhere, shape the design)

- `/plugin update` keys on `plugin.json`'s `version`; an unchanged
  string reports "already at the latest" (task 035). So **any release
  path must include a version bump** — merging code alone does not
  deliver a release to pinned users.
- `embo-deliver release` mode already does tag + GitHub Release, and it
  **verifies** the version bump is present but does not perform the bump
  itself (the G-series hardening in 0.2.10, task 058). A staging→main
  flow must therefore bump the version before/at merge, not rely on the
  release step to do it.
- The marketplace source lives in `.claude-plugin/marketplace.json`
  (`source: ./plugin`). What "released" resolves to for a normal install
  is central to any option here and must be pinned down before
  designing (does the marketplace point at a branch, a tag, or the repo
  tip?).

## Open questions for the PRD

- Which consumer install modes exist today, and which of them
  auto-track the default branch? (Determines who actually sees the
  leak.)
- Does the marketplace resolve to `main`'s tip, or to a tag/release? Can
  it be pointed at a release?
- Solo vs. multi-contributor cadence — does the PR volume justify a
  second long-lived branch (option 1), or is tag-based release
  (option 2) enough?
- How does `embo-deliver`'s `release` mode change under a staging model
  — new `base`, a pre-merge version bump step, or a new mode?

## Related

- Task 035 (plugin update awareness) — the auto-update-off fact and the
  `/plugin update` version-keying constraint.
- Task 058 (release hardening) — the deliver/release mechanism this
  strategy sits on top of; hardened the `release` mode's checks.
- Task 043 (one-shot release) — introduced the `release` delivery mode.
- `.claude-plugin/marketplace.json`, `plugin/.claude-plugin/plugin.json`
  — the manifests a release bumps.

## Recommended next step

Run `/embo:prd` to expand this, then `/embo:research:examine` on the
resulting options (staging branch vs. tag-based release vs. docs-only)
against how embo is actually installed — this is a process change with a
long-term maintenance effect, worth an independent second opinion before
committing.
