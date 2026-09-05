# 062: Git-Worktree Sessions with Shared Memory - Technical Design

**Status**: Draft
**PRD**: [2026-09-04-062-worktree-isolation-prd.md](2026-09-04-062-worktree-isolation-prd.md)
**Created**: 2026-09-04
**Scope**: v1 only (ride on native `claude --worktree`; build the
missing shared-state layer + thin local merge-back). v2/fallback
(embo owns the full lifecycle) is out of this design.

## Overview

v1 makes embo's project-local state (RLM index, and by extension the
correction files) resolve to the **main tree** even when a session runs
inside a git worktree, and serializes index writes so parallel sessions
cannot corrupt the single pickle. Native `claude --worktree` provides
the worktree; embo provides state-sharing and a docs-first local
merge-back that reuses `embo-deliver`'s reconcile machinery.

The design rests on two facts verified this session (below), so the
core mechanism is not speculative: the state path is CWD-relative today
(so it breaks in a worktree), and `git rev-parse --git-common-dir`
reliably points back to the main tree from any worktree (so it is the
fix).

## Current Architecture (RLM-verified)

Each inherited PRD fact re-verified this session:

- **RLM state path is CWD-relative** — `DEFAULT_STATE_PATH =
  Path(".claude/rlm_state/state.pkl")`, a *relative* path resolved
  against the process CWD — verified via: reading
  `plugin/rlm_scripts/rlm_repl.py:56`, 2026-09-04. **Consequence:** a
  process run inside a worktree writes/reads the *worktree's*
  `.claude/rlm_state/`, not the main tree's. This is the bug v1 fixes.
- **The `rlm_repl` wrapper does not change CWD and resolves the state
  path relative to the caller** — verified via: reading
  `plugin/bin/rlm_repl:13-16,26-31`, 2026-09-04. It resolves the
  *script* location via symlink-following but leaves state resolution
  to `rlm_repl.py`. So fixing resolution in `rlm_repl.py` covers every
  caller, wrapper or not.
- **`git rev-parse --git-common-dir` returns the main tree's `.git`
  from inside a worktree; `--show-toplevel` returns the WORKTREE's own
  root** — verified live 2026-09-05: from a linked worktree,
  `--path-format=absolute --git-common-dir` → `<main>/.git` (main
  tree), `--git-dir` → `<main>/.git/worktrees/<name>` (per-worktree),
  and `--show-toplevel` → `<worktree>` (NOT the main tree). **The main
  root is `parent(absolute --git-common-dir)`** — `--show-toplevel`
  must NOT be used for this.
- **In the main (non-worktree) tree, `--git-dir` == `--git-common-dir`
  (both `.git`)** — verified via: `git rev-parse --git-dir
  --git-common-dir` in the repo root, 2026-09-04. This equality is the
  detector for "am I in a worktree" (they differ iff linked worktree).
- **`embo-deliver` reconcile + idempotency machinery** exists and is
  reusable for the merge-back finish flow — verified via: RLM subcall
  reading `plugin/bin/embo-deliver:205-266,334-456`, 2026-09-04.

## Past Decisions (Claude-Mem)

- **#35670 / #35848** — the `bin/` wrapper pattern exists specifically
  to avoid `${...}`/`$(...)` approval prompts; any new bin wrapper for
  the finish flow must follow it (bare command, self-resolving path, no
  expansion in the command string).
- **#40504** — OMC keeps its state inside the worktree and loses it on
  cleanup unless `OMC_STATE_DIR` is set. v1's whole point is to avoid
  this: state resolves to the main tree, so worktree deletion is safe.

## Proposed Design

### Architecture

Three independent changes, smallest-blast-radius first:

1. **State resolution in `rlm_repl.py`** (core). Add a resolver that
   computes the state path from the main tree when inside a worktree,
   and keeps today's CWD-relative default otherwise.
2. **Write serialization in `rlm_repl.py`** (correctness). Guard the
   index-writing code paths with an advisory OS file lock in the state
   root.
3. **A local merge-back finish flow** (UX). A new bin wrapper that
   tests → merges into the local integration branch → cleans up
   conservatively, reusing `embo-deliver` patterns.

### Components

**Modified: `plugin/rlm_scripts/rlm_repl.py`**

- **State resolver** (new function, called where `DEFAULT_STATE_PATH`
  is currently used).
  - Detect worktree: run `git rev-parse --git-dir --git-common-dir`;
    if the two differ, we are in a linked worktree.
  - When in a worktree: main-tree root = **`git rev-parse
    --path-format=absolute --git-common-dir`** then take `.parent`;
    state root = `<main-root>/.claude/rlm_state`. Otherwise: unchanged
    CWD-relative default.
    - **Why `--git-common-dir`, NOT `--show-toplevel`** (corrected at
      impl, proven live 2026-09-05): an earlier critique suggested
      `--show-toplevel`, but from inside a worktree `--show-toplevel`
      returns the **worktree's own root**, not the main tree — which
      would defeat the whole feature. `--git-common-dir` points at the
      MAIN tree's `.git` from any worktree; its parent is the main
      working tree. The relative-vs-absolute problem the critique
      raised is solved by `--path-format=absolute`, which forces an
      absolute path so `.parent` is meaningful (verified: worktree →
      `<main>/.git` absolute; `--show-toplevel` → `<worktree>` root,
      2026-09-05).
  - **Bare-repo guard** (critique #3): if `git rev-parse
    --is-bare-repository` is `true`, or `--show-toplevel` is empty (no
    working tree), fall back to the CWD default — a bare repo has no
    main working tree to anchor to. Documented as an unsupported
    topology for shared state.
  - **Decision (user, 2026-09-04):** resolution lives in
    `rlm_repl.py`, not the wrapper — one change covers every caller.
  - **Decision (user, 2026-09-04):** the behavior change is
    **worktree-only** — the main tree keeps the exact current path, so
    existing non-worktree users see zero change (no regression risk).
  - Failure mode: if `git` is absent or the command fails (not a git
    repo), fall back to the CWD-relative default and continue — RLM
    must not hard-depend on git for the common case.
  - The explicit `--state` flag, if passed, overrides the resolver
    (preserves existing behavior for callers that set it).

- **Write lock** (guards **every** `_save_state` call).
  - **Correction (critique, verified 2026-09-04):** `_save_state` runs
    on `cmd_exec` too, not only init — verified via: `grep _save_state
    plugin/rlm_scripts/rlm_repl.py` → lines **944 (cmd_init), 994
    (cmd_init_repo), 1158 (cmd_exec)**. So the index is **NOT
    read-mostly**: every `exec` writes the pickle. The lock MUST wrap
    all three `_save_state` sites, not just init-repo. Locking only
    init would leave concurrent `exec` sessions racing on every REPL
    step — the exact failure this feature must prevent.
  - **Decision (user, 2026-09-04):** advisory OS file lock (`fcntl`),
    stdlib, crash-safe (released on process exit).
  - Lockfile lives in the resolved state root (so all worktrees of one
    repo contend on the same lock).
  - A writer that cannot acquire the lock exits non-zero with an
    "index busy" message rather than writing — never blocks
    indefinitely by default. (The atomic `tmp → rename` in
    `_save_state` prevents partial-write corruption; the lock prevents
    lost updates from concurrent sessions. Both are needed.)
  - **Windows** (critique #6, decided now — not deferred): `fcntl` is
    POSIX-only and would raise `ImportError` on Windows, crashing
    `rlm_repl`. v1 uses a **conditional import**: `try: import fcntl`
    → on failure, the lock becomes a **no-op with a one-time warning**
    ("worktree write-serialization unavailable on this platform").
    Windows worktree sessions thus degrade to unserialized writes
    (best-effort, same as today's single-tree behavior) rather than
    crash. A real Windows lock (`msvcrt.locking`) is a follow-up, not
    v1.
  - Pure read paths (`status`, queries that do not call `_save_state`)
    take no lock.

**New: `plugin/bin/embo-worktree-finish`** (bare wrapper)

- Purpose: one-command local merge-back for a worktree branch.
- Follows the wrapper pattern (self-resolving, no expansion, matches a
  `Bash(embo-worktree-finish *)` allow rule).
- Sequence (see below); reuses `embo-deliver`'s branch-reconcile and
  the "locate the checkout that owns the base" logic.

**New: `plugin/bin/embo-worktree-start`** (bare wrapper) — FR-7

- Purpose: remove native `claude --worktree`'s naming/tracking friction.
- `embo-worktree-start <branch>`: creates a worktree at
  `.worktrees/<derived-name>` on `<branch>`, where the name is derived
  from the branch (slashes → `-`, so `feat/x` → `feat-x`). Refuses to
  nest (abort if already inside a linked worktree). Prints the path.
- `embo-worktree-start --list` (or `list`): prints existing worktrees +
  their branches (`git worktree list`), so the user never hand-tracks.
- Does NOT install deps or run a baseline in v1 (that was FR-1, a
  v2/fallback concern) — it is a thin create+name+track helper only.
  Native `claude --worktree` stays fully supported alongside it.
- Follows the wrapper pattern; matches `Bash(embo-worktree-start *)`.

### Data Contracts

**State resolver** (internal to `rlm_repl.py`):

```
resolve_state_path(explicit: Optional[Path]) -> Path
  explicit given             -> explicit                   (unchanged)
  git absent / not a repo    -> CWD/.claude/rlm_state/state.pkl
  bare repo / no worktree    -> CWD/.claude/rlm_state/state.pkl  (guard)
  --git-dir == common-dir    -> CWD/.claude/rlm_state/state.pkl  (main tree)
  --git-dir != common-dir    -> parent(<abs --git-common-dir>)/.claude/
                                 rlm_state/state.pkl
                                 # git-common-dir (absolute), NOT
                                 # show-toplevel (returns worktree root)
```

**Write lock** (internal):

```
with index_write_lock(state_root):   # fcntl.flock, non-blocking
    ...write state.pkl...
  # LockUnavailable -> exit non-zero, "index busy: another session
  #                    is re-indexing <state_root>"
```

### Communication Pattern — finish flow (sequence)

```
embo-worktree-finish <base>
  1. run tests in the worktree; red -> abort, no merge
  2. resolve <base>; ensure <base> not DIRTY in its owning checkout
  3. git worktree list --porcelain -> find checkout holding <base>
       - held by a worktree, clean -> merge FROM that checkout
       - held by a worktree, dirty -> abort, ask user to finish it first
       - not checked out anywhere  -> see "base-not-checked-out" below
  4. merge the worktree branch into <base> (no force)
  5. re-run tests on the MERGED result; red -> stop, preserve worktree
  6. cleanup (only if steps 1-5 green): git worktree remove <path>
     (no --force; dirty -> abort + surface files) ; git worktree prune
  7. git branch -d <branch>   (never -D except explicit discard)
```

**Definition of DIRTY** (critique #4, pinned): "dirty" means
`git status --porcelain -uno` reports any line — i.e. staged or
unstaged changes to **tracked** files. Untracked files (`-uno`
excludes them) do NOT count as dirty, so generated build artifacts
never block a finish; matches the PRD's "uncommitted work is surfaced"
(tracked changes) intent.

**base-not-checked-out path** (critique #5, narrowed): the naive
"check out `<base>` in the main tree and merge" would mutate the
developer's live main session if the main tree is on another branch.
So:
  - main tree is CLEAN and on `<base>` already -> merge there.
  - main tree is CLEAN but on another branch -> create a **temporary
    worktree** for `<base>`, merge there, remove it (never switch the
    main tree's branch out from under a live session).
  - main tree is DIRTY -> abort; ask the user to resolve or name the
    checkout to use. Never force-checkout.

Simultaneous finish from two worktrees into the same `<base>` is
serialized at the git level: step 3's dirty-abort plus git's own
refusal to check out a branch already checked out elsewhere prevents
two concurrent merges into one base. A file lock on `<base>` is **not**
added in v1 (git's own guard suffices); revisit if real
concurrent-finish races appear.

### Integration Points

- `rlm_repl.py` state resolution — the one code site every RLM caller
  flows through (verified: wrapper delegates to it).
- `embo-deliver` — the finish flow reuses its reconcile/idempotency
  logic rather than duplicating; extend `embo-deliver` only if the
  local-merge path needs a mode it lacks (assess during impl).
- `.gitignore` — add `.worktrees/` so any repo-adjacent worktree (and
  the verified probe location) is never staged.

### Error Handling

- Git absent / not a repo → state resolver falls back to CWD default;
  no crash (RLM works outside git).
- Lock unavailable → exit non-zero with a clear "index busy" message;
  caller retries or waits. Never silent-overwrite.
- Finish flow: any red test or dirty tree → abort before any
  destructive step; the worktree and branch are preserved. No `--force`
  / `-D` anywhere except an explicit user "discard".

### Testing Strategy

Follows the repo's `*.test.sh` fixture pattern (as used by
`embo-deliver.test.sh`, `subagent-rules.test.sh`): a temp git repo,
`git worktree add` into a repo-adjacent path, assert resolved state
path and lock behavior, tear down.

**Lock test must be genuinely concurrent** (critique low #1): a
sequential fixture cannot trigger the race (the first writer finishes
before the second starts, so the second always succeeds — a vacuous
pass). The serialized-writes test MUST hold the lock open in a
**backgrounded** process (e.g. a subshell holding `flock` on the
lockfile), THEN launch the second writer and assert it exits non-zero
with "index busy". Without the backgrounded holder the test gives false
confidence.

**Finish-menu scope** (critique low #2): the PRD Story 2 offers
merge-local / push-PR / keep-as-is. v1 designs only the **merge-local**
path in full. The other two are thin dispatches at the decision point:
`pr` → `embo-deliver` in pr mode; `keep` → exit after step 5 without
cleanup. These are stubs to wire, not new machinery.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-3: shared RLM index across worktrees | `auto-test` | unit | test.sh: worktree session resolves state path to main tree's `.claude/rlm_state/` |
| FR-3: main-tree behavior unchanged | `auto-test` | unit | test.sh: non-worktree resolves to CWD default (regression guard) |
| FR-3: serialized writes | `auto-test` | unit | test.sh: second concurrent writer gets "index busy" non-zero, first index intact |
| FR-4: shared claude-mem | `manual-run-claude` | integration | worktree session sees main-tree memory (claude-mem project scope) |
| FR-6: state survives worktree delete | `auto-test` | integration | test.sh: `git worktree remove` leaves main-tree state.pkl intact |
| FR-2: local merge-back | `auto-test` | integration | test.sh: finish flow merges to base, re-tests, removes worktree, deletes branch; dirty tree aborts |
| FR-2: base-owned-elsewhere | `auto-test` | unit | test.sh: base held by another worktree → merge from there, no force-checkout |

## Trade-offs

**State resolution site** (decided: `rlm_repl.py`):
1. *Wrapper computes + passes `--state`* — keeps `rlm_repl.py`
   git-agnostic, but only covers callers going through the wrapper and
   splits the logic across two files.
2. *`rlm_repl.py` resolves (Recommended, chosen)* — one change covers
   every caller including direct `python3 rlm_repl.py`; couples RLM to
   git, mitigated by the git-absent fallback.
3. *Env var from a hook* — central but adds a hook dependency and env
   plumbing; a missing/one-off env is a silent wrong-path risk.

**Scope of behavior change** (decided: worktree-only):
- *Always resolve via git* — simpler single path, but changes behavior
  for every existing non-worktree user (regression surface).
- *Worktree-only (Recommended, chosen)* — main tree byte-for-byte
  unchanged; the new path activates only when `--git-dir !=
  --git-common-dir`.

**Write lock** (decided: fcntl advisory):
- *Lockfile presence check* — simpler but leaves stale locks on crash.
- *fcntl advisory (Recommended, chosen)* — released automatically on
  process exit, no stale-lock cleanup.

## Implementation Constraints

- **From RLM:** the wrapper pattern (no expansion, self-resolving) is
  mandatory for `embo-worktree-finish`. RLM must keep working outside
  git (stdlib-only, no hard git dependency) — hence the fallback.
- **From claude-mem (#40504):** never place state inside the worktree.
- **The branch-shaped-index tradeoff** (PRD): v1 shares one index
  read-mostly; sessions on diverged branches may see foreign symbols.
  v1 accepts this; a per-branch index namespace is **deferred** (not
  designed here) — flagged for a future task if it bites.

## Files to Create/Modify

**Create**:
- `plugin/bin/embo-worktree-finish` — local merge-back finish flow.
- `plugin/bin/embo-worktree-finish.test.sh` — fixture test.
- (extend) `plugin/rlm_scripts/` test coverage for the resolver + lock.

**Modify**:
- `plugin/rlm_scripts/rlm_repl.py:56` and its state-path call sites —
  add `resolve_state_path()` + `index_write_lock()`.
- `.gitignore` — add `.worktrees/`.

## Dependencies

**External**: git (already required); Python stdlib `fcntl` (POSIX).
**[assumption, verify at impl]** `fcntl` is POSIX-only — Windows needs
`msvcrt.locking` or a portable fallback; confirm the Windows story at
impl (embo supports Windows per README).

**Internal**: `embo-deliver` (reconcile/idempotency, reused by the
finish flow).

## Security Considerations

No new external surface. The finish flow runs only git + tests locally;
it never force-deletes or force-checks-out. The lock is advisory and
local.

## Performance Considerations

State resolution adds one `git rev-parse` per `rlm_repl` startup
(negligible). Read paths take no lock (no contention on the common
case). The shared index avoids a full re-index per worktree — the
performance win that motivates FR-3.

## Rollback Plan

Each change is independent and revertible: the resolver falls back to
today's exact behavior when git is absent, so reverting it restores the
status quo; the lock only affects write paths; the finish flow is a new
file that changes nothing until invoked.

## References

### Code (RLM)
- `plugin/rlm_scripts/rlm_repl.py:56` — state path default (the change site).
- `plugin/bin/rlm_repl:13-16` — wrapper delegates state resolution.
- `plugin/bin/embo-deliver:205-266` — reconcile logic to reuse.

### History (Claude-Mem)
- #40504 — OMC state-in-worktree gotcha (what to avoid).
- #35670/#35848 — bin wrapper pattern (what to follow).

---

**Next Steps**:
1. Review and approve design
2. Run `/embo:tasks` for task breakdown
