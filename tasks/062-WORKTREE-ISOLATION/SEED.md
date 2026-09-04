# 062: Git-worktree isolation for embo's agents — Seed

**Status**: Not started (run /embo:prd to begin).
**Origin**: 2026-09-04 competitor landscape refresh — identified as
embo's single clearest competitive gap.

## Problem

embo runs its subagents (RLM subcall, the 5 test subagents, research
agents) in the **same working tree** as the main session. The
2026-09-04 landscape comparison found this is the most conspicuous
capability gap: **GitHub Spec-Kit, Superpowers, OMC, and
claude-workflow-template all isolate parallel agents in separate git
worktrees**, embo does not. A user who wants parallel agents working on
independent slices without stepping on each other's files has no
isolation in embo today.

## Goal

Let embo run agent work in an isolated git worktree so parallel or
risky agent operations do not mutate the user's main working tree,
matching the isolation the rest of the field offers — WITHOUT abandoning
embo's focused (not swarm) agent model.

## Prior art to study (verified live 2026-09-04)

- **Superpowers** `using-git-worktrees` skill: creates an isolated
  workspace on a new branch, runs project setup, verifies a clean test
  baseline; `finishing-a-development-branch` cleans it up.
  (github.com/obra/superpowers)
- **OMC** "Native Team Worktree Mode": worktree behind an opt-in/config
  gate; `.omc/` state lives inside the worktree (deleting the worktree
  deletes its state) unless `OMC_STATE_DIR` is set — a state-location
  gotcha embo must handle. (github.com/Yeachan-Heo/oh-my-claudecode)
- **Spec-Kit**: feature-level worktree isolation with DAG-ordered
  parallel waves. (github.com/github/spec-kit)

## Open questions for the PRD

- **Which operations** run in a worktree? All impl, only parallel test
  subagents, or a user-invoked "isolated run" mode?
- **State location** — embo's RLM state (`.claude/rlm_state/`) and
  claude-mem: do they live in the worktree or the main tree? (OMC's
  gotcha: worktree deletion nukes in-worktree state.)
- **Lifecycle** — who creates/cleans the worktree, and when? Reuse the
  `embo-deliver` branch-reconcile machinery, or a new bin wrapper?
- **Merge-back** — how does isolated work return to the main tree
  (PR, merge, cherry-pick)?
- **Fit with the focused model** — embo is deliberately NOT a swarm;
  worktrees should serve isolation/safety, not become a throughput
  swarm feature.

## Related

- Landscape verdict: `tasks/017-.../landscape-verdict-2026-09.md`
  (gap #1).
- `plugin/bin/embo-deliver` — existing branch-reconcile logic that a
  worktree lifecycle could extend.
- The `.claude/rlm_state/` location constraint (gitignored, never
  committed) interacts with worktree state placement.
