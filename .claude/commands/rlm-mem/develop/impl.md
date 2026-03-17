# Task Implementation with RLM-Mem Hybrid

Implement tasks with pattern discovery (RLM) + historical context
(claude-mem).

## Critical Evaluation of Instructions

Do NOT silently execute user instructions. Before implementing
any instruction, evaluate it against:

1. **PRD and tech-design**: Does the instruction align with
   documented requirements and architecture?
2. **Current tasks**: Is this covered by an existing task?
3. **Common sense and feasibility**: Is this technically sound?
   Could the user be mistaken, even in a clear instruction?
4. **Vague instructions**: Never interpret-and-implement
   immediately. Ask for clarification first.

If you spot a problem, raise it before implementing — even if
the instruction seems clear. The user is the boss, but the agent
is responsible for flagging risks.

## Scope Verification (Doc-First Development)

Sessions are idempotent. If a session is restarted, code must
match PRD, tech-design, and tasks. Therefore:

**Before implementing any instruction**, check:
- Does this map to a task in the active task list?
- If YES → proceed normally
- If NO → this is scope drift. Handle it:

**Scope drift handling:**
1. **Clarification-level change** (implementation detail, matter
   of preference, minor adjustment): Just implement it. Updating
   docs would create unnecessary overhead.
2. **New feature or significant change** (new user story, new
   component, architecture change): Auto-update the relevant docs
   BEFORE implementing:
   - Small: add subtask to existing story in tasks file
   - Medium: add new story to tasks file + update tech-design
   - Large: update PRD + tech-design + tasks, ask user to
     confirm the doc changes before proceeding

**Judgment call**: Be smart. The goal is maintaining idempotency
for changes that matter, not creating bureaucratic overhead for
every instruction. If updating docs costs more context/time than
the change itself, skip the update.

## Task Completion Rules

- **`[X]` (done)**: ONLY when tested AND passing, OR explicitly
  confirmed by user
- **`[~]` (coded, pending testing)**: implementation is written
  but not yet verified
- **`[ ]` (not started)**: no work done
- Tasks that are tests themselves (story 8-style verification)
  may be marked `[X]` once the test is run and the result is
  known, even if the result reveals bugs to fix
- Marking `[X]` without testing is **never acceptable** — be
  pessimistic, assume it doesn't work until proven otherwise

## Task Implementation Protocol

- **One sub-task at a time:** Do **NOT** start the next sub-task
  until you ask the user for permission and they say "yes" or "y"
- **Completion protocol:**
  1. When you finish a **sub-task**, immediately mark it as
     completed by changing `[ ]` to `[X]`.
  2. If **all** subtasks underneath a parent task are now `[X]`,
     also mark the **parent task** as completed.
- Stop after each sub-task and wait for the user's go-ahead.

## Process

### 1. Load Context

**Search claude-mem for similar implementations:**
```
mcp__plugin_claude-mem_mcp-search__search(
  query="{task_keywords} implementation pattern",
  project="{project_name}",
  limit=5
)
```

**Initialize RLM:**
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py status
```
- If not initialized, suggest `/rlm-mem:discover:init`

### 2. Load and Understand Current Task

- Read the current task file from
  `/tasks/[JIRA-ID]-[feature-name]/`
- Identify the next incomplete sub-task
- Extract requirements and acceptance criteria

### 3. RLM-Powered Context Discovery

**3a. Find relevant existing code:**
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py exec <<'PY'
keywords = ['feature_term', 'related_concept']  # fill with terms from the task description

relevant = []
for kw in keywords:
    relevant += find_symbol(kw, type='function')
    relevant += find_files_by_pattern(f'**/*{kw}*')
for f in list(set(relevant))[:5]:
    relevant += get_related_files(f)
paths = write_file_chunks(list(set(relevant))[:20], strategy='file')
import json; print(json.dumps(paths))
PY
```

**3b. Analyze patterns using rlm-subcall:**
- For each relevant file chunk, invoke rlm-subcall with:
  - Query: "Analyze for: (1) architectural patterns, (2) coding
    conventions, (3) how [feature] is currently handled,
    (4) testing approach"
- Collect: code structure, naming conventions, error handling,
  testing patterns, dependency injection approach

**3c. Find existing tests:**
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py exec <<'PY'
test_files = find_files_by_pattern('**/*test*') + find_files_by_pattern('**/*.spec.*')
relevant_stems = {f.split('/')[-1].split('.')[0] for f in relevant}
related = [t for t in test_files if any(s in t for s in relevant_stems)]
paths = write_file_chunks(related[:10], strategy='file')
import json; print(json.dumps(paths))
PY
```

### 4. Synthesize Implementation Plan

Based on RLM analysis and claude-mem history, create a plan:

```
### Implementation Plan for [sub-task]

**Discovered Patterns (RLM):**
- Architecture: [from analysis]
- File organization: [from existing code]
- Testing approach: [from test analysis]

**Past Lessons (Claude-Mem):**
- [Relevant decision from memory]

**Files to Modify:**
- `src/x/handler.py:45` - [change]

**Files to Create:**
- `src/x/new_feature.py` - [purpose]
```

### 5. Implement Following Discovered Patterns

- Write tests first (TDD) following discovered testing patterns
- Implement matching discovered architectural patterns
- Use same naming conventions and code structure
- Follow dependency injection patterns found in codebase

### 6. Verify and Save to Claude-Mem

**Save completion to claude-mem:**
```
mcp__plugin_claude-mem_mcp-search__save_memory(
  text="[JIRA: {jira_id}]\n[TYPE: IMPLEMENTATION]\n\n
Task '{task_name}' complete.\n\nPatterns used:\n{patterns}
\n\nFiles:\n{files}",
  title="{jira_id} - {task_name} Implementation",
  project="{project_name}"
)
```

### 7. Update Task List and Documentation

- Mark sub-task as complete per Task Completion Rules above
- Update "Relevant Files" section in task file
- If parent task completed, save to claude-mem and update
  ai-docs/ if present

## Context7

When referencing any library, framework, or external API — use the Context7 MCP to look up current documentation rather than guessing. Call `mcp__context7__resolve-library-id` then `mcp__context7__get-library-docs`. Never invent API signatures or assume version-specific behaviour.

## Code Style

- Focus on readability
- Try and keep to 120 character row length
- Trim empty characters in line ends
- IMPORTANT: Always end files with an empty line
- **Avoid comments:** Write self-documenting code with clear
  variable/function names. Only add comments for complex business
  logic or non-obvious design decisions.
- **Architecture Terminology:** Use "handler" instead of
  "usecase" for application layer components

## Testing Guidelines (TDD)

- **Test External Interface Only:** Public APIs, exported
  functions, external interfaces — never internal implementation
- **Test Functionality, Not Implementation:** What the code does,
  not how
- **Focus on Module Contracts:** Inputs, outputs, side effects,
  error conditions
- **Test First:** Write test before implementing functionality
- Follow testing patterns discovered via RLM analysis
