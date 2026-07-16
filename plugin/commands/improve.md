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
the active claude-mem mode:

```bash
jq -r '.CLAUDE_MEM_MODE // "code"' ~/.claude-mem/settings.json
```

If it is **not** `code-embo`, correction capture was never turned on.
Output exactly this and stop (do not say "nothing found"):

> Correction capture is not turned on, so there are no corrections to
> review. Run `/embo:enable-corrections` first, then use Claude
> normally — corrections you give it will be saved for next time.

This distinguishes "never enabled" from "enabled but nothing to
review" (the latter is handled in Step 1).

### Step 1: Query Corrections

Source the helper library, then list corrections for the current
project with one bare call:

```bash
source "$CLAUDE_PLUGIN_ROOT/claude-mem/corrections-lib.sh"
corrections_list <project-name>
```

`<project-name>` is the current project (the working-directory
basename, same value used elsewhere in embo). `corrections_list` prints
a JSON array (id, title, subtitle, narrative, created_at), newest
first, which you parse directly.

Keep it a single bare call — do not inline the SQL. The function reads
claude-mem's relational source of truth; a raw multi-line
`sqlite3 "SELECT ..."` in the command would trip the approval dialog
every run (RULE:AVOID-APPROVAL).

> **Why the DB and not the MCP `search` tool** — the MCP `type=` filter
> is broken for custom types on the worker runtime (issue #3279, fix PR
> #3289), and its free-text fallback is lossy (semantic ranking +
> `limit` can silently miss corrections). Corrections are correctly
> stored AND indexed; only the tool's `type` handling is wrong, so
> reading the source table is both a sidestep and strictly more
> complete. Even if #3289 merges, this stays correct.

Read the local curation state (IDs already reviewed in a prior run):

```bash
corrections_curation_read .claude/correction-curation.json
```

Remove any correction whose ID is in that list. If zero corrections
remain after filtering, output `"No corrections to review."` and stop
(this is the "enabled but nothing new" case).

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
to the local curation file so they do not resurface next run. There is
no claude-mem write tool in the worker runtime (`save_memory` was
removed), so this is a local, project-scoped file. Every reviewed
correction — accepted OR rejected — is recorded as curated (a rejected
one was a one-off, and must not resurface either):

```bash
source "$CLAUDE_PLUGIN_ROOT/claude-mem/corrections-lib.sh"
corrections_curation_write .claude/correction-curation.json <reviewed-id>...
```

`corrections_curation_write` merges and dedups against any existing
curated IDs and writes atomically, so the file is never left truncated.
It is disposable: if it is deleted, the only effect is that
already-reviewed corrections resurface once (the corrections themselves
live in claude-mem, not here).

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
