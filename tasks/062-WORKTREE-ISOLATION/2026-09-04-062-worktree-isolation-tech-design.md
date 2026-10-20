# 062: Git-Worktree Sessions with Shared Memory - Technical Design

**Status**: Draft
**PRD**: [2026-09-04-062-worktree-isolation-prd.md](2026-09-04-062-worktree-isolation-prd.md)
**Created**: 2026-09-04
**Scope**: v1 only (ride on the native worktree lifecycle; build the
missing shared-state layer + a thin lifecycle command over the native
tools). v2/fallback (embo owns the full lifecycle) is out of this
design.

## Overview

v1 makes embo's project-local state (RLM index, and by extension the
correction files) resolve to the **main tree** even when a session runs
inside a git worktree, and serializes index writes so parallel sessions
cannot corrupt the single pickle. The native `EnterWorktree` /
`ExitWorktree` tools own the worktree lifecycle; embo provides
state-sharing plus one thin command (`/embo:worktree`) that drives
those tools and adds what they leave to the user — a derived name, a
base-ref warning, and a cleanup that refuses to throw away uncommitted
work. There is no merge step: the user merges via their normal
PR/merge flow.

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
- **`embo-deliver` establishes the bin-wrapper conventions** (bare
  command, no expansion) — verified via: RLM subcall reading
  `plugin/bin/embo-deliver:205-266,334-456`, 2026-09-04. (Its
  merge/reconcile machinery is not reused. The worktree surface no
  longer uses a wrapper at all — it is a command file driving the
  native tools — so these conventions now bind only `rlm_repl` here.)

## Past Decisions (Claude-Mem)

- **#35670 / #35848** — the `bin/` wrapper pattern exists specifically
  to avoid `${...}`/`$(...)` approval prompts; any `bin/` script this
  design touches must follow it (bare command, self-resolving path, no
  expansion in the command string). The worktree surface ships as a
  command file instead, so the pattern does not apply to it.
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
3. **Worktree lifecycle command** (UX). One command file,
   `plugin/commands/worktree.md`, driving the **native**
   `EnterWorktree` / `ExitWorktree` tools: open a worktree with a
   derived name, list them, remove one safely. No auto-merge — the
   user merges via their normal PR/merge flow. (Originally two bin
   wrappers, `embo-worktree-start` / `embo-worktree-remove`; both were
   deleted — see the component section for the reasoning.)
4. **Correction-capture hook** resolves `.claude` to the main tree, so
   a correction recorded from inside a worktree is not lost when the
   worktree is removed (same primitive as the RLM resolver).

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

**New: `plugin/commands/worktree.md`** (command file) — FR-2 + FR-7

Supersedes the two bare wrappers originally designed here
(`embo-worktree-start`, `embo-worktree-remove`), which have been
deleted. **Why the change:** no comparable Claude Code project ships a
standalone shell script for worktrees — Superpowers uses a skill,
Oh-My-ClaudeCode a compiled TypeScript library for its agent swarm, and
claude-workflow-template a slash command wrapping the native
`EnterWorktree` / `ExitWorktree` tools; Spec-Kit has no worktree
support at all. Superpowers calls bypassing the native tool **"the #1
mistake — it creates phantom state your harness can't see or manage."**
The PRD already required v1 not to rebuild the native lifecycle, and
the scripts, by calling `git worktree add` / `remove` themselves, had
drifted past that. `/embo:worktree` follows
claude-workflow-template's thin-wrapper approach.

- **Tool gate (first step, before anything).** If `EnterWorktree` is
  not available in the session, the command stops and says so,
  pointing the user at manual `git worktree add` or the main tree. It
  explicitly **refuses to fall back** to raw `git worktree add` on its
  own — a worktree created outside the native tool is state the
  harness cannot see or clean up.
- `/embo:worktree <branch>` — open. Refuse to nest (compare
  `git rev-parse --path-format=absolute --git-dir` against
  `--git-common-dir`; differing means already inside a linked
  worktree). Then warn about the base ref, then call `EnterWorktree`
  with `name` = the branch with slashes replaced by hyphens
  (`feat/my-thing` → `feat-my-thing`), so the directory is
  recognisable and nobody invents a name; reusing a name resumes that
  worktree. Confirm the landing with `git branch --show-current`.
- **Base-ref warning (new, not in the script design).** Native
  worktrees branch from the **remote default branch**
  (`worktree.baseRef: "fresh"`), NOT from current HEAD. So a worktree
  opened off a feature branch will not contain that branch's work, and
  uncommitted or unpushed files will be missing inside it. The command
  states in one line which base the worktree will have and what that
  means for the files in play — above all when the current branch is
  not the default one or `git status --porcelain` is non-empty. It
  names `worktree.baseRef: "head"` as the user's remedy and **does not
  set it for them.**
- `/embo:worktree list` — `git worktree list`, reported as path +
  branch, marking the current one.
- `/embo:worktree remove [path]` — clean up, only after the work has
  landed. `ExitWorktree` with `action: "remove"` from inside the
  worktree; named from the main tree. If removal is refused for
  uncommitted or unmerged work, **do not force and do not retry with a
  force flag**: show the files via `git -C <path> status --porcelain
  -uno` and put the choice to the user (commit them, or confirm
  explicitly that they are to be discarded). Deleting the branch is a
  separate explicit `git branch -d` (which itself refuses unmerged
  work); `-D` only on an explicit request in those terms.
- **Does not:** merge (the user's normal PR/merge flow), install
  dependencies (it says so rather than guessing the command). Subagents
  never call the worktree tools — the lifecycle belongs to the session
  that opened it, and a subagent cannot exit one.
- **Enforcement caveat (load-bearing, stated plainly).** This is a
  prose-driven command file, so every safety rule above — no force, no
  `-D`, no nesting, no raw-git fallback — is an **instruction the agent
  follows**, not a mechanically enforced guarantee. The deleted scripts
  enforced the same rules with exit codes (a dirty worktree exited 3
  and removed nothing, whatever the agent intended). That is a real
  reduction in enforcement strength, not a cosmetic change, and it is
  recorded as such rather than papered over. The partial mitigation:
  the native `ExitWorktree` tool is itself the gate that refuses dirty
  removals, so the prose rule guards only against the agent routing
  around that refusal. A PreToolUse hook rejecting `--force`/`-D` on
  worktree commands would restore mechanical enforcement; it is an open
  follow-up, not part of this design.

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

### Communication Pattern — command surface (sequence)

```
/embo:worktree <branch>            # open
  0. gate: EnterWorktree available? no -> stop, say so, do NOT fall
     back to raw `git worktree add`
  1. refuse to nest: git rev-parse --path-format=absolute --git-dir
     vs --git-common-dir; differ -> already inside a worktree, stop
  2. warn on base ref: native base is the REMOTE DEFAULT branch
     (worktree.baseRef: "fresh"), not HEAD -> say what will be
     missing; name worktree.baseRef: "head" as the user's remedy,
     never set it
  3. EnterWorktree name=<branch with "/" -> "-">
  4. confirm: git branch --show-current ; report path + branch

/embo:worktree list                # show
  1. git worktree list ; report path + branch, marking the current one

/embo:worktree remove [path]       # clean up (only after work landed)
  1. inside the worktree: ExitWorktree action="remove"
     from the main tree: name the worktree to remove
  2. if removal is REFUSED for uncommitted/unmerged work -> do NOT
     force, do NOT retry with a force flag; show the files via
     git -C <path> status --porcelain -uno
  3. put the choice to the user: commit them, or confirm explicitly
     that they are to be discarded
  4. branch deletion is a SEPARATE explicit step: git branch -d
     (refuses unmerged); -D only if the user asks in those terms
```

**Definition of DIRTY** (pinned): "dirty" means `git status --porcelain
-uno` reports any line — staged or unstaged changes to **tracked**
files. Untracked files (`-uno` excludes them) do NOT count, so
generated build artifacts never block removal. The command uses this
same `-uno` form when surfacing files after a refused removal.

**No merge, by design.** Removal does not merge, test, or touch any base
branch — those are the user's normal PR/merge workflow. This is the
scope correction from live testing: an auto-merging "finish" command
was built, then cut because interactive worktree use merges via PR like
any other branch, so the automation solved a problem the user does not
have. Only open, list, and remove remain — as the three modes of one
command.

### Integration Points

- `rlm_repl.py` state resolution — the one code site every RLM caller
  flows through (verified: wrapper delegates to it).
- `capture-correction.sh` — resolves `.claude` to the main tree via the
  same `--git-common-dir` primitive, so corrections captured from a
  worktree are shared, not stranded.
- `.gitignore` — add `.worktrees/` so any repo-adjacent worktree (and
  the verified probe location) is never staged.

### Error Handling

- Git absent / not a repo → state resolver falls back to CWD default;
  no crash (RLM works outside git).
- Lock unavailable → exit non-zero with a clear "index busy" message;
  caller retries or waits. Never silent-overwrite.
- Remove flow: the native `ExitWorktree` refuses removal for
  uncommitted or unmerged work; the command surfaces those files and
  asks the user, removing nothing. No `--force` and no force retry;
  `-D` on the branch only on an explicit user request. (The script
  form's "exit 3" contract is gone with the script — the refusal now
  comes from the native tool, and the response to it from the command's
  instructions.)
- Tool gate: `EnterWorktree` unavailable → the command stops and
  reports; it does not substitute `git worktree add`.

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

**The worktree wrapper tests no longer exist.**
`embo-worktree-start.test.sh` (11 cases) and
`embo-worktree-remove.test.sh` (13 cases) were deleted with the
scripts they covered. `/embo:worktree` is a prose command file: it has
no executable to invoke, so it has no unit tests and cannot have any.
Its behavior — the tool gate, the nest refusal, the base-ref warning,
the no-force removal, the separate branch-delete step — is verified by
**`manual-run-claude`** only: run the command in a session and assert
on the real output and side effects. The fixture coverage that remains
is `rlm_repl.test.sh` (resolver, lock concurrency, fcntl-absent,
state-survival) and `capture-correction.test.sh` — i.e. FR-3/FR-4/FR-6,
the shared-state core, which this change does not touch.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-3: shared RLM index across worktrees | `auto-test` | unit | test.sh: worktree session resolves state path to main tree's `.claude/rlm_state/` |
| FR-3: main-tree behavior unchanged | `auto-test` | unit | test.sh: non-worktree resolves to CWD default (regression guard) |
| FR-3: serialized writes | `auto-test` | unit | test.sh: second concurrent writer gets "index busy" non-zero, first index intact |
| FR-4: shared claude-mem | `manual-run-claude` | integration | worktree session sees main-tree memory (claude-mem project scope) |
| FR-6: state survives worktree delete | `auto-test` | integration | test.sh: `git worktree remove` leaves main-tree state.pkl intact |
| FR-4: shared corrections | `auto-test` | unit | capture-correction.test.sh green; hook resolves `.claude` to main tree from a worktree |
| FR-2: safe remove | `manual-run-claude` | integration | `/embo:worktree remove` on a clean worktree removes it; on a dirty one it does NOT force — the files are surfaced and the choice put to the user |
| FR-2: branch delete | `manual-run-claude` | integration | branch deletion is a separate `git branch -d` step; an unmerged branch is kept, `-D` only on explicit request |
| FR-7: open + derived name | `manual-run-claude` | integration | `/embo:worktree <branch>` enters via `EnterWorktree` under the hyphenated branch name; base-ref consequence stated before entering |
| FR-7: list | `manual-run-claude` | integration | `/embo:worktree list` reports each worktree path + branch |
| NFR-4: no-nest | `manual-run-claude` | integration | invoked from inside a linked worktree, the command stops and says worktrees are opened from the main tree |
| Tool gate: no raw-git fallback | `manual-run-claude` | integration | with `EnterWorktree` unavailable, the command stops and does not run `git worktree add` |

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

- **From RLM:** RLM must keep working outside git (stdlib-only, no hard
  git dependency) — hence the fallback. (The wrapper pattern no longer
  constrains the worktree surface: there is no `embo-worktree-*`
  script, only `plugin/commands/worktree.md`.)
- **From the command form:** `/embo:worktree` can only be as safe as
  the agent reading it. Its rules are prose, not exit codes — see the
  enforcement caveat in its component section.
- **From claude-mem (#40504):** never place state inside the worktree.
- **The branch-shaped-index tradeoff** (PRD): v1 shares one index
  read-mostly; sessions on diverged branches may see foreign symbols.
  v1 accepts this; a per-branch index namespace is **deferred** (not
  designed here) — flagged for a future task if it bites.

## Files to Create/Modify

**Create**:
- `plugin/commands/worktree.md` — `/embo:worktree` with three modes:
  `<branch>` (open), `list`, `remove [path]`. No test file: a prose
  command has no executable to test (verified by `manual-run-claude`).
- `plugin/rlm_scripts/rlm_repl.test.sh` — resolver + lock + fcntl-absent
  + state-survival coverage.

**Delete** (superseded by the command file):
- `plugin/bin/embo-worktree-start` (+ `.test.sh`, 11 cases).
- `plugin/bin/embo-worktree-remove` (+ `.test.sh`, 13 cases).

**Modify**:
- `plugin/rlm_scripts/rlm_repl.py:56` and its state-path call sites —
  add `resolve_state_path()` + `index_write_lock()`.
- `plugin/hooks/capture-correction.sh` — resolve `.claude` to the main
  tree.
- `.gitignore` — add `.worktrees/`.

## Dependencies

**External**: git (already required); Python stdlib `fcntl` (POSIX).
**[assumption, verify at impl]** `fcntl` is POSIX-only — Windows needs
`msvcrt.locking` or a portable fallback; confirm the Windows story at
impl (embo supports Windows per README).

**Internal**: none beyond git. (The removed finish flow would have
reused `embo-deliver`; the remove helper does not.)

## Security Considerations

No new external surface. The worktree command drives the native
worktree tools plus read-only local git (`rev-parse`, `status`,
`worktree list`, `branch --show-current`); it never force-removes a
worktree, and deletes a branch only via `git branch -d` unless the user
explicitly asks for `-D`. Because those are prose rules rather than
script guards, they bound the command's *intent*, not the agent's
capability — see the enforcement caveat. The lock is advisory and
local.

## Performance Considerations

State resolution adds one `git rev-parse` per `rlm_repl` startup
(negligible). Read paths take no lock (no contention on the common
case). The shared index avoids a full re-index per worktree — the
performance win that motivates FR-3.

## Rollback Plan

Each change is independent and revertible: the resolver falls back to
today's exact behavior when git is absent, so reverting it restores the
status quo; the lock only affects write paths; the worktree command is
a new file that changes nothing until invoked.

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
