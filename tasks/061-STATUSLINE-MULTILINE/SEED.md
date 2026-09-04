# 061: Multi-line status line for more dynamic info — Seed

**Status**: Not started (run /embo:prd to begin).
**Origin**: raised 2026-09-03 — one status line row is not enough to fit
the dynamic information wanted.

## Problem

embo's status line (`plugin/statusline.sh`) is a single row:
cwd | git branch | model | cost | ctx % | mem | time. That row is full;
there is no space to add more dynamic signals without dropping existing
ones.

## Feasibility — confirmed against official docs

**Multi-line status lines are officially supported.** Verified against
`code.claude.com/docs/en/statusline` (via Context7, 2026-09-03):

- "Status line scripts can output multiple lines... each print statement
  displays as a row." The docs ship a two-line reference example (model
  / dir / branch on row 1; context bar / cost / duration on row 2).
- Supported output features: **ANSI color** escape codes and **OSC 8
  clickable hyperlinks**, in addition to plain text.

So the capability exists; this is a layout/design task, not a
feasibility question.

## Constraints (verified, shape the design)

- **Terminal width detection must use the `COLUMNS` / `LINES` env vars,
  NOT `tput cols`.** Claude Code captures the script's stdout rather than
  attaching it to a TTY, so TTY-based size queries do not work. Any
  width-aware wrapping/alignment in a multi-line layout must read
  `COLUMNS`. This is the main implementation gotcha.
- **No documented hard cap on line count**, but the status line sits
  above the prompt: each added row is a row taken from the visible
  conversation. The practical limit is design taste (likely 2, at most
  3 rows), not a technical maximum.
- Existing single-line install/refresh mechanics still apply: the script
  lives at the stable path `~/.claude/statusline.sh`, and the
  SessionStart refresh hook keeps it current (with the customized-copy
  opt-out from task 059). A multi-line rewrite must keep the
  `embo:auto-refresh` marker line so refresh/opt-out still work.

## Leading candidate signal — "what am I working on right now?"

The signal most likely to justify a dedicated row is a **current-focus
anchor**: a persistent "you are here" that answers what the session is
working on right now. It has three nested levels:

1. **Feature / PRD level** — the feature being built (the "why"). Static,
   file-backed: derivable from the active task folder / branch.
2. **Subtask level** — the formal subtask from `tasks/**/*-tasks.md` (the
   "what step"), e.g. the current `[~]` / in-progress marker. Also
   file-backed.
3. **Live-activity level** — the concrete thing happening this moment
   ("researching the grep-anchor edge case", "running a routine
   migration"). NOT written in any task file; exists only in the agent's
   working state.

**Why it matters (the motivation).** The agent (and the user) drills
into a sub-problem and gets stuck there, losing sight of which task it
serves — and over-solves a side-quest. A persistent anchor showing
"this research serves subtask 6.1, which serves feature X" lets a
better-scoped decision be made faster. Observed repeatedly in practice.

**The hard part — level 3 freshness (this gates the whole idea).**
Levels 1–2 are cheap: the status-line script reads them off disk. Level
3 cannot be read — the script gets only a fixed JSON payload and has no
channel into the agent's current activity. So level 3 must be *written*
by the agent to a scratch file the script reads (e.g.
`.claude/current-focus.txt`). That reintroduces the "Enforce, don't ask"
problem: an agent told to "keep your focus file updated" forgets under
load, and a STALE focus line is worse than none — it confidently claims
you are on 6.1 when you have wandered off. A wrong "you are here" is a
trap, not an aid.

Freshness options (rank in the PRD):
- **Hook-driven / mechanical** — derive levels 1–2 from the last task
  file touched or the branch name. Honest but coarse; cannot capture
  level 3.
- **Agent-written, marker-based** — reuse the existing marker pattern
  (like `[correction]`): the agent emits a `[focus] …` line, a hook
  captures the latest into the focus file, the row displays it. Fits the
  architecture; risk is staleness when the agent stops emitting.
- **Agent-written with decay** — the focus line carries a timestamp; the
  row greys or drops it after N minutes, so a stale focus visibly ages
  out instead of lying. This decay is what makes agent-written focus
  safe, and is likely required, not optional.

Note the scope split: the *display* (this task) is trivial once the
signal exists; the *reliably-fresh focus signal* is a hook/marker/decay
mechanism that is really a separate concern. Keep them distinct in the
PRD even though the idea is recorded here.

## Open questions for the PRD

- **What extra signals** justify a second (or third) row? The
  current-focus anchor above is the leading candidate. Other candidates:
  claude-mem freshness/last-capture (task 020), active task / branch
  state, RLM index age, token-usage bar, profile name. Rank by value per
  row of screen real estate.
- **Focus freshness** — which of the three freshness options above, and
  is a decay/staleness indicator mandatory? (A stale anchor is worse
  than none.)
- **Level packing** — can levels 1+2 share one row
  (`feat: X › 6.1 anchor guard`) leaving level 3 its own row, since
  level 3 changes most often?
- **How many rows** — fixed 2, or adaptive (collapse to 1 when the info
  is stale/absent)?
- **Width behavior** — truncate, wrap, or hide segments when `COLUMNS`
  is narrow?
- **Color/link use** — adopt ANSI thresholds (e.g. context bar reddens
  near full) and OSC 8 links (e.g. clickable branch / PR)? The docs
  example uses colored bars.
- **Manual-install parity** — the statusline ships only via the manual
  `--statusline-only` path; the multi-line version must document the
  same install/refresh steps.

## Related

- `plugin/statusline.sh` — the current single-line script to extend.
- Task 008 (statusline config) — original statusline content/format.
- Task 020 (statusline mem-freshness indicator) — a candidate second-row
  signal; may fold into this.
- Task 059 (statusline custom-preserve) — the refresh/opt-out mechanism
  a multi-line rewrite must remain compatible with (keep the
  `embo:auto-refresh` marker).

## Recommended next step

Run `/embo:prd` to decide the row count, the signals per row, and the
width/color behavior — grounded in the verified constraints above
(`COLUMNS` for width, keep the refresh marker).
