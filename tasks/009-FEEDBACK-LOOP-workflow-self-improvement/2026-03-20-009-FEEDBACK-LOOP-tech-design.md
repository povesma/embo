# 009-FEEDBACK-LOOP: Workflow Self-Improvement - Technical Design

**Status**: Draft
**PRD**: [009-FEEDBACK-LOOP-prd.md](2026-03-20-009-FEEDBACK-LOOP-prd.md)
**Created**: 2026-03-20

---

## Overview

Two deliverables:

1. **Prompt addition to `impl.md`** — behavioral guidance that teaches
   Claude to recognize user corrections and save them as claude-mem
   observations directly via the MCP save tool.

2. **New command `support/improve.md`** — queries claude-mem for
   correction observations, groups by pattern, walks user through
   curation, and produces a Markdown change proposal.

No scripts, no temp files, no new binaries. All changes are to `.md`
command prompt files. Observations go straight to claude-mem via its
native MCP `save_memory` tool — no write+read hook workaround.

---

## Component 1: Correction Recognition (impl.md addition)

### Responsibility

Detect when the user corrects Claude's behavior and silently save
a structured observation to claude-mem. Must not interrupt the
implementation flow.

### What constitutes a correction

A correction is when the user redirects **how Claude works**, not
**what Claude works on**:

| Correction (capture) | Not a correction (ignore) |
|---|---|
| "Use Context7, don't guess the API" | "Let's do feature B instead" |
| "Don't add comments to code you didn't change" | "Actually, make that field optional" |
| "Check the web first" | "I changed my mind about the design" |
| "That's over-engineered, simplify" | "Add error handling for X case" |
| "This step should verify tests exist first" | "Skip task 3, it's not needed" |

**Rule of thumb**: If the user's message would be equally valid in a
different project on a different feature, it's a behavioral correction.
If it's specific to the current feature/task, it's a scope/design
change.

### Observation data contract

Saved via `mcp__plugin_claude-mem_mcp-search__save_memory` with these
fields encoded in the text body:

```
[TYPE: CORRECTION]
[CATEGORY: verification|code-style|workflow|approach|process]
[WORKFLOW-STEP: impl|start|prd|tech-design|tasks|check]
[SEVERITY: pattern|one-off]
[STATUS: pending]

**What happened**: {what Claude did or was about to do}
**What user wanted**: {the correction, in user's words where possible}
**Context**: {brief context — what task/file was being worked on}
```

**Field definitions:**

- **CATEGORY** — one of five values:
  - `verification`: User redirected to external source (Context7, web,
    docs) instead of Claude guessing from memory/source
  - `code-style`: Code formatting, naming, comments, test patterns
  - `workflow`: Skip/add/change workflow steps or command behavior
  - `approach`: Over-engineering, wrong tool, wrong pattern choice
  - `process`: New idea for how the workflow should work
- **SEVERITY** — Claude's best judgment:
  - `pattern`: Likely applies broadly (e.g., "always check web first")
  - `one-off`: Likely context-specific (e.g., "this particular API
    changed last week, check the docs")
- **STATUS** — lifecycle marker:
  - `pending`: Not yet reviewed by user
  - `curated`: Included in a curation proposal

**Title format**: `Correction: {short description}`

**Project**: Set to current project name for scoping.

### Where in impl.md

Add a new section **"Correction Capture"** after the existing
"Scope Verification" section (after line 48). This positions it as a
behavioral rule alongside other behavioral rules, before the Process
steps.

### Prompt text (exact addition)

```markdown
## Correction Capture

When the user corrects how you work — redirecting your approach,
fixing your code style, telling you to verify externally, or
suggesting a workflow improvement — silently save a correction
observation to claude-mem. Do NOT announce that you are saving it.
Do NOT interrupt the flow.

**What to capture** (behavioral corrections):
- "Use Context7 / check the web / read the docs" → category: verification
- "Don't add comments / wrong naming / simplify" → category: code-style
- "Skip this step / add a check for X" → category: workflow
- "That's over-engineered / use a simpler approach" → category: approach
- "We should always do X before Y" → category: process

**What NOT to capture** (scope/design changes):
- "Let's do feature B instead" — scope change
- "Make that field optional" — design decision
- "Skip task 3" — task prioritization

**How to save**:
mcp__plugin_claude-mem_mcp-search__save_memory(
  title="Correction: {short description}",
  text="[TYPE: CORRECTION]\n[CATEGORY: {cat}]\n[WORKFLOW-STEP: impl]\n[SEVERITY: {pattern|one-off}]\n[STATUS: pending]\n\n**What happened**: {what you did}\n**What user wanted**: {their correction}\n**Context**: {task/file being worked on}"
)

Save immediately when the correction occurs. Then continue with
the corrected approach. No acknowledgment of the save.
```

### Rejected alternative: write+read hook pattern

The health check uses Write → Read → hook captures. For corrections,
this adds 2 tool calls per correction and creates temp file clutter.
claude-mem's native `save_memory` MCP tool writes directly — one call,
no files, no hook dependency.

---

## Component 2: Conditional Suggestion (impl.md addition)

### Responsibility

At the natural end of an `/impl` session (all subtasks done, or user
signals they're wrapping up, or context is running low), check whether
any corrections were captured and suggest `/rlm-mem:support:improve`
only if material exists.

### Where in impl.md

Add to the existing "Step 7: Update Task List and Documentation"
section (after line 176), as a final sub-step:

```markdown
### 8. Session Wrap-Up Check

Before ending the session, check for captured corrections:

mcp__plugin_claude-mem_mcp-search__search(
  query="[TYPE: CORRECTION] [STATUS: pending]",
  limit=1
)

- If results exist: suggest
  `"{N} workflow corrections captured — run /rlm-mem:support:improve
  to review and package feedback"`
- If no results: say nothing about corrections
```

### Design decision: search query

The search for `[TYPE: CORRECTION] [STATUS: pending]` relies on
claude-mem's text search matching these exact tags. This is the same
pattern used by `[TYPE: HEALTH-CHECK]` in the health check command —
proven to work.

---

## Component 3: Curation Command (support/improve.md)

### Responsibility

Query accumulated corrections, group by pattern, present to user for
accept/edit/reject curation, assemble and display a Markdown proposal.

### File location

`.claude/commands/rlm-mem/support/improve.md`

This creates a new "Support" phase in the command structure alongside
existing discover/plan/develop phases.

### Curation flow

```
┌─────────────────────────────────────────┐
│  Step 1: Query claude-mem               │
│  search "[TYPE: CORRECTION]             │
│          [STATUS: pending]"             │
│  → fetch full observations              │
├─────────────────────────────────────────┤
│  Step 2: Group by CATEGORY              │
│  Sort groups by frequency (desc)        │
│  Within group: merge near-duplicates    │
├─────────────────────────────────────────┤
│  Step 3: Present each group             │
│  Show: category, count, examples,       │
│  suggested change (which file + rule)   │
│  User: accept / edit / reject           │
├─────────────────────────────────────────┤
│  Step 4: Mark curated corrections       │
│  save_memory with [STATUS: curated]     │
│  referencing original correction IDs    │
├─────────────────────────────────────────┤
│  Step 5: Assemble + display proposal    │
│  Markdown formatted for GitHub issue    │
│  User copies or saves as they prefer    │
└─────────────────────────────────────────┘
```

### Step 1: Query

```
mcp__plugin_claude-mem_mcp-search__search(
  query="[TYPE: CORRECTION] [STATUS: pending]",
  limit=50
)
```

Then fetch full observations via `get_observations` for all returned
IDs.

If zero results: output `"No pending corrections to review."` and stop.

### Step 2: Grouping logic

Claude performs the grouping in-context (no external tool needed):

1. Parse each observation's `[CATEGORY: ...]` tag
2. Group observations by category
3. Within each category, identify near-duplicates by comparing the
   "What user wanted" text semantically (Claude's judgment)
4. Sort categories by total observation count, descending
5. For each group, select 1-3 representative examples

### Step 3: Interactive curation

For each category group, present to user via AskUserQuestion:

```
Category: verification (3 corrections across 2 sessions)

Examples:
  1. "Use Context7 to look up API docs instead of guessing from source"
  2. "Check the web for current library version before assuming"
  3. "Read official docs, don't infer from test files"

Suggested change:
  File: .claude/commands/rlm-mem/develop/impl.md
  Rule: "Before using any external library API, look up current
  documentation via Context7 or web search. Do not infer API
  signatures from source code or memory."

[Accept] [Edit] [Reject]
```

- **Accept**: Include in proposal as-is
- **Edit**: User provides modified text; include modified version
- **Reject**: Exclude from proposal; still mark as curated (so it
  doesn't resurface)

### Step 4: Mark as curated

After curation completes, save a single observation:

```
mcp__plugin_claude-mem_mcp-search__save_memory(
  title="Curation: {date} — {N} corrections reviewed",
  text="[TYPE: CURATION-LOG]\n[DATE: {date}]\n[REVIEWED-IDS: {id1, id2, ...}]\n[ACCEPTED: {N}]\n[REJECTED: {M}]\n\nCorrection IDs reviewed: {list}\nAccepted groups: {summary}\nRejected groups: {summary}"
)
```

For individual corrections, update their status by saving a new
observation that references the original:

```
mcp__plugin_claude-mem_mcp-search__save_memory(
  title="Correction status: curated — {original title}",
  text="[TYPE: CORRECTION-STATUS]\n[ORIGINAL-ID: {id}]\n[STATUS: curated]\n[DECISION: accepted|rejected]\n[CURATION-DATE: {date}]"
)
```

**Why a separate status observation instead of editing the original?**
claude-mem observations are immutable — there's no update/edit API.
The curation command searches for `[STATUS: pending]` and excludes
IDs that have a corresponding `[TYPE: CORRECTION-STATUS]` observation.

### Step 5: Proposal assembly

The proposal is pure Markdown text, output directly to the
conversation. The user copies it.

### Proposal template

```markdown
# RLM-Mem Workflow Improvement Proposal

**Generated**: {date}
**Project**: {project_name}
**Corrections reviewed**: {total} ({accepted} accepted, {rejected} rejected)
**Date range**: {earliest correction} — {latest correction}

---

## Summary

{1-2 sentence overview of the main themes}

---

## Proposed Changes

### 1. {Category}: {Pattern title}

**Pattern observed** ({N} occurrences across {M} sessions):
{Description of what keeps happening}

**Examples from sessions**:
- "{example 1 — user's actual words}"
- "{example 2}"

**Suggested change**:
- **File**: `{path to command file}`
- **Section**: {which section to modify}
- **Add rule**: "{the behavioral rule to add}"

---

### 2. {Next category group}

{Same structure}

---

## Raw Corrections

<details>
<summary>Full correction observations ({N} total)</summary>

| # | Date | Category | What happened → What user wanted |
|---|------|----------|----------------------------------|
| 1 | {date} | {cat} | {summary} |
| ... | | | |

</details>

---

*Generated by `/rlm-mem:support:improve`. Submit as a GitHub issue
at {repo URL} or send to the project maintainer.*
```

### Suggested change mapping

The curation command must recommend which file to change for each
correction category. Default mapping:

| Category | Primary target file | Rationale |
|---|---|---|
| `verification` | `develop/impl.md` | Implementation behavior |
| `code-style` | `develop/impl.md` § Code Style | Coding conventions |
| `workflow` | Varies — depends on which step | Workflow step behavior |
| `approach` | `develop/impl.md` § Critical Evaluation | Decision-making guidance |
| `process` | May require new section or new command | Process innovation |

Claude should read the target file during curation to provide a
specific section reference, not just the filename.

---

## Component 4: Documentation Updates

### README.md

Add `/rlm-mem:support:improve` to the Available Commands section.
New phase: **Support**.

### Command README

Add Support phase table to `.claude/commands/rlm-mem/README.md`
(if it exists; otherwise create during task execution).

---

## Integration Points

### Modified files

| File | Change | Risk |
|---|---|---|
| `.claude/commands/rlm-mem/develop/impl.md` | Add Correction Capture section (~30 lines) + Session Wrap-Up Check (~10 lines) | Low — additive only, no existing behavior changed |

### New files

| File | Purpose |
|---|---|
| `.claude/commands/rlm-mem/support/improve.md` | Curation command |

### claude-mem observation types introduced

| Type tag | Purpose | Written by |
|---|---|---|
| `[TYPE: CORRECTION]` | Raw correction observation | impl.md (auto) |
| `[TYPE: CORRECTION-STATUS]` | Curation status update | support/improve.md |
| `[TYPE: CURATION-LOG]` | Curation session summary | support/improve.md |

---

## Trade-offs

### Considered: Write+Read hook pattern (rejected)

The PostToolUse hook captures file reads as observations. Could write
corrections to temp files and read them back. **Rejected**: adds 2 tool
calls per correction, creates temp file clutter, and the hook may not
fire reliably (per health check findings). Direct `save_memory` call
is simpler and more reliable.

### Considered: In-memory accumulation with batch save (rejected)

Collect corrections in Claude's context, save all at session end.
**Rejected**: corrections lost if session crashes or context compresses.
Per-correction immediate save is safer — the cost is one MCP call.

### Considered: Editing original observations for curation status (rejected)

claude-mem has no update API. Observations are immutable. The
CORRECTION-STATUS companion observation pattern is the standard
workaround — same approach used by other systems that track lifecycle
on immutable records.

### Considered: Local state file for curation tracking (rejected)

`.claude/rlm_state/curated-corrections.json` would be simpler but
not portable across machines. claude-mem is already the single source
of truth for cross-session state.

---

## Failure Modes

| Failure | Impact | Mitigation |
|---|---|---|
| Claude fails to recognize a correction | Correction not captured | Acceptable — partial capture is still valuable. User can also file feedback manually. |
| Claude over-captures (false positive) | Noise in correction pool | User rejects during curation. Low cost. |
| save_memory call fails mid-impl | Correction lost | Acceptable — impl flow continues uninterrupted. |
| claude-mem unavailable during curation | Command cannot run | Check at start, report error with fix instruction (same as health check pattern). |
| User runs /support:improve with 100+ corrections | Long curation session | Group aggressively; present top 5 categories. Offer to export all raw data in collapsible section. |

---

**Next Steps:**
1. Review and approve this technical design
2. Run `/rlm-mem:plan:tasks` to break down into implementation tasks
