# 062: Git-Worktree Sessions with Shared Memory - PRD

**Status**: Draft
**Created**: 2026-09-04
**Author**: Claude (via embo hybrid analysis)

---

## Chosen Scope (v1) — build on native `claude --worktree`

**v1 rides on native Claude Code for the worktree lifecycle and adds
only the layer native CC does not provide.** Native `claude --worktree`
already creates the worktree, branch, checkout, and isolated session in
one command; embo must not rebuild that. What embo adds on top:

1. **Shared RLM index across worktrees** — a native-created worktree
   has no `.claude/rlm_state/`; embo wires each worktree session to the
   main tree's index so no re-index is needed. (FR-3)
2. **Shared claude-mem memory across worktrees** — same anchoring. (FR-4)
3. **State-survival guarantee** — embo state never lives inside a
   deletable worktree. (FR-6)
4. **A thin, docs-first local merge-back flow** — test → merge into the
   local integration branch → conservative cleanup, which native CC
   does not opinionate. (FR-2)
5. **Start-side ergonomics** — a `start` helper that creates a
   repo-adjacent worktree with a **derived** name (from the branch, so
   the user need not invent one) and a `list` that shows existing
   worktrees + their branches, so the user never hand-tracks them.
   Native `claude --worktree` remains fully supported; this removes the
   naming/tracking friction it leaves. (FR-7)

**Out for v1:** embo does NOT build worktree setup/isolation mechanics
(FR-1 as originally written) — that is native CC's job and is listed
below only for the fallback. Subagent isolation (FR-5) stays a
secondary, opt-in item.

**Fallback (v2, only if building on native CC proves unworkable):**
embo owns the full lifecycle as specified in the body below. The full
spec is retained here as the reference for that fallback — treat FR-1
and the setup user story as fallback-only unless v1 hits a wall.

### State Discovery and Write Model (v1 — load-bearing)

The whole v1 bet rests on two questions the rest of the PRD must not
leave open:

**Discovery — how a worktree session finds the main tree's state.**
A session launched inside a worktree at `/path/repo-wt/feat-x/` must
resolve embo's canonical state location, which lives beside the main
tree's `.git`. Git already exposes this from any worktree:
`git rev-parse --git-common-dir` returns the shared `.git` directory
(the main tree's), while `--git-dir` returns the per-worktree one.
**Requirement:** any embo hook or bin wrapper that reads or writes
state (RLM index, claude-mem, corrections) MUST resolve the state root
from `git rev-parse --git-common-dir` (its parent is the main tree
root), never from `$PWD` or `--git-dir`. This is the single discovery
primitive; the tech-design verifies it behaves as stated.

**Write model — what happens when N sessions touch one index.**
`.claude/rlm_state/state.pkl` is a single pickle file; concurrent
writes from parallel sessions (the exact v1 use pattern) would let the
last writer silently erase the others. v1 resolves this by making the
shared index **read-mostly with serialized writes**:

- Worktree sessions treat the shared RLM index as **read-only** for
  normal operation; they do not auto re-index.
- Any operation that *writes* the index (an explicit `init-repo` /
  re-index) acquires a **file lock** on the state root and runs to
  completion before another writer proceeds; a session that cannot get
  the lock reports "index busy" rather than writing.
- claude-mem writes are already serialized by claude-mem's own store;
  v1 relies on that and does not add a second lock. **[assumption,
  verify in tech-design]**

**Known tradeoff — the index is branch-shaped.** An RLM index reflects
one file tree; parallel worktrees are on *different* branches, so a
shared index can show Session B symbols that exist only on Session A's
branch. v1 accepts this as a best-effort performance optimization
(skip re-index when branches are close); the tech-design decides
whether diverged branches get a per-branch index namespace or a
re-index-on-demand. This is called out here so tech-design treats it as
a decision, not a surprise.

---

## Wider Context / Higher Goal

The 2026-09-04 competitor landscape refresh identified git-worktree
isolation as embo's single clearest capability gap. But two facts
reframe it. First, the seed framed the gap as *subagent* isolation,
and live research (2026-09) shows that lane is either already owned
(native Claude Code `--worktree`, OMC Team Mode) or deliberately not
built (Spec-Kit chose sub-agents over worktrees for parallel tasks).
Second, native `claude --worktree` already provides the worktree
lifecycle (setup, branch, isolated session) — so the gap embo should
fill is NOT worktree mechanics but the layer native CC lacks: a
**shared index and memory across parallel worktrees**, plus a
docs-first local merge-back. See "Chosen Scope (v1)" above.

The real motivation, stated by the maintainer who will use this:
**"I don't start simultaneous Claude Code sessions on different
features because it's a pain to spin up the workflow and then merge it
back to `dev` locally."** The feature exists to remove that friction —
make parallel local worktree sessions cheap to start and painless to
merge back locally — and to do it with the one thing no competitor
offers: **a shared codebase index (RLM) and shared cross-session
memory (claude-mem) across all the parallel worktrees.**

## Context

A developer working several features of one repo at once cannot do so
in a single working tree — the branches collide. Git worktrees solve
this (one repo, multiple checked-out branches in separate
directories), and every major peer framework wraps them. embo does
not, so its users either serialize their work or hand-manage worktrees
with raw git — including the error-prone local merge-back.

Two distinct problems hide under "worktree isolation," and research
separates them sharply:

1. **Parallel developer sessions** (the primary problem): N Claude Code
   instances, each on a different feature of the same repo, each in its
   own worktree. Mainstream use case; the friction is setup + local
   merge-back, not conflicts.
2. **Parallel subagent isolation** (a narrower, secondary problem):
   within one `/embo:impl` session, write-capable subagents running
   concurrently in a shared tree can silently overwrite each other's
   files.

### Current State (observed)

- embo maintains four project-local, gitignored state stores:
  RLM index, embo runtime state, and two correction files —
  verified via: `.gitignore:29,33,36,39`
  (`.claude/rlm_state/`, `.claude/embo_state/`,
  `.claude/correction-curation.json`, `.claude/corrections.jsonl`),
  2026-09-04.
- RLM state path is `.claude/rlm_state/state.pkl` (pickle, stdlib) —
  verified via: RLM subcall reading `rlm_scripts/rlm_repl.py:56`,
  2026-09-04.
- `embo-deliver` already reconciles the working tree onto a target
  branch without force-reset (`git switch`, `git switch -c <b> <base>`),
  refuses protected branches as push targets, and is idempotent on all
  side effects — verified via: RLM subcall reading
  `plugin/bin/embo-deliver:205-266,334-456`, 2026-09-04.
- `embo-deliver` already carries a git-worktree upstream-tracking fix:
  `git worktree add -b <b> ... origin/main` auto-tracks the base, so a
  plain push fails on name mismatch; it uses `git push -u` to re-point —
  verified via: RLM subcall reading `plugin/bin/embo-deliver:289-298`,
  2026-09-04.
- Subagents are spawned via the Task tool and receive injected
  behavioral rules from a SubagentStart hook (`subagent-rules.sh`);
  they inherit no session context — verified via: RLM subcall reading
  `plugin/hooks/subagent-rules.sh:1-58`, 2026-09-04.
- embo runs all subagents in the same working tree as the main session
  (no isolation today) — verified via: `tasks/062-WORKTREE-ISOLATION/SEED.md:9-16`,
  2026-09-04.

### Past Similar Features (from claude-mem)

- Task 038 (`embo-deliver`, one-shot git delivery): established the
  branch-reconcile + idempotent-side-effect machinery this feature
  extends. Lesson: name the true destination branch as authoritative;
  never trust the ambient checkout.
- Task 044 / 055 (subagent utilization + rule inheritance): established
  how subagents are dispatched and how rules reach them — the injection
  point a subagent-isolation mode would extend.

## Problem Statement

**Who**: A developer (starting with the embo maintainer) working more
than one feature of a single repository concurrently with Claude Code.
**What**: Running parallel sessions requires manual git-worktree setup
and a fiddly, error-prone local merge back into an integration branch;
the cost is high enough that they simply don't do it.
**Why**: Lost parallelism — features are serialized that could run at
once — and, secondarily, silent overwrite of work when write-capable
subagents share one tree.
**When**: Any time more than one independent slice of work is in flight.

## Goals

### Primary Goal

Let a developer start a parallel Claude Code session in an isolated
git worktree with one command, and finish it — merge back into a local
integration branch and clean up — with one command, while **all
parallel worktrees share the same RLM index and claude-mem memory**.

### Secondary Goals

- Offer opt-in worktree isolation for **write-capable** parallel
  subagents within one session, where silent-overwrite risk is real.
- Reuse `embo-deliver`'s branch-reconcile and idempotency machinery
  rather than building a parallel lifecycle.
- Keep embo's focused (not swarm) model: worktrees serve
  isolation/safety and parallel human sessions, not automated fan-out.

## User Stories

### Epic

As a developer running Claude Code on one repo, I want to work several
features in parallel isolated worktrees that share embo's index and
memory, so that I get true parallelism without manual git-worktree
bookkeeping or a painful local merge-back.

### User Stories

1. **As a** developer starting a second feature
   **I want** a session started in a native worktree to automatically
   share the main tree's index and memory
   **So that** I get parallel work without re-indexing or manual state
   setup.

   > **v1 note:** worktree creation itself is native CC's job
   > (`claude --worktree <branch>`); embo does NOT build it. This story
   > is embo's shared-state wiring that activates in the native-created
   > worktree. The original "one command creates + installs deps +
   > baseline" criteria are **v2 / fallback only** (see FR-1) and are
   > listed under Story 1b below for that fallback.

   **Acceptance Criteria (v1)**:
   - [ ] When a session runs inside a worktree created by
     `claude --worktree`, embo's state wiring activates without a
     separate embo command.
   - [ ] The worktree session resolves the shared state root via
     `git rev-parse --git-common-dir` (not `$PWD`) and sees the **same**
     RLM index and claude-mem history as the main tree — no re-index.
   - [ ] The shared index is read-only from the worktree session by
     default (per the Write Model); it is not auto re-indexed.

1b. **(v2 / fallback only)** **As a** developer starting a second feature
   **I want** one embo command that creates an isolated worktree,
   installs dependencies, and confirms a clean baseline
   **So that** I can begin parallel work without native CC.

   **Acceptance Criteria (v2 / fallback)**:
   - [ ] A single command creates a worktree under a git-ignored
     default location on a new branch from the chosen base.
   - [ ] It refuses to nest (detects it is already inside a worktree
     and stops) rather than creating a worktree-in-a-worktree.
   - [ ] It installs project dependencies and runs the baseline test
     suite, reporting "ready" only on a clean baseline.

2. **As a** developer finishing a feature in a worktree
   **I want** one command that merges it into a local integration
   branch and cleans up
   **So that** I never hand-manage checkout order, branch deletion, or
   the "branch already checked out elsewhere" error.

   **Acceptance Criteria**:
   - [ ] The finish flow runs tests on the feature branch, aborts if
     red, and does not merge.
   - [ ] It locates whichever checkout owns the integration branch and
     merges from there; it never force-checks-out a branch held by
     another worktree.
   - [ ] It re-runs tests on the **merged result** before any cleanup;
     a red merge preserves the worktree and stops.
   - [ ] Cleanup order is: remove worktree, prune, then delete branch —
     and only for worktrees embo created.
   - [ ] It never force-removes a dirty worktree or force-deletes an
     unmerged branch; uncommitted work is surfaced and the user is
     asked.
   - [ ] The finish flow offers, at minimum: merge locally / push +
     open PR / keep as-is (user chooses; never automatic).

3. **As a** developer running write-capable subagents in parallel
   **I want** embo to isolate those subagents in their own worktrees
   **So that** two subagents editing the same file cannot silently
   overwrite each other.

   **Acceptance Criteria**:
   - [ ] Worktree isolation for subagents is opt-in and applies only to
     **write-capable** subagents; read-only agents (session-scout,
     rlm-subcall, examine-advisor) run in place.
   - [ ] `git worktree add` calls for subagents are serialized, not
     fired concurrently (avoids the `.git/config.lock` race).
   - [ ] Each isolated subagent's result is merged back or surfaced to
     the parent deterministically.

4. **As a** developer whose worktree gets cleaned up
   **I want** embo's index and memory state to survive worktree deletion
   **So that** removing a worktree never destroys my RLM index or
   claude-mem history.

   **Acceptance Criteria**:
   - [ ] embo's state stores (RLM index, memory, corrections) are
     anchored to the main tree / a stable location, never written
     inside a worktree that gets deleted.
   - [ ] Deleting a worktree leaves the shared index and memory intact
     and usable by remaining sessions.

## Requirements

### Functional Requirements

1. **FR-1**: One-command worktree session setup (create + deps +
   baseline + shared-state wiring).
   - **Priority**: High
   - **Rationale**: The setup half of the maintainer's stated friction.
   - **Dependencies**: git worktree; project dependency manager
     detection; RLM/claude-mem state anchoring.

2. **FR-2**: One-command local finish flow (test → locate base owner →
   merge → re-test merged → conservative cleanup), with a
   user-chosen finish menu.
   - **Priority**: High
   - **Rationale**: The merge-back half — the primary stated pain.
   - **Dependencies**: `embo-deliver` reconcile/idempotency machinery.

3. **FR-3**: Shared RLM index across all worktrees of one repo.
   - **Priority**: High
   - **Rationale**: The core differentiator; no competitor shares an
     index across parallel sessions.
   - **Dependencies**: state-anchoring design; RLM state location.

4. **FR-4**: Shared claude-mem memory across all worktrees of one repo.
   - **Priority**: High
   - **Rationale**: Second half of the differentiator.
   - **Dependencies**: claude-mem project scoping; state anchoring.

5. **FR-5**: Opt-in worktree isolation for write-capable parallel
   subagents, with serialized creation.
   - **Priority**: Medium (justified by evidence, but narrow)
   - **Rationale**: Silent-overwrite of shared-tree writes is common
     and unrecoverable, but only for write-capable agents.
   - **Dependencies**: SubagentStart hook / dispatch; FR-1 mechanics.

6. **FR-6**: State-survival guarantee — embo state never lives inside a
   deletable worktree.
   - **Priority**: High
   - **Rationale**: The OMC gotcha, confirmed; violating it destroys
     the index/memory on cleanup.
   - **Dependencies**: FR-3, FR-4.

7. **FR-7**: Start-side ergonomics — `start` creates a repo-adjacent
   worktree with a name derived from the branch (no user-invented
   name); `list` shows existing worktrees + branches for tracking.
   - **Priority**: Medium (removes real friction; native
     `claude --worktree` remains supported).
   - **Rationale**: Native setup leaves the user to invent names and
     hand-track worktrees — the "spin-up" friction the PRD names.
   - **Dependencies**: git worktree; `.worktrees/` default location.

### Non-Functional Requirements

1. **NFR-1**: Safety — never `--force` a worktree removal, never `-D`
   an unmerged branch, never force-checkout a branch held elsewhere;
   uncommitted work is always surfaced, never silently discarded.
2. **NFR-2**: Performance — per-worktree dependency cost minimized
   (e.g. content-addressed store / shared venv where the ecosystem
   supports it); worktrees share one `.git` (no full clone).
3. **NFR-3**: Idempotency — setup and finish are safe to re-run; a
   partial failure leaves a recoverable state, matching `embo-deliver`.
4. **NFR-4**: No-nest — the setup command detects existing isolation
   and refuses to create a worktree inside a worktree.

### Technical Constraints

- Must integrate with: `embo-deliver` (branch reconcile, idempotent
  side effects, the existing worktree upstream-tracking fix).
- Should follow patterns: bare `bin/` wrappers invoked as plain
  commands (no `${...}`/`$(...)`) to stay auto-approved; explicit file
  staging (never `git add -A`/`.`).
- Cannot change: `.gitignore` entries that keep state out of git;
  claude-mem worker-runtime tooling (no server-beta migration here);
  the no-force safety rules.
- The exact native `claude --worktree` cleanup-sweep semantics are
  **[assumption, verify in tech-design]** (research came from search
  snippets; native auto-GC has open bugs deleting dirty work, so embo
  should not rely on it).

## Out of Scope

- Automated swarm / fan-out parallelism (embo stays focused, not swarm).
- Per-subagent isolation for **read-only** agents (cost without benefit).
- Remote-first PR workflows as the primary path (local merge-back is
  the point; PR remains an offered option).
- A GUI/TUI worktree dashboard (Claude Squad / Conductor territory).
- Cross-*developer* shared memory (this is cross-*worktree*, one dev,
  one machine; multi-developer sharing is the claude-mem server-beta
  migration, tracked separately).

## Success Metrics

1. Starting a parallel feature session: from N manual steps to **1
   command**, reaching a verified clean baseline.
2. Finishing a feature locally: from manual multi-step git to **1
   command**, with **zero** force operations and zero lost uncommitted
   work in the finish flow.
3. Worktree deletion destroys **0** shared index/memory state.
4. The maintainer actually runs parallel sessions (the behavior the
   friction currently prevents) — qualitative adoption signal.

## References

### From Codebase (RLM)

- `plugin/bin/embo-deliver` — branch reconcile, idempotent side
  effects, existing worktree upstream-tracking fix (extend, don't
  duplicate).
- `plugin/hooks/subagent-rules.sh` — subagent dispatch/rule-injection
  point (FR-5 extends this).
- `plugin/rlm_scripts/rlm_repl.py:56` — RLM state path (FR-3/FR-6).
- `.gitignore:29,33,36,39` — the four state stores that must stay
  anchored (FR-6).

### From History (Claude-Mem)

- #40653 / #40603 — task 062 seed and gap identification.
- #40504 — OMC worktree architecture and the state-location gotcha.

### From Live Research (2026-09, competitor + real-world)

- Superpowers `using-git-worktrees` + `finishing-a-development-branch`
  skills — the proven setup and local-finish contract embo copies
  (no-nest, `.worktrees/` default, deps+baseline, user-chosen finish
  menu, provenance-scoped never-force cleanup).
- Native Claude Code `--worktree` — proves one-command setup; its
  auto-GC has open bugs (#46444, #74719) deleting dirty work → embo's
  cleanup must be conservative.
- Anthropic agents/worktrees docs + issues #34645, task-master #1567,
  practitioner reports — subagent shared-tree overwrite is COMMON and
  silently unrecoverable, justifying FR-5 but scoping it to
  write-capable agents and requiring serialized `git worktree add`.
- Field gap: **no competitor shares index/memory across parallel
  worktree sessions** — FR-3/FR-4 are the differentiator.

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/embo:tech-design` to create the technical design
3. Run `/embo:tasks` to break down into tasks
