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
| D-3 | Where does the subsequent-run fast-path (FR-5) sentinel go? | Inline in `start.md`'s Batch A section as an explicit conditional check before proceeding to Batch B. | PRD §FR-5 + D-4 decision in PRD: sentinel is `| System status |`; `grep -rn 'System status' plugin/` shows only `start.md` lines 694 and 703. |
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

3. **Subsequent-run cost** (FR-5): an inline sentinel check skips the full
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
- Token sentinel `| System status |`: appears only at `start.md` lines 694
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

**Problem**: `start.md` lines 686–707 (Summary + AskUserQuestion) have no
structural gate preventing the model from emitting the menu before the
session-scout Task result arrives. The existing Batch B prose ("spawn the
session-scout Task") implies an ordering constraint but does not enforce it.
The project's own design principle (CLAUDE.md: "a behavioral rule that exists
only as prose the model is asked to follow will eventually be violated") means
this approach has already proven insufficient — the defect is real and
observed.

**Enforcement mechanism**: A `CHECKLIST:SCOUT-FIRST` block added to `start.md`
is extracted by `behavioral-reminder.sh` and re-injected verbatim into every
prompt. This is identical to how the existing `CLOSING-CHOICE`,
`RESTATE-CORRECTION`, and other checklists work. The model sees the ordering
constraint not once at load time but on every prompt, making it salient at the
moment of action.

**The CHECKLIST block** (to be added to `start.md` in the Batch B or Summary
section, as the last item before the Summary instructions):

```
<!-- CHECKLIST:SCOUT-FIRST
     This block is injected verbatim on every user prompt by
     hooks/behavioral-reminder.sh. Keep it short; edit it here only. -->
[SCOUT-FIRST checklist] Before emitting the session summary or
AskUserQuestion: confirm the session-scout Task result is present in
the current turn's tool results. If it has not returned, do not emit
the summary or AskUserQuestion — wait for the scout.
<!-- /CHECKLIST -->
```

The HTML-comment header is for human readability; the `[SCOUT-FIRST checklist]`
line (starts with `[`) is the awk extraction anchor that matches
`/^\[.*checklist/`. The close-tag `<!-- /CHECKLIST -->` is required by the
extractor. This format is identical to all existing CHECKLIST blocks (verified
from `start.md` lines 92–171).

**FR-2 Single-menu guarantee**: The CHECKLIST block covers the primary path.
For the edge case where the model emitted a first menu before the scout
returned (race condition), an additional instruction in the Summary section
states: "If `AskUserQuestion` was already emitted this turn, do NOT emit
another one — update the earlier response in prose if correction is needed."
This is prose, but it addresses a non-recurring edge case (the CHECKLIST
covers the recurring failure mode). The CHECKLIST is the primary enforcement.

**What this replaces**: the prose-only statement in the current Batch B
section ("the task-file bulk never enters this context") does not address
ordering. The new CHECKLIST block is additive — prose instructions remain,
the CHECKLIST adds machine re-injection.

**Verification**: `manual-run-claude` — run `/embo:start` in a session where
the scout has > 5 s delay; confirm exactly one `AskUserQuestion` appears and
its recommended task matches the scout's digest.

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

> If the string `| System status |` is already present in this session's
> conversation context (from a prior `/embo:start` run this session), run
> only these two commands:
>
> - `git log --oneline -10`
> - `git diff --stat HEAD`
>
> Then emit a short delta note ("N new commits since last check; working
> tree clean/dirty") and the next-action `AskUserQuestion`. Skip Batch A
> and Batch B entirely.

The sentinel `| System status |` appears in no other context output
(verified: only `start.md` lines 694 and 703; not in CLAUDE.md, hooks, or
README). Risk of false positive is low; a false positive causes a cheaper-
than-full startup, not a broken one.

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
- If the sentinel check for FR-5 produces a false positive (some other
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
  add FR-5 sentinel check; tighten rules region (FR-3)
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

- FR-1 CHECKLIST adds ~10 tokens per `behavioral-reminder.sh` injection
  (every prompt). Negligible; offset by the eliminated double-scout-spawn
  cost.
- FR-3/FR-4 directly reduce per-session token cost; the target is ≤ 6,650
  tokens for `start.md` total (8,866 × 0.75 = 6,650; PRD target ≤ 6,700
  remains satisfied).
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
