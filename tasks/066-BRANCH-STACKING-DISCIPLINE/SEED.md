# 066: Don't stack an independent feature on an unrelated branch — Seed

**Status**: Not started (run /embo:prd to begin).
**Origin**: raised 2026-09-09 while building the session-telemetry
feature (task 065). The feature was branched off
`feat/062-worktree-isolation` (an unrelated, unmerged feature) instead
of off `main`, and the consequences only surfaced at release-planning
time.

## Problem

When a new, independent feature branch is created on top of another
unmerged feature branch (stacking), the new branch inherits the base
feature's commits. Nothing fails immediately — tests pass, work
proceeds — so the mistake stays invisible until:

- **Release scope is muddled.** A PR from the stacked branch to `main`
  shows both features' diffs. The CHANGELOG `[Unreleased]` section
  accumulates entries for a feature the current work never touched.
- **A test / feature plan mixes the two.** Enumerating "what ships in
  this release" from the branch state lists the base feature's
  user-facing commands as if they were part of the new work, producing
  confident but wrong statements about what a user can do.
- **The new feature cannot merge independently.** It is blocked behind
  the base feature's PR even when it has no code dependency on it.

Concrete instance (task 065): telemetry was stacked on the worktree
branch. The release test plan then described `embo-worktree-start` /
`embo-worktree-remove` as part of the release and made four cascading
errors about how those commands are invoked — all rooted in the base
feature's presence in the branch, not in the telemetry work. The fix
was to cherry-pick the 3 telemetry commits onto a fresh branch off
`main`, re-point the PR, and delete the stacked branch.

## Goal

Make the correct default — **branch each independent feature off the
integration base (`main` today), not off another feature branch** — the
path of least resistance, and make an accidental stack **fail loudly or
get flagged early**, not at release time.

## Options to weigh (rank by KISS / maintainability)

1. **Guidance only (docs / a rule in the workflow).** State the default
   in the git/impl guidance: new feature → branch off `main` unless
   there is a real code dependency, and if you must stack, say so
   explicitly and plan to rebase before release. Cheapest; relies on the
   agent remembering — which is exactly the failure mode embo's
   "enforce, don't ask" principle distrusts.
2. **A start-of-work check.** When beginning a new task's branch, detect
   that the current HEAD is an unmerged feature branch (not `main` / not
   a release base) and surface it: "you are about to branch off
   `<X>` — intended, or should this come off main?" A cheap
   `git` check at branch-creation time.
3. **A pre-PR / pre-deliver guard.** Before opening a PR or delivering,
   compare the branch's commit range against the base: if it contains
   commits that belong to a *different* task's docs (e.g. commits whose
   changed files map to another `tasks/NNN-*` folder), warn that the
   branch may be stacked and the release scope may be wider than
   intended.

## Constraints (shape the design)

- The check must not fire on a *legitimate* stack (a feature that
  genuinely depends on unmerged work) — it should flag and ask, not
  block.
- `main` is the integration base today; task 060 may change that to a
  staging branch. Whatever "the integration base" is, the rule is
  "branch independent features off it," so this should reference 060's
  outcome rather than hardcode `main`.
- Detecting "commits that belong to another task" is heuristic (map
  changed files → `tasks/NNN-*` folder). It will not be perfect; treat
  it as a warning signal, not a hard gate.

## Open questions for the PRD

- Is the right intervention at branch-creation (option 2), at
  PR/deliver time (option 3), or both?
- How is "the integration base" determined once task 060 lands a
  staging model — is it always `main`, or the configured base?
- Can the stacked-commit heuristic (changed files → task folder) be made
  reliable enough to warn without crying wolf on shared-infra files
  (hooks.json, CHANGELOG, README) that many tasks touch?

## Related

- Task 060 (release branch strategy) — the *release* end of branch
  discipline (released vs. latest development for consumers). This seed
  is the *development* end (feature-branch topology). They share the
  "what is the integration base" question but solve different problems;
  keep them separate.
- Task 065 (session telemetry) — the instance that surfaced this; its
  branch was un-stacked (cherry-picked onto a clean branch off `main`)
  as the immediate fix.

## Recommended next step

Run `/embo:prd` to expand this. Because it is a process change with a
long-term effect and overlaps task 060's "integration base" question,
run `/embo:research:examine` on the options (guidance vs.
branch-creation check vs. pre-deliver guard) before committing.
