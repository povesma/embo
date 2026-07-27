# 048: Wider-Context Question in the PRD Command - Technical Design

**Status**: Draft
**PRD**: [2026-07-25-048-wider-context-prd.md](2026-07-25-048-wider-context-prd.md)
**Created**: 2026-07-25

## Overview

The change is entirely a prompt-text edit to one shipped command file,
`plugin/commands/prd.md`. No code, no new file, no new tool. Two edits:

1. **Step 4** gains an asked-first wider-context question (its own
   `AskUserQuestion` call preceding the existing clarifying-questions
   call), with an inline approved-framing list, an inline blocklist, a
   redundancy-detection rule, a JIRA-parent branch, and a one-follow-up
   rule.
2. **Step 5's PRD template** gains a `## Wider Context / Higher Goal`
   section at the very top of the generated document (before
   `## Context`).

Because the "rule" here is instructions the model follows at PRD time —
not a hook — the design's job is to make those instructions concrete and
checkable, per the PRD's FR-2 verifiability requirement.

## Current Architecture (RLM-verified)

- Step 4 ("Ask Clarifying Questions (MANDATORY)") spans
  `plugin/commands/prd.md:97-124`; it instructs a single
  `AskUserQuestion` call with a menu of common areas. — verified via:
  read of `plugin/commands/prd.md:97-124`, 2026-07-25
- The business-goal text is the second clause of a single two-line
  bullet: line 103 is `- **Problem/Goal:** "What problem does this
  feature solve for the user?" or` and line 104 is `  "What is the main
  business goal we want to achieve?"`. FR-1 removes only the ` or "What
  is the main business goal we want to achieve?"` clause, leaving the
  bullet as one question ending at `for the user?"` — a whole-line-104
  deletion would leave a dangling `or`. — verified via: read of
  `plugin/commands/prd.md:103-104`, 2026-07-25
- The Step 5 generated-PRD template begins at `plugin/commands/prd.md:130`
  (fenced block) with the title block, then `## Context` at line 140.
  The new section slots between the `---` (line 138) and `## Context`
  (line 140). — verified via: read of `plugin/commands/prd.md:130-172`,
  2026-07-25

## Past Decisions (Claude-Mem)

- Observation #25066 (2026-07-02): the comprehensive PRD template
  structure was deliberately restored after being condensed — implies the
  template's section set is intentional, so the new section is an
  addition, not a restructuring of existing sections.
- Observation #29239 (2026-07-15): a correction required plain,
  jargon-free PRD wording — reinforces the FR-2 blocklist approach
  (ban blunt/jargon phrasings, prefer plain framings).

## Proposed Design

### Edit 1 — Step 4: the asked-first wider-context question

Inserted at the top of Step 4 (before the existing "common areas to
explore" menu), as a distinct sub-step that runs its own
`AskUserQuestion` call BEFORE the call carrying the other clarifying
questions. The command text specifies:

**Trigger / skip logic (FR-4 + FR-3), in evaluation order:**

1. **Redundancy check (runs first).** Treat wider context as already
   known only if the user's initial prompt or an earlier answer states a
   motivation *distinct from the feature's mechanism* — signalled by a
   "so that" / "because" / "in order to" / "we need this to…" clause, or
   an explicit reference to a parent goal or ticket. A bare restatement
   of the feature's name or action does NOT count. If already known:
   skip the question, restate the understood context in one line for
   confirmation, proceed.
2. **JIRA-parent branch (FR-3).** If not already known AND the task text
   contains a JIRA-style ID (pattern: uppercase project key, hyphen,
   digits — e.g. `AS-1234`): before asking, suggest the user consult the
   ticket's parent / epic / linked higher-level tickets for the wider
   context. If a parent yields the context, treat as known. Otherwise —
   the ticket is a leaf (no parent), OR a parent exists but does not
   yield usable context (the user has no access to it, or the parent
   itself states no "why") — fall through to step 3 and ask normally.
   "Suggest the parent" never becomes "block on the parent."
3. **Ask (FR-1 + FR-2).** Ask the wider-context question in its own
   preceding `AskUserQuestion` call, wording drawn from the approved list
   below.

**One-follow-up rule (FR-5).** If the answer only restates the feature
(no distinct motivation per the same signal test as step 1), ask exactly
ONE probing follow-up, then accept whatever is given. Never block:
"skip" / "none" is always accepted and recorded as "none given".

**Approved framing list (FR-2 positive test)** — the emitted question
MUST use one of these framings (verbatim or a close paraphrase that
keeps the framing):

- "What is the result of this feature used for?"
- "What is the motivation for this task?"
- "What wider context does this fit into?"
- "Once this is built, what does it enable?"
- "What larger goal does this support?" (note: "larger goal", not
  "higher goal" — see blocklist)

**Blocklist (FR-2 negative test)** — the emitted question MUST NOT
contain any of these:

- "higher goal" (blunt; the PRD's named bad phrasing)
- "why do you even want" / "why do you want this" (interrogative,
  accusatory)
- "your request is incomplete" / "this is under-specified" / any wording
  implying the user's description is deficient

A reviewer verifies a shipped phrasing by checking it matches a positive
framing and contains no blocklist phrase.

**Header-vs-question disambiguation.** The generated-PRD section (Edit 2)
is titled "Wider Context / Higher Goal" — that phrase is the *document
header only*. The blocklist bans "higher goal" in the *asked question*.
Step 4's text must state this explicitly so the model does not reuse the
section title as the spoken question: the header names the section; the
question uses an approved framing.

### Edit 2 — Step 5 template: the new section

Insert into the fenced template block, between the `---` separator and
`## Context`:

```markdown
## Wider Context / Higher Goal

{The motivation / parent goal / what-the-result-is-used-for captured in
Step 4. If the user gave nothing: "None given — feature described in
isolation." If drawn from a JIRA parent: cite the parent ticket.}
```

The Step 4 text instructs: whatever is captured (or "none given") is
written into this section. This is what carries the context past the PRD
conversation into tech-design and tasks.

### Data Models / API Design

None — this is prompt text.

### Integration Points

- Step 4's existing `AskUserQuestion` menu call: unchanged except the
  business-goal line at :104 is removed (superseded by the dedicated
  question).
- Step 5's template: one section added; all other sections unchanged.
- The reality-check (5.5) and sanitization (5.6) passes: unchanged — the
  new section carries user-supplied prose, subject to the same passes.

### Error Handling

The only "error" is a user with no wider context. Handled by the
never-block rule: record "none given" and proceed. No failure path.

### Testing Strategy

The change is instruction text executed by the model, so verification is
manual review of command runs plus a static check that the shipped lists
and logic are present and internally consistent.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1: asked-first, own preceding call; replaces :104 clause | `code-only` + `manual-run-claude` | integration | prd.md Step 4 shows a distinct preceding AskUserQuestion sub-step and the business-goal clause is gone (code); a run's transcript shows TWO distinct AskUserQuestion calls, the wider-context one first (runtime — guards against the model collapsing them into one batched call) |
| FR-2: approved list + blocklist present and applied | `code-only` | — | both lists present inline in Step 4; a reviewer can match/grep an emitted phrasing against them |
| FR-3: JIRA-parent suggestion on ID pattern; leaf fallback | `manual-run-claude` | integration | run with an `AS-1234`-style task → command suggests parent; run with a leaf → falls back to the question |
| FR-4: redundancy skip with distinct-motivation rule; precedence over FR-5 | `manual-run-claude` | integration | run with a prompt containing a "so that" motivation → question skipped, context restated; no follow-up fires |
| FR-5: one follow-up on shallow answer, then accept; never block | `manual-run-claude` | integration | shallow answer → exactly one follow-up; "skip" → recorded "none given", PRD proceeds |
| FR-6: generated PRD has the top Wider Context section | `code-only` + `manual-run-claude` | — | template shows the section before `## Context`; a generated PRD contains it populated; separately, a run with no wider context shows "None given — feature described in isolation." |

## Trade-offs

**Considered Approaches**:

1. **Separate reference file for the framing lists.**
   - Pros: cleaner separation of data from instructions.
   - Cons: adds a file and an indirection; the model must be told to read
     it; inconsistent with how the rest of the command specifies behavior
     inline.
   - Rejected: the lists are short and read once at PRD time; inline is
     simpler and greppable (KISS).

2. **Inline lists in Step 4 (Recommended).**
   - Pros: zero new files; self-contained; a reviewer greps one file;
     matches the command's existing style.
   - Cons: Step 4 grows longer.
   - Chosen: simplest form that meets FR-2's verifiability requirement.

**Also considered — asking within the same batched call** (one
`AskUserQuestion` with the wider-context question as the first of up to 4
questions) instead of a separate preceding call. Rejected: the PRD's
"anchor the downstream answers" rationale requires the user to answer the
wider-context question *before seeing* the others, which a batched call
does not guarantee.

## Implementation Constraints

- `CLAUDE.md` is not the home for this behavior; the rule lives in the
  shipped command file (`plugin/commands/prd.md`), per the
  not-a-deliverable constraint.
- The change must not disturb the existing "All clear, proceed" escape or
  the reality-check / sanitization passes.

## Files to Create/Modify

**Create**: none.

**Modify**:
- `plugin/commands/prd.md` — Step 4 (insert asked-first question sub-step
  with the two lists + logic; remove ONLY the ` or "What is the main
  business goal we want to achieve?"` clause of the :103-104 bullet — a
  sub-string removal, not a line deletion, else a dangling `or` ships);
  Step 5 template (insert the top section).
- `plugin/.claude-plugin/plugin.json` — patch version bump so a live test
  picks up the change from the version-keyed plugin cache.

## Dependencies

None — no external libraries, no internal modules. Uses the existing
`AskUserQuestion` tool.

## Security Considerations

None — no data handling, no new inputs beyond user prose already handled
by the sanitization pass.

## Performance Considerations

The extra preceding `AskUserQuestion` call adds one user round-trip when
the wider context is not already known; the redundancy check avoids it
when it is. Negligible.

## Rollback Plan

Revert the single commit to `plugin/commands/prd.md` and the version bump.
No state, no migration, no data — clean revert.

## References

### Code (RLM):
- `plugin/commands/prd.md:97-124` — Step 4, edit target.
- `plugin/commands/prd.md:104` — business-goal line to remove.
- `plugin/commands/prd.md:130-172` — Step 5 template, section insertion
  point.

### History (Claude-Mem):
- #25066 — template structure is intentional (add, don't restructure).
- #29239 — plain-wording correction (supports the blocklist).

---

**Next Steps**:
1. Review and approve design.
2. Run `/embo:tasks` for task breakdown.
