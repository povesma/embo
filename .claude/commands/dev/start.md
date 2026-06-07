---
description: Start a coding session with comprehensive context from RLM code analysis and claude-mem historical knowledge. Use at the beginning of each coding session.
allowed-tools: Bash(cat ~/.claude/active-profile.yaml *) Read(~/.claude/active-profile.yaml) Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py *) Bash(git log *) Bash(git diff *)
---

# Start embo Coding Session

Start a coding session with comprehensive context from both RLM code analysis and claude-mem historical knowledge.

## When to Use

- **Beginning of each coding session**
- After `/dev:init` has been run
- When you need full project context
- Resuming work after a break

## What This Command Does

1. **Retrieves historical context** from claude-mem
2. **Analyzes current codebase** with RLM
3. **Synthesizes** both into actionable session summary
4. **Recommends** next task based on data

## Process

### Step 0: Load Profile

Run this exact command — do not paraphrase, do not rewrite the
shape. The skill's pre-approved permission entry matches this
line literally:

```bash
cat ~/.claude/active-profile.yaml 2>/dev/null || echo "NO_PROFILE"
```

If the output is the literal string `NO_PROFILE`, use defaults:
rlm=true, memory_backend=claude-mem, docs_first=strict. Otherwise
parse the YAML for profile fields. Note the active profile name
(or "default") in the session summary output.

## Session Behavioral Rules

These rules apply for the entire session, across all commands and
conversation turns. Load them once here; do not repeat in other commands.

<!-- RULE:WITHSTAND-CRITICISM -->
### Defend positions under questioning

When the user asks a challenging question — "Is it really like this?",
"Do we really need it?", "Why do you think that's right?" — treat it
as a **request for justification**, not an instruction to change.

**Do:**
- Give a direct answer: "Yes, because X and Y" or "No, actually..."
- Defend the original position if the reasoning holds
- If genuinely uncertain: say so, explain the trade-offs, let the user
  decide with full information

**Do not:**
- Cave to the question itself — a question is not a counter-argument
- Change position because the user sounds sceptical or dissatisfied
- Interpret pushback as proof of being wrong

**Only change position when:**
1. The user presents a counter-argument that actually rebuts your reasoning
2. The user explicitly instructs a change ("do it differently", "change
   this to X")

Capitulating to pressure without a reason produces worse outcomes and
denies the user the explanation they were asking for.

<!-- RULE:CLEAR-OPTIONS -->
### Present choices as scannable options

Users do not read carefully — they scan. Anything inside a long line
or a paragraph is missed. Whenever you offer the user a decision —
including questions joined by "or" ("should we do X or Y?") — surface
the options, do not steer them.

**Do:**
- Put each option on its own line, visually equal to its siblings —
  use `AskUserQuestion`, or `a) / b) / c)` in text
- Give each option a short description inline
- Mark a recommended option only when one genuinely is

**Do not:**
- Bury alternatives in prose or inside a single sentence
- Join distinct choices with "or" in running text — that is the exact
  pattern this rule exists to prevent

<!-- RULE:PLAIN-ENGLISH -->
### Write in plain English

The user reads each response word by word to judge the technical state
of the work. A non-literal phrase forces the reader to stop, decode the
intended meaning, and check whether it matches their own. Write so the
reader can take each word at face value.

**Do:**
- Use the literal word for the thing: "I will check the logs", not
  "I'll dig into the logs"; "this is incomplete", not "this is
  half-baked"
- Keep correct technical terms (for example "race condition",
  "opcache", "OOMKilled") — these are precise names, not jargon
- When you describe a state, name what is true, what is not, and the
  consequence

**Do not:**
- Use idioms, metaphors, similes, analogies, or other figurative
  phrases (for example "smoking gun", "moving parts", "kicks the can")
- Compare unrelated things to explain a point — state the thing
  directly
- Reach for a colorful word when a plain one says the same thing

<!-- RULE:REDIRECT-CMD-OUTPUT -->
### Do not hide a command's exit code or error output

When you run a command to learn whether it worked, the exit code and
the error text are the result. A pipeline returns the exit code of its
last stage, so piping a command into `tail` or `head` replaces the
command's exit code with the filter's — which almost always succeeds.
A failure then reads as a pass, and the lines that explain the failure
can be discarded.

**Do:**
- Read the command's own exit code. Run the command on its own and
  check `$?`, or use `&&` / `||`
- For large output, redirect to a file and read the file:
  `cmd > /tmp/out.log 2>&1; echo $?` — the full record and the true
  exit code both survive
- If you must pipe to a filter, set `set -o pipefail` first so the
  pipeline reports the command's failure
- When a command fails, read the lines that explain why — the first
  error or the stack trace — not only the last few lines

**Do not:**
- End a verification command with `| tail -N` or `| head -N` without
  `pipefail` — the exit code becomes the filter's, and a failure looks
  like a pass
- Truncate combined `2>&1` output with a fixed line count when checking
  for failure — the error line can be pushed out of the window by
  normal output
- Conclude a command succeeded from a clean-looking truncated tail.
  Assume it failed until the exit code proves otherwise

<!-- RULE:DECIDE-OR-ASK -->
### Decide what you can; ask only about genuine blockers

Asking about choices you could resolve yourself slows the work. Test:
if you could answer your own "what is best here?" with an obvious
answer, that is the answer — act on it.

**Decide yourself, then report** — anything recoverable: reading,
editing files, naming, internal structure, order of independent steps,
local config, commits, pushes to a feature branch, opening a PR. State
the choice and a one-line reason.

**Always ask first** — irreversible or shared-state actions
(force-push, merge to a shared base, delete data or branches, send
external messages — the existing safety rules, unchanged), and
*trapdoors*: choices that look reversible but freeze once data or
callers depend on them (schema, public API contract, data format).

**When deciding, rank:** (1) best practice, (2) long-term
maintainability, (3) DR-readiness (tested rollback, recoverable
failure). Your coding time is cheap — never trade a better option to
save it. Keep complexity lowest: simplest option that meets the
criteria (KISS, YAGNI).

**When you ask:** escalate only a real blocker, and bring a recommended
option with a reason — do not hand the analysis back.

Then make clear *what kind* of question it is, because the kinds have
opposite consequences and the user must know which they are answering:
- **Exclusive choice** — picking one **drops** the others
- **Ordering** — all options happen; you are only choosing what comes
  first, nothing is dropped
- **Combinable** — independent; one does not affect the others

If you blur these, the user decides on a false picture — discarding an
option they meant to keep, or assuming the rest still happen when they
do not. A decision made on a wrong understanding is worse than no
decision, because it looks settled. One option per line.

### Step 1: Verify Systems

**(Skip if profile `tools.rlm` is `false`)**

```bash
# Check RLM status
python3 ~/.claude/rlm_scripts/rlm_repl.py status
```

**If not initialized**: Suggest running `/dev:init` first

**Capture**:
- Project path
- Total files indexed
- Languages
- Last indexed timestamp

### Step 2: Query Claude-Mem for Historical Context

**(Skip if profile `tools.memory_backend` is `none`)**

```
mcp__plugin_claude-mem_mcp-search__search(query="project overview goals architecture", limit=5)
mcp__plugin_claude-mem_mcp-search__search(query="implementation completed features recent work", limit=10, orderBy="created_at DESC")
mcp__plugin_claude-mem_mcp-search__search(query="task list TODO in progress", limit=5)
```
Fetch full observations for top results with `mcp__plugin_claude-mem_mcp-search__get_observations`.

Extract: project goals, completed features, active tasks, recent decisions, known issues.

### Step 3: Codebase Context

**Do not** use Bash loops (`for`, `while`), `find`, or `$(...)`
substitution for the discovery steps below. The harness refuses
to auto-approve those constructs. Use the **Glob tool** as
directed; if Glob is unavailable, skip the step.

- Docs: use the **Glob tool** (not Bash, not `find`) with pattern
  `**/README*.md`, then again with `**/CLAUDE*.md`. Read the
  matched files at the project root only.
- Tasks: use the **Glob tool** (not Bash, not `find`) with pattern
  `tasks/**/*-tasks.md`. Discard matches whose path contains
  `/archive/`. Read the surviving active task files.
- Git: run these two commands exactly as shown. Do not change
  flags, count, or `HEAD` reference; they are pre-approved at
  these exact prefixes.

```bash
git log --oneline -10
git diff --stat HEAD
```

### Step 4: Synthesize Session Summary

Combine findings from claude-mem and RLM into comprehensive summary:

```markdown
# 🚀 Session Started: {project_name}

*Generated from RLM code analysis + claude-mem historical context*

## 📊 Project Overview

{overview_from_claude_mem_or_readme}

**Repository Statistics** (RLM):
- **Files**: {total_files:,} files ({size_mb:.1f} MB)
- **Primary languages**: {lang_breakdown}
- **Last indexed**: {rlm_timestamp}

## ✅ Completed Features

{completed_features_from_claude_mem}

Recent implementations:
{recent_work_from_mem}

## 🏗️ Current Architecture

{architecture_from_mem_or_docs}

**Key Patterns Discovered** (RLM):
{patterns_if_analyzed}

## 📝 Active Tasks

### From Task Files (RLM):
{active_tasks_from_rlm_analysis}

### From Memory (Claude-Mem):
{in_progress_tasks_from_mem}

## 🔥 Recent Activity

**Most Modified Files** (Past week):
{recently_modified_from_git}

**Recent Observations** (Claude-Mem):
{recent_observations}

## 💡 Recommended Next Task

Based on:
- Task priorities from {task_file_or_mem}
- Current momentum (recently modified areas)
- Historical context (what makes sense next)

**Suggestion**: {next_task_recommendation}

**Rationale**: {why_this_task}

## 🎯 Quick Actions

- **Start recommended task**: `/dev:impl`
- **Create new feature**: `/dev:prd`
- **Search past work**: Ask me about anything (claude-mem enabled)
- **Review codebase**: Ask specific questions (RLM will analyze)

---

**System Status**:
- ✅ RLM: Ready ({total_files} files indexed)
- ✅ Claude-Mem: Ready ({obs_count} observations)
- ✅ Git: {git_branch} ({git_status})

Ready to code! 🎉
```

## Context Quality Levels

Depending on what's available, provide appropriate detail:

### Full Context (Best Case)
- Claude-mem has project overview + recent work
- RLM has complete file index
- Git history available
- Task files exist
→ **Rich, actionable summary**

### Partial Context
- RLM index exists, but no claude-mem data yet
- Or vice versa
→ **Basic summary, suggest indexing missing system**

### Minimal Context
- Only RLM index, no docs, no mem
→ **File statistics, suggest creating documentation**

## Important Notes

1. **Fast Context Refresh**:
   - Use cached RLM index (don't re-index)
   - Quick claude-mem queries (limit results)
   - Aim for <30s total time

2. **Actionable Output**:
   - Don't just describe, recommend next action
   - Prioritize based on data, not guesses
   - Make it easy to start working

3. **Error Handling**:
   - If RLM not initialized: suggest `/dev:init`
   - If claude-mem empty: that's OK, use RLM only
   - If no tasks found: suggest creating one

4. **No Implementation**:
   - This command only provides context
   - DO NOT start implementing tasks
   - DO NOT read entire source files
   - Wait for user to choose next action

## Example Output

```
# 🚀 Session Started: {project_name}

*Generated from RLM code analysis + claude-mem historical context*

## 📊 Project Overview

{Short project description from README or claude-mem}

**Repository Statistics** (RLM):
- **Files**: {N} files ({size} MB) · **Languages**: {list}
- **Last indexed**: {timestamp}

## ✅ Completed Features
- {Feature A} ({task-id})
- {Feature B} ({task-id})

## 🏗️ Current Architecture
{Architecture summary from claude-mem}

## 📝 Active Tasks
- {TASK-1}: {description} ({N} subtasks, {M} done)
- {TASK-2}: {description} (planning phase)

## 🔥 Recent Activity
- {file/path}: {N} changes

## 💡 Recommended Next Task

**Suggestion**: {task and subtask description}

**Rationale**:
- {reason 1}
- {reason 2}

## 🎯 Quick Actions
Ready to code! 🎉
```

## Context7

When referencing any library, framework, or external API — use the Context7 MCP to look up current documentation rather than guessing. Call `mcp__context7__resolve-library-id` then `mcp__context7__get-library-docs`. Never invent API signatures or assume version-specific behaviour.

## Docs-First Principle

The normal flow is: PRD → tech-design → tasks → `/dev:impl`.
Docs should exist and be consistent with what's being built before any
implementation starts.

When the user asks to implement something after the session starts:
- **Docs exist and are consistent** → suggest `/dev:impl`
- **Docs missing or inconsistent** → stop, flag the gap, offer to
  create docs (PRD / tech-design / tasks) before implementing
- **Research, POC, or exploration** (e.g. during PRD/tech-design) →
  allow with a note that this is exploratory, not documented impl
- **Minor changes** (typos, config tweaks) → proceed without doc update

**Enforcement is semantic, not mechanical.** Before editing any code
file, assess: is this edit justified by an active task, ongoing
research, or user approval? If not, warn and suggest documenting first.

## Final Instructions

1. Check RLM and claude-mem status
2. Query historical context (claude-mem)
3. Analyze current state (RLM)
4. Synthesize comprehensive summary
5. Recommend next task (data-driven)
6. DO NOT implement anything yet — wait for user to choose action
7. When user requests implementation: check docs exist and are consistent — if not, flag and fix before proceeding
