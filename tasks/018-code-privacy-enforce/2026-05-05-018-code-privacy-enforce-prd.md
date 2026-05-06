# 018-code-privacy-enforce: Sanitization pass in workflow commands - PRD

**Status**: Draft
**Created**: 2026-05-05
**Author**: dpovesma + Claude

---

## Problem

Workflow command files (`/dev:prd`, `/dev:tech-design`, `/dev:impl`)
already enforce evidence discipline (Step 5.5: every factual claim
must be sourced or tagged as an assumption). Sourcing a claim
verifies it is *true*. It does not verify it is *shareable*.

A correctly verified claim can still leak private data: real
hostnames, customer IPs, internal service names, account/tenant IDs,
ticket numbers, or paths from a specific deployment. PRDs,
tech-designs, and impl evidence notes get committed to public
repositories and shared upstream. There is currently no checkpoint
that enforces sanitization before save.

## Goal

Add a "Sanitization Pass" checkpoint to each workflow command that
produces persistent docs, with the same level of explicitness as
the existing reality-check pass.

## Requirements

**FR-1**: `/dev:prd` and `/dev:tech-design` MUST gain a Step 5.6
"Sanitization Pass (MANDATORY)" after the existing Step 5.5
(reality-check) and before save.

**FR-2**: `/dev:impl` MUST gain an "Evidence Note Sanitization"
subsection adjacent to the evidence-note format definition. Evidence
notes are written inline during work, not at a final save gate, so
sanitization applies at write time (no working-state exception).

**FR-3**: All three additions MUST defer to a project-defined
"Documentation Sanitization" rule in CLAUDE.md when present. When
absent, they apply the default policy (replace private values with
`<descriptor>` placeholders, or RFC 5737 / RFC 2606 for IPs/domains).

**FR-4**: The PRD/tech-design Sanitization Pass MUST allow a
working-state exception: drafts may carry private values to keep
reasoning concrete; sanitization is required by the time
`Status: Complete` is set. The `/dev:impl` evidence-note version
MUST NOT have this exception.

**FR-5**: The Sanitization Pass MUST be described as orthogonal to
the reality-check pass: 5.5 verifies claims are true; 5.6 verifies
they're shareable. Both must hold.

**FR-6**: Changes to `prd.md`, `tech-design.md`, and `impl.md` MUST
be minimal — terse imperative bullets, no prose. Do not restate
context the surrounding sections already establish. The full rule
text in the brief is a maximum, not a target; trim aggressively.
Hard line budgets (excluding heading line):
- `prd.md` Step 5.6: <= 6 lines
- `tech-design.md` Step 5.6: <= 4 lines (refer to prd.md, do not
  restate the rule)
- `impl.md` Evidence Note Sanitization: <= 6 lines including one
  example pair
If a budget cannot be met without losing essential meaning, flag
the overrun in the implementation evidence note. Bloat is the
failure mode this PRD exists to prevent.

## Non-Goals

- Adding a canonical "Documentation Sanitization" rule to this
  repo's CLAUDE.md. (Per user instruction: command files reference
  CLAUDE.md if present, but this repo does not need its own rule.)
- A commit-time hook or CI check for unsanitized examples in the
  command-prompt text itself. (Mentioned in the brief as optional
  for the maintainer's repo, not in scope here.)
- Tooling to detect private data automatically. The pass is a
  human/LLM read-through, not an automated scanner.

## Insertion points (located)

- `.claude/commands/dev/prd.md`: insert between line 263 (end of
  Step 5.5) and line 265 (start of Step 6). New heading:
  `### Step 5.6: Sanitization Pass (MANDATORY)`.
- `.claude/commands/dev/tech-design.md`: insert before line 342
  (start of Step 7: Save to File). New heading:
  `### Step 6.5: Sanitization Pass (MANDATORY)`. Step number is
  6.5 (not 5.6 as in the brief) because tech-design.md's existing
  numbering reaches Step 6 (Synthesize) and Step 7 (Save), with no
  Step 5.5/5.6 pair to mirror.
- `.claude/commands/dev/impl.md`: insert after line 155 (end of
  Evidence note format examples) and before line 156
  (`<!-- RULE:ONE-SUBTASK -->`). New heading:
  `### Evidence Note Sanitization` (no step number — impl.md uses
  rule/protocol structure, not numbered planning steps).

## Acceptance Criteria

- [ ] `/dev:prd` contains a Step 5.6 section after Step 5.5 with
  the exact wording from the brief, before the Step 6 save
- [ ] `/dev:tech-design` contains a Step 5.6 section after the
  reality-check / verify-PRD-facts pass, before save
- [ ] `/dev:impl` contains an "Evidence Note Sanitization"
  subsection near the evidence-note format definition with
  positive/negative examples
- [ ] All three additions explicitly mention deferring to
  CLAUDE.md "Documentation Sanitization" when defined
- [ ] PRD/tech-design version states the working-state exception
  (drafts may carry private values; sanitize before Status: Complete)
- [ ] /dev:impl version explicitly does NOT carry the working-state
  exception (sanitize at write time)
- [ ] Each addition states orthogonality to Step 5.5

## References

- `/dev:prd` Step 5.5 (existing) - the reality-check pass model
  this new step mirrors
- `/dev:tech-design` Step 1.5 (existing) - verify-inherited-PRD-facts
  pass (separate from but conceptually adjacent to 5.6)
- claude-mem corrections in commit `4e1fd8d` introduced Step 5.5;
  this PRD continues that line by adding the shareability axis

## Out of scope (future work)

- Build a CI/grep check for unsanitized example text inside the
  command files themselves (`prd.md`, `tech-design.md`, `impl.md`).
  Useful for the maintainer's repo to catch drift in templates.
