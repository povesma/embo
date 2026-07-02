# 036: Token Efficiency in embo Task Files — Technical Design

**Status**: Draft
**Created**: 2026-07-02
**PRD**: `2026-07-02-036-TOKEN-EFFICIENCY-task-file-compaction-prd.md`

---

## Compaction Rule (Validated)

Three subagent passes over completed task files (030, 031, 032) produced a
consistent finding: the candidate rule classifies the two dominant populations
correctly (process-narration subtask bodies → discard; outcome `→` lines with
decisions/findings/verification results → retain), but all three flagged the
same gap: **mixed-content lines** — a single `→` block that opens with a
retained element (finding, decision, constraint) but also contains narration
of follow-up action or framing.

**Retain/discard splits measured:**
- 032 (428 lines, 329 non-blank): ~54% retain, ~46% discard
- 031 (151 lines, 108 non-blank): ~48% retain, ~52% discard
- 030 (171 lines, 118 non-blank): ~61% retain, ~39% discard

Average: ~54% retained. Combined with the 79% reduction from the original
report (a fully completed file), this suggests the rule achieves the ≥70%
target on files that are complete or near-complete.

**Validated compaction rule (refined from candidate):**

> **Retain** a line if it states: a decision (what was chosen and why),
> a constraint (what must remain true), an unexpected finding (something
> discovered that was not anticipated), or a verification result (what ran
> and what the outcome was).
>
> **Discard** if the line describes: the process by which something was
> done (how a file was moved, how a command was invoked), a step that was
> superseded by a later outcome (TDD red phases, bug-found states that were
> then fixed), or procedural scaffolding with no lasting meaning.
>
> **Mixed lines** (a line containing both retained and discarded content):
> retain if the decision/finding/constraint/verification content is the
> primary substance; discard only the trailing narration. When in doubt,
> retain — a false discard costs more than a false retain.

This rule is ≤6 lines and is ready to paste into command files.

---

## Components

### 1. Evidence format in `/embo:impl` (edit `plugin/commands/impl.md`)

**Current** (`impl.md:147–151`):
```
→ <summary> [live] (<date>)
→ <summary> [simulated: <reason>] (<date>)
```
No verbosity constraint. The `<summary>` field accepts arbitrary length.

**Change**: add a compact format rule immediately after the format block,
before the examples. No structural change to the format itself — just an
explicit constraint on what `<summary>` must and must not contain.

Text to insert after line 151:

```
**Compact summary rule**: `<summary>` must be one clause stating the
outcome or decision. Add a second clause only if something unexpected
occurred. Omit: how the work was done, intermediate states that were
superseded (TDD red phases, bug-found states fixed before [X] was marked),
and tool invocation details. The evidence line is a permanent record, not
a session log.

Bad:  `→ wrote tests first (TDD red: 3 failed), then implemented, then
      ran again: 3 passed, 0 failed [live] (2026-07-02)`
Good: `→ 3 passed, 0 failed [live] (2026-07-02)`

Bad:  `→ found a naming conflict in foo.py, renamed to bar.py, re-ran,
      now all pass [live] (2026-07-02)`
Good: `→ renamed foo→bar (naming conflict); 5 passed, 0 failed [live]
      (2026-07-02)`
```

### 2. Selective reading in `/embo:start` (edit `plugin/commands/start.md`)

**Current** (`start.md:439–441`): Glob `tasks/**/*-tasks.md`, read all
surviving files in full, unconditionally.

**Change**: replace the unconditional read instruction with a two-path read.

**Completeness heuristic**: count `[X]` markers vs total `[ ]` + `[~]` + `[X]`
markers in the file. If ≥80% are `[X]`, the file is "mostly complete."

**Implementation in the command text**: the model counts markers by scanning
the file content after reading it. This is a judgment instruction, not a
grep — the command text instructs the model to read each file and then decide
whether to use the full content or extract only the open items.

Revised instruction (replaces lines 439–441):

```
- Tasks: use the **Glob tool** with pattern `tasks/**/*-tasks.md`. Discard
  matches whose path contains `/archive/`. For each surviving file:
  - Read it.
  - Count `[X]` markers vs all task markers (`[ ]`, `[~]`, `[X]`).
  - If ≥80% are `[X]` (mostly complete): use only the file's header block
    (title, status line, story titles) and lines containing `[ ]` or `[~]`.
    Discard completed subtask bodies and their evidence notes from context.
  - Otherwise: use the full file content.
  - When the user selects this task for active work, re-read the full file.
```

**Why not grep/awk**: `start.md` already forbids `find`, loops, and `$(...)`.
The model reads the file and applies judgment — consistent with the existing
pattern. No new tool permissions needed.

### 3. `/embo:wrapup` — new command (`plugin/commands/wrapup.md`)

**Trigger**: user runs `/embo:wrapup` at end of session.

**Steps** (in order):

1. **Identify task files touched this session**
   Use `git diff --name-only HEAD` to find modified files, filter to
   `tasks/**/*-tasks.md`. If none, report "no task files modified this
   session" and skip to step 3.

2. **Compact each modified task file**
   For each file:
   - Read it.
   - Apply the validated compaction rule to completed subtasks only
     (subtasks marked `[X]`). Open (`[ ]`) and in-progress (`[~]`) subtask
     bodies are never touched.
   - Show the user a before/after diff summary: "N lines → M lines in
     `tasks/xxx-tasks.md`". Ask for confirmation before writing.
   - On confirmation: write the compacted version.

3. **Surface uncommitted work**
   Run `git diff --stat HEAD`. If non-empty, list the modified files and
   ask: commit now, skip, or note it for next session.

4. **Optional session observation**
   Ask: "Save a session summary to claude-mem? (y/n)". If yes, prompt for
   a one-line summary and save via `mcp__plugin_claude-mem_mcp-search__observation_add`
   (or `memory_add` on the worker runtime — verify tool name in impl).

**Safety constraints** (non-negotiable):
- Never compact `[ ]` or `[~]` subtasks — only `[X]`.
- Never write without showing the diff summary and receiving confirmation.
- Never touch PRD, tech-design, seed, or other non-tasks files.
- If `git diff` is not available, skip step 1 and ask the user which task
  files to compact.

### 4. `plugin.json` update

**Current** (`plugin/.claude-plugin/plugin.json:1–19`): no `commands` field —
plugin.json contains only metadata (name, version, description, author,
homepage, repository, license, keywords). Command discovery is file-based
(Claude Code scans `commands/`), not declared in plugin.json.

**Constraint verified**: no plugin.json edit is needed to register a new
command. Adding `plugin/commands/wrapup.md` is sufficient. A version bump
IS required to trigger `/plugin update` for existing installs.

**Version bump**: `0.1.2` → `0.1.3` when this ships.

---

## Rejected Alternatives

**Automatic compaction on `[X]` mark in /embo:impl (write compact, never
verbose)**: rejected. During active development, verbose evidence is useful
— the developer may be mid-session and the extra detail aids debugging.
Compaction at session end (wrapup) captures the same result without
interfering with active work.

**A separate `/embo:compact` command (compaction only, no wrapup)**: rejected
in favour of `/embo:wrapup`. A broader end-of-session command is more useful
and is the natural trigger. Compaction-only is too narrow to stand alone.

**grep-based marker counting in /embo:start**: rejected. `start.md` forbids
`find`, loops, `$(...)`. A model judgment call after reading the file is
consistent with the existing pattern and needs no new permissions.

---

## Files Changed

| File | Change |
|---|---|
| `plugin/commands/impl.md` | Add compact summary rule after evidence format block (lines ~151–152) |
| `plugin/commands/start.md` | Replace unconditional task-file read with completeness-gated two-path read (lines ~439–441) |
| `plugin/commands/wrapup.md` | New file |
| `plugin/.claude-plugin/plugin.json` | Version bump `0.1.2` → `0.1.3` |

README command table update (add `/embo:wrapup`) is a docs-only change,
not a functional one — included in the same commit.

---

## Verification Plan

| Item | Method |
|---|---|
| Compact summary rule in impl | `[verify: code-only]` — text change only; verified by reading the updated section |
| Selective reading in start | `[verify: manual-run-claude]` — run `/embo:start` on a session with a ≥80%-complete task file; confirm startup summary omits completed subtask bodies |
| `/embo:wrapup` compaction step | `[verify: manual-run-claude]` — run on a task file with known verbose evidence; confirm diff summary shown, compacted file written after confirmation |
| `/embo:wrapup` uncommitted work step | `[verify: manual-run-claude]` — run with a dirty working tree; confirm modified files listed |
| Version bump | `[verify: code-only]` |
