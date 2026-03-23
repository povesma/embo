# Check Task List Status with RLM

Check task completion status by analyzing actual code implementation.

## Process

### Step 1: Load Task List

Use the Glob tool to find task files:
- Pattern: `tasks/**/*-tasks.md`
- Exclude paths containing `/archive/`

### Step 2: Read Task File

Read the active task file

### Step 3: Verify Each Task Against Code

For each incomplete task `[ ]`:

**Use RLM to verify implementation**:
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py exec <<'PY'
# Search for files related to task
# Example: task is "Add OAuth2 handler"
search_terms = ['oauth2', 'handler']

found_files = []
for term in search_terms:
    matches = [
        path for path, meta in repo_index['files'].items()
        if term.lower() in path.lower()
        and not meta['is_binary']
    ]
    found_files.extend(matches)

print(f"Found {len(set(found_files))} related files")
print('\n'.join(sorted(set(found_files))[:10]))
PY
```

**Read relevant files** to verify implementation

### Step 4: Update Task Status

**Task marking rules — apply strictly:**
- **`[X]`** — ONLY when tested AND passing, or explicitly confirmed by user
- **`[~]`** — code exists but not yet tested/verified (pending testing)
- **`[ ]`** — not started
- Code analysis showing a file/function exists → `[~]` at best, never `[X]`
- Never upgrade to `[X]` based on code presence alone

**For implemented-but-untested tasks** (code found, no test evidence):
- Mark subtask as `[~]`
- Parent stays `[ ]` until all subtasks are at least `[~]`, then becomes `[ ]` with a note

**For confirmed-complete tasks** (tested, passing, or user-confirmed):
- Mark subtask as `[X]`
- If all subtasks `[X]`, mark parent as `[X]`
- Update ai-docs/ when parent complete:
  - ai-docs/API.md
  - ai-docs/ARCHITECTURE.md
  - ai-docs/DEVELOPMENT.md
  - ai-docs/PRD.md
  - ai-docs/README.md
  - ai-docs/SCHEMA.md
  - ai-docs/USAGE.md

**Index in claude-mem**: Read the updated tasks file — the PostToolUse
hook captures it automatically. No explicit save call needed.

### Step 5: Scope Drift Detection

While checking tasks, if you find code that doesn't correspond
to any task in the task list, flag it as potential scope drift.
Report it in the status summary — do not silently accept
untracked changes.

### Step 6: Halt on First Incomplete

Stop checking when you find first truly incomplete task

## Final Instructions

1. Find task files using Glob tool: `tasks/**/*-tasks.md`
2. Read the active task file
3. For each `[ ]` task, use RLM to verify in code
4. Update status: `[~]` if code found but untested, `[X]` only if tested/confirmed
5. Flag any code found that doesn't match a task (scope drift)
6. Update ai-docs/ when parent tasks are `[X]`
7. Save completions to claude-mem
8. Halt at first truly incomplete (`[ ]`) task
