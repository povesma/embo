# worktree-isolation (v1) - Live Test Plan

**Status**: Draft
**Tech design**: [2026-09-04-062-worktree-isolation-tech-design.md](2026-09-04-062-worktree-isolation-tech-design.md)
**Created**: 2026-09-08

Unit/fixture tests (throwaway git repos) already pass: 24 (`rlm_repl`),
43 (`capture-correction`). The 24 worktree-wrapper tests
(13 `embo-worktree-remove` + 11 `embo-worktree-start`) are **gone**:
both scripts were deleted in 2026-10 and replaced by the prose command
`/embo:worktree`, which has no executable to unit-test. So the
worktree surface is covered here only — `manual-run-claude` is its
sole verification method. This plan is the **live** coverage — the
real developer cycle those fixtures only approximate — and is the
canonical verification for release readiness.

## Canonical verification methods

- `manual-run-claude` — run the command in this session; assert on real
  output/side-effects.
- `manual-run-user` — needs a separate interactive Claude session the
  agent cannot start; the user runs it and confirms.

## Story Coverage

| # | Scenario | Method | Steps | Pass criteria |
|---|----------|--------|-------|---------------|
| L1 | Open derives the worktree name | manual-run-claude | `/embo:worktree feat/t1` from the main tree | enters via `EnterWorktree` with name `feat-t1` (slashes → hyphens); the base-ref consequence is stated BEFORE entering; landing path + branch reported |
| L1b | Tool gate, no raw-git fallback | manual-run-claude | `/embo:worktree feat/t1` in a session where `EnterWorktree` is unavailable | stops with the "worktree tools not available" message; does NOT run `git worktree add` |
| L2 | Shared index, no re-index | manual-run-claude | `rlm_repl status` with the worktree as CWD | State file resolves to the MAIN tree's `.claude/rlm_state/state.pkl`; full file count; no re-index |
| L3 | Real Claude session sees index | manual-run-user | launch `claude` in the worktree; run `/embo:start` | SessionStart reports the main-tree RLM index + claude-mem history |
| L4 | Two live sessions, no corruption | manual-run-user | two worktrees, both trigger an index write near-simultaneously | one write succeeds, the other reports "index busy"; index intact afterward |
| L5 | Nest refusal | manual-run-claude | `/embo:worktree feat/t2` from INSIDE a linked worktree | compares `--git-dir` against `--git-common-dir`, stops, says worktrees are opened from the main tree; no worktree created |
| L5b | List | manual-run-claude | `/embo:worktree list` | each worktree reported with its branch; the current one marked |
| L6 | Remove clean worktree | manual-run-claude | `/embo:worktree remove` on a clean worktree whose work has landed (from inside it, and again by path from the main tree) | removed via `ExitWorktree` `action: "remove"`; branch deletion offered only as a separate explicit `git branch -d` step |
| L7 | Remove refuses to force | manual-run-claude | leave an uncommitted tracked change, then `/embo:worktree remove` | removal is refused; the command does NOT force and does NOT retry with a force flag; files surfaced via `git -C <path> status --porcelain -uno`; the choice (commit vs. explicitly discard) is put to the user; nothing removed |
| L8 | Unmerged branch kept | manual-run-claude | after removing a worktree whose branch is unmerged, attempt the branch delete | `git branch -d` refuses; branch kept; `-D` is NOT used absent an explicit user request in those terms |
| L8b | Base-ref warning is accurate | manual-run-claude | with `worktree.baseRef` left at `"fresh"`, open a worktree from a non-default branch with uncommitted files present | the command warns BEFORE entering that the worktree branches from the remote default branch and will lack that branch's work and the uncommitted files; it names `worktree.baseRef: "head"` as the remedy and does not set it |
| L9 | State survives delete | manual-run-claude | remove a worktree, check the main tree | `state.pkl` intact; `rlm_repl status` still works |
| L10 | Correction from a worktree | manual-run-user | in a worktree Claude session, emit a `[correction]`, then check the MAIN tree's `.claude/corrections.jsonl` | the correction is recorded in the main tree, not the worktree's `.claude/` |

## Notes

- L3 and L4 require a genuinely separate interactive `claude` session
  (SessionStart, two concurrent live agents) that cannot be launched
  from within this session — those are `manual-run-user`.
- The native `EnterWorktree` tool chooses the worktree directory, so
  the path is no longer embo's to pick; `.worktrees/` stays gitignored
  for hand-made worktrees. Every test worktree is removed at the end of
  its scenario.
- No row here can be promoted to `auto-test`: `/embo:worktree` is a
  prose command file with no executable, so its safety rules (no force,
  no `-D`, no nesting, no raw-git fallback) are agent-followed
  instructions. These live runs are the only evidence that they hold.
