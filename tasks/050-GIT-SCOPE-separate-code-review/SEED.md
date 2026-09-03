# 050: `/embo:git` should not review code — separate the review concern

**Status**: Not started (seed).
**Origin**: surfaced 2026-08-08 while writing the 0.2.4 release post. The
`/embo:git pr` "Reviewer-friendliness check" (git.md Step 5) inspects the
code diff for over-engineering, noise, oversized changesets, and
uncommented logic, and returns a `file:line` cut-or-simplify list. That
is code review, not git work.
**Priority**: medium — architectural cleanliness; no user-facing breakage
today, but the concern is misplaced and will grow.

## Problem

`/embo:git` is the git-and-PR tooling command: generate commit messages,
generate PR descriptions, manage commit style, deliver. Its job is to
move committed work to the repository correctly — stage, commit, push,
open/merge a PR, tag, release.

It currently also **reviews the code being delivered**. `/embo:git pr`
Step 5 ("Reviewer-friendliness check") reads the diff and flags:
- code that reinvents an existing option (stdlib call, built-in,
  installed dependency, existing repo code) — with a `file:line`
  cut-or-simplify list;
- noise (debug prints, commented-out code, stray formatting);
- oversized changesets;
- non-obvious logic without comments.

This is a **separation-of-concerns violation**. Judging code quality is
a distinct responsibility from packaging and shipping a change. Bundling
them means:
- `/embo:git` can't be reasoned about as "just git" — a user running it
  to open a PR gets an unrelated code critique.
- The review logic can't be invoked on its own (e.g. mid-implementation,
  before a commit exists).
- The two concerns evolve under one command file and one description,
  making both harder to change safely.

## Proposed direction (validate in a design pass, do not assume)

- **Extract the code-quality review into its own entity.** Options to
  weigh:
  - (a) a dedicated command, e.g. `/embo:review` (or fold into an
    existing review-oriented command if one fits);
  - (b) a dedicated subagent that any command can spawn (an independent
    context is the right shape for adversarial review — it should not
    ratify code authored in the same session);
  - (c) both — a thin command that spawns the subagent.
  Lean (c): a subagent gives the clean-context independence review
  needs; a command gives an explicit entry point.
- **`/embo:git` keeps only git/PR mechanics.** Commit-message and
  PR-description generation stay (they describe the change, they do not
  judge the code). The Step 5 diff-quality inspection moves out.
- **Decide the hand-off.** Does `/embo:git pr` still *offer* to run the
  review (a prompt: "review the code before opening the PR?"), or is the
  review purely separate and the user's responsibility to run first?
  A default that keeps the current safety (a review happens before a PR)
  without `/embo:git` doing the reviewing itself.

## Scope

- Move git.md Step 5 (Reviewer-friendliness check) out of `/embo:git`.
- Define the new review entity's contract (input: a diff or a range;
  output: the same `file:line` finding list, plus the noise / oversized
  / uncommented-logic checks).
- Update git.md's description and README so `/embo:git` no longer claims
  a review responsibility.
- Keep the existing check content — it is good; only its home is wrong.

## Related

- `plugin/commands/git.md` Step 5 ("Reviewer-friendliness check").
- Existing shipped review-capable agents (if any) as a possible home.
- The DELEGATE rule (start.md) — a review subagent is exactly the
  "judging work authored this session, a clean context can't ratify its
  own errors" case it names.
