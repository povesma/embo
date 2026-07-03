---
description: >
  End-of-session command: compact completed subtask evidence in task
  files touched this session, surface uncommitted work, and optionally
  save a session observation to claude-mem.
---

# /embo:wrapup — End-of-Session Wrap-Up

## Compaction Rule

Applied only to `[X]` subtask bodies (never `[ ]` or `[~]`, never
PRDs, tech-designs, or seeds):

> Retain if the line states a decision, constraint, unexpected finding,
> or verification result. Discard if it describes process (how something
> was done) or a superseded intermediate state. Mixed lines: retain if
> the decision/finding content is primary. When in doubt, retain.

## Steps

### 1. Find modified task files

```bash
git diff --name-only HEAD
```

Filter to `tasks/**/*-tasks.md`. If none, print "No task files modified
this session." and skip to Step 3.

### 2. Compact each file

For each file:
- Read it.
- Apply the compaction rule to every `[X]` subtask's body lines.
  Leave `[ ]` and `[~]` subtask bodies untouched.
- Show the user: `N lines → M lines (−K)` and ask for confirmation
  via `AskUserQuestion` before writing. On rejection, skip that file.

### 3. Surface uncommitted work

```bash
git diff --stat HEAD
```

If non-empty, list the files and ask via `AskUserQuestion`: commit now
(invoke `/embo:git commit`), skip, or note it in the session observation.

### 4. Report

One-line summary of what was done: files compacted, commit status.
