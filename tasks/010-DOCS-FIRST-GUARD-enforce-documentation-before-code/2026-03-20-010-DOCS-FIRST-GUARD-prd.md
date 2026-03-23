# 010-DOCS-FIRST-GUARD: Enforce Documentation Before Code - PRD

**Status**: Revised (v2 — prompt-based enforcement)
**Created**: 2026-03-20
**Author**: Claude (via rlm-mem analysis)

---

## Introduction/Overview

The RLM-Mem workflow has a "docs-first" rule: PRD → tech-design →
tasks → `/impl`. Documentation should exist before code is written.

In practice, this rule is **actively ignored**. The agent starts
coding during casual conversation, when the user explores solutions,
or when the user asks for a change without invoking `/impl`. The
root causes are:

1. **The rule exists only as soft prompt text** — in `start.md` and
   `impl.md`, only loaded when those commands are explicitly invoked.
   When a user types "fix this bug" without a slash command, the
   docs-first rule is never in context.
2. **The prompt has soft exceptions that undermine the rule** —
   "minor changes proceed without docs," "if updating docs costs
   more than the change, skip it," "be smart, no bureaucratic
   overhead." Claude will almost always classify a user's request
   as fitting one of these exceptions, so it skips the check.
3. **No mechanical enforcement** — no hook intercepts Edit/Write
   calls to verify task docs exist. The model self-polices, which
   is the weakest possible enforcement.
4. **No PreToolUse hook** — no mechanical gate intercepts Edit/Write
   calls to check whether the change is backed by task docs.

### V1 approach: PreToolUse hook (attempted and abandoned)

The original design used a two-layer enforcement:

1. **Prompt hardening** — strengthen the docs-first rule in command
   files, remove soft exceptions
2. **PreToolUse hook** (`docs-first-guard.sh`) — shell script on
   Edit/Write that checks a marker file and asks permission

**Why the hook approach failed:**

1. **Breaks "Allow all edits" (Shift+Tab)**: The hook's `"ask"`
   response fires even when the user has granted blanket edit
   permission via Shift+Tab. This makes the standard Claude Code
   permission escalation completely non-functional.
2. **`permission_mode` workaround is a false fix**: Reading
   `permission_mode` from hook input and skipping the prompt in
   `acceptEdits` mode means the guard is silently disabled exactly
   when the user is most actively editing — defeating its purpose.
3. **`systemMessage` is too subtle**: Returning `"allow"` with a
   `systemMessage` warning in auto-edit mode produces a line in the
   transcript the user will never notice during fast iteration.
4. **Marker file is semantically wrong**: A filesystem flag for
   "is `/impl` active?" is binary — it can't distinguish "user is
   doing a documented task" from "user ran `/impl` an hour ago and
   is now off-topic." The real question is semantic: "is this edit
   justified by the current context?"
5. **Hooks can't reason about context**: A bash script cannot
   evaluate whether an edit is covered by existing documentation,
   whether it's a POC during planning, or whether the user is
   exploring. Only the LLM has that context.

### V2 approach: Prompt-based semantic enforcement

The enforcement moves entirely into command prompts where Claude
has full context to make semantic judgments:

- During `/impl` with documented tasks → edit freely
- During PRD/tech-design doing research/POC → allow with a note
- Undocumented code change in casual conversation → Claude warns
  and suggests documenting first before proceeding
- User explicitly approves → proceed

This is softer mechanically but semantically correct. Claude can
distinguish "temp POC in /tmp" from "rewriting production code
without a task."

---

## Objectives & Success Metrics

**Objectives:**
- Prevent Claude from writing code outside of `/impl` sessions
  without user awareness
- When code is attempted without docs, prompt the user with the
  option to document first
- Preserve the smooth `/impl` flow (hook is silent during `/impl`)
- Ship as part of the installation package so all users benefit

**Success Metrics:**
- When a user discusses a feature casually and Claude attempts to
  Edit a file, the hook fires and asks permission
- During `/impl` with existing task docs, no interruption occurs
- The permission message clearly suggests running `/impl` or
  creating docs first
- Zero false positives on Read, Grep, Glob, or `.md` file edits

---

## User Personas & Use Cases

**Casual Explorer**: Discussing a problem, exploring solutions.
Doesn't want Claude to start editing files — just wants analysis.
Claude's eagerness to code is the problem.
- **Need**: Guard that catches "unauthorized" code edits

**Quick Fixer**: Wants to fix a typo or config tweak. Doesn't
need a full PRD for a one-line change. Should be able to approve
the edit when prompted.
- **Need**: Permission prompt, not hard block. Option to proceed.

**Disciplined Developer**: Uses the full PRD → tasks → `/impl`
flow. Shouldn't be interrupted during `/impl`.
- **Need**: Hook is silent when `/impl` is active

---

## User Stories

### Story 1 — PreToolUse hook blocks unplanned code edits

**As a** developer chatting with Claude about a problem,
**I want** Claude to be stopped from editing code files unless
I've explicitly started an `/impl` session,
**so that** code changes are always intentional and documented.

**Acceptance Criteria:**
- [ ] A PreToolUse hook on `Edit|Write` fires when `/impl` is
  NOT active
- [ ] The hook checks if the target file is a code file (not `.md`,
  not in `tasks/`, not in `docs/`)
- [ ] When triggered on a code file, the hook responds with
  `permissionDecision: "ask"` and a reason message:
  "No /impl session active. This edit has no backing task docs.
  Options: (1) Allow this edit, (2) Run /rlm-mem:develop:impl
  to start documented implementation, (3) Run
  /rlm-mem:plan:prd to create docs first."
- [ ] User can approve the edit (proceeds) or deny (blocked)
- [ ] The hook is silent (exit 0) when `/impl` is active
  (detected via marker file)

---

### Story 2 — Marker file for /impl session tracking

**As a** system component,
**I want** `/impl` to create a marker file at session start and
remove it at session end,
**so that** the hook can detect whether `/impl` is active.

**Acceptance Criteria:**
- [ ] `/impl` creates `~/.claude/rlm_state/.impl-active` at the
  start of its process (before any implementation work)
- [ ] `/impl` removes the marker at the end (final step)
- [ ] Marker file includes a timestamp for staleness detection
- [ ] Hook ignores marker files older than 2 hours (stale session
  protection — prevents a crashed session from suppressing the
  hook permanently)

---

### Story 3 — Allow-list for non-code files

**As a** developer writing documentation, task files, or PRDs,
**I want** the hook to NOT trigger when I'm editing markdown,
config, or docs files,
**so that** documentation work is never blocked.

**Acceptance Criteria:**
- [ ] Files matching `*.md` are always allowed
- [ ] Files in `tasks/` directory are always allowed
- [ ] Files in `.claude/` directory are always allowed
- [ ] Read, Grep, Glob, and search tools are never intercepted
  (hook matcher is `Edit|Write` only)
- [ ] Bash commands are NOT intercepted (too broad — would block
  `git status`, `python3 rlm_repl.py`, etc.)

---

### Story 4 — Prompt hardening in shipped command files

**As a** developer,
**I want** the docs-first rule in the command files to be clear
and unambiguous, without soft exceptions that let Claude skip it,
**so that** the prompt reinforces what the hook enforces.

**Note:** CLAUDE.md is the user's own file — this project does not
ship or modify it. All prompt changes go into the command files we
deliver (`start.md`, `impl.md`).

**Acceptance Criteria:**
- [ ] `start.md` Docs-First Principle section rewritten: remove
  "minor changes proceed without doc update" — the hook handles
  the minor-change case (user approves at the prompt)
- [ ] `impl.md` Scope Verification section tightened: remove
  "if updating docs costs more, skip" and "be smart, no
  bureaucratic overhead" language. Keep the clarification-level
  exception but define it strictly: "implementation detail within
  an existing task subtask only"
- [ ] Both files reference the PreToolUse hook as the enforcement
  mechanism for code edits outside `/impl`

---

### Story 5 — Installation and documentation

**As a** new installer,
**I want** the hook to be installed automatically and documented,
**so that** I get the protection without manual setup.

**Acceptance Criteria:**
- [ ] Hook script lives at `.claude/hooks/docs-first-guard.sh`
  in the repo
- [ ] `install.sh` copies the hook to `~/.claude/hooks/`
- [ ] Hook is registered in the project's `.claude/settings.json`
  under PreToolUse with matcher `Edit|Write`
- [ ] README documents the hook's purpose and how to bypass it
  (for users who want to opt out)

---

### Story 6 — Future: agent hook for semantic validation (out of
  scope for v1)

**As a** developer,
**I want** the hook to understand WHETHER the edit is covered by
an existing task, not just whether `/impl` is active,
**so that** even within `/impl`, scope drift is caught.

**Note:** V1 uses a simple marker-file check. Future versions
could use Claude Code's `type: "agent"` hook to spawn a subagent
that reads the task file and compares the current Edit against
active tasks. This is more nuanced but costs an API call per
Edit/Write. Documented here for future consideration.

---

## Requirements

### Functional Requirements

**FR-1: PreToolUse hook script**
- **What**: Shell script `.claude/hooks/docs-first-guard.sh`
- **Trigger**: Fires on `Edit|Write` tool calls
- **Logic**:
  1. Read JSON from stdin
  2. Extract `tool_input.file_path`
  3. If file matches allow-list (`*.md`, `tasks/*`, `.claude/*`):
     exit 0 (allow)
  4. If marker file `~/.claude/rlm_state/.impl-active` exists
     and is not stale (< 2 hours old): exit 0 (allow)
  5. Otherwise: output JSON with `permissionDecision: "ask"` and
     reason message suggesting `/impl` or docs creation
- **Priority**: Critical

**FR-2: Marker file management in impl.md**
- **What**: Add marker creation/cleanup to `/impl` command
- **Create**: `touch ~/.claude/rlm_state/.impl-active` as Step 0
- **Cleanup**: `rm -f ~/.claude/rlm_state/.impl-active` as final step
- **Priority**: Critical

**FR-3: Prompt hardening in shipped command files**
- **What**: Tighten docs-first language in `start.md` and `impl.md`
  (the command files this project delivers to users)
- **Content**: Remove soft exceptions that let Claude skip the check.
  Reference the PreToolUse hook as the enforcement mechanism.
- **Note**: CLAUDE.md is the user's own file — not modified.
- **Priority**: High

**FR-5: Hook registration in settings**
- **What**: Add PreToolUse hook entry to
  `.claude/settings.json` (project-level, committed)
- **Priority**: High

**FR-6: Installation integration**
- **What**: `install.sh` copies hook script and updates settings
- **Priority**: Medium

### Non-Functional Requirements

**NFR-1: Speed** — Hook script must complete in under 100ms.
No API calls, no network. Pure file-system checks.

**NFR-2: No false positives on reads** — The hook matcher is
`Edit|Write` only. Read, Grep, Glob, Agent, and Bash are never
intercepted.

**NFR-3: Graceful degradation** — If the marker file mechanism
fails (stale file, missing directory), the hook should default to
"ask" (safe default), not "deny" (would block all edits).

**NFR-4: User bypass** — Users can disable the hook by setting
`"disableAllHooks": true` in their settings or removing the hook
entry. This is documented, not hidden.

**NFR-5: No disruption to /impl** — When the marker file exists
and is fresh, the hook adds zero friction. Exit 0, no output.

### Technical Constraints

- Hook script must be POSIX sh + `jq` (same as statusline.sh)
- The PreToolUse hook receives JSON on stdin with `tool_name`,
  `tool_input`, `session_id`, `cwd`, and `transcript_path` — but
  NO information about which slash command is active (confirmed
  missing feature, GitHub issue #22655 closed as not planned)
- Marker file workaround is the only way to detect `/impl` state
- Project-level settings (`.claude/settings.json`) are committed
  and shared with all users; hook registration goes here
- Users CAN disable hooks via `disableAllHooks: true`

---

## Out of Scope

- **Bash command interception** — Too broad; would block git, RLM
  REPL, and other necessary commands
- **Semantic task-matching** — V1 doesn't check if the edit matches
  a specific task; only checks if `/impl` is active
- **Agent hook** — V1 uses a simple shell script; agent-based
  semantic validation is Story 6 (future)
- **Hard deny** — V1 uses `"ask"` (user can approve), not `"deny"`
  (hard block). The goal is awareness, not lockdown.
- **New file creation detection** — Write tool creates new files;
  Edit modifies existing. Both are covered by the same hook.

---

## Gherkin Scenarios

```gherkin
Feature: Docs-First Guard

  Scenario: Code edit outside /impl triggers permission prompt
    Given no /impl session is active (no marker file)
    And the user is discussing a problem casually
    When Claude attempts to Edit a .ts file
    Then the PreToolUse hook fires
    And the user sees a permission prompt with the message:
      "No /impl session active. This edit has no backing task
      docs. Consider: /rlm-mem:develop:impl or
      /rlm-mem:plan:prd"
    And the user can approve or deny

  Scenario: Markdown edit outside /impl is allowed
    Given no /impl session is active
    When Claude attempts to Edit a .md file
    Then the hook allows it silently (exit 0)

  Scenario: Code edit during /impl is allowed
    Given /impl is active (marker file exists, < 2 hours old)
    When Claude attempts to Edit a .ts file
    Then the hook allows it silently (exit 0)

  Scenario: Stale marker file is ignored
    Given a marker file exists but is 3 hours old
    When Claude attempts to Edit a .ts file
    Then the hook ignores the stale marker
    And the user sees a permission prompt

  Scenario: Read/Grep/Glob are never intercepted
    Given no /impl session is active
    When Claude uses Read, Grep, or Glob tools
    Then no hook fires (matcher is Edit|Write only)

  Scenario: User approves the edit
    Given the permission prompt is shown
    When the user approves
    Then the edit proceeds normally

  Scenario: User denies the edit
    Given the permission prompt is shown
    When the user denies
    Then the edit is blocked
    And Claude receives the denial reason

  Scenario: /impl creates marker at start
    Given the user runs /rlm-mem:develop:impl
    When the command starts processing
    Then ~/.claude/rlm_state/.impl-active is created

  Scenario: /impl removes marker at end
    Given the user completes /impl tasks
    When the command finishes
    Then ~/.claude/rlm_state/.impl-active is removed
```

---

## References

### From Codebase
- `.claude/commands/rlm-mem/discover/start.md:217-227` — Current
  docs-first text (soft, with soft exceptions)
- `.claude/commands/rlm-mem/develop/impl.md:6-48` — Critical
  Evaluation and Scope Verification sections
- `.claude/hooks/context-guard.sh` — Existing hook pattern to follow
- `.claude/settings.json` — Does not exist yet at project level;
  needs hook registration

### From Research (2026-03-20)
- **Claude Code hooks**: PreToolUse can hard-block or ask-permission
  on any tool call. Four handler types: command, http, prompt, agent.
  Shell script is fastest (< 100ms).
- **Marker file pattern**: Only reliable way to detect `/impl`
  context from a hook. PreToolUse JSON does not include slash
  command context (GitHub #22655, closed as not planned).
- **Staleness protection**: `find -mmin +120` prevents stale markers
  from permanently suppressing the hook.
- **Industry**: Invariant Guardrails (Snyk) and NeMo Guardrails
  validate the pre-action interception pattern. Danger JS validates
  the "docs required alongside code" pattern at CI level.

### Root Cause Analysis
Five compounding reasons the current rule fails:
1. Pure prompt enforcement with no mechanical gate
2. Rule only loaded when `/start` or `/impl` explicitly invoked
3. Language has built-in soft exceptions
4. Context pressure causes mid-session forgetting
5. No PreToolUse hook exists for Edit/Write

---

**Next Steps:**
1. Review and approve this PRD
2. Run `/rlm-mem:plan:tech-design` to design the hook script and
   prompt changes
3. Run `/rlm-mem:plan:tasks` to break down into tasks
