# 046 Hard Harness — reconciled examine findings

**Date:** 2026-07-23 · **Method:** `/embo:research:examine` — internal
pass (codebase/consistency) + two research passes + a direct 5-notebook
NotebookLM cross-query (run from main context after the subagent could
not resolve the NotebookLM MCP tools).

**Source-availability caveat:** the first research subagent ran without
NotebookLM tools and advised from domain knowledge (flagged
`EXTERNAL-CHECK-SKIPPED`). The prior-art check was then completed for
real by a direct `cross_notebook_query` over five notebooks
(all 5 succeeded) — findings below are corroborated by that query.

## Verdict

Mechanism **types** (M1 state-gate for CLASS 2, M3 trigger-substitute
for CLASS 1, M9 capture) are **sound and are established prior art**, and
buildable on existing embo hook machinery. The PRD originally **asserted
genericity more strongly than its FR-level schemas supported** —
validated only on the easiest instance per class. All fixes below are
now folded into the PRD revision.

## HIGH (flagged by all reconstructions)

1. **Genericity was permitted to be faked.** OQ-5's "v1 may hand-wire the
   2 example rules" default contradicted the Design mandate. → RESOLVED:
   OQ-5 withdrawn; FR-config now requires runtime config read;
   FR-genericity-test added as the held-out falsifier.
2. **Schemas validated only on the easy member per class.** Auth =
   string-matchable stderr; jq/yq = isomorphic substitute. → RESOLVED:
   scope-honesty notes added (M1 = observable-signal subset; M3 =
   near-isomorphic substitutions only); FR-first-rules now ships a
   structurally different 2nd rule per class.

## MEDIUM

3. **Detector narrower than gate (cross-tool circumvention).** FR-1 was
   `Bash`-only while FR-2 gate is `*`; a non-Bash tool's failure would go
   undetected. → RESOLVED: FR-1 matcher widened to `*`.
4. **NeMo canonical-form brittleness of trigger matching.** → RESOLVED:
   FR-5 states regex/normalize suffices because Bash grammar is a
   constrained domain (unlike NL); conflict/precedence added to FR-config.
5. **M9 mis-framed as enforcement.** → RESOLVED: reclassified as
   instrumentation; enforcement set is M1+M3; evidence-pack rationale +
   review cadence added.
6. **Multi-hook precedence race unverified.** → RESOLVED as VQ-1 +
   FR-9 both-hooks-together fixture requirement.
7. **M1 matcher-`*` could deadlock its own clearing.** → RESOLVED: FR-2
   exempts read-only tools + the clear path.
8. **Flap/re-trip risk on a flaky detector.** → RESOLVED: FR-3 flap guard.
9. **FR-4/FR-5 file-location split.** → RESOLVED: FR-config is the single
   normative location; detectors keyed by rule id.

## LOW / strengthenings (folded in)

- Hooks **sidestep** instruction-hierarchy collapse (act at the tool
  boundary) — added as Design Principle 9; strongest argument for gates.
- HiL-Bench "Self-Assessment" failure added as independent (behavioral)
  confirmation that recall ≠ action.
- Missing prior art named as considered-and-scoped: NeMo canonical forms,
  constrained decoding, factory/phantom tools, dual-LLM (CaMeL),
  RLVR self-halting (Ask-F1).

## Prior-art confirmation of the four core claims (NotebookLM, 5/5)

1. Salience-at-decision-point beats upstream — confirmed across 4
   notebooks (lost-in-the-middle, recency weaponization, lazy-loading,
   JIT context flooding).
2. CLASS 1 vs CLASS 2 need different mechanisms — every production
   example splits along this line (tool-contract redesign vs state-gate).
3. Infinite surface forms beaten only by removing the action space —
   best-supported claim (Zup cross-tool circumvention, CaMeL,
   "Personas are hints; tool access is enforcement").
4. Prompt-only capped, determinism needs an external gate — confirmed
   from a second literature (HiL-Bench) beyond the PRD's own citations.

## Process finding (for /embo:improve)

The `embo:examine-advisor` subagent **could not resolve the
`mcp__notebooklm-mcp__*` tools** even though its agent definition lists
them and the tools worked in the main context. This defeated the
research pass twice. The prior-art query had to be run directly from the
main context. This is a subagent-MCP-tool-resolution gap worth a task
seed — the examine command's research pass is unreliable until fixed.
