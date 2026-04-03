# 015: Behavioral Reminder Hook — Technical Design

**Status**: Draft
**PRD**: [2026-04-01-015-behavioral-reminder-hook-prd.md](2026-04-01-015-behavioral-reminder-hook-prd.md)
**Created**: 2026-04-01

---

## Overview

Three deliverables:

1. **`behavioral-reminder.sh`** — `UserPromptSubmit` hook that classifies
   the incoming user prompt and injects a targeted `additionalContext`
   reminder pointing to the relevant rule tag in the command files
2. **Rule tag comments** — `<!-- RULE:X -->` HTML comments added to
   `dev:impl`, `dev:start`, and `dev:git` at the relevant sections
3. **`install.sh` update** — auto-registers the hook in `settings.json`
   using the same jq pattern as the statusLine registration

---

## Current Architecture (RLM Analysis)

**Existing hooks**:

- `context-guard.sh` (`UserPromptSubmit`): reads `transcript_path`
  from stdin JSON via Python, then does bash logic, outputs plain
  stdout text. Registered in `settings.json` as:
  ```json
  "UserPromptSubmit": [{"hooks": [{"type": "command",
    "command": "bash ~/.claude/hooks/context-guard.sh"}]}]
  ```
- `docs-first-guard.sh` (`PreToolUse`): reads stdin via `jq`,
  outputs JSON with `permissionDecision` + `systemMessage`

**`settings.json` hook schema** (live, from `~/.claude/settings.json`):
```json
"hooks": {
  "UserPromptSubmit": [
    {"hooks": [{"type": "command",
      "command": "bash ~/.claude/hooks/context-guard.sh"}]}
  ],
  "PreToolUse": []
}
```

**`install.sh` pattern for settings.json edits**:
Uses `jq` to transform the file in-place via a temp file. Guarded
by an idempotency check and a user prompt. Falls back to manual
instructions if `jq` is absent.

---

## Proposed Design

### Component 1: `behavioral-reminder.sh`

**Location**: `.claude/hooks/behavioral-reminder.sh`
(installed to `~/.claude/hooks/` by `install.sh`)

**Event**: `UserPromptSubmit`

**stdin fields used**:
- `prompt` — the user's raw text (only field needed; no transcript
  parsing required)

**Logic flow**:

```
stdin JSON
  → jq extracts .prompt → PROMPT_LOWER (lowercased)
  → classify into flags: CRITICISM, IMPL_REQUEST, GIT_REQUEST
  → build additionalContext string:
      always:   1-line tag-list baseline
      if flags: targeted reminder lines per flag
  → output JSON { hookSpecificOutput: { hookEventName, additionalContext } }
  → exit 0
```

**Classification patterns** (bash `case`, defined as named blocks at
top of script):

```bash
# CRITICISM patterns — triggers WITHSTAND-CRITICISM + CHALLENGE-INSTRUCTION
*"you're wrong"*|*"that's not right"*|*"why did you"*|*"you missed"*|\
*"i disagree"*|*"no,"*|*"incorrect"*|*"that's incorrect"*|\
*"you ignored"*|*"you should have"*

# IMPL_REQUEST patterns — triggers DOCS-FIRST + ONE-SUBTASK
*"implement"*|*"write the code"*|*"create the file"*|*"add feature"*|\
*"build"*|*"start task"*|*"start story"*|*"next subtask"*|\
*"next task"*|*"write a"*|*"create a"*

# GIT_REQUEST patterns — triggers GIT-SKILL
*"commit"*|*"push"*|*"pull request"*|*" pr"*|*"open a pr"*|\
*"create a pr"*|*"merge"*|*"git "*)
```

**Output format**:

```
[RULES ACTIVE: CHALLENGE-INSTRUCTION · WITHSTAND-CRITICISM · DOCS-FIRST · ONE-SUBTASK · GIT-SKILL]

[REMINDER:WITHSTAND-CRITICISM][REMINDER:CHALLENGE-INSTRUCTION]
Criticism or challenge detected. Before responding:
re-read <!-- RULE:WITHSTAND-CRITICISM --> in dev:start
and <!-- RULE:CHALLENGE-INSTRUCTION --> in dev:impl.
```

The baseline tag-list line is always present. Targeted blocks are
appended only when the relevant flag is set. Multiple flags can fire
on a single prompt.

**Error handling**: `trap 'exit 0' ERR` at top. Any parse failure,
missing field, or jq error → silent exit 0.

---

### Component 2: Rule tag comments in command files

**Format**: HTML comment on its own line, immediately before the
relevant section heading.

```markdown
<!-- RULE:CHALLENGE-INSTRUCTION -->
## Critical Evaluation of Instructions
```

This is invisible in rendered markdown but present in the raw text
that Claude receives when the command file is loaded as context.
Claude sees `<!-- RULE:CHALLENGE-INSTRUCTION -->` and can associate
it with the `[REMINDER:CHALLENGE-INSTRUCTION]` injected by the hook.

**Tag placements**:

| Tag | File | Before section |
|-----|------|----------------|
| `CHALLENGE-INSTRUCTION` | `dev:impl` | `## Critical Evaluation of Instructions` |
| `WITHSTAND-CRITICISM` | `dev:start` | `## Session Behavioral Rules` → `### Defend positions under questioning` |
| `DOCS-FIRST` | `dev:impl` | `## Scope Verification (Doc-First Development)` |
| `ONE-SUBTASK` | `dev:impl` | `## Task Implementation Protocol` |
| `GIT-SKILL` | `dev:git` | `## When to Use` |

---

### Component 3: `install.sh` changes

**Behavioral-reminder registration** — unconditional (no prompt).
It is a core workflow component, not optional. Idempotency check
only: if already registered, skip; otherwise register automatically.

**statusLine registration** — interactive, default Yes (`[Y/n]`).

**`--force` and `--yes` flags** added to all interactive prompts
via a `confirm()` function (same pattern as Homebrew/rustup):

```bash
confirm() {
    if [ "$FORCE" = "1" ]; then
        if [ "$YES" = "1" ]; then return 0; fi
        SKIPPED=$((SKIPPED + 1))
        return 1
    fi
    local yn=""
    read -r -p "$1" yn || true
    case "${yn:-${2:-n}}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}
```

Behavior matrix:

| Mode | statusLine `[Y/n]` | Remove old `[Y/n]` |
|------|--------------------|--------------------|
| Interactive, Enter | yes | yes |
| `--force` | no (safe) | no (safe) |
| `--force --yes` | yes | yes |

Behavioral-reminder: always registered regardless of flags.

A `SKIPPED` counter tracks how many prompts were auto-declined by
`--force`, and prints a summary at the end suggesting `--force --yes`
or interactive mode.

The `hooks.UserPromptSubmit` array may not exist yet; `+= [...]`
creates it if absent (jq behaviour).

---

## Data Contracts

**Hook stdin** (subset used):
```json
{ "prompt": "string — raw user message text" }
```

**Hook stdout** (on match):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "string — reminder text"
  }
}
```

**Hook stdout** (no match — baseline only, still JSON):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "[RULES ACTIVE: CHALLENGE-INSTRUCTION · WITHSTAND-CRITICISM · DOCS-FIRST · ONE-SUBTASK · GIT-SKILL]"
  }
}
```

The hook always outputs valid JSON. Plain stdout (user-visible) is
never used.

---

## Trade-offs

### Prompt classification vs transcript scanning

**Rejected**: Scan recent assistant messages for violation patterns
(ljw1004 approach). Requires JSONL parsing, slower (~50ms), detects
violations *after* they occur in the previous turn.

**Chosen**: Classify the incoming user prompt. No file I/O needed,
~5ms, fires *before* Claude responds to the triggering message.
Limitation: can produce false positives (e.g., "commit" in a
discussion about git theory). Acceptable — reminders are advisory,
false positives cost only a few extra tokens.

### Bash vs Python for classification

**Rejected**: Python subprocess. ~50ms startup cost on every prompt.
Keyword matching doesn't need regex — bash `case` with glob patterns
is sufficient and consistent with the existing hook style.

**Chosen**: Pure bash `case` statement. Pattern constants defined at
top of script (maintainable). ~5ms total execution.

### HTML comment vs visible tag marker

**Rejected**: `## [RULE:X] Section Name` — clutters headings, affects
rendering in any markdown preview.

**Chosen**: `<!-- RULE:X -->` on its own line before the heading.
Invisible when rendered, present in raw text, grep-friendly.

---

## Verification Approach

| Requirement | Method | Expected Evidence |
|---|---|---|
| Hook outputs JSON with additionalContext | `manual-run-claude` | Run hook with test stdin; confirm JSON output |
| Baseline tag-list present on every prompt | `manual-run-claude` | Send neutral prompt; inspect system-reminder in transcript |
| WITHSTAND-CRITICISM fires on criticism prompt | `manual-run-claude` | Send "you're wrong"; confirm reminder injected |
| DOCS-FIRST fires on impl request | `manual-run-claude` | Send "implement X"; confirm reminder injected |
| GIT-SKILL fires on commit/PR request | `manual-run-claude` | Send "commit my changes"; confirm reminder injected |
| No output on clean prompt (only baseline) | `manual-run-claude` | Send "what's the status"; confirm only baseline |
| install.sh registers hook in settings.json | `manual-run-claude` | Run install.sh; confirm settings.json updated |
| install.sh idempotent on second run | `manual-run-claude` | Run install.sh twice; confirm no duplicate entry |
| Rule tags visible in raw command files | `code-only` | Grep for `<!-- RULE:` in impl.md, start.md, git.md |
| Hook fails open on malformed stdin | `manual-run-claude` | Feed `{}` as stdin; confirm exit 0, no crash |

---

## Files to Create / Modify

**Create**:
- `.claude/hooks/behavioral-reminder.sh` — the hook script

**Modify**:
- `.claude/commands/dev/impl.md` — add `<!-- RULE:CHALLENGE-INSTRUCTION -->` and `<!-- RULE:DOCS-FIRST -->` and `<!-- RULE:ONE-SUBTASK -->`
- `.claude/commands/dev/start.md` — add `<!-- RULE:WITHSTAND-CRITICISM -->`
- `.claude/commands/dev/git.md` — add `<!-- RULE:GIT-SKILL -->`
- `install.sh` — add hook registration block
- `README.md` — document the new hook in §Hooks

---

## References

### Code (RLM)
- `.claude/hooks/context-guard.sh` — stdin parsing pattern, trap ERR,
  additionalContext output
- `.claude/hooks/docs-first-guard.sh` — jq stdin parsing, JSON output
- `~/.claude/settings.json` — live hook registration schema
- `install.sh:46-78` — statusLine jq registration pattern to replicate

### History (Claude-Mem)
- Task 009-FEEDBACK-LOOP — correction capture (complementary system)
- Obs #7462 — settings.json hook architecture confirmed

---

**Next Steps**:
1. Review and approve this design
2. Run `/dev:tasks` to break into implementation subtasks
