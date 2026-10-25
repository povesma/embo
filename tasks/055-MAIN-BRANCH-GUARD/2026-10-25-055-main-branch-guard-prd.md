# 055: Main Branch Guard - PRD

**Status**: Draft
**Created**: 2026-10-25
**JIRA**: none (internal task 055)
**Author**: Claude (unattended doc-tree phase)

---

## Wider Context / Higher Goal

embo's core principle is "Enforce, Don't Ask": a rule that exists only
as prose is unreliable and must become a deterministic mechanism that
fails loudly. The seed records a real violation of a prose-only rule:
the agent committed a fix onto local `main` and tried to push it, on a
repo whose `main` is protected. This feature turns "do not work on a
protected branch" from a reminder into a guard.

## Context

Nothing stops the agent from editing, committing, or pushing while a
protected branch is checked out. The blindness is wider than protected
branches: during the work phase nothing checks that the checked-out
branch corresponds to the task being worked on.

### Current State (observed)

- The seed describes the incident (commit on `main`, attempted push) and a second one (task changes on the branch of an already-completed task) — verified via: `tasks/055-MAIN-BRANCH-GUARD/SEED.md:3-27`, 2026-10-25.
- The only registered PreToolUse hook matches `Bash` and is the compound-command approver; no hook inspects `Edit`/`Write` or the current branch at tool time — verified via: `plugin/hooks/hooks.json` PreToolUse block, 2026-10-25.
- A SessionStart hook already warns (never blocks) when the branch does not match the task derived from uncommitted changes, and fails open on any uncertainty — verified via: `plugin/hooks/branch-task-check.sh:1-20`, 2026-10-25.
- The branch-to-task match rule and task derivation are shared sourceable functions — verified via: `plugin/lib/branch-task-lib.sh` (`branch_task_matches`, `branch_task_derive_from_paths`, `branch_task_paths_from_porcelain`), 2026-10-25.
- The profile is read through a plain `embo-profile get <dotted.field>` command that prints an empty string when the field is absent — verified via: `plugin/bin/embo-profile:20-30`, 2026-10-25.
- The profile has a `rules:` section with grouped sub-sections (code style, testing, ...) in the canonical default profile — verified via: `plugin/profiles/default.yaml:10-22`, 2026-10-25.
- Every existing hook has a sibling fixture test file (`*.test.sh`) — verified via: `ls plugin/hooks`, 2026-10-25.
- The exact PreToolUse payload fields and the block/deny output contract for hooks — RESOLVED against the live hooks docs (2026-10-25): deny is `hookSpecificOutput{hookEventName, permissionDecision: "deny", permissionDecisionReason}` on exit 0 (exit 2 + stderr as fallback); warn uses `additionalContext` with no `permissionDecision`; two PreToolUse hooks on `Bash` resolve by deny > defer > ask > allow, so a guard deny wins over approve-compound's allow.
- Whether a hook can reliably tell that a `Bash` command is a `git commit`/`git push` (including compound or aliased forms) — best-effort by design (the command is a string; compound/aliased/wrapped forms are not fully decidable); the guard is a guardrail, not a security boundary.
- **A zero-code stopgap already ships** (PR #76): a `permissions.deny` rule in tracked `.claude/settings.json` blocking `git push origin main`/`master`, enforced by the existing `approve-compound.sh`. It is kept alongside this hook as defense-in-depth (see Out of Scope and the tech-design). VERIFIED: the deny mechanism is sound under bash; a deny rule must use an exact or space-star shape — a glued glob (`main*`) silently fails to match, which is why this feature matches branch names by exact string (D7).

### Past Similar Features (from claude-mem)

Not searched in unattended mode beyond the repository; the nearest
precedents in-repo are the SessionStart branch/task warning hook and
the other hooks with fixture tests (behavioral-reminder,
approve-compound), whose conventions this feature follows.

## Problem Statement

**Who**: The agent (and the developer supervising it) working in an embo-enabled repo.
**What**: The agent can modify, commit, and push on a protected branch, and can edit on a branch unrelated to the current task.
**Why**: Lost or misplaced work, rejected pushes, history on the wrong branch; prose reminders already failed.
**When**: Any time a protected branch is checked out, or at the first edit of a work run on a branch that does not belong to the task.

## Goals

### Primary Goal
Block, deterministically and loudly, edits to tracked files and commits/pushes while a protected branch is checked out, with the policy configurable through the profile.

### Secondary Goals
- Detect a branch/task mismatch before the first edit of an implementation run and say how to fix it.
- Keep the policy out of the hook code: branch list and mode come from the profile, with safe defaults.
- Leave a short human-facing rule that points at the hook as the enforcement.

## User Stories

### Epic
As a developer using embo, I want the agent to be unable to change or publish work on a protected branch, so that mistakes are stopped before they cost me work.

### User Stories
1. **As a** developer
   **I want** edits to tracked files refused while a protected branch is checked out
   **So that** the agent must branch first

   **Acceptance Criteria**:
   - [ ] An `Edit`/`Write` to a tracked file on a protected branch in `block` mode is denied with a message naming the branch and telling the agent to create a feature branch
   - [ ] The same action in `warn` mode proceeds with a visible warning; in `off` mode it proceeds silently
   - [ ] Edits to untracked or ignored paths (scratch output, task docs not yet tracked) are not blocked

2. **As a** developer
   **I want** commits and pushes refused when they target a protected branch
   **So that** nothing is committed to or published from it

   **Acceptance Criteria**:
   - [ ] `git commit` while on a protected branch is denied in `block` mode
   - [ ] `git push` that targets a protected branch (current branch or explicit refspec) is denied in `block` mode
   - [ ] The denial text is explicit, never silent

3. **As a** developer
   **I want** to configure the protected branches and the mode in my profile
   **So that** my repo's own branching policy is honoured

   **Acceptance Criteria**:
   - [ ] A profile field holds the protected branch list and another the mode (`block` | `warn` | `off`)
   - [ ] The default profile ships with `main` and `master` protected, mode `block`
   - [ ] A profile without the fields behaves as the default; an unreadable profile never silently disables the guard in a way the user cannot see
   - [ ] The fields are documented alongside the other profile field explanations

4. **As a** developer
   **I want** a mismatch between the branch and the task being worked reported before the first edit of an implementation run
   **So that** work does not land on a finished task's branch

   **Acceptance Criteria**:
   - [ ] The mismatch is reported with a suggestion to create or switch to the task's branch
   - [ ] Its policy mode lives in the profile next to the protected-branch mode
   - [ ] It reuses the existing shared branch/task match rule rather than a second definition

5. **As a** maintainer of embo
   **I want** the guard covered by fixture tests and registered with the plugin
   **So that** it is verified like every other hook

   **Acceptance Criteria**:
   - [ ] A sibling test file covers block/warn/off, protected vs unprotected branch, tracked vs untracked path, commit, push, and fail-open cases
   - [ ] The hook is registered in the plugin hook manifest

## Requirements

### Functional Requirements
1. **FR-1**: A PreToolUse guard inspects the checked-out branch and, in `block` mode on a protected branch, denies (a) Edit/Write/NotebookEdit calls to tracked files and (b) Bash commands that are recognisably file-mutating or history-mutating (commit, push, merge, rebase, cherry-pick, redirects or `sed -i`/`tee` onto tracked paths).
   - **Known limit**: Bash is Turing-complete (scripts, interpreters, wrappers, aliases). Detection is best-effort by design; the guard is a habit-enforcing guardrail, not a security boundary. This limit is stated in the user docs and the complement is remote branch protection (see Out of Scope).
   - **Priority**: High
   - **Rationale**: The primary failure mode in the seed; closing only Edit/Write leaves the shell path open.
   - **Dependencies**: Hook payload contract (tech-design); Bash command parsing approach (tech-design).

2. **FR-2**: The guard denies commit and push commands that target a protected branch.
   - **Priority**: High
   - **Rationale**: The incident involved a commit and an attempted push.
   - **Dependencies**: Reliable recognition of git commit/push in shell commands (tech-design).

3. **FR-3**: Every denial and warning states the branch, the reason, and the corrective action.
   - **Priority**: High
   - **Rationale**: "Fail loudly with guidance, never silently."

4. **FR-4**: The policy (protected branch list, mode `block`/`warn`/`off`) is read from the active profile through the existing profile reader, with defaults of `main`/`master` and `block`.
   - **Priority**: High
   - **Rationale**: User request in the seed; avoids hardcoding.
   - **Dependencies**: Profile schema and default profile.

5. **FR-5**: A work-phase check reports a branch/task mismatch before the first edit of an implementation run, governed by its own profile mode.
   - **Priority**: Medium
   - **Rationale**: Closes the wider blindness described in the seed.
   - **Dependencies**: Shared branch/task match rule; implementation command.
   - **Coverage caveat**: reliable only when `/embo:impl` records the active
     task in a state file the guard reads (tech-design FR-5 trigger). Without
     it, the task cannot be derived at a first edit on a clean tree, so
     coverage is **best-effort** — the check then silently passes rather than
     firing a false mismatch.

6. **FR-6**: The guard is registered in the plugin hook manifest and has fixture tests.
   - **Priority**: High
   - **Rationale**: Hook test convention.

7. **FR-7**: A terse human-facing note in the project Safety Rules states the rule and points at the hook.
   - **Priority**: Low
   - **Rationale**: Documentation for humans; enforcement is the hook.

### Non-Functional Requirements
1. **NFR-1**: Performance - the guard adds negligible latency per tool call (one branch lookup and at most one profile read) and must not slow non-matching tools.
2. **NFR-2**: Reliability - a failure to determine state (no git repo, detached HEAD, unreadable profile) must be handled by a defined, visible policy; the choice between fail-open and fail-closed is a design decision recorded in tech-design.
3. **NFR-3**: Usability - messages are short, actionable, and free of internal task references.
4. **NFR-4**: Safety - the guard itself never performs destructive git actions.

### Technical Constraints
- Must integrate with: the plugin hook manifest, the profile reader, the default profile.
- Should follow patterns: shell hook plus sibling `.test.sh` fixture tests; shared sourceable lib for branch/task logic.
- Cannot change: the hook failure-mode expectations of existing hooks; no new runtime dependencies beyond tools already required (`yq` is already hard-required by the profile reader).

## Out of Scope

- Server-side branch protection or git hosting configuration.
- Intercepting git operations run outside the agent (the developer's own terminal, git hooks).
- Automatically creating or switching branches for the agent.
- Blocking read-only tools.
- Changes to delivery-time branch rules in the deliver flow.

## Success Metrics

1. Protected-branch edit/commit/push attempts in `block` mode: 100% denied in the fixture suite.
2. Unprotected-branch and `off`-mode actions: 0 false denials in the fixture suite.
3. Policy change requires only a profile edit, with no hook code change.

## Decisions-taken

The clarifying-question step was skipped (unattended); each question was decided from evidence.

1. **Wider context**: taken from the seed's origin and the repo's "Enforce, Don't Ask" principle (`SEED.md:3-9`); no JIRA parent exists.
2. **Scope includes work-phase branch awareness (FR-5)** at Medium priority: the seed lists it under proposed direction and scope, so it is kept but ranked below the core guard.
3. **Default mode `block`, default branches `main`/`master`**: stated in the seed (`SEED.md:44`).
4. **Policy via profile, not env var or repo file**: seed requires the profile and the reader already exists.
5. **Identifiers left to tech-design**: exact field names, hook payload keys, and output contract are not fixed here, per the PRD rule to describe by class rather than identifier.
6. **Fail-open vs fail-closed on uncertainty**: not decided here; existing hook precedent is fail-open (`branch-task-check.sh:16-17`) but a safety guard may warrant otherwise. Deferred to tech-design as an explicit decision (NFR-2).
7. **Mismatch check trigger point**: PRD requires "before the first edit of an implementation run"; whether that is a hook or a command step is a tech-design choice.

BLOCKED: none.

## References

### From Codebase (RLM)
- Relevant files: `plugin/hooks/hooks.json`, `plugin/hooks/branch-task-check.sh`, `plugin/lib/branch-task-lib.sh`, `plugin/bin/embo-profile`, `plugin/profiles/default.yaml`, `plugin/hooks/*.test.sh`
- Existing patterns: fail-open hooks with sibling fixture tests; shared lib for branch/task logic; profile read via bare `embo-profile get`
- Integration points: hook manifest, profile schema, implementation command

### From History (Claude-Mem)
- Not consulted in this unattended run; marked provisional.

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/embo:tech-design` to create technical design
3. Run `/embo:tasks` to break down into tasks
