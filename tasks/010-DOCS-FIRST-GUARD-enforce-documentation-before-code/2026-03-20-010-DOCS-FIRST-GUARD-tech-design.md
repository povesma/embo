# 010-DOCS-FIRST-GUARD: Enforce Documentation Before Code - Tech Design

**Status**: Revised (v2 — prompt-based enforcement)
**PRD**: [010-DOCS-FIRST-GUARD-prd.md](2026-03-20-010-DOCS-FIRST-GUARD-prd.md)
**Created**: 2026-03-20

---

## Overview

### V1 (abandoned): PreToolUse hook + marker file

The original design used two components:

1. **PreToolUse hook** (`docs-first-guard.sh`) — shell script on
   Edit/Write, checked allow-list + marker file, escalated to
   user permission outside `/impl`
2. **Prompt hardening** — removed soft exceptions from command files

**Why V1 was abandoned** (see PRD for full rationale):
- Hook's `"ask"` response breaks Shift+Tab "Allow all edits"
- Skipping the hook in `acceptEdits` mode silently disables the guard
- `systemMessage` warning in auto-edit mode goes unnoticed
- Marker file is binary — can't reason about semantic context
- Bash scripts can't evaluate whether an edit is contextually justified

The hook file (`docs-first-guard.sh`) remains in the repo for
reference but is **not registered** in settings.json and should
**not be installed**.

### V2 (current): Prompt-based semantic enforcement

Single component: **prompt instructions in command files** that
leverage Claude's full context to make semantic judgments about
whether an edit is documented/justified.

No hooks, no marker files, no filesystem state. Claude itself is
the enforcement mechanism — it has the context to distinguish a
POC during planning from undocumented production code changes.

---

## Component 1: PreToolUse Hook Script

### File location

`.claude/hooks/docs-first-guard.sh`

Installed to `~/.claude/hooks/docs-first-guard.sh` by `install.sh`.

### Hook registration

In the **user-level** `~/.claude/settings.json` (added by
`install.sh`), alongside the existing RTK rewrite hook:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "..." }]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/docs-first-guard.sh"
          }
        ]
      }
    ]
  }
}
```

**Why user-level, not project-level?** This project is an
installation package — it doesn't have a persistent `.claude/
settings.json` that lives in target projects. The hook protects
the user across ALL their projects, which is the desired behavior.
The `install.sh` script adds the hook entry to the user's global
`~/.claude/settings.json`.

### Hook input contract

PreToolUse receives on stdin:

```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file.ts",
    "old_string": "...",
    "new_string": "..."
  },
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "transcript_path": "/path/to/transcript.jsonl"
}
```

For `Write`, `tool_input` has `file_path` and `content`.

### Hook output contract

To escalate to user permission:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "..."
  }
}
```

To allow silently: exit 0 with no stdout.

### Decision logic

```
INPUT = read stdin JSON
FILE_PATH = tool_input.file_path

# 1. Allow-list: documentation and config files
if FILE_PATH ends with .md → exit 0
if FILE_PATH contains /tasks/ → exit 0
if FILE_PATH contains /.claude/ → exit 0
if FILE_PATH ends with .json → exit 0
if FILE_PATH ends with .yaml or .yml → exit 0
if FILE_PATH ends with .toml → exit 0
if FILE_PATH ends with .txt → exit 0

# 2. Marker file check: /impl active?
MARKER = ~/.claude/rlm_state/.impl-active
if MARKER exists AND is less than 2 hours old → exit 0

# 3. If stale marker exists → remove it silently
if MARKER exists AND is 2+ hours old → rm MARKER

# 4. Not allowed → ask user
output JSON with permissionDecision: "ask"
reason: message suggesting /impl or docs creation
```

### Allow-list rationale

| Pattern | Why allowed |
|---|---|
| `*.md` | Documentation — the whole point is to write docs first |
| `/tasks/` | Task files — docs-first workflow artifacts |
| `/.claude/` | Command files, hooks, config — meta-work |
| `*.json`, `*.yaml`, `*.toml` | Config files — not "code" |
| `*.txt` | Plain text — not code |

Everything else (`.ts`, `.py`, `.sh`, `.js`, `.go`, `.rs`, `.java`,
`.html`, `.css`, etc.) requires either an active `/impl` session or
user approval.

### Permission message

```
⚠️ No /impl session active — this code edit is undocumented.

Consider:
  • /rlm-mem:develop:impl — start documented implementation
  • /rlm-mem:plan:prd — create docs first
  • Allow this edit if it's a quick fix

(The docs-first-guard hook enforces this check. See README §Hooks.)
```

### Error handling

Following the `context-guard.sh` pattern:

- `trap 'exit 0' ERR` at the top — any error fails open (allows
  the edit)
- If `jq` is not installed: exit 0 (allow)
- If `file_path` is empty or missing: exit 0 (allow)
- If marker directory doesn't exist: proceed to "ask" (safe default)

### Script structure (pseudocode)

```bash
#!/usr/bin/env bash
set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)

# Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r \
  '.tool_input.file_path // empty') || exit 0
[ -z "$FILE_PATH" ] && exit 0

# --- Allow-list ---
case "$FILE_PATH" in
  *.md|*.json|*.yaml|*.yml|*.toml|*.txt) exit 0 ;;
esac
case "$FILE_PATH" in
  */tasks/*|*/.claude/*) exit 0 ;;
esac

# --- Marker file check ---
MARKER="$HOME/.claude/rlm_state/.impl-active"
if [ -f "$MARKER" ]; then
  STALE=$(find "$MARKER" -mmin +120 2>/dev/null)
  if [ -z "$STALE" ]; then
    exit 0  # fresh marker → /impl is active
  else
    rm -f "$MARKER"  # stale → clean up
  fi
fi

# --- Ask user ---
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: "⚠️ No /impl session active — this code edit is undocumented.\n\nConsider:\n  • /rlm-mem:develop:impl — start documented implementation\n  • /rlm-mem:plan:prd — create docs first\n  • Allow this edit if it is a quick fix\n\n(docs-first-guard hook — see README §Hooks)"
  }
}'
```

---

## Component 2: Marker File Management

### Marker file path

`~/.claude/rlm_state/.impl-active`

This directory already exists (used by RLM REPL for `state.pkl`).

### Marker creation in impl.md

Add as the very first step (before "Load Context"):

```markdown
### 0. Activate Implementation Session

```bash
touch ~/.claude/rlm_state/.impl-active
```

This signals the docs-first-guard hook that an `/impl` session
is active. Code edits will not trigger permission prompts.
```

### Marker cleanup in impl.md

Add as the final step (after "Update Task List"):

```markdown
### 8. Deactivate Implementation Session

```bash
rm -f ~/.claude/rlm_state/.impl-active
```
```

### Staleness protection

The hook uses `find "$MARKER" -mmin +120` to detect markers older
than 2 hours. If stale, the marker is deleted and the hook proceeds
to "ask". This handles:

- Session crashed mid-impl (marker left behind)
- User closed terminal without completing impl
- Context window exhausted before impl finished

2 hours is generous — most impl sessions complete in under 1 hour.
Short enough to prevent stale markers from suppressing the hook
across session boundaries.

### Race condition analysis

**Can the marker be created but never cleaned up?** Yes — if the
session crashes, context compresses, or the user quits. The
staleness check mitigates this. Worst case: the hook is suppressed
for up to 2 hours after a crash, then self-heals.

**Can the marker be cleaned up prematurely?** Only if Claude
executes the cleanup step before implementation is done. The prompt
places cleanup as the explicit final step, and the task completion
protocol prevents skipping ahead. Low risk.

---

## Component 3: Prompt Hardening

### Changes to start.md (lines 217-226)

**Current text:**
```
When the user asks to implement something after the session starts, check:
- **Docs exist and are consistent** → proceed to /impl
- **Docs missing or inconsistent** → flag, offer to create docs
- **Minor changes** (typos, config tweaks) → proceed without doc update
```

**New text (V2):**
```
When the user asks to implement something after the session starts:
- **Docs exist and are consistent** → suggest /rlm-mem:develop:impl
- **Docs missing or inconsistent** → stop, flag the gap, offer to
  create docs (PRD / tech-design / tasks) before implementing
- **Research, POC, or exploration** (e.g. during PRD/tech-design) →
  allow with a note that this is exploratory, not documented impl
- **Minor changes** (typos, config) → proceed, no doc update needed

Before editing any code file, Claude must assess the semantic context:
is this edit justified by an active task, ongoing research, or user
approval? If not, warn and suggest documenting first.
```

Key changes:
- Removed hook reference — enforcement is prompt-based
- Added research/POC case — planning phases need code exploration
- Kept minor changes exception — Claude can judge these semantically
- Changed "proceed to /impl" to "suggest /impl"

### Changes to impl.md (lines 23-48)

**Current "Scope Verification" section contains:**
- "If updating docs costs more context/time than the change itself,
  skip the update"
- "Be smart. The goal is maintaining idempotency for changes that
  matter, not creating bureaucratic overhead"

**Remove both sentences.** Replace with:

```
**Judgment call**: The clarification-level exception applies only to
implementation details within an existing task subtask — such as
choosing between two equivalent approaches, adjusting whitespace,
or picking a variable name. If the change adds new behavior,
modifies an API, or touches a file not listed in the task's
"Relevant Files" section, it requires a doc update first.
```

This keeps the escape valve for genuinely trivial decisions within
an active task, but removes the broad "be smart, skip docs" language
that Claude abuses to skip the check entirely.

---

## Component 4: Installation

### install.sh additions

After the existing hooks section:

```bash
# --- Docs-First Guard Hook ---
echo "Installing docs-first-guard hook..."
cp .claude/hooks/docs-first-guard.sh "$TARGET/hooks/docs-first-guard.sh"
chmod +x "$TARGET/hooks/docs-first-guard.sh"
```

For settings.json, the install script should check if a PreToolUse
entry with `docs-first-guard` already exists. If not, add it using
`jq`:

```bash
if command -v jq &>/dev/null; then
  SETTINGS="$TARGET/settings.json"
  if [ -f "$SETTINGS" ]; then
    # Check if already registered
    if ! jq -e '.hooks.PreToolUse[]? |
      select(.hooks[]?.command |
      test("docs-first-guard"))' "$SETTINGS" \
      >/dev/null 2>&1; then
      # Add the hook entry
      jq '.hooks.PreToolUse += [{
        "matcher": "Edit|Write",
        "hooks": [{
          "type": "command",
          "command": "bash ~/.claude/hooks/docs-first-guard.sh"
        }]
      }]' "$SETTINGS" > /tmp/_rlm_settings.tmp \
        && mv /tmp/_rlm_settings.tmp "$SETTINGS"
      echo "  ✓ Registered in settings.json"
    else
      echo "  ✓ Already registered in settings.json"
    fi
  fi
fi
```

### README additions

Add to §Hooks section:

- Purpose: prevents undocumented code edits
- How it works: fires on Edit/Write, checks for `/impl` marker
- How to bypass: approve at the prompt, or disable via
  `disableAllHooks: true`

---

## Integration Points

### Modified files

| File | Change | Risk |
|---|---|---|
| `.claude/commands/rlm-mem/develop/impl.md` | Add Step 0 (marker create) + Step 8 (marker cleanup) + tighten Scope Verification | Low — additive |
| `.claude/commands/rlm-mem/discover/start.md` | Rewrite Docs-First Principle (3 lines changed) | Low |
| `install.sh` | Add hook copy + settings registration | Medium — jq manipulation |
| `README.md` | Add hook documentation | Low |

### New files

| File | Purpose |
|---|---|
| `.claude/hooks/docs-first-guard.sh` | PreToolUse hook script |

---

## Trade-offs

### Considered: Project-level settings.json (rejected)

Could register the hook in `.claude/settings.json` committed to
THIS repo. But this repo is an installation package — the hook
should protect ALL user projects, not just this one. User-level
`~/.claude/settings.json` is the correct scope.

### Considered: Hard deny instead of ask (rejected)

`permissionDecision: "deny"` would hard-block all code edits
outside `/impl`. Too aggressive — users need the ability to make
quick fixes. "Ask" gives awareness without lockdown.

### Considered: Agent hook for semantic matching (deferred)

A `type: "agent"` hook could spawn a subagent to check whether the
edit matches an active task. More nuanced but costs an API call per
Edit/Write (~$0.005-0.02 each). Deferred to future version.

### Considered: Bash interception (rejected)

Matching on Bash would catch `sed`, `echo >`, etc. But would also
block `git status`, `python3 rlm_repl.py`, `ls`, and every other
shell command. Too broad. Edit/Write covers the vast majority of
code changes.

---

## Failure Modes

| Failure | Impact | Mitigation |
|---|---|---|
| jq not installed | Hook fails open (allows edit) | `trap 'exit 0' ERR` + jq presence check in install.sh |
| Marker file left from crashed session | Hook suppressed for up to 2h | Staleness check (`find -mmin +120`) auto-cleans |
| Claude skips `touch` at impl start | Hook fires during /impl | User sees prompt, approves. Minor friction but not blocking. |
| Claude skips `rm` at impl end | Hook suppressed until staleness | 2h timeout auto-cleans |
| User disables all hooks | No protection | Documented, intentional. User's choice. |
| File path not in tool_input | Hook fails open | `[ -z "$FILE_PATH" ] && exit 0` |

---

**Next Steps:**
1. Review and approve this technical design
2. Run `/rlm-mem:plan:tasks` to break down into implementation tasks
