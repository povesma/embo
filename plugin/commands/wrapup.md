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

**Write each update to the doc whose rules cover it (PRD /
tech-design / tasks). Do not ask first.** Recording what the session
established is this command's purpose, not a menu: you hold the
session context and the user does not, so "which of these should be
written down?" asks them to ratify a judgment only you have the
evidence for — and the answer is almost always "all of them".

Ask — via `AskUserQuestion`, for that item only — only on genuine
doubt: the correct content is ambiguous, two docs conflict and
picking a winner is a real decision, or the update targets a file
outside the docs tree (a user's global `CLAUDE.md`, a shipped
command file). Everything else: write it.

If nothing is flagged, say so.

### 3. Compact each file

For each file:
- Read it.
- Apply the compaction rule to every `[X]` subtask's body lines.
  Leave `[ ]` and `[~]` subtask bodies untouched.
- **Write it. Do not ask for confirmation.** The compaction rule
  already decides what goes ("when in doubt, retain"), the change is
  in git, and the user cannot judge a line count without re-reading
  the file themselves.
- **Report it only when the saving is substantial** — at least 20%
  of the file, or at least 50 lines. Below that, write the file and
  say nothing about it: a few lines saved is not worth the user's
  reading time, and a report they must parse to conclude "that was
  nothing" costs more than the compaction gained. Time is more
  precious than tokens.

### 4. Surface uncommitted work

```bash
git diff --stat HEAD
```

If non-empty, list the files and ask via `AskUserQuestion`: commit now
(invoke `/embo:git commit`) or leave uncommitted.

### 5. Report

- Doc updates applied (Step 2) — the doc and what was written.
- Files compacted (Step 3) — `N lines → M lines (−K)` and what kind
  of content was dropped.
- Anything deferred for genuine doubt — what, and why undecided.
- Commit status (Step 4).
