# 015: Behavioral Reminder Hook — PRD

**Status**: Draft
**Created**: 2026-04-01
**Author**: Claude (dev:prd workflow)

---

## Context

### The Problem

Claude Code has detailed behavioral rules in its loaded instructions
(`dev:impl`, `dev:start`) — challenge instructions, docs-first,
withstand criticism, one-subtask-at-a-time, use-git-skill — but routinely
ignores them during execution.

Adding more instructions to CLAUDE.md or prompts does not help:
the model reads them at session start, but they fade out of effective
attention. The rules are present in context; what is missing is a
mechanism that re-surfaces the right rule at the right moment — as
a reminder, not as a new instruction.

Known failure modes observed in production sessions:
- Claude agrees with user criticism immediately ("You're right, let
  me fix") without evaluating whether the criticism is correct
- Skips checking task list / docs before writing code
- Implements multiple subtasks without asking permission between them
- Makes git commits / PRs directly via shell commands instead of
  using the `/dev:git` skill

### The Insight

The `UserPromptSubmit` hook fires **before** Claude processes each
user prompt. By reading the incoming prompt — not Claude's response —
the hook can classify the situation and inject a short, targeted
reminder that Claude sees *before* it generates its response.

The hook does not try to detect whether Claude will violate a rule.
It detects situations that require specific rules to be active:
- User sends criticism / feedback → remind: withstand-criticism rule
- User requests code / implementation → remind: docs-first rule
- User requests git commit or PR → remind: use-git-skill rule
- User sends any prompt → 1-line baseline reminder always present

The reminder does not repeat the rule. It points back to the
authoritative text using a short, unique rule tag — so that Claude
consults the already-loaded instruction, not a paraphrase of it.

### Prior Work

**Task 009-FEEDBACK-LOOP** built after-the-fact correction capture.
This PRD is the before-the-fact complement: prevent the violation
rather than record it afterwards.

**Prior art**: `ljw1004` "You're right" gist uses a `UserPromptSubmit`
hook that scans recent *assistant* messages. This PRD uses a simpler
pattern: classify the *user's prompt* instead — more reliable, no
JSONL parsing required.

---

## Problem Statement

**Who**: Developers using RLM-Mem commands (`/dev:impl`, `/dev:git`,
`/dev:start`) in any project

**What**: Claude violates its own loaded behavioral rules because
nothing re-surfaces those rules at the moment the relevant
situation arises

**Why**: Violations cause wasted work — scope drift, wrong decisions
defended too late, git ops bypassing skill, multiple subtasks merged

**When**: Every user prompt that falls into a rule-triggering category

---

## Goals

### Primary Goal

At the moment the user submits a prompt that belongs to a
rule-triggering category, inject a short reminder that brings the
relevant existing rule to Claude's attention — using the rule's
unique tag, not by copying its text.

Example injection for a feedback prompt:

```
[REMINDER:WITHSTAND-CRITICISM] A criticism or challenge is present.
See dev:start §"Defend positions under questioning".
```

### Secondary Goal

Establish a **rule tagging convention** in existing command files
so that any future reminder or reference can point to a rule by
its tag rather than by line number or section name. Tags are stable
identifiers; section names are not.

---

## User Stories

### Story 1: Baseline reminder always present

**As a** developer running any RLM-Mem session
**I want** a 1-line reminder visible to Claude on every prompt
**So that** behavioral rules stay in effective attention throughout

**Acceptance Criteria**:
- [ ] Every `UserPromptSubmit` injects one short line listing the
  active rule tags (e.g., `[REMINDER: rules active:
  CHALLENGE-INSTRUCTION, WITHSTAND-CRITICISM, DOCS-FIRST,
  GIT-SKILL, ONE-SUBTASK]`)
- [ ] This line is injected via `additionalContext` JSON path
  (not user-visible in the chat UI)
- [ ] The hook never blocks, never exits non-zero

### Story 2: Targeted reminder on criticism/feedback prompts

**As a** developer giving feedback or corrections
**I want** the WITHSTAND-CRITICISM and CHALLENGE-INSTRUCTION rules
  brought to Claude's attention before it responds to my feedback
**So that** Claude evaluates my criticism instead of agreeing reflexively

**Acceptance Criteria**:
- [ ] When the user's prompt contains feedback/criticism signals
  (e.g., "you're wrong", "that's not right", "why did you",
  "you missed", "I disagree", "no,"), targeted
  `[REMINDER:WITHSTAND-CRITICISM]` and
  `[REMINDER:CHALLENGE-INSTRUCTION]` lines are injected alongside
  the baseline reminder
- [ ] The injected text does not reproduce the rule — it names the
  tag and references the command file section

### Story 3: Targeted reminder on code/implementation requests

**As a** developer asking Claude to implement something
**I want** the DOCS-FIRST and ONE-SUBTASK rules brought to
  Claude's attention before it starts coding
**So that** it checks the task list and asks for subtask-by-subtask
  approval before implementing

**Acceptance Criteria**:
- [ ] When the user's prompt contains implementation-request signals
  (e.g., "implement", "write the code", "create the file",
  "add feature", "build", "start task"), targeted
  `[REMINDER:DOCS-FIRST]` and `[REMINDER:ONE-SUBTASK]` lines are
  injected
- [ ] Reminder fires even inside `/dev:impl` sessions (rules apply
  within impl too)

### Story 4: Targeted reminder on git/PR requests

**As a** developer asking for a commit or PR
**I want** the GIT-SKILL rule brought to Claude's attention
**So that** it uses `/dev:git` instead of running git commands directly

**Acceptance Criteria**:
- [ ] When the user's prompt contains git-operation signals
  (e.g., "commit", "push", "pull request", "PR", "merge"),
  a targeted `[REMINDER:GIT-SKILL]` line is injected pointing to
  `dev:git` skill
- [ ] This reminder covers both `/dev:git` sessions and sessions
  where the user casually asks Claude to commit

### Story 5: Rule tags embedded in existing command files

**As a** developer or maintainer of RLM-Mem command files
**I want** each behavioral rule in `dev:impl` and `dev:start`
  to have a unique short tag
**So that** reminders can point to rules by tag, and the tag serves
  as a stable reference in all future hooks and corrections

**Acceptance Criteria**:
- [ ] Each behavioral rule section in `dev:impl` and `dev:start`
  that is covered by a reminder gets a tag comment in this format:
  `<!-- RULE:CHALLENGE-INSTRUCTION -->`,
  `<!-- RULE:WITHSTAND-CRITICISM -->`, `<!-- RULE:DOCS-FIRST -->`,
  `<!-- RULE:ONE-SUBTASK -->`, `<!-- RULE:GIT-SKILL -->`
- [ ] The hook's reminder text uses these exact tag names
- [ ] Tags do not modify how the command files are read or displayed

---

## Rule Tag Definitions

The following tags are proposed for this feature. The authoritative
text lives in the referenced command file section.

| Tag | Rule in plain words | Source |
|-----|---------------------|--------|
| `CHALLENGE-INSTRUCTION` | Before acting — assess whether the instruction is correct, in-scope, technically sound. Could the user be mistaken? | `dev:impl §Critical Evaluation` |
| `WITHSTAND-CRITICISM` | When challenged or criticized — assess whether they're right before changing position. Don't automatically agree. | `dev:start §Defend positions` |
| `DOCS-FIRST` | Before writing code — a documented task must exist. | `dev:impl §Scope Verification` |
| `ONE-SUBTASK` | Implement one subtask at a time; ask permission before next. | `dev:impl §Task Implementation Protocol` |
| `GIT-SKILL` | Use `/dev:git` for all git operations; never run git/gh commands directly. | `dev:git §When to Use` |

---

## Requirements

### Functional Requirements

**FR-1**: `UserPromptSubmit` hook (`behavioral-reminder.sh`)
- Reads `prompt` field from stdin JSON (no transcript parsing needed)
- Classifies prompt into one or more categories via string matching
- Outputs JSON with `hookSpecificOutput.additionalContext` containing:
  - Always: 1-line tag-list reminder
  - If feedback/criticism detected: `[REMINDER:WITHSTAND-CRITICISM]` +
    `[REMINDER:CHALLENGE-INSTRUCTION]` with section reference
  - If implementation request detected: `[REMINDER:DOCS-FIRST]` +
    `[REMINDER:ONE-SUBTASK]` with section reference
  - If git/PR request detected: `[REMINDER:GIT-SKILL]` with
    `/dev:git` reference
- `trap 'exit 0' ERR` — fails open on every error

**FR-2**: Rule tags added to existing command files
- `dev:impl` and `dev:start` and `dev:git` receive `<!-- RULE:X -->`
  comments immediately before or inside the relevant section headings
- No functional change to the command files; comments only

**FR-3**: Hook registered in `settings.json`
- `UserPromptSubmit` event gets `behavioral-reminder.sh` hook
- Registration follows same schema as existing hooks

**FR-4**: `install.sh` and `install.ps1` updated
- `behavioral-reminder.sh` copied to `~/.claude/hooks/`
- `settings.json` registration included in install

### Non-Functional Requirements

**NFR-1 Performance**: Hook must complete in < 100ms. Since it reads
only the prompt string (no file I/O), this is achievable with pure
bash or minimal Python.

**NFR-2 Fail-open**: Never block Claude from responding. Exit 0 on
all error paths.

**NFR-3 No rule duplication**: Hook reminder text must not copy
rule prose from command files. Tag + section reference only.

**NFR-4 User-invisible**: All output goes via `additionalContext`
JSON path. No plain stdout (which would appear in UI).

**NFR-5 Maintainability**: Detection patterns are defined as
a named constant block at the top of the script (e.g., a
`CRITICISM_PATTERNS` list), not scattered through logic.

### Technical Constraints

- Shell script (`bash`), consistent with existing hooks
- `jq` for JSON parsing (available on target machines)
- Python3 acceptable for complex logic if needed
- Must work on macOS and Linux (no `bash` version assumptions)
- No new dependencies beyond existing hook requirements

---

## Out of Scope

- Post-compaction amnesia handling (project does not use compaction)
- `PreToolUse` Bash hook for git-skill bypass — the `UserPromptSubmit`
  prompt-classifier approach covers this at the right moment
- Blocking any command or prompt
- Windows PowerShell hook version
- Violation analytics or reporting
- ML-based pattern detection (string matching only)

---

## Success Metrics

1. **WITHSTAND-CRITICISM followed**: "You're right" / reflexive
   agreement responses eliminated in sessions where hook is active
2. **Docs-first compliance**: No undocumented code changes during
   `/dev:impl` sessions with hook active
3. **Git skill usage**: No direct `git commit`/`gh pr` commands
   outside `/dev:git` sessions
4. **Zero false blocks**: Hook never prevents Claude from responding

---

## References

### From Codebase (RLM)

- `.claude/hooks/context-guard.sh` — existing `UserPromptSubmit`
  hook (stdin JSON parsing, `additionalContext` pattern, `trap ERR`)
- `.claude/commands/dev/impl.md` — rule authority for
  CHALLENGE-INSTRUCTION, DOCS-FIRST, ONE-SUBTASK tags
- `.claude/commands/dev/start.md` — rule authority for
  WITHSTAND-CRITICISM tag
- `.claude/commands/dev/git.md` — rule authority for GIT-SKILL tag

### From History (Claude-Mem)

- Task 009-FEEDBACK-LOOP: after-the-fact correction capture
  (this feature is the before-the-fact complement)
- Obs #7355: "Workflow principle for responding to user questions"
  (WITHSTAND-CRITICISM rule origin)
- `ljw1004` "You're right" gist: reactive transcript-scanning hook
  (this feature uses simpler prompt-classification instead)

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/dev:tech-design` for the hook design and tag placement
3. Run `/dev:tasks` to break into implementation subtasks
