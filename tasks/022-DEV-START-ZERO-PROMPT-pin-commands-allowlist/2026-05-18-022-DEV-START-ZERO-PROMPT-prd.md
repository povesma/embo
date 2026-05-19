# 022-DEV-START-ZERO-PROMPT: Eliminate Permission Prompts During `/dev:start` — PRD

**Status**: Draft
**Created**: 2026-05-18
**Author**: Claude (via dev workflow analysis)

---

## Context

Running `/dev:start` intermittently triggers Claude Code harness
permission prompts on read-only commands, delaying session
initialization. The intermittency is the key symptom: identical
intent ("read the active profile") shows up across runs as
different shell shapes — e.g.
`cat ~/.claude/active-profile.yaml 2>/dev/null || echo "NO_PROFILE"`,
`test -f ~/.claude/active-profile.yaml && cat ~/.claude/active-profile.yaml || echo "NO_PROFILE"`,
or `[ -f ~/.claude/active-profile.yaml ] && cat …` — so even a
correct narrow allowlist entry matches some runs but not others,
and the user gets prompted again on the runs that miss.

The user's request explicitly couples both halves of the fix: "all
should be pre-approved or manually approved just once." That can
only be delivered if the skill stops producing varying shell
shapes for the same step **and** the allowlist precisely covers
the pinned shapes.

This work directly extends two recent commits:
`ebd833a` (add read-only permission rules to installers) and
`6752223` (remove double-prompting on git commands) — both
followed the same principle: the harness permission prompt is
the only safety gate, and pre-approving narrow read-only shapes is
the way to remove friction without weakening safety.

### Current State (observed)

- `/dev:start` has exactly two pinned (fenced) Bash commands:
  `python3 ~/.claude/rlm_scripts/rlm_repl.py status` and the git
  pair `git log --oneline -10` / `git diff --stat HEAD` —
  verified via: `Read .claude/commands/dev/start.md`, 2026-05-18.
- The remaining filesystem-touching steps are described in
  prose: Step 0 says "Read `~/.claude/active-profile.yaml` if it
  exists" and Step 3 says "Glob `**/README*.md`, `**/CLAUDE*.md`"
  and "Glob `tasks/**/*-tasks.md`" — verified via:
  `Read .claude/commands/dev/start.md` lines 21–26 and 90–92,
  2026-05-18. These are the lines that allow paraphrasing.
- Claude-mem MCP calls (`mcp__plugin_claude-mem_mcp-search__search`,
  `…__get_observations`) are already pre-approved in
  `~/.claude/settings.json` — verified via: this session's earlier
  `Read ~/.claude/settings.json`, 2026-05-18.
- A read-only Bash allowlist already exists from commit `ebd833a`:
  `Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)`,
  `Bash(find:*)`, `Bash(git log:*)`, `Bash(git diff:*)`,
  `Bash(git status:*)`, `Bash(grep:*)`, `Bash(head:*)` — verified
  via: `install.sh` `RLM_PERMS` array and `install.ps1`
  `$rlmPerms` array, 2026-05-18.
- The `cat` / `test` / `[ -f ]` shape family is **not** in the
  allowlist — verified via: same source, 2026-05-18. This is the
  root cause of the prompts the user reported.
- `UserPromptSubmit` hooks (`context-guard.sh`,
  `behavioral-reminder.sh`) run in-process from the harness and
  consume stdin / produce JSON to stdout; they do not issue
  external commands that would require additional permissions —
  verified via: Explore agent inventory, 2026-05-18.
- The pinned commands' shapes drift over Claude Code releases as
  the model version changes; the prose lines in start.md let
  newer models produce shapes the older allowlist did not
  anticipate. [assumption, verify in tech-design that pinning a
  single canonical shape per step in the skill text reliably
  causes the model to copy verbatim rather than paraphrase. This
  is the load-bearing claim of the chosen approach.]

### Past Similar Features (from claude-mem)

- `#13888` (2026-05-18) — full command-surface inventory for
  `/dev:start` produced during this session's research phase.
  Becomes input to tech-design, not a substitute for it.
- `#13889` (2026-05-18) — design strategy captured in
  `~/.claude/plans/during-dev-start-claude-code-bright-cascade.md`.
  This PRD supersedes that plan file as the source of truth.
- `#12299` (2026-05-07) — PowerShell installer auto-injects
  read-only Bash permissions. Pattern to extend.
- `#12291` (2026-05-07) — earlier narrowing of `Bash(python3:*)`
  to `Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)`. Sets
  precedent for narrow-over-broad allow patterns.
- `#12269` / `#12272` (2026-05-06/07) — rationale for relying on
  the harness permission prompt as the single confirmation gate
  (motivation for narrow allowlist rather than skill-level
  gates).

## Problem Statement

**Who**: any developer using `/dev:start` to begin a session in
this repo or any repo where the skill is installed.

**What**: every `/dev:start` invocation interrupts the developer
with one or more harness permission prompts on read-only
commands. The prompts are intermittent because the skill prose
lets the model issue different shell shapes for the same step
across runs.

**Why**: a "start" skill that prompts on every invocation is
worse than no automation — it imposes a steady-state click tax on
every session, and the inconsistency (sometimes prompts, sometimes
doesn't) means the developer cannot internalize a habit of
auto-approving. The user explicitly called this "unacceptably
delays the session initiation."

**When**: at the beginning of every coding session that uses
`/dev:start`, which the skill itself recommends as standard
practice ("Beginning of each coding session" — start.md line 7).

## Goals

### Primary Goal

After completing this work, running `/dev:start` from a clean
Claude Code session against a freshly installed RLM-Mem
configuration produces **zero** harness permission prompts for
the duration of the skill's execution, on five consecutive cold
starts.

### Secondary Goals

- The pre-approved allowlist remains narrow: only the exact
  read-only shapes the skill is allowed to issue, nothing
  broader. Approving `/dev:start` must not grant the harness
  permission to read arbitrary files or run arbitrary tools.
- New installations of the repo get the fix automatically through
  the existing `install.sh` / `install.ps1` permission-injection
  block. No additional user step.
- The change is robust against model-version drift: if a newer
  model paraphrases the skill text, the skill text itself
  constrains the output to one canonical shape, not the
  allowlist trying to enumerate all possible paraphrases.
- The change is reversible by deleting three allow rules and one
  skill-text patch; no infrastructure, no schema, no migration.

## User Stories

### Epic

As a developer beginning a coding session, I want `/dev:start` to
run end-to-end without any permission prompts, so that session
initialization is instant and predictable.

### User Stories

1. **As a** returning developer with an established RLM-Mem
   install
   **I want** `/dev:start` to load profile, RLM status, claude-mem
   history, and git context without ever prompting me
   **So that** I get a usable session summary in seconds and can
   start work.

   **Acceptance Criteria**:
   - [ ] Across five consecutive cold-start invocations of
     `/dev:start` in fresh Claude Code sessions, **zero** harness
     permission prompts appear at any point during skill
     execution.
   - [ ] The skill still produces the same session summary
     content it did before (profile noted, RLM stats, claude-mem
     observations summarized, git context, recommended next
     task).
   - [ ] On each of the five runs, the transcript shows the exact
     same fenced commands for the steps that were previously
     prose-driven (profile load, doc/task discovery, git
     inspection). No paraphrased variants.

2. **As a** new RLM-Mem installer running `install.sh` (or
   `install.ps1`) for the first time
   **I want** the zero-prompt property to be set up automatically
   **So that** my very first `/dev:start` runs without prompts.

   **Acceptance Criteria**:
   - [ ] A fresh installation on a machine with no prior
     `~/.claude/settings.json` produces the allowlist entries
     needed for `/dev:start` to run prompt-free.
   - [ ] Re-running the installer on an already-configured
     machine is idempotent: existing allow rules are not
     duplicated; the installer reports "all rules already
     present" rather than re-adding them.

3. **As a** security-conscious developer reviewing my
   `~/.claude/settings.json`
   **I want** the allow rules to be narrow and self-explanatory
   **So that** I can audit them at a glance and not worry that
   `/dev:start` granted the harness wider permissions than the
   skill actually uses.

   **Acceptance Criteria**:
   - [ ] No rule introduced by this work uses an unscoped wildcard
     against a high-risk tool surface (no `Bash(cat:*)`, no
     `Bash(test:*)`, no `Read(~/**)`).
   - [ ] Every rule introduced by this work maps 1:1 to a
     specific command shape pinned in the skill text. A reviewer
     reading the rule can locate the matching skill line.
   - [ ] An unrelated read-only command outside the allowlist
     (e.g. `cat ~/.zshrc`) still prompts. The harness gate remains
     effective for everything not explicitly pre-approved.

4. **As a** maintainer of this repo updating `/dev:start` in the
   future
   **I want** the rule that "commands the skill expects to execute
   must be pinned" to be documented in the skill itself
   **So that** I do not accidentally reintroduce the paraphrase
   problem by replacing a fenced command with prose.

   **Acceptance Criteria**:
   - [ ] The skill text contains a brief, visible note next to
     each pinned command explaining why the verbatim shape
     matters (so a future editor does not "improve" it back to
     prose).
   - [ ] The relationship between pinned commands and allowlist
     entries is discoverable from the skill text alone (no need
     to read tech-design or PRD to find it).

## Requirements

### Functional Requirements

1. **FR-1**: The skill text in `.claude/commands/dev/start.md`
   MUST replace every filesystem-touching prose instruction with
   an exact, fenced command (or a directive to use a non-Bash
   tool by name, e.g. "use the Glob tool"). The set of pinned
   sites is enumerated in tech-design; it is not part of the
   PRD's scope to list shell-level command shapes.
   - **Priority**: High
   - **Rationale**: This is the load-bearing change; without it,
     no allowlist can be narrow enough to eliminate prompts
     without also being too broad to audit.

2. **FR-2**: The harness allowlist (in `~/.claude/settings.json`)
   MUST contain a rule for every exact command shape FR-1
   pins, and no rule broader than what those shapes require.
   - **Priority**: High
   - **Rationale**: Pinning without allowlisting still produces
     prompts; allowlisting without pinning produces a broad,
     hard-to-audit list.

3. **FR-3**: Both installers (`install.sh`, `install.ps1`) MUST
   inject the FR-2 rules into the target machine's settings.json,
   using the existing permission-injection mechanism (the
   `RLM_PERMS` / `$rlmPerms` arrays).
   - **Priority**: High
   - **Rationale**: Per User Story 2 — the fix must be zero-touch
     for new installs.

4. **FR-4**: The skill MUST continue to produce a session summary
   with the same information classes it produces today:
   active profile, RLM stats, completed features, active tasks,
   recent activity, recommended next task, system status.
   - **Priority**: High
   - **Rationale**: Removing prompts must not regress the value
     the skill delivers.

5. **FR-5**: The change MUST be auditable from the skill text
   alone — a developer reading `.claude/commands/dev/start.md`
   MUST be able to identify which lines correspond to which
   allowlist rules.
   - **Priority**: Medium
   - **Rationale**: Allowlists drift; this property keeps drift
     visible. If the skill changes and the allowlist doesn't
     (or vice versa), the mismatch should be obvious.

### Non-Functional Requirements

1. **NFR-1**: Performance — `/dev:start` total runtime MUST NOT
   regress measurably. The expected change is a small reduction
   (no prompt round-trips), not an increase.
2. **NFR-2**: Privacy / safety — no allowlist rule introduced by
   this work may grant the harness permission to read files
   outside the paths the skill actually touches. No `Bash(cat:*)`
   or equivalent broad pattern.
3. **NFR-3**: Portability — both `install.sh` (macOS / Linux) and
   `install.ps1` (Windows) MUST inject the same logical set of
   rules. The two installers' existing injection mechanisms are
   the canonical path.
4. **NFR-4**: Idempotency — re-running the installer MUST NOT add
   duplicate rules. The existing dedup logic in both installers
   is the canonical mechanism.
5. **NFR-5**: Reversibility — the change MUST be reversible by
   deleting a small number of allow rules and a small skill-text
   patch, with no schema migration and no other side effects.

### Technical Constraints

- Must integrate with: the existing permission-injection block
  in `install.sh` (`RLM_PERMS` array) and `install.ps1`
  (`$rlmPerms` array). Both already exist from commit `ebd833a`.
- Should follow patterns: narrow-over-broad allow rules (per
  observation `#12291` — `Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)`
  rather than `Bash(python3:*)`).
- Cannot change: the semantics of `/dev:start` outputs. The
  session-summary template must continue to render the same
  fields.
- Cannot grant: read access to user-private files (`~/.ssh/*`,
  `~/.aws/*`, etc.) — these are explicitly denied by the
  existing `deny` block, but a too-broad allow rule could
  shadow that. [assumption, verify in tech-design that the
  chosen narrow rules do not collide with the existing
  `permissions.deny` rules.]
- Cannot assume: that the Claude Code harness's allowlist
  matcher does string-prefix vs. shell-glob matching the way
  the developer expects. [assumption, verify in tech-design by
  examining at least one already-working allow rule and
  confirming the match semantics for `Bash(<verbatim line>)`
  patterns.]

## Out of Scope

- Other dev:* skills (`/dev:prd`, `/dev:tech-design`,
  `/dev:tasks`, `/dev:impl`, `/dev:git`, `/dev:check`,
  `/dev:health`, `/dev:improve`, `/dev:profile`,
  `/dev:test-plan`, `/dev:init`) may have similar paraphrase
  problems, but auditing them is a follow-up. This PRD scopes
  the fix to `/dev:start` only.
- Pre-approving the `Read` tool itself on broad paths
  (`Read(~/.claude/**)`). Tool-level pre-approval is a separate
  decision with a different risk profile.
- Replacing the harness permission system with anything else
  (e.g. a project-level trust file). The existing
  permissions.allow mechanism is sufficient.
- Improving the session-summary content, layout, or recommended-
  task heuristic. Quality of output is out of scope; only
  permission friction is in scope.
- Cross-machine sync of allowlists. Each machine's settings.json
  remains local.
- Reducing prompts during the `UserPromptSubmit` hooks
  themselves; those run in-process from the harness and do not
  produce prompts.
- A test framework or CI gate that verifies the zero-prompt
  property automatically. Verification in v1 is manual (User
  Story 1 acceptance criteria).

## Success Metrics

1. **Zero-prompt cold-start**: five consecutive `/dev:start`
   invocations from fresh Claude Code sessions, against a clean
   install of this repo with the changes in place, produce zero
   harness permission prompts. Measured by transcript inspection.
2. **Idempotent installer**: running `install.sh` (or
   `install.ps1`) twice on the same machine adds the allow rules
   exactly once. Verified by diffing `~/.claude/settings.json`
   permissions.allow before and after the second run.
3. **Narrow-allowlist preservation**: a control read-only command
   outside the allowlist (e.g. `cat ~/.zshrc`) still prompts.
   Verified manually by running it after the change is in place.
4. **Output parity**: a `diff` of the session summary
   produced by `/dev:start` before and after the change shows no
   regressions in information content (allowing for content
   differences driven by claude-mem and git state changing
   between runs).
5. **Skill-text auditability**: a reviewer reading the updated
   `.claude/commands/dev/start.md` can locate, within 30
   seconds, the lines that correspond to each new allow rule.

## References

### From Codebase (RLM)

- `.claude/commands/dev/start.md` — the skill to be modified.
- `install.sh` `RLM_PERMS` array (line ~130) — extension point.
- `install.ps1` `$rlmPerms` array (line ~252) — extension
  point.
- `~/.claude/settings.json` `permissions.allow` — target of the
  installer injection.
- `.claude/commands/dev/health.md` — sibling skill (referenced by
  start.md but not chained into it).
- `.claude/hooks/context-guard.sh`,
  `.claude/hooks/behavioral-reminder.sh` — run on
  UserPromptSubmit; do not produce prompts; out of scope.

### From History (Claude-Mem)

- `#13888` (2026-05-18) — command-surface inventory for
  `/dev:start`.
- `#13889` (2026-05-18) — plan file with the proposed pinning
  strategy and narrow allowlist set.
- `#12299` (2026-05-07) — installer permission-injection
  pattern.
- `#12291` (2026-05-07) — precedent for narrow allow rules.
- `#12269` / `#12272` (2026-05-06/07) — single-gate confirmation
  principle.

---

**Next Steps**:
1. Review and refine this PRD.
2. Run `/dev:tech-design` to enumerate the exact set of pinned
   shapes and matching allowlist rules, verify allowlist match
   semantics against a working example, and confirm no overlap
   with `permissions.deny`.
3. Run `/dev:tasks` to break down into tasks.

---

## Addendum — 2026-05-19 (reopened, then resolved)

Stories 1.0–5.0 shipped, but `/dev:start` still prompted in fresh
sessions. Root cause was not the Bash command-shape gate (cleared
by 022); it was Claude Code's filesystem sandbox firing on Step
0's read of `~/.claude/active-profile.yaml` (outside the project
root).

The real fix: per the Claude Code permissions docs, slash-command
markdown supports an `allowed-tools` frontmatter field that
pre-approves specific tool shapes **for that command only**, no
user-settings edit required.

### Resolution requirements

- **FR-6**: `.claude/commands/dev/start.md` MUST declare an
  `allowed-tools` frontmatter field listing the exact shapes Step
  0 + Step 3 emit, including the `Read(~/.claude/active-profile.yaml)`
  shape that clears the filesystem sandbox.
- **FR-7**: the installers MUST NOT carry global allowlist
  entries for these shapes (they were added during diagnosis and
  are dead weight under the frontmatter approach; removed).
- **FR-8**: `start.md` Step 3 MUST contain an explicit negative
  directive forbidding Bash loops, `find`, and `$(...)` for
  discovery; the harness refuses to auto-approve unanalyzable
  shell regardless of allowlists.

### Out of scope

- Broadening `Read(...)` beyond the one file `/dev:start` reads.
- Migrating other dev:* skills to frontmatter allow-rules
  (follow-up).
- Cross-project memory filtering on claude-mem search calls
  (deferred separately).
