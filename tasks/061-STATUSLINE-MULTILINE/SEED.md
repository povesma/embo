# 061: Multi-line status line for more dynamic info — Seed

**Status**: Partially done — the minimal 2-row *layout* and the ATC
`.cc.json` consumer writer shipped 2026-11-07 (commit `1b513ae`, ATC
live-verified); the richer focus-anchor design below is still not started
(run /embo:prd to begin that part). One open cross-session promise: ping
ATC when this reaches the installed version (see Remaining scope).
**Origin**: raised 2026-09-03 — one status line row is not enough to fit
the dynamic information wanted.

## Done 2026-11-07 — minimal 2-row layout (the "display" half)

The single-row overflow (long path + long branch pushed metrics
off-screen, worsened by task 070's new `embo:` stage segment) was fixed
by splitting `plugin/statusline.sh` into two rows:

- **Row 1 (identity):** `<path> | <branch>` — the two long items.
- **Row 2 (metrics):** `<model> | <used>/<total> $<cost> | ctx <pct>% |
  embo:<stage> | mem:<freshness> | <HH:MM:SS>`.

No `COLUMNS` math was needed — the plain split alone keeps the long items
off the metrics row. The `embo:auto-refresh` marker is preserved. Covered
by `plugin/statusline.test.sh`. The format contract is documented in
`docs/REFERENCE.md` §Statusline so external consumers can parse it.

### Remaining scope (still task 061)

- **Raw Claude Code stdin JSON, saved to a per-session file** — BUILT,
  committed in `1b513ae`, verified live by ATC 2026-11-07 (agreed with
  the ATC consumer — supersedes the earlier "env-gated stdout JSON mode"
  idea, which cannot reach ATC: ATC sees only the screen via herdr, not
  the script's stdout, so a file is required).
  - **Status:** implemented as `save_cc_stdin()` in `plugin/statusline.sh`,
    covered by `plugin/statusline.test.sh` (6 cc cases). ATC measured the
    committed branch build: 2-row line parses (model/ctx/limit/cost read),
    `.cc.json` present at the agreed path, 0600, named by herdr's session
    id — confirming herdr's id == Claude Code's `session_id`.
  - **Open follow-up (cross-session promise):** ATC asked to be pinged
    when this reaches the INSTALLED version (merged to the shared branch +
    plugin reloaded in `~/.claude`), not just on the feature branch. The
    next session must send that ping to the ATC session after install/merge.
  - **Auto-propagation caveat (found 2026-11-07):** `~/.claude/statusline.sh`
    does NOT stay branch-only. The `statusline-refresh.sh` SessionStart
    hook copies the active plugin's bundled `statusline.sh` over the
    installed copy whenever they differ and the copy still carries the
    `# embo:auto-refresh` marker. So while this branch is the active
    (dogfood) plugin, every new session refreshes the installed statusline
    to this branch's version — ATC saw the 2-row line + `.cc.json` from a
    plain no-`--settings` probe for exactly this reason. Practical effect:
    the feature is effectively installed already on this machine, ahead of
    a formal merge. The still-pending formal ping is just to mark a clean,
    agreed, merged version.
  - **Confirmed consumer:** ATC parses embo's statusline. (An earlier
    message wrongly said it parsed a separate "Claude Code footer"; the
    owner confirmed the line ATC reads IS embo's statusline, set in the
    owner's user settings.)
  - **Design (agreed):** the statusline writes the raw stdin JSON blob,
    unchanged, to `${XDG_STATE_HOME:-$HOME/.local/state}/embo/session-state/<session_id>.cc.json`
    — a SEPARATE file from task 070's own `<session_id>.json` so the two
    never collide. Atomic write (temp + rename), mode 0600, mtime prune
    reuses task 070's prune. **Always on** (ATC needs every session),
    **but the write must NEVER affect the statusline output or exit code**
    — errors swallowed, statusline prints regardless.
  - **Rationale for raw:** ATC treats every field as optional and many
    fields are version-dependent / null early (`used_percentage`,
    `current_usage`), so a raw blob means embo maintains no schema.
  - **Resolved with ATC 2026-11-07:** (1) NO redaction — save fully raw
    (ATC already shows the dir to its signed-in owner). (2) NO forced
    `refreshInterval` — ATC reads staleness from the file's mtime. (3) The
    path and the `.cc.json` name are a **contract between embo and ATC**:
    do not change either without telling ATC first. (4) 14-day prune is
    fine — a pruned file just makes ATC fall back to screen parsing until
    the next write.
  - **Stale-doc note:** the earlier REFERENCE claim that embo also emits a
    trailing "`<n> tokens`" field was wrong — that field is Claude Code's
    own footer, never embo's.
- The **current-focus anchor** (3-level "you are here") and its freshness
  / decay mechanism, below — the original richer-signal idea, unbuilt.

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
