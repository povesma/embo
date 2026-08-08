# 049: Proof Table for the Verification Agent - PRD

**Status**: Draft
**Created**: 2026-07-26
**Task**: 049-PROOF-TABLE-claim-proof-record
**Author**: Claude (via embo dev workflow)

---

## Wider Context / Higher Goal

The higher goal is to stop the LLM from asserting guesses as facts. The
user wants data-proven conclusions with a confidence calibrated to the
data that actually exists — replacing the model's felt certainty, which
reads as authoritative regardless of whether anything was checked. A
phrase like "is now precisely defined" is the failure this targets: it
sounds settled while resting on nothing verified. The proof table makes
the LLM show the methodology, the evidence, and how sure the *data*
(not the model) allows it to be.

## Context

embo's `/embo:research:verify` command spawns the `approach-validator`
agent to prove a chosen approach against independent sources before
implementation. Today the agent returns a verdict table with three
values — proven / unproven / contradicted — plus a claims list and
advice. That output records *whether* a claim was proven but not *how*,
not *why the alternatives were ruled out*, and not *how much the
available data actually supports the conclusion*. A confident-sounding
"proven" with a thin source reads the same as one with reproduced
authoritative data.

This feature enriches that agent's output into a **proof table**: for
each load-bearing claim, a structured record of the assumption, the
numbered methodology (usually a CLI that fetches data), the evidence,
a differential assessment of competing explanations, the conclusion,
and a 0–10 confidence calibrated to real data availability. It also adds
a **hedge-check** forcing step: the agent scans its own draft for hedge
words on load-bearing claims and must, for each, either produce a proof
-table entry or downgrade the claim to explicitly unproven.

### Current State (observed)

- The `approach-validator` agent's current output contract is a verdict
  table (proven / unproven / contradicted), a load-bearing-claims list,
  and constructive advice. — verified via: read of
  `plugin/agents/approach-validator.md` (Output section), 2026-07-26
- The agent already has a step to prove claims against independent
  sources and a step to "exercise un-proven executable paths once" (a
  read-only command) — the numbered-methodology field maps onto this
  existing behavior, it is not new capability. — verified via: read of
  `plugin/agents/approach-validator.md` (Process steps 2–3), 2026-07-26
- There are two distinct research agents: `approach-validator` (spawned
  by `/embo:research:verify`) and `examine-advisor` (spawned by
  `/embo:research:examine`, which itself runs two passes). They are not
  two passes of one agent. This feature touches only
  `approach-validator`. — verified via: read of both agent files,
  2026-07-26
- Subagents cannot run PostToolUse/Stop hooks, so an in-agent artifact
  is contract-forced, not hook-measured (unlike the main-loop
  `Objection-check`). — verified via: claude-mem obs #33488
  (PostToolUse limitation), 2026-07-26

### Past Similar Features (from claude-mem)

- #21212 / #21369 / #21371 — the verify command and the
  approach-validator agent (originally verify-critic), which already
  return structured constructive advice. This feature extends that
  contract.
- Task 047 (`Objection-check`) — the reference pattern for a forced,
  one-line artifact the agent must emit before proceeding. The
  hedge-check is modeled on it, minus the hook measurement (subagent
  limitation).

## Problem Statement

**Who**: An embo user running `/embo:research:verify` to check an
approach before building on it.
**What**: The verification agent can state a claim as "proven" without
showing the methodology, without ruling out competing explanations, and
without signalling how thin or thick the underlying data is — so a
guess dressed in confident language passes as verified.
**Why**: Building on a claim that was asserted rather than proven is the
exact cost `/embo:research:verify` exists to prevent; a lossy verdict
lets that cost through.
**When**: Every verification run, most dangerously when the agent has
little data and fills the gap with fluent, confident prose.

## Goals

### Primary Goal

For each load-bearing claim, the verification agent produces a structured
proof-table record whose confidence is calibrated to the data that
actually exists, and it cannot let a hedged (guessed) claim stand as a
fact without either proving it or marking it unproven.

### Secondary Goals

- A low confidence acts as a forcing function: it obliges the agent to
  name the methodology that would raise it, or to prove that no such
  methodology is available without more access/research.
- The quick top-line (the existing verdict) is preserved for scanning,
  above the full record.
- The mechanism is generic — no coupling to any one investigation domain.

## User Stories

### Epic

As an embo user, I want the verification agent to show its work per
claim — method, evidence, ruled-out alternatives, and a data-calibrated
confidence — and to refuse to state a guess as a fact, so I can trust a
"proven" and act on the confidence.

### User Stories

1. **As a** user reading a verification result
   **I want** each load-bearing claim recorded as a proof table (env,
   domain, assumption, numbered methodology, evidence, differential
   assessment, conclusion, confidence 0–10)
   **So that** I can see how the conclusion was reached and re-run the
   methodology myself.

   **Acceptance Criteria**:
   - [ ] For each load-bearing claim, the agent emits all 8 fields; the
     methodology field names the actual command/source used and is
     numbered (one claim may carry several numbered methodologies).
   - [ ] The differential field states why the evidence is not explained
     by the competing alternatives, not only why it fits the conclusion.
   - [ ] The existing verdict (proven/unproven/contradicted) is retained
     as a one-line summary above each claim's proof-table block.

2. **As a** user who must not be misled by confident prose
   **I want** the agent to catch its own hedged claims and resolve them
   **So that** no guess is stated as a fact.

   **Acceptance Criteria**:
   - [ ] Before finalizing, the agent scans its own draft for hedge
     words on load-bearing claims and emits a one-line `Hedge-check:`
     declaration per such claim (`proven | unproven | needs-methodology`).
   - [ ] Each hedged load-bearing claim is either backed by a proof-table
     entry or downgraded to explicitly unproven with a stated confidence
     — never left as a bare confident assertion.

3. **As a** user who needs the confidence to mean something
   **I want** the 0–10 confidence tied to data availability and used to
   push for more methodology
   **So that** a low number drives further investigation, not a shrug.

   **Acceptance Criteria**:
   - [ ] Confidence is a 0–10 value defined against anchored bands tied
     to data availability (direct reproduced data → high; inference with
     no usable data → low).
   - [ ] When confidence is low, the record names the methodology that
     would raise it, OR proves (with evidence) that none is available
     without more access/research.

## Requirements

### Functional Requirements

1. **FR-1**: The `approach-validator` output gains a per-claim proof
   table with the 8 fields; the numbered-methodology field reuses the
   agent's existing prove/exercise steps.
   - **Priority**: High
   - **Rationale**: This is the core record that shows the work.
   - **Dependencies**: The agent's existing multi-source verification
     and read-only-exercise steps.

2. **FR-2**: The existing verdict value is kept as a one-line summary per
   claim, above its proof-table block (not replaced).
   - **Priority**: Medium
   - **Rationale**: Preserves the fast scan; the verdict is the proof
     table's lossy summary, the same investigation at lower resolution.

3. **FR-3**: A mandatory hedge-check step — the agent scans its own draft
   for hedge words on load-bearing claims and emits a one-line
   `Hedge-check:` declaration per such claim; each is then proven or
   downgraded.
   - **Priority**: High
   - **Rationale**: The anti-guessing forcing function; modeled on
     `Objection-check`. Contract-forced within the agent (no hook —
     subagent limitation).

4. **FR-4**: Confidence is a 0–10 value on anchored, data-availability
   bands, and a low value obliges naming the raising methodology or
   proving none is available.
   - **Priority**: High
   - **Rationale**: Makes confidence comparable and turns a low score
     into an instruction to investigate further, not a caveat.

5. **FR-5**: The mechanism is generic — the fields and hedge-check carry
   no assumption about the investigation domain.
   - **Priority**: Medium
   - **Rationale**: Reusable across any verification, not one domain.

### Non-Functional Requirements

1. **NFR-1**: Usability — the proof table stays readable; the verdict
   summary lets a user scan without reading every block.
2. **NFR-2**: Consistency — the change stays within the existing
   `approach-validator` agent contract; no new command, no new agent, no
   always-on main-loop checklist (avoids diluting the existing five).
3. **NFR-3**: Honesty — a claim with no usable data is marked low-
   confidence and unproven, never smoothed into a confident conclusion.

## Out of Scope

- A main-loop, hook-measured artifact for the general agent (rejected:
  a 6th always-on checklist would dilute the existing five; enforcement
  stays in the subagent contract).
- Changes to `examine-advisor` or `/embo:research:examine`.
- A new standalone investigation command.
- Mechanically measuring hedge-check emit-rate (subagents cannot run
  Stop/PostToolUse hooks — accepted limitation).
- Running any specific real-world investigation (e.g. the www/dev-www
  case that motivated the method); this ships the generic mechanism only.

## Success Metrics

Measured by review of `/embo:research:verify` runs before the feature is
called done (no telemetry in scope):

1. Every load-bearing claim in a verification result carries a complete
   proof-table record (8 fields), over a review of at least 3 runs.
2. In those runs, no load-bearing claim is stated as a fact while carrying
   a hedge word without a `Hedge-check:` resolution.
3. At least one run exercises a low-confidence claim and shows the
   record naming the raising methodology or proving none is available.

## References

### From Codebase (RLM / read)

- `plugin/agents/approach-validator.md` — Output and Process sections,
  the edit target.
- `plugin/agents/examine-advisor.md` — confirms the two agents are
  distinct (this feature does not touch it).

### From History (Claude-Mem)

- #21212, #21369, #21371 — verify command + approach-validator origin.
- Task 047 — `Objection-check` forced-artifact pattern (the model for
  the hedge-check).
- #33488 — PostToolUse/subagent hook limitation.

---

**Next Steps**:
1. Review and refine this PRD.
2. Run `/embo:tech-design` to create the technical design.
3. Run `/embo:tasks` to break it into tasks.
