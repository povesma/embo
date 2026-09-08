# worktree-isolation (v1) - Live Test Plan

**Status**: Draft
**Tech design**: [2026-09-04-062-worktree-isolation-tech-design.md](2026-09-04-062-worktree-isolation-tech-design.md)
**Created**: 2026-09-08

Unit/fixture tests (throwaway git repos) already pass: 24 (`rlm_repl`),
13 (`embo-worktree-remove`), 11 (`embo-worktree-start`), 43
(`capture-correction`). This plan is the
**live** coverage — the real developer cycle those fixtures only
approximate — and is the canonical verification for release readiness.

## Canonical verification methods

- `manual-run-claude` — run the command in this session; assert on real
  output/side-effects.
- `manual-run-user` — needs a separate interactive Claude session the
  agent cannot start; the user runs it and confirms.

## Story Coverage

| # | Scenario | Method | Steps | Pass criteria |
|---|----------|--------|-------|---------------|
| L1 | Start derives dir + branch | manual-run-claude | `embo-worktree-start feat/t1` from the main tree | `.worktrees/feat-t1/` exists; branch `feat/t1` created; path printed |
| L2 | Shared index, no re-index | manual-run-claude | `rlm_repl status` with the worktree as CWD | State file resolves to the MAIN tree's `.claude/rlm_state/state.pkl`; full file count; no re-index |
| L3 | Real Claude session sees index | manual-run-user | launch `claude` in the worktree; run `/embo:start` | SessionStart reports the main-tree RLM index + claude-mem history |
| L4 | Two live sessions, no corruption | manual-run-user | two worktrees, both trigger an index write near-simultaneously | one write succeeds, the other reports "index busy"; index intact afterward |
| L5 | Nest guard | manual-run-claude | `embo-worktree-start feat/t2` from INSIDE a worktree | aborts with the nesting message, exit non-zero |
| L6 | Remove clean worktree | manual-run-claude | `embo-worktree-remove .worktrees/<name> --branch` on a clean, merged worktree | worktree removed + pruned; merged branch deleted |
| L7 | Remove dirty guard | manual-run-claude | leave an uncommitted tracked change, then `embo-worktree-remove` | aborts (exit 3); worktree preserved; files surfaced |
| L8 | Remove keeps unmerged branch | manual-run-claude | `--branch` on a worktree whose branch is unmerged | worktree removed; branch kept with a note (no `--force-branch`) |
| L9 | State survives delete | manual-run-claude | remove a worktree, check the main tree | `state.pkl` intact; `rlm_repl status` still works |
| L10 | Correction from a worktree | manual-run-user | in a worktree Claude session, emit a `[correction]`, then check the MAIN tree's `.claude/corrections.jsonl` | the correction is recorded in the main tree, not the worktree's `.claude/` |

## Notes

- L3 and L4 require a genuinely separate interactive `claude` session
  (SessionStart, two concurrent live agents) that cannot be launched
  from within this session — those are `manual-run-user`.
- All test worktrees live under `.worktrees/` (gitignored) and are
  removed at the end of each scenario.
