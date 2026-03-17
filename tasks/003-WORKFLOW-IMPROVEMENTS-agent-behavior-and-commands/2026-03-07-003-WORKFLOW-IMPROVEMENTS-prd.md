# Workflow Improvements - Product Requirements Document

## Introduction/Overview

Three pain points have emerged from real usage of the RLM-Mem
workflow system:

1. **Tech-design documents contain operational noise** — setup
   guides, CLI examples, and magic numbers that belong in README
   or code, not in architecture documentation.
2. **Agent blindly executes ad-hoc instructions** — when a user
   gives a direct instruction outside PRD/tech-design/tasks scope,
   the agent implements it immediately, breaking session
   idempotency and document-code traceability.
3. **`/start` command is slow and noisy** — inline Python exec
   blocks generate unique commands each run, triggering permission
   prompts and making the session-start experience sluggish.

This PRD addresses all three as a single coherent improvement to
the command workflow system.

## Objectives & Success Metrics

**Business Objectives:**
- Improve tech-design document quality so developers get
  architecture decisions, not user manuals
- Enforce document-first development to maintain session
  idempotency across restarts
- Make `/start` frictionless so developers begin coding faster

**Success Metrics:**
- Tech-design documents contain zero operational/README content
  (manual review of next 3 generated docs)
- Agent never implements out-of-scope changes without first
  updating PRD/tech-design/tasks (verified by session replay)
- `/start` completes with zero interactive permission prompts
  for RLM commands (verified by running `/start` in a project
  with standard Claude Code allow-list)

## User Personas & Use Cases

### User Personas

**Solo Developer (primary)**: Uses RLM-Mem workflow for personal
projects and client work.
- **Characteristics**: Familiar with Claude Code, uses `/start`
  daily, writes PRDs for non-trivial features
- **Needs**: Fast session start, trustworthy docs that match code,
  architecture docs that help implementation
- **Goals**: Ship features quickly with high quality, resume work
  seamlessly across sessions

**Team Lead**: Reviews PRDs and tech-designs written by AI agent.
- **Characteristics**: Reads docs to understand decisions, does
  not run Claude Code directly
- **Needs**: Tech-designs that explain "why" not "how to install"
- **Goals**: Quickly assess architecture quality and trade-offs

### User Stories

- As a developer, I want tech-design documents to contain only
  architecture decisions so that I can focus on implementation
  without wading through README-style content
- As a developer, I want the agent to flag out-of-scope
  instructions and update docs before implementing so that my
  sessions remain idempotent and code always matches docs
- As a developer, I want `/start` to complete without permission
  prompts so that I can begin working immediately

### Use Cases

1. **Tech-design review**: Developer generates a tech-design and
   finds only component boundaries, data contracts, sequence
   diagrams, failure patterns, and rejected alternatives — no
   setup guides or CLI examples
2. **Ad-hoc instruction handling**: Developer says "add a --verbose
   flag to the REPL" mid-session. Agent recognizes this is not in
   current tasks, warns about scope drift, auto-updates the
   relevant docs (PRD/tech-design/tasks as appropriate), then
   implements. If the doc change is massive, agent asks user to
   confirm before proceeding.
3. **Frictionless start**: Developer runs `/rlm-mem:discover:start`
   and the session starts with zero permission prompts — RLM
   status, claude-mem queries, and git info all execute without
   interruption

## Feature Scope

### In Scope

- **A: Tech-design content quality rules** — add to tech-design
  command templates across 3 active trees (rlm-mem, coding, rlm)
- **B: Critical agent behavior + idempotency** — add scope-drift
  detection and doc-first enforcement to impl command templates
  across 3 active trees
- **B2: /plan:check across all trees** — create check.md for
  coding and rlm trees (currently only exists in rlm-mem), add
  scope-drift detection to all check.md files
- **C: Frictionless /start** — rewrite start command templates to
  use only deterministic, allowlist-friendly commands; drop inline
  Python exec blocks

### Out of Scope

- Changing the RLM REPL Python script itself
- Modifying claude-mem plugin behavior
- Changes to `/dev` tree (deprecated)
- Changes to PRD or tasks command templates (only tech-design,
  impl, check, and start are affected)

### Future Considerations

- Claude Code hooks for auto-allowing known-safe commands
- Pre-built `/start` output caching for instant session resume
- Automated idempotency verification tool (diff docs vs code)

## Functional Requirements

### Cucumber/Gherkin Scenarios

```gherkin
Feature: Tech-design content quality

Scenario: Tech-design excludes operational content
  Given a developer runs /plan:tech-design
  When the document is generated
  Then it contains component boundaries and responsibilities
  And it contains data contracts between components
  And it contains rejected alternatives with reasons
  And it does NOT contain setup guides or workflow steps
  And it does NOT contain CLI usage examples or sample output
  And it does NOT contain algorithm parameter values

Scenario: Tech-design self-check
  Given a developer runs /plan:tech-design
  When the agent writes a section
  Then the agent evaluates: "would a developer not know this
    without reading this section?"
  And removes sections that read like user manuals

Feature: Agent scope-drift detection

Scenario: Small out-of-scope instruction
  Given a developer gives an instruction not in current tasks
  When the agent detects scope drift
  Then it warns the developer about the drift
  And it auto-updates the relevant docs (tasks at minimum)
  And it proceeds with implementation after docs are updated

Scenario: Large out-of-scope instruction
  Given a developer gives an instruction requiring significant
    doc changes (new user story, architecture change)
  When the agent detects scope drift
  Then it warns the developer about the drift
  And it presents the proposed doc changes
  And it asks for confirmation before updating docs
  And it implements only after user confirms

Scenario: In-scope instruction
  Given a developer gives an instruction matching current tasks
  When the agent checks scope
  Then it proceeds normally without warnings

Feature: Frictionless /start command

Scenario: Start with no permission prompts
  Given RLM is initialized in the project
  When the developer runs /start
  Then all RLM commands execute without permission prompts
  And claude-mem queries execute without prompts
  And the session summary appears within seconds

Scenario: Start without RLM
  Given RLM is NOT initialized
  When the developer runs /start
  Then it suggests running /init
  And does not error or prompt for permissions
```

### Detailed Requirements

1. **Tech-design content quality rules**: Add a "Content Quality
   Rules" section to tech-design.md command templates that
   instructs the agent to include only architecture content and
   exclude operational/README content. Rules must be explicit
   enough that the agent can self-evaluate each section.

2. **Scope-drift detection in /impl**: Add a "Scope Verification"
   step to impl.md command templates that fires before any
   implementation. The agent must check whether the current
   instruction maps to a task in the active task list. If not,
   it must update docs before implementing.

3. **Auto-doc-update behavior**: When scope drift is detected,
   the agent updates the minimum necessary docs:
   - Small change: add subtask to existing story in tasks file
   - Medium change: add new story to tasks file + update
     tech-design if architecture is affected
   - Large change: update PRD + tech-design + tasks, ask user
     to confirm

4. **Critical evaluation of user instructions**: The agent must
   evaluate all instructions (including clear ones) against PRD,
   tech-design, common sense, and technical feasibility before
   executing. Vague instructions must be clarified, not
   interpreted and immediately implemented.

5. **Deterministic /start commands**: Replace all inline
   `python3 ... exec <<'PY'` blocks in start.md with:
   - `python3 ~/.claude/rlm_scripts/rlm_repl.py status`
   - `Glob` tool for task file discovery
   - `git log --oneline -10` for recent activity
   - claude-mem MCP queries for historical context
   No dynamic Python code generation.

6. **Cross-tree consistency**: All changes apply to the 4
   command trees that have the affected commands: rlm-mem,
   coding, rlm, dev.

## Non-Functional Requirements

### Performance
- `/start` must complete in under 15 seconds with no user
  interaction required for permissions

### Security
- No changes to authentication or authorization
- No new external dependencies introduced

### Usability
- Zero learning curve — existing command invocations unchanged
- Agent behavior change is transparent (warns before acting)

### Reliability
- Scope-drift detection must not block normal in-scope work
- If scope check is uncertain, agent asks rather than blocks
- All changes are backward-compatible with existing task files

### Architecture
- Changes are limited to markdown command templates
- No code changes to rlm_repl.py or claude-mem plugin
- Document-first principle: docs are the source of truth

## Dependencies & Risks

### Dependencies
- **Internal**: Existing command templates (tech-design.md,
  impl.md, start.md) across all 4 trees
- **External**: Claude Code permission system (for /start
  frictionless behavior — user must allowlist `rlm_repl.py`)

### Risks
- **Risk 1**: Scope-drift detection may be too aggressive,
  flagging legitimate in-scope work as out-of-scope —
  *Mitigation*: Check against task list explicitly, not
  heuristically. When uncertain, ask user.
- **Risk 2**: Users may not have `rlm_repl.py` in their
  allowlist, still getting prompts —
  *Mitigation*: Document allowlist setup in README; minimize
  number of distinct commands to allowlist.
- **Risk 3**: Updating docs automatically may introduce errors
  in PRD/tech-design —
  *Mitigation*: For large changes, always ask user confirmation.
  For small changes (adding a subtask), the risk is low.

## Resolved Questions

- **Doc-first in /plan:check?** Yes — enforce in both `/impl`
  and `/plan:check`. If check discovers code that doesn't match
  docs, it should flag the drift.
- **Small vs large scope drift?** No strict threshold. "Small"
  means clarification, implementation detail, or matter of
  preference — things that don't constitute a new feature or
  critical change. The agent should be smart: if updating docs
  would create unnecessary overhead, delay, or context usage
  relative to the change, just implement it. Scope-drift
  detection is for genuinely new features or architectural
  changes that would break idempotency, not for nitpicking
  every instruction.
