# 021-CONFIG-AUDIT-TRAIL: Local Change History for Claude Code Configuration — PRD

**Status**: Draft
**Created**: 2026-05-14
**Author**: Claude (via dev workflow analysis)

---

## Context

Claude Code's local configuration files (statusline, settings,
top-level config, hooks, agents, commands, profiles) are edited by
multiple actors: the user, Claude itself during sessions, the
installer, plugin updates, and occasionally external tools. These
edits are sometimes destructive and silent: a value is overwritten,
a section is removed, a hand-tuned file is replaced with the
shipped default, and the user only notices days later when
something stops working.

A concrete recent example: the claude-mem freshness indicator added
to `~/.claude/statusline.sh` on 2026-04-22 was lost without warning
and only rediscovered on 2026-05-14 — verified via: claude-mem
observations #10354–#10357 (Apr 22) and #13722 (May 14), and
`diff ~/.claude/statusline.sh ./.claude/statusline.sh` returning
identical files with no `mem:` segment, 2026-05-14. The user reports
this is **not the first such loss** and explicitly asked for a
mechanism to "keep the trace of changes of those files and be able
to find out time and the content of the change, automatically,
100% effortlessly, 100% LOCAL."

There is currently **no change-history mechanism** for these files —
verified via: `find ~/.claude -name '*.bak' -o -name '*.history*'`
returns nothing, 2026-05-14. The repo itself is git-tracked but the
user's installed `~/.claude/` tree is not — verified via:
`git -C ~/.claude rev-parse --git-dir` fails, 2026-05-14.

### Current State (observed)

- The installer copies repo files into `~/.claude/` and provides no
  rollback or pre-write snapshot — verified via: `install.sh` lines
  41–73 (agents, commands, profiles, hooks, rlm_scripts, statusline
  all copied unconditionally), 2026-05-14.
- The user-level `~/.claude/` tree contains user-edited files,
  Claude-edited files (e.g. settings.json edited via `update-config`
  skill), and installer-managed files, all mixed together — verified
  via: review of `~/.claude/settings.json` history in this session
  showing manual permission edits + installer-injected entries,
  2026-05-14.
- A claude-mem observation pattern exists where damaging
  overwrite-vs-merge issues recur — verified via: observation
  #12110 (Apr 6, 2026: "Scrape overwrites prices.json instead of
  merging, losing outbound one-way data"), illustrating the same
  failure mode in another domain.
- No `~/.claude.json` or other system-level Claude Code config
  files are inspected here because reading them requires explicit
  permission (per global rule). [assumption, verify in tech-design
  which files exist at the top level and which are user-private.]

### Past Similar Features (from claude-mem)

- No prior PRD in this repo covers configuration auditing —
  verified via: claude-mem search `query="audit trail file changes
  history backup local"` returned zero PRDs in `claude_code_RLM_mem`,
  2026-05-14.
- Loss-of-state failure modes documented previously: #12110
  (overwrite vs. merge in another tool), #13722 (the present
  motivating loss).
- Adjacent design discipline pattern: PRD-020 explicitly defers
  install.sh overwrite prevention to this PRD; the two are
  intentionally complementary (020 = restore the feature that was
  lost; 021 = make sure future losses are detectable and
  reversible).

## Problem Statement

**Who**: a developer using the RLM-Mem installation, particularly
one who customizes their local `~/.claude/` configuration.

**What**: local configuration files are silently rewritten or
damaged by various actors (installer runs, Claude edits, plugin
updates, manual edits). The user has no record of when each version
of a file existed or what it contained, so when something stops
working there is no straightforward way to find the change that
broke it, see what was there before, or restore it.

**Why**: configuration changes that take effect silently and
irreversibly produce three categories of harm — (1) lost work,
because customizations have to be redone from memory; (2) lost
debugging time, because the change that caused a regression cannot
be located; (3) lost trust in the system, because users start
hedging against silent rewrites with manual external backups.

**When**: every time a file under `~/.claude/` is created, modified,
or replaced, regardless of which actor performed the change and
whether the change was intentional.

## Goals

### Primary Goal

Every change to any tracked configuration file produces a durable,
locally-stored record from which the user can determine (a) when
the change happened, (b) what the file contained before and after,
and (c) recover the prior content as a complete file.

### Secondary Goals

- The recording happens automatically: the user does not have to
  remember to run any command, start any process, or take any
  per-session action.
- The recording is **entirely local**: no network calls, no remote
  storage, no telemetry.
- Disk usage is bounded by the actual change volume, not by the
  number of files multiplied by the number of refresh cycles —
  i.e., unchanged files cost nothing extra to keep tracked.
- Best-effort attribution is captured when feasible: when the
  recorder can identify which actor wrote the change (Claude, the
  installer, a plugin, the user via an editor), it records that;
  when it cannot, the absence is itself recorded.
- The query path uses an already-installed standard CLI tool, so
  the user does not have to learn a new command surface to
  investigate a change.

## User Stories

### Epic

As a developer whose local Claude Code configuration is edited by
multiple actors, I want a zero-touch, fully local change history of
those files, so that when something is rewritten or damaged I can
identify when and what changed and recover the prior content.

### User Stories

1. **As a** developer who has just installed RLM-Mem
   **I want** change tracking to be active from that moment on
   **So that** I don't have to remember to enable it later, and the
   very first installer-induced change is itself captured.

   **Acceptance Criteria**:
   - [ ] After `install.sh` (or `install.ps1`) completes, the audit
     system is initialized and active without further user action.
   - [ ] The first recorded entry in the audit history reflects the
     state of the tracked files immediately after the installer's
     copy step finishes — i.e. the installer's own changes are
     visible as the audit's first checkpoint.
   - [ ] Initialization is idempotent: running the installer again
     on an already-initialized system does not destroy existing
     history or duplicate entries.

2. **As a** developer investigating a regression
   **I want** to list every change to a given configuration file,
   ordered by time
   **So that** I can correlate "when did this stop working?" with
   "what changed?".

   **Acceptance Criteria**:
   - [ ] For any tracked file, a single short CLI invocation returns
     a chronological list of entries, each with at minimum: a
     timestamp and a short identifier the user can use to fetch
     details.
   - [ ] The CLI invocation uses a tool that is either already
     present on a typical macOS / Linux dev machine, or installed as
     a documented dependency of this feature.
   - [ ] The CLI surface is documented in `README.md` (or a linked
     doc) under a clearly-named heading the user can find by
     searching for terms like "history", "audit", or "what
     changed".

3. **As a** developer who has identified a suspicious change
   **I want** to see the diff between two versions of the file
   **So that** I can read precisely what was added, removed, or
   modified.

   **Acceptance Criteria**:
   - [ ] Given any two history entry identifiers for the same file,
     a single short CLI invocation produces a unified diff between
     them.
   - [ ] The diff is rendered with standard syntax (recognizable to
     anyone familiar with patch files), suitable for piping to
     `less` or sharing.

4. **As a** developer who wants to undo a damaging change
   **I want** to retrieve any historical version of a file as a
   complete file, not just as a diff
   **So that** I can restore it (manually or by copy) without
   reconstructing the content from a diff against the broken
   current version.

   **Acceptance Criteria**:
   - [ ] Given a file path and a history entry identifier, a single
     CLI invocation prints the file's contents at that point in
     time to stdout (or writes it to a chosen path).
   - [ ] Retrieval works even when the file has since been deleted
     from the live tree.

5. **As a** developer trying to determine who or what made a
   particular change
   **I want** best-effort attribution recorded alongside each entry
   **So that** when attribution is available, I can use it to
   narrow my investigation.

   **Acceptance Criteria**:
   - [ ] When the recorder can identify the writing actor by
     reliable, locally-available signal (e.g. a process name, an
     environment marker, an installer-set sentinel), that
     attribution is stored with the entry.
   - [ ] When attribution is not available, the entry is still
     stored (the change record itself takes precedence over the
     attribution metadata) and the absence is represented
     explicitly rather than fabricated.
   - [ ] Attribution heuristics are documented and tagged as
     best-effort in the tech-design; the audit is correct even
     when attribution is missing or wrong.
     [assumption, verify in tech-design — reliable cross-platform
     process attribution is non-trivial and may degrade to a
     coarse "Claude session in progress" / "outside session"
     distinction.]

6. **As a** long-time user of the system
   **I want** the audit history to be retained indefinitely
   **So that** I can investigate regressions whose root cause is
   weeks or months in the past, not just yesterday's edits.

   **Acceptance Criteria**:
   - [ ] No retention cutoff is enforced by default; the history
     grows monotonically.
   - [ ] Total disk usage of the history is bounded by the volume
     of actual change content (unchanged files do not bloat the
     archive across refreshes / scans).
   - [ ] Per-user disk usage of the audit data after one year of
     normal use remains within a budget agreed in tech-design
     (small enough not to alarm the user; large enough to retain
     full content of all changes). [assumption, verify in
     tech-design — the exact budget depends on storage mechanism
     compression.]

## Requirements

### Functional Requirements

1. **FR-1**: The system MUST automatically record a change-history
   entry whenever any tracked configuration file is created,
   modified, or removed.
   - **Priority**: High
   - **Rationale**: The whole point of the feature.
   - **Dependencies**: A local change-detection mechanism (file
     watcher, periodic scan, or pre/post-write hook). Choice is a
     tech-design concern.

2. **FR-2**: Each recorded entry MUST include at minimum: a
   timestamp, a stable reference to the prior content of the file,
   and a stable reference to the new content of the file (such that
   either content can be retrieved or a diff between them
   computed).
   - **Priority**: High
   - **Rationale**: Without these three, none of the investigation
     workflows in User Stories 2–4 are possible.

3. **FR-3**: Each recorded entry SHOULD include best-effort
   attribution metadata identifying the writing actor when locally
   determinable.
   - **Priority**: Medium
   - **Rationale**: Attribution accelerates investigation but is
     not required for correctness; the audit must function even
     when attribution is unavailable.

4. **FR-4**: The set of tracked files MUST cover the
   configuration surface that has historically suffered silent
   rewrites, at minimum the user-level Claude Code configuration
   tree.
   - **Priority**: High
   - **Rationale**: The motivating loss was in this tree
     (statusline). Picking the precise file list is a
     tech-design decision; this PRD scopes the *class* of files,
     not the enumeration. [assumption, verify in tech-design which
     specific files within the user-level tree are in / out of
     scope, particularly with respect to volatile state files that
     would dominate the history with noise.]

5. **FR-5**: The system MUST be initialized and started by the
   existing installers (`install.sh`, `install.ps1`) without
   requiring an additional user step.
   - **Priority**: High
   - **Rationale**: Per the user's explicit "zero touch"
     requirement.

6. **FR-6**: The query / inspection path MUST be a standard,
   widely-installed CLI tool (or a documented dependency of the
   audit feature), not a new bespoke command added to this repo's
   `dev/` command tree.
   - **Priority**: High
   - **Rationale**: Per the user's explicit "pure CLI" choice. A
     bespoke command would expand the surface area without adding
     investigative power.

7. **FR-7**: The system MUST NOT make any network calls and MUST
   NOT write any data outside the user's local machine.
   - **Priority**: High
   - **Rationale**: Per the user's explicit "100% LOCAL"
     requirement.

8. **FR-8**: The system MUST be idempotent and tolerant of being
   started multiple times (e.g. re-running the installer); existing
   history MUST NOT be destroyed by re-initialization.
   - **Priority**: High
   - **Rationale**: Installers are run repeatedly; losing history
     because of an installer run would defeat the feature on a
     stress event that matters.

9. **FR-9**: When change detection fails (e.g. watcher process not
   running, scan interrupted, disk full), the system MUST surface
   the failure to the user via a visible signal at session start.
   - **Priority**: Medium
   - **Rationale**: Silent failure of an audit system is itself a
     silent failure mode the audit is supposed to prevent.

### Non-Functional Requirements

1. **NFR-1**: Performance — the change-recording path must not
   measurably slow down statusline refresh, file save operations
   in normal editors, or installer runtime.
2. **NFR-2**: Privacy — only loopback / local-filesystem operations
   are permitted. No outbound network traffic; no transmission of
   file contents anywhere.
3. **NFR-3**: Storage efficiency — historical entries that differ
   by a small change from prior entries must take storage
   proportional to the change, not to the whole file (i.e.
   delta-style storage).
4. **NFR-4**: Robustness — corrupted, partial, or in-progress
   writes by external actors must not corrupt the audit store. The
   audit store must be safe to read while writes are in progress.
5. **NFR-5**: Portability — must operate on macOS (BSD userland)
   and Linux (GNU userland); Windows / PowerShell parity is a
   goal but may follow a different implementation path.
   [assumption, verify in tech-design that Windows can be supported
   with the same backing tool or whether a parallel implementation
   is required.]

### Technical Constraints

- Must integrate with: the existing `install.sh` / `install.ps1`
  flow (extend, do not replace).
- Should follow patterns: documented, jq-style, single-purpose,
  no-dependencies-where-avoidable, same as the rest of the repo's
  install footprint.
- Cannot change: the layout of `~/.claude/` itself — the audit
  store must live somewhere it cannot interfere with the files it
  is auditing, but also must be discoverable.
- Cannot read: any file the user has not authorized — including
  `~/.claude.json` whose contents have not been read in this PRD
  session. The audit's scope must be explicitly opted into per
  file class, with safe defaults. [assumption, verify in
  tech-design with the user that `~/.claude.json` should be
  in-scope despite being outside `~/.claude/`.]

## Out of Scope

- Preventing the destructive change from happening in the first
  place (e.g. a write-lock on customized files, an installer
  diff-prompt before overwriting). The user's request is
  specifically to **trace** changes, not block them. Prevention
  is a candidate follow-up but not v1.
- Cross-machine sync of the audit history.
- Pruning, compaction, or retention policy beyond "indefinite,
  delta-stored, locally". Long-term disk-budget management may
  be addressed in a follow-up if the projected budget in NFR-3
  proves wrong.
- Auditing files outside the user-level Claude Code configuration
  tree (e.g., the per-project `.claude/` directories in user
  repositories). Per-project audit, if desired, is a separate
  feature.
- Auditing the contents of the per-project RLM state
  (`.claude/rlm_state/state.pkl`) — that's a derived artifact,
  not a configuration source.
- A new bespoke `/dev:audit` command. Explicit user choice: query
  through the underlying CLI tool only.
- Restoring prior content automatically (the user can copy a
  retrieved version manually; an "auto-restore" workflow is a
  follow-up, not v1).
- Auditing log files, cache directories, or other write-heavy
  artifacts under `~/.claude/`. [assumption, verify in
  tech-design which subpaths are exclusion candidates by class.]

## Success Metrics

1. **Coverage**: every change to in-scope files made during a
   typical week (installer runs, manual edits, Claude edits) is
   represented by an entry in the audit history. Verified by a
   pre-defined manual reproduction script in the test plan.
2. **Recoverability**: any historical version of any in-scope file
   can be retrieved as a complete file via the documented CLI
   workflow.
3. **Zero-touch**: a new installer-driven setup on a clean machine
   produces a working audit history with no user action beyond
   running the installer.
4. **Locality**: no outbound network traffic is generated by the
   audit subsystem during a normal day of use (verifiable by
   inspecting the system's network activity during a controlled
   reproduction).
5. **Disk budget**: after one simulated year of typical use, the
   audit store size remains within the budget agreed in
   tech-design.

## References

### From Codebase (RLM)

- `install.sh` — installer to extend with audit initialization.
- `install.ps1` — Windows equivalent.
- `.claude/statusline.sh` — the motivating loss case.
- `tasks/020-STATUSLINE-MEM-FRESHNESS-indicator/` — sibling PRD;
  the loss it remediates is the primary motivating example.

### From History (Claude-Mem)

- #10354–#10357 (Apr 22, 2026) — the original feature that was
  lost.
- #13722 (May 14, 2026) — record of the loss.
- #12110 (May 6, 2026) — illustrative prior occurrence of the
  overwrite-vs-merge failure mode in another domain.
- #13059 (May 9, 2026) — Claude Code settings.json structure
  context.

---

**Next Steps**:
1. Review and refine this PRD.
2. Run `/dev:tech-design` to choose the change-detection
   mechanism, the storage backend, the watched-file enumeration,
   the attribution heuristics, and the disk budget.
3. Run `/dev:tasks` to break down into tasks.
