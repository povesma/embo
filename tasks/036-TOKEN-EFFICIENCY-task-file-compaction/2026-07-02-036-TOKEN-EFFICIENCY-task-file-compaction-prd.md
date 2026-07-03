# 036: Token Efficiency in embo Task Files — PRD

**Status**: Draft
**Created**: 2026-07-02

*This PRD was compacted to ~100 lines as a demonstration of the rule it defines.*

---

## Problem

`/embo:impl` appends verification evidence to each subtask as it completes.
No compaction step exists. Over a multi-session feature a task file accumulates
process narration, superseded intermediate states, and live-test transcripts —
none of which are needed after the subtask closes.

`/embo:start` reads all active task files in full on every startup, loading
that noise into the startup context window each session.

**Measured signal**: manual compaction of one completed task file reduced it from
516 to 107 lines (79%) without losing any decision-relevant content. A ~4:1
noise-to-signal ratio in a completed task file is structural, not incidental.

**Core deliverable**: the compaction rule is NOT yet defined. The candidate
rule that emerged must be validated against real task files before being encoded
into any command:

> Retain a line if and only if it states a decision, a constraint, an unexpected
> finding, or a verification result (what ran + outcome). Discard if the line
> describes the process by which something was done, or narrates a superseded
> intermediate state.

---

## Scope

Three delivery pieces, in dependency order:

**1. Validate the compaction rule** (blocks everything else)
- Apply the candidate rule to 3–5 completed task files via a subagent pass
  (examine-advisor or equivalent)
- Present retain/discard decisions for human review; resolve ambiguous cases
- Output: a plain-English rule, ≤6 lines, ready to paste into a command file

**2. Compact evidence at write time in `/embo:impl`**
- Enforce the validated rule when marking `[X]`: one decision/outcome clause +
  one deviation clause (only if present) + one evidence line
- Process narration and superseded intermediate states are explicitly forbidden
- No extra tool calls or steps — format constraint only

**3. `/embo:wrapup` — new end-of-session command**
- Scope: task files only (not PRDs, tech-designs, seeds)
- Steps: compact task files touched this session; surface uncommitted work;
  optionally save a session observation to claude-mem
- Safety: does not silently delete — shows what will be removed and asks for
  confirmation, OR applies the rule only to content it classifies as unambiguous
  noise
- Reads only files modified since session start, not all task files

**4. Selective reading in `/embo:start`**
- For task files where ≥80% of subtasks are `[X]`: read only the status header
  and open `[ ]` items
- For files below that threshold: read in full as today
- When a user selects a task for active work: load the full file then

---

## Constraints (verified)

- Evidence format source: `plugin/commands/impl.md:147–160` — current format
  allows arbitrary summary length, no verbosity constraint
- Start reads unconditionally: `plugin/commands/start.md:439–441` — Glob
  `tasks/**/*-tasks.md`, reads all surviving files in full
- No wrapup command exists: confirmed via `ls plugin/commands/`, 2026-07-02
- New command requires entry in `plugin/.claude-plugin/plugin.json` + version
  bump — exact format to verify in tech-design
- Start's Glob + Read pattern must stay pre-approved (no `find`, no `$(...)`)

**5. Fix broken RLM exec calls in `/embo:impl`**
- `plugin/commands/impl.md` Steps 3a and 3c call `find_files_by_pattern`,
  `find_symbol`, `write_file_chunks`, and `get_related_files` — none of
  which exist in `rlm_repl.py`'s exec namespace (verified: `_make_helpers`
  at `plugin/rlm_scripts/rlm_repl.py:850` exposes only `peek`, `grep`,
  `chunk_indices`, `write_chunks`).
- These were copied from an aspirational template at day one and have never
  worked. Every call fails with `NameError`; the model falls through to
  direct `Read` calls.
- Fix: implement the missing helpers in `_make_helpers` using the
  `repo_index` already injected into the exec env at line 1119.

## Out of Scope

- Compacting PRDs, tech-designs, seeds
- Archiving or deleting task files
- Automatic compaction without user interaction

## Success Metrics

- ≥70% token reduction at startup for task files ≥80% complete
- Zero cases in the validation set where a discarded line is later identified
  as decision-relevant

---

**Next**: `/embo:tech-design` — runs the subagent validation pass on real task
files to nail down the compaction rule before any command file is edited.
