# 049: Proof Table for the Verification Agent - Technical Design

**Status**: Draft
**PRD**: [2026-07-26-049-proof-table-prd.md](2026-07-26-049-proof-table-prd.md)
**Created**: 2026-07-27

## Overview

A prompt-contract edit to one file, `plugin/agents/approach-validator.md`.
No code, no new file, no hook, no main-loop checklist. Three coordinated
changes to the agent's instructions:

1. **Output section** — replace the single verdict table with a compact
   summary table (claim | verdict | confidence) followed by one 8-field
   proof-table block per load-bearing claim.
2. **Hedge-check step** — a mandatory pre-finalize step: the agent scans
   its own draft for hedge words on load-bearing claims and emits a
   one-line `Hedge-check:` declaration per such claim, then proves or
   downgrades each.
3. **Confidence scale** — a 0–10 value on four data-availability bands,
   with a forcing function: a low score obliges naming the methodology
   that would raise it, or proving none is available.

**Load-bearing design constraint (from user):** the proof table exists to
make a claim *independently repeatable*, not merely recorded. The
methodology field must therefore be a **reproducible command another
party can run to obtain the same evidence** — not a prose description of
what the agent did. Repeatability is the acceptance bar for the
methodology field; a methodology that cannot be re-run is treated as
absent (drops the claim's confidence).

## Current Architecture (RLM-verified)

- The edit target is the `## Output` section at
  `plugin/agents/approach-validator.md:133`: currently a verdict table
  (proven / unproven / contradicted), a load-bearing-claims list, and a
  "Then advise" block. — verified via: read of
  `plugin/agents/approach-validator.md:133-162`, 2026-07-27
- The Process section already has step 2 ("prove each against an
  independent source") and step 3 ("exercise un-proven executable paths
  once" — a read-only command). The numbered-methodology field reuses
  these; no new capability. — verified via: read of
  `plugin/agents/approach-validator.md:118-131`, 2026-07-27
- Subagents cannot run PostToolUse/Stop hooks, so the `Hedge-check:`
  artifact is contract-forced within the agent, not hook-measured. —
  verified via: claude-mem obs #33488, 2026-07-27
- The agent's Output header says "return this; edit nothing" — the agent
  is report-only; this design does not change that. — verified via:
  read of `plugin/agents/approach-validator.md:133`, 2026-07-27

## Past Decisions (Claude-Mem)

- Task 047 `Objection-check` — the forced one-line artifact pattern the
  `Hedge-check:` line copies (declare before proceeding). The difference:
  Objection-check is hook-measured in the main loop; Hedge-check is
  contract-only in the subagent (obs #33488).
- #21371 — approach-validator already returns structured constructive
  advice; the proof table extends that structure rather than replacing
  the agent's purpose.

## Proposed Design

### Edit 1 — Output section: summary table + proof-table blocks

Replace the current single verdict table with:

**(a) A summary table**, one row per load-bearing claim, for scanning:

```
| ID | Claim | Verdict | Confidence |
|----|-------|---------|------------|
```

- **ID** is a short claim identifier — `C1`, `C2`, … in the order claims
  appear. This is the single source of the claim ID used by the
  proof-table blocks and the Hedge-check line; nothing else defines it.
- Verdict keeps the existing three values: proven / unproven /
  contradicted.
- Confidence is the 0–10 value (Edit 3).

**(b) One proof-table block per claim**, below the summary, each headed
by its ID (`### C1 — <short claim label>`), with the eight fields:

1. **env** — the environment/context the claim is scoped to.
2. **domain** — the subject area of the claim.
3. **assumption** — the claim as initially stated (the guess).
4. **methodology NN** — the **reproducible command** used to get data,
   numbered. One claim may carry several (NN = 1, 2, …) when a single
   method is unreliable alone. MUST be re-runnable by another party; a
   non-reproducible "method" counts as no method and lowers confidence.
5. **evidence** — what the data actually showed (quote/verbatim extract,
   not a paraphrase).
6. **critical assessment (differential)** — why the evidence is NOT
   explained by the competing alternatives, not only why it fits.
7. **conclusion** — what the evidence supports.
8. **confidence (0–10)** — per the bands in Edit 3.

The existing "Then advise" block is kept, unchanged, after the blocks.

### Edit 2 — Hedge-check step (new, before Output)

Add a Process step (after the current step 5, before Output):

> **6. Hedge-check (a revision pass over your drafted proof table,
> before you emit it as final Output).** After you have drafted the
> proof-table blocks internally but before emitting them, scan that
> draft for hedge words on any load-bearing claim. For each load-bearing
> claim carrying a hedge, emit one line:
> `Hedge-check: <ID> — <proven | unproven | needs-methodology>`, where
> `<ID>` is the claim's `C1`/`C2`/… identifier from the summary table.
> Then resolve every such claim: a `proven` claim must have a
> proof-table block with reproducible methodology and evidence; an
> `unproven` claim is stated as unproven with its confidence; a
> `needs-methodology` claim names the method that would settle it (Edit
> 3 forcing function). A hedged load-bearing claim may NEVER be emitted
> as a fact without one of these resolutions.

**Hedge-word list (fixed core + generalization):** should be, presumably,
precisely, likely, typically, I believe, probably, seems, appears, ought
to, in all likelihood, my sense is — **and similar epistemic softeners**.
The "and similar" clause obliges the agent to generalize beyond the
literal list.

**Load-bearing test** (which claims the hedge-check applies to): a claim
is load-bearing if, were it false, the approach breaks (same definition
already in Process step 1). A hedge on a non-load-bearing aside does not
require a proof-table block.

### Edit 3 — Confidence: four data-availability bands + forcing function

Confidence is a 0–10 integer on these bands:

- **9–10** — direct authoritative data obtained and reproduced (the
  methodology was run and returned the confirming evidence).
- **6–8** — strong indirect evidence, or a single authoritative source
  not independently reproduced.
- **3–5** — partial evidence, or a single source of questionable
  reliability.
- **0–2** — no usable data; conclusion rests mostly on inference.

**Forcing function.** The threshold is ≤5, which covers bands 0–2 and
3–5; bands 6–8 and 9–10 are exempt. When a claim's confidence is ≤5, the
proof-table block MUST additionally state either:
- the specific methodology (command/source/access) that would raise it,
  and why it was not available this run; OR
- a proof (with its own evidence) that no such methodology exists without
  more access/research.

A low confidence is therefore an instruction to find another methodology
or to demonstrate none is available — never a bare caveat.

### Data Models / API Design

None — prompt text. The "8-field block" and "summary table" are output
format specifications, not data structures.

### Integration Points

- `/embo:research:verify` command: unchanged — it spawns the agent and
  relays its output. The richer output flows through with no command
  change.
- The agent's report-only constraint ("edit nothing"): unchanged.
- `examine-advisor` / `/embo:research:examine`: untouched (out of scope).

### Error Handling

The failure mode is a claim with no reproducible methodology and no data.
Handled by the confidence bands: it lands at 0–2, is marked unproven, and
the forcing function requires stating what would raise it. No claim is
smoothed into a false "proven."

### Testing Strategy

The change is agent-instruction text, verified by (a) reading the shipped
file for the three edits and their internal consistency, and (b) a live
`/embo:research:verify` run whose output shows the summary table, the
per-claim blocks, a `Hedge-check:` line where a hedge occurs, and a
confidence with the forcing function on a low score.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1: 8-field proof table per claim; methodology reproducible | `code-only` + `manual-run-claude` | integration | Output section defines all 8 fields with the reproducibility constraint (code); a live run emits a block whose methodology is a re-runnable command (runtime) |
| FR-2: verdict kept as one-line summary above blocks | `code-only` | — | Output section shows the summary table + blocks structure |
| FR-3: mandatory Hedge-check step; hedge list + generalization | `code-only` + `manual-run-claude` | integration | the step and hedge list are present (code); a live run on a claim the agent would hedge shows a `Hedge-check:` line and a resolution (runtime) |
| FR-4: 0–10 four bands + low-confidence forcing function | `code-only` + `manual-run-claude` | integration | the bands and forcing function are defined (code); a live run with a low-confidence claim names the raising methodology (runtime) |
| FR-5: generic, no domain coupling | `code-only` | — | no www/dev-www or other domain-specific wording in the added text |

## Trade-offs

**Considered — one wide 8-column table.** Rejected: the methodology,
evidence, and differential fields are multi-line prose; an 8-column row
is unreadable in a terminal. The summary-table-plus-blocks split keeps
the scan fast and the detail readable.

**Considered — replacing the verdict entirely with the proof table.**
Rejected per the user: the verdict is a useful one-line scan; keep it as
the proof table's summary (same investigation, two resolutions).

**Considered — main-loop hook enforcement of Hedge-check (like
Objection-check).** Rejected: a 6th always-on checklist dilutes the
existing five (WITHSTAND-CRITICISM, CLEAR-OPTIONS, RESTATE-CORRECTION,
AVOID-APPROVAL, DELEGATE — verified via `grep -c "<!-- CHECKLIST:"
plugin/commands/start.md` → 5, 2026-07-26). Enforcement stays in the
subagent contract; accepted as weaker (contract-forced, not
hook-measured).

## Implementation Constraints

- The agent stays report-only ("edit nothing"); no change to its tool
  use or spawn contract.
- No new always-on checklist in `start.md` (dilution constraint above).
- Methodology field must be reproducible — this is the load-bearing bar,
  not a nicety.

## Files to Create/Modify

**Create**: none.

**Modify**:
- `plugin/agents/approach-validator.md` — Process (add the Hedge-check
  step after step 5); Output section at :133 (replace the single verdict
  table with the summary table + 8-field blocks; add the confidence
  bands and forcing function).

No `plugin.json` bump is strictly required for an agent-only change if
agents are not version-cache-keyed the way commands are; **[assumption,
verify at impl]** — resolve by checking how the cache loads agents
(e.g. inspect `~/.claude/plugins/cache/embo/embo/<version>/agents/` for
this agent, as commands were confirmed cache-keyed this session). If
agents are cache-keyed, add a patch bump in the same change. Cheap
fallback: bump regardless — a spurious bump is harmless.

## Dependencies

None — no libraries, no modules. The methodology field relies on the
agent's existing Bash/Context7/NotebookLM tools (already in its toolset).

## Security Considerations

None new — the agent stays read-only and report-only; reproducible
methodologies are read-only commands (Process step 3 already forbids
destructive/stateful commands).

## Performance Considerations

Output grows (one block per claim), but verify runs have few load-bearing
claims; negligible. No extra round-trips.

## Rollback Plan

Revert the single edit to `plugin/agents/approach-validator.md` (and the
version bump if added). No state, clean revert.

## References

### Code (RLM):
- `plugin/agents/approach-validator.md:118-162` — Process steps 2–3 and
  Output section, the edit targets.

### History (Claude-Mem):
- Task 047 — `Objection-check` forced-artifact pattern.
- #21371 — approach-validator's structured-advice output.
- #33488 — subagent hook limitation.

---

**Next Steps**:
1. Review and approve design.
2. Run `/embo:tasks` for task breakdown.
