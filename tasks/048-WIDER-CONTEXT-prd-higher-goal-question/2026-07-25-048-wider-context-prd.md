# 048: Wider-Context Question in the PRD Command - PRD

**Status**: Draft
**Created**: 2026-07-25
**Task**: 048-WIDER-CONTEXT-prd-higher-goal-question
**Author**: Claude (via embo dev workflow)

---

## Wider Context / Higher Goal

*(This section dogfoods the feature the PRD proposes.)*

The higher goal is embo's central promise: a spec-driven workflow whose
output matches what was actually intended. A PRD that captures only the
mechanism, not the motivation, breaks that promise at the first step —
every downstream doc and every line of code inherits the gap. This
feature closes it at the source, and it is the first instance of embo
holding *itself* to the context-quality standard it will ask of users:
if the PRD command should demand a "why," the PRD for that command must
carry one too.

## Context

Users often describe a feature as an isolated capability — sometimes
with no stated connection to other features, and often with no
connection to the higher goal the feature ultimately serves. A request
like "we want to know the free disk size" is descriptive but tells the
implementer nothing about *why*: to let the user install more programs,
to warn before a backup fails, to decide whether to offer a larger disk.
Each of those higher goals would change what gets built. The claim under
this PRD is that surfacing that wider context during requirements
gathering produces a better implementation outcome.

### Research finding (verified before this PRD)

Checked via `/embo:research:verify`, 2026-07-24: the *mechanism* is
PROVEN and the *effect* is PLAUSIBLE with a large effect size for
AI-assisted development (agents drop from ~90% to 4–24% success on
ambiguous specs; structured context cut drift up to 86%). Sourced papers:
ACE (Stanford/SambaNova 2025), HiL-Bench (Elfeki 2026, arXiv:2604.09408),
HULA (Takerngsaksiri 2024, arXiv:2411.12924), Tang 2008. The classical
human-team RE literature was not retrievable and is not load-bearing —
embo runs alongside AI agents, the domain the confirmed evidence covers.
The feature is justified.

### Current State (observed)

- The PRD command's clarifying-questions step is `Step 4` and is marked
  MANDATORY; it uses the AskUserQuestion tool. — verified via:
  `grep "Step 4" plugin/commands/prd.md` → line 97, 2026-07-25
- The command already asks "What is the main business goal we want to
  achieve?" as an equal first-listed alternative to the problem question
  (not a buried sub-bullet). This partially overlaps the wider-context
  intent, but it is one framing among a menu, is never asked first as a
  distinct anchoring question, and does not vary its wording, suggest a
  JIRA parent, follow up on a shallow answer, or get recorded as its own
  PRD section. — verified via: read of `plugin/commands/prd.md:103-104`,
  2026-07-25
- The generated PRD template has a `## Context` section and a `## Goals`
  section (Primary / Secondary), but no section that records the wider
  context / motivation as inherited context for downstream docs. —
  verified via: read of `plugin/commands/prd.md:130-160`, 2026-07-25

### Past Similar Features (from claude-mem)

- Task 001 (PRD-QUESTIONS-ask-questions-before-docs) established the
  mandatory-clarifying-questions step this PRD extends.
- Observation #29239 (2026-07-15): a prior correction required the PRD
  command to produce jargon-free, plainly-worded output — the
  non-offensive framing requirement here is consistent with that.

## Problem Statement

**Who**: An embo user running `/embo:prd` to plan a feature.
**What**: The user describes the feature in isolation, giving the
implementer (a human or an AI coding agent) no wider context — no
motivation, no parent goal, no statement of what the result is used for.
**Why**: Without that context the implementer cannot make trade-off or
scope decisions and must guess; the verified research shows this
degrades outcomes with a large effect size.
**When**: At the start of every PRD, before requirements are written —
the point where the wider context, if captured, would frame every
downstream answer, the tech-design, and the task breakdown.

## Goals

### Primary Goal

The PRD command elicits the feature's wider context (motivation / parent
goal / what the result is used for) early, in a non-offensive way, and
records it in the generated PRD so it propagates to tech-design and
tasks.

### Secondary Goals

- The question does not fire redundantly when the wider context is
  already established (prior conversation, or a JIRA parent/epic that
  can be consulted instead).
- The framing varies and never reads as an interrogation or an accusation
  that the user's request is incomplete.
- A user with genuinely no wider context can proceed without being
  blocked.

## User Stories

### Epic

As an embo user, I want the PRD command to draw out the wider context
behind my feature before writing requirements, so that the resulting
PRD, tech-design, and code reflect what the feature is actually for.

### User Stories

1. **As a** user starting a PRD from a bare feature description
   **I want** to be asked, in a non-blunt way, what the feature is
   ultimately for
   **So that** the PRD captures the motivation, not just the mechanism.

   **Acceptance Criteria**:
   - [ ] When no wider context is present, the command asks for it in its
     own `AskUserQuestion` call that precedes the call carrying the other
     clarifying questions (so it is answered first).
   - [ ] The emitted question's wording is drawn from the pre-approved
     framing list (FR-2 positive test) and contains no phrase on the
     blocklist (FR-2 negative test).
   - [ ] The captured answer appears in the generated PRD as a dedicated
     "Wider Context / Higher Goal" section.

2. **As a** user whose task is a JIRA ticket with a parent/epic
   **I want** the command to point me at the parent ticket rather than
   ask me to restate its goal
   **So that** I am not asked to hand-type context that already exists
   upstream.

   **Acceptance Criteria**:
   - [ ] When the task references a JIRA ID, the command suggests
     consulting the parent/epic/linked higher-level tickets for the
     wider context instead of asking the user to supply it from memory.
   - [ ] When the ticket is a leaf (no parent/epic), the command falls
     back to the normal wider-context question rather than skipping it.

3. **As a** user who gives a shallow, feature-restating answer
   **I want** at most one gentle follow-up
   **So that** more context is drawn out when it's easy, without the
   command nagging.

   **Acceptance Criteria**:
   - [ ] If the first answer only restates the feature, the command asks
     exactly one probing follow-up (e.g. "and what does that enable?"),
     then accepts whatever is given.
   - [ ] The command never blocks PRD generation on a wider-context
     answer; "skip" / "none" is always accepted.

4. **As a** user who already stated the wider context earlier in the
   session
   **I want** the command not to ask again
   **So that** the step stays out of the way when it adds nothing.

   **Acceptance Criteria**:
   - [ ] When the wider context is already established in the
     conversation, the command does not re-ask; it restates the
     understood context and proceeds.

## Requirements

### Functional Requirements

1. **FR-1**: The clarifying-questions step elicits the feature's wider
   context first when it is not already known. This replaces the existing
   "What is the main business goal we want to achieve?" alternative
   (prd.md:104): the wider-context question is its own, asked-first
   question with varied framing (FR-2), not one option in the
   problem/goal menu. "Asked first" means a **separate preceding
   `AskUserQuestion` call**, so the user answers it before seeing the
   remaining clarifying questions — that is what makes it anchor the rest.
   - **Priority**: High
   - **Rationale**: The research shows goal context should anchor the
     downstream answers; asking it in its own preceding call is what makes
     it anchor.
   - **Dependencies**: The existing MANDATORY Step 4 / AskUserQuestion
     flow.

2. **FR-2**: The question uses non-offensive framing, made *verifiable*
   (not a subjective judgment): tech-design ships a fixed positive list
   of approved framings (e.g. "what is the result used for?", "the
   motivation for this task") the emitted question must draw from, and a
   negative blocklist (e.g. "higher goal", any wording implying the
   user's request is deficient) it must avoid. A reviewer checks the
   emitted string against both lists.
   - **Priority**: High
   - **Rationale**: The user's explicit constraint — the question must not
     read as "your request is deficient" — made checkable.

3. **FR-3**: Context-source awareness — when the task references a JIRA
   ticket, the command suggests consulting parent/epic/linked
   higher-level tickets rather than asking the user to supply the context
   unaided. **Leaf-ticket fallback:** if there is no parent/epic (a leaf
   ticket, the common case), the command falls back to FR-1's normal
   wider-context question — it never skips both.
   - **Priority**: Medium
   - **Rationale**: Avoids asking the user to restate context that already
     exists upstream, without leaving leaf tickets (most tickets) with no
     question at all.

4. **FR-4**: Redundancy suppression — the command skips the question when
   the wider context is already present, and instead restates its
   understanding for confirmation. **Detection rule:** wider context
   counts as "already known" only if the user's initial prompt or an
   earlier answer states a motivation *distinct from the feature's own
   mechanism* — a "so that" / "because" / "in order to" clause, or an
   explicit reference to a parent goal or ticket. A bare restatement of
   the feature's name or action does NOT count. **Precedence:** the
   redundancy check runs before the shallow-answer follow-up (FR-5); if
   both could apply to the same input, redundancy-skip wins (do not ask,
   then immediately follow up).
   - **Priority**: Medium
   - **Rationale**: Keeps the step from firing when it adds nothing, and
     removes the collision between "skip because known" and "follow up
     because shallow."

5. **FR-5**: One gentle follow-up on a shallow answer, then accept; never
   block PRD generation on this answer.
   - **Priority**: Medium
   - **Rationale**: Extracts more context when cheap, respects the
     "non-offensive" and "not blocking" constraints.

6. **FR-6**: The generated PRD gains a "Wider Context / Higher Goal"
   section that records the captured context, positioned so tech-design
   and tasks inherit it.
   - **Priority**: High
   - **Rationale**: Persisting the context is what carries the benefit
     past the PRD conversation into the rest of the workflow.

### Non-Functional Requirements

1. **NFR-1**: Usability — the question must never read as an accusation
   that the user's request is incomplete; tone is collaborative.
2. **NFR-2**: Consistency — the change stays within the existing Step 4
   AskUserQuestion mechanism and the existing PRD template structure; no
   new command and no new tool.
3. **NFR-3**: Non-regression — the existing "All clear, proceed" escape
   and the other clarifying questions continue to work unchanged.

### Technical Constraints

- Must integrate with: the existing MANDATORY clarifying-questions step
  in `plugin/commands/prd.md` (Step 4) and the PRD template in Step 5.
- Should follow patterns: AskUserQuestion usage already established in
  the command; the plain-English / non-jargon writing rule (obs #29239).
- Cannot change: `CLAUDE.md` is not the home for this behavior — the rule
  lives in the shipped command file (`plugin/commands/`), per the
  not-a-deliverable constraint.

## Out of Scope

- Automatically reading JIRA parent tickets via an API — the command
  *suggests* the user consult them; it does not fetch them.
- Changing the wider-context handling in any command other than
  `/embo:prd` (e.g. tech-design, tasks) — those inherit the PRD section
  but their own prompts are unchanged in this iteration.
- Enforcing or measuring the question with a hook — this iteration is a
  command-prompt change, not a deterministic enforcement mechanism.
- Retrieving the classical human-team RE literature to close the
  research gap noted above.

## Success Metrics

No hook or telemetry is in scope (see Out of Scope), so these are
measured by manual review of PRD-command transcripts before the feature
is called done.

1. Generated PRDs contain a populated "Wider Context / Higher Goal"
   section (or an explicit "none given") rather than omitting it: target
   present in ≥90% of PRDs where the user supplied any answer, over a
   review of at least 5 real PRD-command runs.
2. Across those same runs, zero cases where the wider-context question is
   asked redundantly — i.e. re-asked when the FR-4 detection rule shows
   the context was already known, or asked despite a usable JIRA parent.

(The "asks first, with approved framing" behavior is verified by the
US-1 acceptance criteria, not restated as a metric.)

## References

### From Codebase (RLM / grep)

- `plugin/commands/prd.md:97-124` — Step 4 clarifying-questions block to
  modify.
- `plugin/commands/prd.md:130-160` — PRD template (Context / Goals) to
  extend with the new section.

### From History (Claude-Mem)

- Task 001 — established the mandatory clarifying-questions step.
- Observation #29239 — plain-English / non-jargon PRD output correction,
  consistent with the non-offensive-framing requirement.

### From Research

- research:verify run, 2026-07-24 — mechanism PROVEN, effect PLAUSIBLE
  (large), classical-RE gap noted and judged non-load-bearing.

---

**Next Steps**:
1. Review and refine this PRD.
2. Run `/embo:tech-design` to create the technical design.
3. Run `/embo:tasks` to break it into tasks.
