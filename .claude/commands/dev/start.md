# Start RLM-Mem Coding Session

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

Read `~/.claude/active-profile.yaml` if it exists. If not present,
use defaults: rlm=true, memory_backend=claude-mem, docs_first=strict.
Note the active profile name in the session summary output.

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

- Docs: Glob `**/README*.md`, `**/CLAUDE*.md` — read top-level only
- Tasks: Glob `tasks/**/*-tasks.md` (exclude `/archive/`) — read active task files
- Git: `git log --oneline -10` and `git diff --stat HEAD`

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
