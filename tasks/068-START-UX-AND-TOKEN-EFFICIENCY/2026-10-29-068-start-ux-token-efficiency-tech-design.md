# 068: /embo:start UX fixes and token efficiency — Technical Design

**Status**: Draft
**PRD**: [2026-10-29-068-start-ux-token-efficiency-prd.md](2026-10-29-068-start-ux-token-efficiency-prd.md)
**Created**: 2026-10-29

---

## Decisions Taken (unattended mode)

This tech-design was written with `EMBO_DOCTREE_UNATTENDED` set. Every
interactive gate that would have asked a clarifying question was decided
from evidence as follows:

| # | Question | Decision | Evidence |
|---|---|---|---|
| D-1 | How should FR-1/FR-2 (scout-first ordering) be enforced? | Add a `CHECKLIST:SCOUT-FIRST` block to `start.md`, extracted and re-injected by `behavioral-reminder.sh`. Prose-only ordering is the known failure mode. | CLAUDE.md "Core Design Principle — Enforce, Don't Ask"; `behavioral-reminder.sh` lines 110–115: awk extraction of every `CHECKLIST` region; PRD amendment evidence from SkillReducer (arxiv.org/pdf/2605.11774) and LLM-DCP (arxiv.org/pdf/2504.11004). |
| D-2 | How should token tightening (FR-3/FR-4) be verified? | `embo-tokens` measurement before and after each file. | PRD §NFR-2; `start.md` already references `embo-tokens`; no other token counter exists in the toolchain. |
| D-3 | Where does the subsequent-run fast-path (FR-5) check go? | Inline in `start.md`'s Batch A section as an explicit conditional check before proceeding to Batch B. | PRD §FR-5 + D-4 decision in PRD. (The marker named there, `| System status |`, was later superseded — see the Proposed Design section below.) |
| D-4 | Should FR-5 be a separate file or inline? | Inline in `start.md`. | No flag/config mechanism exists for per-run conditional logic; command files are read in full, so the conditional must be prose within the command. |
| D-5 | PRD assumption: "Token costs of other files measured 2026-10-29 [assumption, verify in tech-design]" | Verified with a fresh `embo-tokens` run on 2026-10-29: `start.md` 8,866 tok, `prd.md` 4,113 tok, `impl.md` 4,470 tok, `tech-design.md` 2,800 tok, `tasks.md` 2,612 tok, `session-scout.md` 848 tok, `examine-advisor.md` 1,283 tok, `approach-validator.md` 2,711 tok. PRD figures accurate. These are the baselines for Story 2/3 measurement. | `plugin/bin/embo-tokens` run output, 2026-10-29 (in this session). |
| D-6 | CHECKLIST block format: does the awk extractor fire on the `<!-- CHECKLIST:NAME -->` HTML comment or on the `[NAME checklist]` line inside the block? | The awk fires on `/^\[.*checklist/` — matching lines that START with `[`. The `<!-- CHECKLIST:NAME -->` header is metadata only; the `[NAME checklist]` content line (which starts with `[`) is the actual extraction anchor. Any new SCOUT-FIRST block must include both: the HTML comment header (for human readability) and the `[SCOUT-FIRST checklist]` content line for awk extraction. | `behavioral-reminder.sh` line 114: awk pattern confirmed; `start.md` lines 92–106 (WITHSTAND-CRITICISM block) and lines 155–171 (CLEAR-OPTIONS block): both use `<!-- CHECKLIST:NAME -->` + `[NAME checklist]` format — verified by direct file read 2026-10-29. |

---

## Overview

Three problems in `start.md` are addressed:

1. **Double-menu defect** (FR-1/FR-2): the model emits `AskUserQuestion`
   before the session-scout Task returns, then emits a second one when the
   scout notification arrives. The fix adds a machine-enforced ordering
   constraint via a CHECKLIST block, not prose alone.

2. **Token overhead** (FR-3/FR-4): the behavioral-rules region of `start.md`
   (~7,000 tokens, ~79% of the file) duplicates what `behavioral-reminder.sh`
   already re-injects per-prompt via CHECKLIST extraction. The rules prose is
   tightened; other high-load command files are tightened to ≥ 15%.

3. **Subsequent-run cost** (FR-5): an inline marker check skips the full
   startup document when this session has already completed a `/embo:start`
   run.

---

## Current Architecture (RLM-verified)

**Verified facts** (all re-confirmed for this tech-design, 2026-10-29):

- `start.md` line count: 740 lines — verified via `wc -l` 2026-10-29.
- Token baselines (fresh `embo-tokens` run, 2026-10-29):
  - `start.md`: 8,866 tokens (char/4 estimate)
  - `prd.md`: 4,113 tokens
  - `impl.md`: 4,470 tokens
  - `tech-design.md`: 2,800 tokens
  - `tasks.md`: 2,612 tokens
  - `session-scout.md`: 848 tokens
  - `examine-advisor.md`: 1,283 tokens
  - `approach-validator.md`: 2,711 tokens
- Rules region: lines 36–618 (583 lines). Workflow region: lines 619–740
  (122 lines). Verified by reading `start.md` lines 1–50 and 620–740
  directly.
- `behavioral-reminder.sh` lines 110–115: uses `awk '/<!-- \/CHECKLIST -->/{f=0} f{print} /^\[.*checklist/{f=1;print}'` to extract every `CHECKLIST` block from `start.md` at runtime. The awk pattern matches lines starting with `[` (not `<!--`) — this is the awk anchor; the CHECKLIST open-tag in `start.md` uses the form `<!-- CHECKLIST:NAME -->` which does NOT start with `[`. The existing extraction relies on the open-tag being a bare `[...checklist` line — this must be preserved when adding new blocks.
- Session-scout Task invocation: `start.md` lines 658–667 — scout is spawned
  in Batch B with no explicit wait-for-result gate before the Summary section
  (lines 686–707). This is the structural gap that causes the double-menu
  defect.
- `AskUserQuestion` is emitted in the Summary section close, line 705.
- `behavioral-reminder.sh` hook is registered as a `UserPromptSubmit` hook
  (injects into every prompt); re-injection is unconditional — verified via
  `hooks/hooks.json` reference in `CLAUDE.md`.
- The string `| System status |`: appears only at `start.md` lines 694
  and 703. Not present in CLAUDE.md, hook outputs, or README — verified via
  `grep -rn 'System status' plugin/` returning only those two lines.

**CHECKLIST extraction awk anchor (critical constraint):**

The awk extractor fires on `/^\[.*checklist/` (line starts with `[`).
The existing CHECKLIST blocks in `start.md` use this two-part format
(verified by direct read of `start.md` lines 92–171, 2026-10-29):

```
<!-- CHECKLIST:NAME
     This block is injected verbatim on every user prompt by
     hooks/behavioral-reminder.sh. Keep it short; edit it here only. -->
[NAME checklist] ...governing sentence here...
...more content...
<!-- /CHECKLIST -->
```

The `<!-- CHECKLIST:NAME -->` HTML-comment header is human-readable metadata.
The `[NAME checklist]` line is the awk extraction anchor — it starts with `[`
and matches `/^\[.*checklist/`. Both parts are required: the header for
consistency and documentation; the `[` line for extraction.

Any new CHECKLIST block for SCOUT-FIRST must include both the HTML comment
header AND the `[SCOUT-FIRST checklist]` content line starting with `[`.

---

## Past Decisions (Claude-Mem)

- No TECH-DESIGN observations for task 068 found in claude-mem (new feature).
- Task 047 (CONCLUSION-HARNESS): shipped the `behavioral-reminder.sh`
  CHECKLIST extraction mechanism. The enforcement pattern for ordering rules
  is well-established: add a CHECKLIST block to `start.md`, extraction is
  automatic. This is the correct extension point for FR-1.
- Task 052 (START-SLIM): closed; addressed parallel batching. Did not add
  ordering enforcement for scout-first. Confirms that the defect survived
  that task and requires a different fix (structural gate, not structural
  batching).

---

## Proposed Design

### Implementation of FR-1 Scout-first menu and FR-2 Single menu guarantee

**STATUS: BLOCKED.** One design was implemented, live-tested, failed, and
was reverted. No documented plugin-available replacement exists.

**Root cause (confirmed 2026-10-29)**: per the Claude Code documentation,
"subagents Claude spawns from the main conversation already start in the
background by default", and background results "arrive as a completion
notification in a later turn". The command reaches its Summary step before
the scout result exists; the result then lands as a new turn, producing a
second summary and menu. This is documented default behaviour.

**Attempt 1 (reverted, commit 847a6a5)**: rewrite the Summary precondition to
require a `<teammate-message teammate_id="session-scout">` block, enforced by
a `CHECKLIST:SCOUT-FIRST` block, plus a prose guard against a second
`AskUserQuestion` in the same turn.

Live result: the command DID wait for the scout — that part worked — but still
produced two summaries and two menus, the second as prose rather than
`AskUserQuestion`.

Why it failed:
- `<teammate-message>` is the envelope for several distinct events (a
  mid-flight message, a completion report, an idle notification). The
  condition was satisfied by the first, not by the agent finishing. In one
  observed case the two deliveries carried *different content*, so acting on
  the earlier one is not merely early — it can use worse data.
- The tag, the `idle_notification` shape and the "Teammate @X finished" line
  are **undocumented**. The documented completion signal is the agent ID.
- The single-menu guard said "this turn"; the later delivery arrives as a NEW
  turn, so the guard was literally true and never applied.

**Options assessed, none both documented and available to a plugin:**

| Option | Status |
|---|---|
| `background: false` in agent frontmatter | `background` is real, but documented only as *forcing* background; `false` as a blocking switch is **undocumented**. The one remaining candidate — must be live-tested. |
| Per-call foreground parameter | **Undocumented**. Only `model` and `effort` are documented per-call overrides. |
| `CLAUDE_CODE_FORK_SUBAGENT=0` | **Documented** as making Claude wait, but a session environment variable a plugin cannot set. |
| Run the scout inline, no subagent | Works, but discards the delegation that keeps task-file bulk out of the main context — contradicting this task's own goal. |

**Next step**: live-test `background: false`. If it does not block, FR-1 and
FR-2 close as blocked pending a Claude Code capability, and the finding is
worth reporting upstream.

**Caveat on the sources**: the documentation above was reached via WebFetch,
which summarises with a small model. Two fixes have now failed on second-hand
claims about undocumented behaviour — confirm the quotes against the live
page before building on them.

**Verification**: `manual-run-claude` — run `/embo:start`; confirm exactly one
`AskUserQuestion` appears and its recommended task matches the scout's digest.

---

### Implementation of FR-3 — start.md rules tightening

The rules region (lines 36–618) is edited in-place. The tightening strategy:

1. **Remove verbose examples** that illustrate a rule already stated
   clearly. The governing sentence stays; the example is cut.
2. **Remove restatement of context** — sentences that recap what the user
   or model "already knows" before stating the rule. Cut the preamble,
   keep the rule.
3. **Merge redundant sub-bullets** within a rule block when they say the
   same thing at different levels of specificity.
4. **CHECKLIST blocks are not touched.** They are extracted verbatim by
   the hook; any change risks breaking extraction or changing behavior.

Each rule block is measured (token diff) before and after. Total target:
≥ 25% reduction in the rules region (lines 36–618), from ~7,000 to
≤ 5,250 tokens.

The CHECKLIST blocks introduced for SCOUT-FIRST (FR-1) are additive and
excluded from the tightening delta measurement — they pay for themselves by
removing the need for the verbose prose ordering description.

**Constraint**: `behavioral-reminder.sh`'s extraction test must pass after
every edit. The extraction awk relies on:
- Open tag: a line starting with `[`, containing `checklist`
- Close tag: a line containing `<!-- /CHECKLIST -->`

No other changes to `start.md` format are required.

---

### Implementation of FR-4 — Command and agent tightening

Files in scope: `prd.md`, `impl.md`, `tech-design.md`, `tasks.md`,
`session-scout.md`, `examine-advisor.md`, `approach-validator.md`.

Same tightening strategy as FR-3. Per-file target: ≥ 15% token reduction.

Token baselines are re-measured at implementation start (PRD assumption
D-5 above). The `embo-tokens` command is the measurement tool.

A file is skipped if tightening would require removing a behavioral
constraint (any instruction that governs model behavior), rather than
merely shortening its prose expression.

---

### Implementation of FR-5 — Subsequent-run fast path

An inline conditional is added at the very start of `start.md`'s workflow
section (before Step 0 / Batch A), instructing the model:

> If the output marker `<!-- embo-start: complete -->` is already present
> in this session's conversation context (written by a prior `/embo:start`
> summary step), run only these two commands:
>
> - `git log --oneline -10`
> - `git diff --stat HEAD`
>
> Then emit a short delta note ("N new commits since last check; working
> tree clean/dirty") and the next-action `AskUserQuestion`. Skip Batch A
> and Batch B entirely.

**Why this marker**: it MUST be a string that only a completed run's
*output* produces. The previously considered `| System status |` appears
at `start.md` line 703 inside the command file itself, so it is always
present in context on every invocation — this would cause the fast path
to fire on the very first run, preventing Batch A/B from ever running.

The correct marker is `<!-- embo-start: complete -->`. Before finalising:
verify via `grep -rn 'embo-start: complete' plugin/ ~/.claude/` that this
string appears nowhere in existing command files, hook outputs, CLAUDE.md, or
README. If found, choose a different unique string.

The Summary step in `start.md` must write this marker line at the end of
its output on every full run.

The first run's session summary remains in context (it is never deleted).
The delta note is additive.

---

## Data Models

No new data structures. The session summary table (existing Markdown table
in `start.md` lines 693–703) is the only in-context state involved; it is
read as text, not stored as structured data.

---

## API Design

No new endpoints or tools. The `Task` tool invocation for session-scout
(existing) is unchanged. The CHECKLIST block is the only new interface
(read by `behavioral-reminder.sh` via awk).

---

## Integration Points

- **`behavioral-reminder.sh`**: reads `start.md` at hook-fire time and
  extracts all CHECKLIST blocks. The SCOUT-FIRST block is added to this
  extraction set automatically; no change to the hook script is required.
- **`session-scout` agent**: invocation in Batch B is unchanged. The
  CHECKLIST enforces that the caller waits for the result.
- **`embo-tokens`**: used for before/after measurement; no change to the
  tool itself.

---

## Error Handling

- If `behavioral-reminder.sh` fails to extract the SCOUT-FIRST block (awk
  error or malformed tag), the hook exits 0 silently (existing behavior).
  The fallback is the prose instruction in `start.md`, which is not removed.
  This is a degraded-but-not-broken state.
- If the marker check for FR-5 produces a false positive (some other
  context source includes `| System status |`), the command runs a cheaper-
  than-full startup — the user sees a delta note instead of a full summary.
  This is recoverable: the user can re-run `/embo:start` explicitly.

---

## Testing Strategy

**Existing test to preserve**: `behavioral-reminder.sh` extraction must
extract all CHECKLIST blocks, including SCOUT-FIRST, after the edits.
Run: verify via `awk` dry-run on the edited `start.md`.

---

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1: Scout-first ordering enforced | `manual-run-claude` | integration | Single `AskUserQuestion` after scout returns; recommended task matches scout digest |
| FR-2: Single menu guarantee | `manual-run-claude` | integration | No second `AskUserQuestion` in the same turn |
| FR-3: start.md ≥ 25% reduction | `code-only` | — | `embo-tokens start.md` before/after shows ≥ 25% drop in rules region |
| FR-4: Each file ≥ 15% reduction | `code-only` | — | `embo-tokens <file>` before/after shows ≥ 15% drop per file |
| FR-5: Subsequent-run fast path | `manual-run-claude` | integration | Second `/embo:start` in same session skips Batch A/B, emits delta note |
| NFR-1: Behavioral fidelity | `code-only` | — | Before/after diff shows no governing constraint removed |
| NFR-2: Token budget discipline | `code-only` | — | `embo-tokens` output recorded before and after each story |
| NFR-3: No approval-dialog regression | `manual-run-claude` | integration | Headless run completes with no Bash approval dialogs |

---

## Trade-offs

### FR-1/FR-2: CHECKLIST vs. structural gate

**Option A (prose-only)**: Add a sentence to the Summary section: "Do not
emit AskUserQuestion until the scout result is present."

- Pros: Zero implementation effort.
- Cons: This is exactly the approach that failed. The double-menu defect
  exists despite Batch B already implying the ordering. Adding more prose
  to the same section violates CLAUDE.md's core principle.
- Historical context: Task 052 added structural batching without ordering
  enforcement; defect survived.

**Option B (recommended): CHECKLIST block** — the project's established
enforcement mechanism for ordering rules, re-injected on every prompt.

- Pros: Machine-enforced; aligned with the project's design principle;
  zero hook changes needed; survives context compression (re-injected each
  prompt).
- Cons: Adds ~10 tokens to every `behavioral-reminder.sh` injection;
  negligible cost.
- Why recommended: Evidence from SkillReducer and LLM-DCP shows structural
  gates reliably prevent premature emission; the CHECKLIST mechanism is the
  project's established equivalent.

**Option C (structural wait)**: Restructure `start.md` so the Summary section
appears only as a sub-step of Batch B's "after results" block, making it
syntactically impossible to reach before Batch B returns.

- Pros: Fully structural; no runtime enforcement needed.
- Cons: Major restructuring of `start.md` with high risk of regressions;
  command files are prose, not code — there is no execution model that
  "prevents" reaching a later section. Structural prose ordering has the
  same failure mode as prose-only.
- Rejected: the CHECKLIST mechanism is simpler and sufficient.

### FR-3/FR-4: Tightening scope

**Option A (full rewrite)**: Rewrite entire files for maximum compression.

- Pros: Maximum token savings.
- Cons: High risk of losing behavioral constraints; difficult to review.
- Rejected.

**Option B (recommended): Targeted prose tightening** — remove examples,
preambles, redundant sub-bullets while keeping every governing sentence.

- Pros: Reviewable diff; behavioral fidelity verifiable.
- Cons: More conservative savings (≥ 15–25% not maximum).

---

## Implementation Constraints

- The `behavioral-reminder.sh` awk extractor anchor (`/^\[.*checklist/`)
  must be respected when adding new CHECKLIST blocks.
- No CHECKLIST block content may be changed (hook re-injects verbatim;
  any change is immediately live).
- The token reduction must be measured before and after each story (NFR-2).
- `embo-tokens` is the canonical measurement tool; no other tool should be
  used for comparisons.

---

## Files to Create/Modify

**Modify**:
- `plugin/commands/start.md` — add SCOUT-FIRST CHECKLIST block (FR-1/FR-2);
  add FR-5 marker check; tighten rules region (FR-3)
- `plugin/commands/prd.md` — tighten prose (FR-4)
- `plugin/commands/impl.md` — tighten prose (FR-4)
- `plugin/commands/tech-design.md` — tighten prose (FR-4)
- `plugin/commands/tasks.md` — tighten prose (FR-4)
- `plugin/agents/session-scout.md` — tighten prose if ≥ 15% achievable
- `plugin/agents/examine-advisor.md` — tighten prose if ≥ 15% achievable
- `plugin/agents/approach-validator.md` — tighten prose if ≥ 15% achievable

**Create**: none.

---

## Dependencies

**Internal**:
- `behavioral-reminder.sh`: the extraction mechanism is load-bearing for
  FR-1. No changes to the hook itself; the new CHECKLIST block is picked up
  automatically.

**External**: none.

---

## Security Considerations

None specific to this task. No new data flows, tools, or credentials.

---

## Performance Considerations

- FR-1 SCOUT-FIRST CHECKLIST adds ~15 tokens per `behavioral-reminder.sh`
  injection (every prompt, every session). This is a recurring cost that
  partially offsets the FR-3 savings; it must be recorded in NFR-2
  accounting alongside file-level measurements.
- FR-3/FR-4 target: the whole-file total for `start.md` after all Story 1
  and Story 2 additions must be ≤ 6,700 tokens (baseline 8,866; single
  target). Arithmetic check: a 25% rules-region cut (7,000 → 5,250) yields
  ~7,100 whole-file tokens before Story 1 additions (~50 tokens for
  SCOUT-FIRST block + FR-5 prose). To reach ≤ 6,700, the rules region
  must be cut by more than 25%, or the 6,700 target must be adjusted.
  **Tech-design must produce a closing arithmetic table at implementation
  start: budgeted cuts vs. additions, confirming the target is achievable
  before edits begin.**
- FR-5 reduces subsequent-run cost by skipping ~8,000 tokens of Batch A/B
  work; the delta path costs ~110 tokens (two git commands + delta note).

---

## Rollback Plan

All changes are to command/agent `.md` files in the `plugin/` directory.
Rollback is a `git revert` of the commit(s) for each story. No schema
migrations, database changes, or binary state is involved.

---

## References

### Code:
- `plugin/commands/start.md:645–707` — Batch B and Summary sections
- `plugin/hooks/behavioral-reminder.sh:110–115` — CHECKLIST awk extractor
- `plugin/hooks/behavioral-reminder.sh:97` — baseline injection line

### Design principle:
- CLAUDE.md: "Core Design Principle — Enforce, Don't Ask"
- CLAUDE.md: task 047 (CONCLUSION-HARNESS): shipped CHECKLIST enforcement

### Research (from PRD amendment):
- SkillReducer (arxiv.org/pdf/2605.11774): Gate 1/Gate 2 quality gates
  enforce subagent completion before output generation
- LLM-DCP MDP framing (arxiv.org/pdf/2504.11004): emission actions strictly
  conditioned on prior sub-task completion states

---

**Next Steps**:
1. Review and approve design
2. Run `/embo:tasks` for task breakdown
