---
description: >
  Review correction observations captured in claude-mem and generate a
  proposal for improving the workflow, rules, or command files.
---

# Review Corrections & Generate Improvement Proposal

Analyze accumulated user corrections from claude-mem, group by
pattern, walk through interactive curation, and produce a Markdown
change proposal the user can submit upstream.

## When to Use

- At the end of an `/embo:impl` session (suggested automatically when
  corrections were captured)
- When you want to review accumulated feedback across sessions
- Before submitting a GitHub issue with workflow improvements

## Process

### Step 0: Check correction capture is enabled

Corrections are only saved if `/embo:enable-corrections` was run. Read
the active claude-mem mode with one bare command:

```bash
embo-corrections mode
```

If it prints anything other than `code-embo`, correction capture was
never turned on. Output exactly this and stop (do not say "nothing
found"):

> Correction capture is not turned on, so there are no corrections to
> review. Run `/embo:enable-corrections` first, then use Claude
> normally — corrections you give it will be saved for next time.

This distinguishes "never enabled" from "enabled but nothing to
review" (the latter is handled in Step 1).

### Step 1: Query pending corrections

List the corrections for this project that have NOT already been
reviewed, with one bare command:

```bash
embo-corrections list-pending
```

`embo-corrections` is a plain command on PATH (the plugin's `bin/`
wrapper). It derives the project name from the working-directory
basename, reads the corrections from claude-mem's relational store,
subtracts the IDs recorded in `.claude/correction-curation.json`, and
prints only the not-yet-reviewed rows as a JSON array (id, title,
subtitle, narrative, created_at), newest first. Parse that array
directly — the subtraction is done for you, not in your head.

Being a bare command, it auto-approves under a `Bash(embo-corrections
*)` rule with no prompt and needs no `${CLAUDE_PLUGIN_ROOT}` expansion
(RULE:AVOID-APPROVAL). If the array is empty, output
`"No corrections to review."` and stop (the "enabled but nothing new"
case).

> **Why the DB and not the MCP `search` tool** — the MCP `type=` filter
> is broken for custom types on the worker runtime (issue #3279, fix PR
> #3289), and its free-text fallback is lossy (semantic ranking +
> `limit` can silently miss corrections). Corrections are correctly
> stored AND indexed; only the tool's `type` handling is wrong, so
> reading the source table is both a sidestep and strictly more
> complete. Even if #3289 merges, this stays correct.

### Step 2: Group by Theme

Correction observations do not carry a category tag — classify them
yourself from their `title` / `subtitle` / `narrative`. Group them:

1. Assign each correction a theme from its content: `verification`
   (check docs/web/real sources first), `code-style` (naming, comments,
   simplicity), `workflow` (skip/add a step), `approach` (over-
   engineering, wrong method), `process` (a standing "always do X"
   rule). These themes map to target files in Step 3.
2. Within each theme, merge near-duplicates by comparing the
   "what the user wanted changed" meaning semantically.
3. Sort themes by correction count, descending.
4. For each group, select 1-3 representative examples (quote the
   user's actual wording from `title`/`narrative`).

### Step 3: Interactive Curation

For each category group, present to the user via AskUserQuestion:

- Category name and frequency count
- 1-3 representative examples (actual correction text)
- Suggested change: which file to modify + what rule to add

**Category → file mapping:**

| Category | Primary target file |
|---|---|
| `verification` | `plugin/commands/impl.md` |
| `code-style` | `plugin/commands/impl.md` § Code Style |
| `workflow` | Varies — depends on workflow step |
| `approach` | `plugin/commands/impl.md` § Critical Evaluation |
| `process` | May require new section or command |

Read the target file during curation to provide a specific section
reference, not just the filename.

**Options for each group:**
- **Accept** — include in proposal as-is
- **Edit** — user provides modified text; include modified version
- **Reject** — exclude from proposal; still mark as curated so it
  doesn't resurface

### Step 4: Mark Curated

After the user finishes reviewing all groups, persist the reviewed IDs
so they do not resurface next run. There is no claude-mem write tool in
the worker runtime (`save_memory` was removed), so this is a local,
project-scoped file. Every reviewed correction — accepted OR rejected —
is recorded as curated (a rejected one was a one-off, and must not
resurface either). Pass the IDs the pending list surfaced in Step 1
(the ones you just reviewed) to the bare wrapper:

```bash
embo-corrections write <reviewed-id>...
```

`embo-corrections write` merges and dedups the IDs into
`.claude/correction-curation.json` and writes atomically, so the file
is never left truncated. It is disposable: if it is deleted, the only
effect is that already-reviewed corrections resurface once (the
corrections themselves live in claude-mem, not here).

### Step 5: Assemble Proposal

Build and output the proposal as Markdown:

```markdown
# embo Workflow Improvement Proposal

**Generated**: {date}
**Project**: {project_name}
**Corrections reviewed**: {total} ({accepted} accepted,
{rejected} rejected)
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

{Repeat for each accepted group}

## Raw Corrections

<details>
<summary>Full correction observations ({N} total)</summary>

| # | Date | Category | What happened → What user wanted |
|---|------|----------|----------------------------------|
| 1 | {date} | {cat} | {summary} |

</details>

---

*Generated by `/embo:improve`. Submit as a GitHub issue
or send to the project maintainer.*
```

Output directly to conversation. The user copies the text.

## Important Notes

1. **No auto-apply** — this command produces a proposal, it never
   modifies command files
2. **User is the curator** — every correction group must be
   explicitly accepted, edited, or rejected
3. **Idempotent** — running twice without new corrections produces
   "No pending corrections to review"
4. **Project-scoped** — only shows corrections for the current
   project
