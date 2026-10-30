# 068: /embo:start UX fixes and token efficiency — PRD

**Status**: Draft
**Created**: 2026-10-29
**Author**: embo workflow

---

## Wider Context / Higher Goal

Every `/embo:start` run costs context-window budget and takes time.
When the session-startup UX is broken (double menu, stale recommendation)
the user loses trust in the tool. When every command loads more prose
than it needs, that budget cannot be spent on actual work. Both problems
compound across projects: every team member running embo pays the cost
every session.

---

## Decisions Taken (unattended mode)

This PRD was written with the mandatory clarifying-question step (Step 4)
skipped under `EMBO_DOCTREE_UNATTENDED`. Every question that step would
have asked was decided from evidence as follows:

| # | Question | Decision | Evidence |
|---|---|---|---|
| D-1 | Who is the primary user? | embo developers and users running `/embo:start` at session start. | claude-mem obs #73354 (double-menu observed in a live session); the draft already states this explicitly. |
| D-2 | What problem does this solve? | Three concrete defects: double menu, scout-first ordering violation, excessive token cost per run. | claude-mem obs #73354 (double-menu root cause); `start.md` lines 36–618 (7,000-token rules region measured 2026-10-29). |
| D-3 | Success metric targets for tightening? | ≥ 25% reduction for `start.md` rules region; ≥ 15% for `prd.md`, `impl.md`, `tech-design.md`, `tasks.md`. | Draft already carried these thresholds; they are grounded in the `embo-tokens` measurements recorded in the draft's "Current State" section. Accepted as-is. |
| D-4 | Which marker detects a subsequent run? | Match `\| System status \|` alone — it is a required row in every summary table (`start.md` line 703) and appears in no other context output. The `## Session Summary` heading was not found in the command spec and would be unreliable. **Superseded — see D-7 in the task list: that string is inside `start.md` itself, so it is always present.** | `start.md` line 703: `\| System status \| RLM state…` is mandated table content; `grep -rn '## Session Summary' plugin/` → zero results (verified 2026-10-29). |
| D-5 | Priority of Story 4 (subsequent-run fast path)? | Medium — useful but not a correctness fix. | Correctness defects (Stories 1–2) are the user-visible breakage; the fast path is a performance improvement. Consistent with FR-5 in draft. |
| D-6 | Which files are out of scope for tightening? | `visual-impl.md` (~9,200 tokens, rare load); hooks, bin wrappers, manifests (not per-session prompt cost). | Draft already justified these exclusions. No counter-evidence found in codebase. |

---

## Problem Statement

**Who**: embo users running `/embo:start` at the beginning of each session.
**What**: Three distinct failures observed in a real session (2026-10-29):

1. **Double menu** — `/embo:start` shows the next-action `AskUserQuestion`
   before the session-scout agent finishes. When the user does not select
   an option (or dismisses it), the scout notification arrives and the
   model generates a *second* `AskUserQuestion` with a corrected
   recommendation. The user sees two menus for the same question.

2. **Scout not ready when menu appears** — because Batch B spawns the scout
   and immediately continues, the first menu's "Recommended next task"
   slot is empty or wrong. The scout's digest — the whole point of
   spawning it — never influences the first menu.

3. **Excessive token cost per run** — measured on 2026-10-29:
   - `start.md` total: ~8,900 tokens; rules region (lines 31–618):
     ~7,000 tokens (~79% of the file). The workflow instructions that
     actually vary per project are only ~900 tokens (lines 619–740).
   - The CHECKLIST blocks inside the rules are already re-injected by
     `behavioral-reminder.sh` on every prompt. Loading the full RULE
     prose once per session in addition to that re-injection is
     redundant for sessions where rules are already known.
   - Other high-load files (loaded every invocation):
     `prd.md` ~4,100 tok, `impl.md` ~4,500 tok, `tech-design.md`
     ~2,800 tok, `tasks.md` ~2,600 tok.
   - The user's stated requirement: "optimize the size of all embo
     commands, skills and other stuff that loads into the context —
     reduce the size, optimize wording, but keep it as meaningful as it
     is or even more meaningful."

**Why**: A broken startup UX is the first thing a user sees each session.
A 7,000-token overhead in behavioral rules that the hook already injects
piecemeal is waste that cannot be spent on code analysis or planning.

---

## Goals

### Primary Goals
1. The next-action menu appears exactly once per `/embo:start` run, after
   the scout's digest is available.
2. The recommended task in the menu is always drawn from the scout's
   actual digest.
3. The token cost of shipped commands and agents is measurably lower after
   this task, without losing behavioral fidelity.

### Secondary Goals
- Subsequent `/embo:start` runs within the same session are faster and
  cheaper than the first run.
- Any token reduction made in one file is consistent with the budget
  principle: additions must name the saving that offsets them.

---

## User Stories

### Story 1 — Fix the double-menu defect

**As** an embo user,
**I want** `/embo:start` to show the next-action menu exactly once,
**So that** I am not confused by a second menu appearing after I dismissed
the first.

**Acceptance Criteria**:
- [ ] Running `/embo:start` in a session where the scout takes > 5 s
  produces exactly one `AskUserQuestion` at the end.
- [ ] The menu's recommended task matches the scout's digest (not an
  empty slot or a guess made before the scout returned).
- [ ] The command instructions explicitly state: do not call
  `AskUserQuestion` until the scout agent result is in context.

### Story 2 — Reduce start.md token cost

**As** an embo user,
**I want** the behavioral-rules region of `start.md` to be as short as
possible while remaining behaviorally equivalent,
**So that** each session start spends fewer tokens on rules that the hook
already injects as checklists.

**Acceptance Criteria**:
- [ ] The rules region (lines 36–618) is reduced by ≥ 25% in tokens
  without removing any rule's governing constraint or checklist block.
- [ ] The `behavioral-reminder.sh` hook extraction test still passes
  after the edit (all CHECKLIST blocks intact, including the new
  SCOUT-FIRST block added in Story 1).
- [ ] `embo-tokens start.md` shows the whole-file total (including all
  Story 1 and Story 2 additions) is ≤ 6,700 tokens. Note: the 25%
  rules-region cut (7,000 → ≤5,250) yields ~7,100 whole-file tokens
  before Story 1 additions; to reach ≤6,700, the rules region must
  absorb Story 1's additions within its 25% budget, or additional cuts
  must be made. Tech-design must confirm the arithmetic before
  implementation.

### Story 3 — Reduce token cost of other high-load commands

**As** an embo user,
**I want** the per-invocation token cost of each command to be as low as
possible without losing meaning,
**So that** more of my context window is available for code analysis and
planning.

**Acceptance Criteria**:
- [ ] Each of `prd.md`, `impl.md`, `tech-design.md`, `tasks.md` is
  reduced by ≥ 15% in tokens with no loss of behavioral fidelity
  (verified by reading the before/after and confirming every instruction
  is still expressible).
- [ ] Agent files (`session-scout.md`, `examine-advisor.md`,
  `approach-validator.md`) are reviewed; any reduction ≥ 15% is applied.
- [ ] The total token cost of the files above does not increase from any
  change made in this task.

### Story 4 — Faster subsequent `/embo:start` runs

**As** an embo user running `/embo:start` more than once in the same
session (after a context-compression event, or after returning to a
session),
**I want** the command to detect that it already ran this session and
skip or compress the expensive parts,
**So that** repeated startups cost significantly less.

**Design recommendation** (for tech-design to confirm or revise):

The key question is what "expensive" means. From measurement:

| Part | Cost | Re-run value |
|---|---|---|
| `embo-profile show` | ~15 tokens in/out | Zero if profile unchanged; run anyway — it is fast and detects a mid-session `embo-profile set` |
| `rlm_repl status` | ~50 tokens | Zero on repeat; run anyway — 50 tokens is noise |
| `git log --oneline -10` | ~80 tokens | **High** — catches new commits since last start |
| `git diff --stat HEAD` | ~30 tokens | **High** — catches new uncommitted changes |
| `README.md` read | ~400–800 tokens | Zero on repeat; **skip if already in context** |
| memory search (Batch B) | ~300–600 tokens in | Zero on repeat; **skip** |
| session-scout agent | ~850 tokens (agent def) + scout output | Zero if no new task files; **skip if task files unchanged** |
| Behavioral rules prose | ~7,000 tokens | Already in context from first run; **always skip** |

Recommended "subsequent run" detection: the command checks whether the
session summary table is already in the conversation context. If it is
(the string `## Session Summary` together with `| System status |`
from this session), it runs only the two git commands and emits a short
delta note ("N new commits since last check; working tree clean/dirty")
rather than the full startup document. No flag required; detection is
automatic.

**Why not a `--delta` flag?** The user does not know or want to track
which run is the "first". Automatic detection removes that burden.
Risk: a false positive (the string is present from another source).
Mitigation: the two-string marker is specific enough to avoid most
false positives.

**Why not skip the git commands too?** New commits and a changing
working tree are the most likely reasons to re-run `/embo:start`. They
must always be checked.

---

## Requirements

### Functional Requirements

**FR-1 Scout-first menu**: The `AskUserQuestion` call at the end of
`start.md` MUST NOT be emitted until the session-scout agent result is
present in context.

**Status: BLOCKED.** No plugin-available fix is known. See below.

Root cause (confirmed 2026-10-29 by live test and documentation):
**subagents spawned from the main conversation start in the background
by default**, and background results "arrive as a completion
notification in a later turn". The command therefore reaches its
Summary step before the scout's result exists, and the result lands
afterwards as a new turn — producing a second summary and a second
menu. This is documented default behaviour, not a prose defect.

**A first fix was implemented and failed.** It rewrote the Summary
precondition to require a `<teammate-message teammate_id="session-scout">`
block, enforced by a CHECKLIST. A live run showed the command did wait,
then still produced two summaries and two menus: that tag is the
envelope for several events (a mid-flight message, a completion report,
an idle notification), so the condition was met by the first, not by the
agent finishing. The tag, the `idle_notification` shape and the
"Teammate @X finished" line are **all undocumented**; the documented
completion signal is the agent ID. The attempt was reverted.

**No documented fix is available to a shipped plugin.** `background`
frontmatter only *forces* background; `background: false` is not
documented as blocking. No per-call foreground parameter is documented.
`CLAUDE_CODE_FORK_SUBAGENT=0` would make Claude wait but is a session
environment variable a plugin cannot set. Running the scout inline would
work but discards the delegation that keeps task-file bulk out of
context — defeating this task's own goal.

Remaining candidate, untested: `background: false` in the agent
frontmatter. If a live test shows it does not block, FR-1 closes as
blocked pending a Claude Code capability.
- Priority: **High** (UX correctness)

**FR-2 Single menu guarantee**: The command must emit exactly one
`AskUserQuestion` per run. If the scout result arrives after the first
menu was already shown (edge case: the model did not wait), the command
must not emit a second one.
- Priority: **High**
- Rationale: Two menus for the same question is a broken experience.

**FR-3 start.md rules tightening**: The behavioral-rules prose region
is tightened. Each rule retains its full semantic constraint; only
redundant repetition, verbose examples, and restated context are cut.
The CHECKLIST blocks are not shortened (they are extracted by the hook
and must stay verbatim).
- Priority: **High** (highest token leverage: ~7,000 tokens, every
  session)

**FR-4 Command/agent tightening**: `prd.md`, `impl.md`,
`tech-design.md`, `tasks.md`, and the three listed agents are reviewed
and tightened. Target: ≥ 15% per file.
- Priority: **Medium**

**FR-5 Subsequent-run fast path**: When this session has already
completed a `/embo:start` run, the command runs only `git log --oneline
-10` and `git diff --stat HEAD`, then emits a short delta note instead of
the full startup document.

The completion marker MUST be a string that only the completed run's
*output* produces, never a string present in `start.md` itself. (The
previously proposed marker `| System status |` appears at `start.md`
line 703 inside the command file, so it is always present in context on
every run — this renders the fast path always-active and was rejected.)

The correct marker is a literal output-only line that the
Summary step writes into its response, for example:
`<!-- embo-start: complete -->`. This string must not appear anywhere in
`start.md`, `CLAUDE.md`, hook outputs, or README. Tech-design must verify
uniqueness before finalising the exact string.
- Priority: **Medium** (useful but not a correctness fix)
- Constraint: The first run's session summary must remain intact in
  context. The delta note is additive, not a replacement.

### Non-Functional Requirements

**NFR-1 Behavioral fidelity**: No tightening removes a rule's governing
constraint, its checklist block, or any `<!-- RULE:` marker (22 present
in `start.md`; hook text references some by name). Verified by: (a)
reading the before/after diff, (b) the `behavioral-reminder.sh`
extraction test passing, (c) a grep count of `<!-- RULE:` before and
after matching.

**NFR-2 Token budget discipline**: After this task, the total token cost
of the files listed in FR-3 and FR-4 is measurably lower. `embo-tokens`
output is recorded before and after each story. Additionally, the byte
size of the `behavioral-reminder.sh` injection output (the CHECKLIST
blocks extracted at runtime) is recorded before and after Story 1 — the
new SCOUT-FIRST block adds to every-prompt injection cost and must be
accounted for.

**NFR-3 No approval-dialog regression**: After edits to `start.md`, a
headless `claude -p "/embo:start"` run completes with no Bash approval
dialogs (same bar as Task 052 Story 4.2).

---

## Out of Scope

- Hooks, bin wrappers, `.claude-plugin/*` manifests — these are code
  and configuration, not per-session prompt cost. Covered separately
  if needed.
- Changing the rules themselves (which rules exist, what they govern).
  This task only tightens the prose.
- `visual-impl.md` (~9,200 tokens) — rare load; not worth the risk of
  breaking a complex command for marginal saving.
- The `/embo:start` "incremental indexing" RLM idea (re-index only
  changed files): a separate concern, out of scope here.

---

## Current State (observed)

- `start.md` rules region: 587 lines (lines 36–618), ~7,000 tokens —
  verified via `grep -n "<!-- RULE:"` showing first rule at line 36,
  last CHECKLIST closing at line 616, 2026-10-29.
- `start.md` workflow region: lines 619–740 (~122 lines), ~900 tokens —
  verified same method.
- Double-menu defect: observed in a live session transcript and recorded
  in claude-mem obs #73354, 2026-10-29; root cause is the model emitting
  `AskUserQuestion` before the scout notification arrives, then emitting
  a second one on receipt.
- `behavioral-reminder.sh` re-injects CHECKLIST blocks on every prompt
  — verified via hooks architecture, Task 047 shipped mechanism.
- Token costs of other files: measured 2026-10-29 with `embo-tokens`
  [assumption, verify in tech-design with a fresh embo-tokens run].

---

## Success Metrics

1. Zero double-menu occurrences in three consecutive live `/embo:start`
   runs after FR-1/FR-2 are shipped. Test repeated after Story 2 edits.
2. `start.md` whole-file total ≤ 6,700 tokens after all Story 1 and
   Story 2 edits (baseline 8,866; single target, measured post-additions).
3. Each of `prd.md`, `impl.md`, `tech-design.md`, `tasks.md` reduced
   ≥ 15% in tokens.
4. Subsequent-run fast path completes in ≤ 2 assistant turns (git
   commands + delta note + menu) vs ~6 turns for a full run.

---

## References

### Observed
- Live `/embo:start` transcript, 2026-10-29 (user-provided)
- claude-mem obs #73354: double-menu root-cause description
- `start.md` lines 36–618: rules region; lines 619–740: workflow region
  — verified via `grep -n` in this session, 2026-10-29
- `behavioral-reminder.sh` hook, Task 047 (existing mechanism)

### Related tasks
- Task 052-START-SLIM: closed; addressed structure and parallel batching.
  This task addresses scout ordering and token tightening.
- Task 055-TOKEN-AUDIT: seed only; scoped to producing an audit report.
  This task does the tightening.

---

**Next steps**: `/embo:tech-design` → `/embo:tasks` → implement on a
dedicated feature branch.
