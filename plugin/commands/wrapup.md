---
description: >
  End-of-session command: make the session durable in the docs tree —
  detect decisions, findings, and progress not yet written to the docs,
  compact completed subtask evidence, and surface uncommitted work.
---

# /embo:wrapup — End-of-Session Wrap-Up

## Goal

Session idempotency — the docs tree (PRD / tech-design / tasks) reflects
everything decided, discovered, or completed this session, so the next
session resumes from the docs, not from conversation memory.

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
this session." and skip Step 3 (compaction).

### 2. Detect untracked session information

Compare the session's decisions, findings, completed work, and the
working-tree diff against the docs tree. Flag anything with no doc home:
docs-first violations, task progress not yet reflected in status markers,
decisions or findings written nowhere, doc references (paths, tools,
tasks) in this session's touched docs that no longer resolve, and
corrections captured this session that are not yet workflow rules.
Propose each update to the doc whose rules cover it (PRD / tech-design /
tasks), via `AskUserQuestion`; apply only what the user confirms. If
nothing is flagged, say so.

### 3. Compact each file

For each file:
- Read it.
- Apply the compaction rule to every `[X]` subtask's body lines.
  Leave `[ ]` and `[~]` subtask bodies untouched.
- Show the user: `N lines → M lines (−K)` and ask for confirmation
  via `AskUserQuestion` before writing. On rejection, skip that file.

### 4. Surface uncommitted work

```bash
git diff --stat HEAD
```

If non-empty, list the files and ask via `AskUserQuestion`: commit now
(invoke `/embo:git commit`) or leave uncommitted.

### 5. Report

One-line summary of what was done: doc updates applied, files
compacted, commit status.
