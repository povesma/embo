# 009-FEEDBACK-LOOP: Workflow Self-Improvement from User Feedback - PRD

**Status**: Draft
**Created**: 2026-03-20
**Author**: Claude (via rlm-mem analysis)

---

## Introduction/Overview

During coding sessions, users constantly correct, redirect, and improve
Claude's behavior — "check the web first," "don't over-engineer," "use
the existing test pattern," "skip this step." These corrections address
real problems: workflow friction, hallucination-prone behavior, code
style mismatches, and missing verification steps.

Today, every correction dies with the session. The same mistakes repeat
in the next session, in the next project, with the next user. There is
no mechanism to capture this feedback, and no path for it to flow back
into the workflow commands that ship with this project.

This feature adds two capabilities:

1. **Automatic capture**: During `/impl` sessions, Claude recognizes
   when the user corrects, redirects, or improves its behavior, and
   saves a structured observation to claude-mem.

2. **Curation command**: `/rlm-mem:support:improve` analyzes accumulated
   corrections, groups them by pattern, and walks the user through a
   curation process that produces a concrete change proposal — text the
   user can submit as a GitHub issue, paste into a discussion, or send
   to the maintainer.

Users of this project cannot modify the repo directly. The feedback loop
closes when curated proposals reach the maintainer and get incorporated
into command prompts, workflow steps, or behavioral rules.

---

## Objectives & Success Metrics

**Objectives:**
- Capture user corrections that would otherwise be lost
- Reduce repeated mistakes across sessions and users
- Create a low-friction path from "user frustrated mid-session" to
  "concrete improvement proposal for the project"
- Reduce hallucination-driven friction by capturing patterns where
  users redirect to external verification (Context7, web search, docs)

**Success Metrics:**
- Corrections are captured without user having to do anything extra
  during normal `/impl` workflow
- Running `/rlm-mem:support:improve` produces a reviewable, editable
  proposal when corrections exist
- The command is not suggested when there are no corrections to review
- A maintainer receiving the proposal can understand what to change
  and why without additional context

---

## User Personas & Use Cases

### Personas

**Active User**: Uses RLM-Mem daily across projects. Regularly corrects
Claude's approach — prefers web verification, dislikes over-engineering,
has specific code style preferences. Wants these preferences to stick
without having to repeat them every session.
- **Need**: Corrections captured automatically; a way to package them
  into feedback for the project

**Occasional User**: Uses RLM-Mem for specific projects. Encounters
workflow friction but doesn't know how to report it or whether it's
a "them problem" or a "workflow problem."
- **Need**: Low-barrier way to surface friction as structured feedback

**Project Maintainer**: Receives feedback from multiple users. Needs
to understand patterns (what corrections repeat across users?) and
make targeted improvements to command prompts and workflow steps.
- **Need**: Structured proposals that map corrections to specific
  command files and behavioral rules

### Use Cases

**UC-1: Mid-session correction capture**
User is running `/impl`. Claude starts reading a file to understand
an API. User says "no, use Context7 to look up the current docs."
Claude corrects course AND saves an observation noting: "User
redirected from file-reading to Context7 for API documentation
lookup — pattern: prefer external verification over guessing from
source code."

**UC-2: End-of-session improvement proposal**
After a productive `/impl` session with 4 corrections captured,
the user runs `/rlm-mem:support:improve`. The command shows:
- 2 corrections about verification (use web/Context7 before guessing)
- 1 about code style (don't add comments to unchanged code)
- 1 about workflow (don't ask permission for obvious next steps)

User reviews each, edits wording on one, rejects another as a
one-off misunderstanding, and gets a formatted proposal text.

**UC-3: Cross-session accumulation**
Over 5 sessions across 2 weeks, 12 corrections accumulate in
claude-mem. User runs `/rlm-mem:support:improve`. The command
groups them: "Context7/web verification" appeared 5 times across
3 sessions — this is clearly a pattern, not a one-off. It gets
priority in the proposal.

**UC-4: Nothing to report**
User had a smooth session with zero corrections. At the end of
`/impl`, the workflow checks claude-mem for pending corrections —
finds none — and does NOT suggest running `/support:improve`.
No noise.

---

## User Stories

### Story 1 — Automatic correction capture during /impl

**As a** developer using `/rlm-mem:develop:impl`,
**I want** Claude to automatically recognize when I correct, redirect,
or improve its behavior and save a structured observation,
**so that** my feedback is preserved without extra effort.

**Acceptance Criteria:**
- [ ] When user rejects Claude's approach (e.g., "no, do X instead"),
  a correction observation is saved to claude-mem
- [ ] When user redirects to external verification (e.g., "check the
  web," "use Context7"), a correction observation is saved
- [ ] When user corrects code style or testing approach, a correction
  observation is saved
- [ ] When user suggests a workflow improvement (e.g., "this step
  should also do X"), a correction observation is saved
- [ ] Observation includes: what Claude did → what user wanted →
  category → which workflow step was involved
- [ ] Observation type is `correction` for searchability
- [ ] Capture happens without user explicitly requesting it
- [ ] Normal `/impl` flow is not interrupted or slowed down

---

### Story 2 — Correction observation structure

**As a** system processing corrections downstream,
**I want** each correction observation to follow a consistent structure,
**so that** they can be grouped, analyzed, and presented meaningfully.

**Acceptance Criteria:**
- [ ] Each correction observation contains:
  - **What happened**: What Claude did or was about to do
  - **What user wanted**: The correction or redirect
  - **Category**: One of: `verification` (use web/Context7/docs),
    `code-style` (formatting, naming, comments), `workflow`
    (skip/add/change workflow steps), `approach` (over-engineering,
    wrong pattern, wrong tool), `process` (new idea for how things
    should work)
  - **Workflow step**: Which command/phase was active (e.g., `impl`,
    `start`, `prd`)
  - **Severity**: `pattern` (likely repeatable) vs `one-off` (likely
    context-specific) — Claude's best judgment, user can override
    during curation
- [ ] Observations are tagged `[TYPE: CORRECTION]` for search
- [ ] Observations are project-scoped in claude-mem

---

### Story 3 — Curation command: `/rlm-mem:support:improve`

**As a** user who has accumulated corrections over one or more sessions,
**I want** to run a command that presents my corrections grouped by
pattern, lets me review/edit/reject each, and produces a change
proposal I can submit,
**so that** my feedback can reach the project maintainer in a
structured, actionable form.

**Acceptance Criteria:**
- [ ] Command queries claude-mem for `correction` type observations
  in the current project
- [ ] Corrections are grouped by category and ranked by frequency
  (corrections that appeared multiple times across sessions rank
  higher)
- [ ] For each group, the command shows:
  - Category and frequency count
  - Representative examples (actual correction text)
  - Suggested workflow change (Claude's recommendation of what to
    modify in which command file)
- [ ] User can for each group: **accept** (include in proposal),
  **edit** (modify the suggestion), **reject** (discard — was a
  one-off or misunderstanding)
- [ ] After review, the command assembles a formatted proposal

---

### Story 4 — Change proposal output

**As a** user who has completed the curation process,
**I want** a formatted text proposal that I can copy-paste into a
GitHub issue, email, or discussion,
**so that** I can submit feedback without writing it from scratch.

**Acceptance Criteria:**
- [ ] Proposal includes a title and summary
- [ ] Each accepted correction group becomes a section with:
  - The pattern observed (what keeps happening)
  - Frequency and evidence (N occurrences across M sessions)
  - Suggested change: which file(s) to modify and what rule to add
  - Example correction(s) from actual sessions
- [ ] Proposal is formatted as Markdown (suitable for GitHub issue)
- [ ] Proposal includes metadata: project name, date range of
  corrections, total corrections reviewed vs accepted
- [ ] User can copy the full proposal text from the command output

---

### Story 5 — Conditional suggestion after /impl

**As a** user finishing an `/impl` session,
**I want** to be told about `/rlm-mem:support:improve` only when there
are corrections worth reviewing,
**so that** I'm not nagged when there's nothing to act on.

**Acceptance Criteria:**
- [ ] At the end of `/impl` (or when session is about to end due to
  context limits), the workflow checks claude-mem for uncurated
  corrections in the current project
- [ ] If corrections exist: suggest running `/rlm-mem:support:improve`
  with a count (e.g., "3 workflow corrections captured this session —
  run `/rlm-mem:support:improve` to review")
- [ ] If no corrections exist: say nothing about it
- [ ] The check is a lightweight claude-mem query, not a heavy analysis

---

### Story 6 — Future: automatic submission (out of scope for v1)

**As a** user,
**I want** the option to automatically submit my curated proposal as a
GitHub issue,
**so that** I don't have to manually copy-paste.

**Note:** This story is documented for future consideration only.
V1 produces text output that the user submits manually.

**Acceptance Criteria (future):**
- [ ] After curation, offer to create a GitHub issue via `gh issue create`
- [ ] Pre-fill title, body, and labels from the proposal
- [ ] Require user confirmation before submitting
- [ ] Handle auth gracefully (if `gh` not authenticated, fall back to
  text output)

---

## Requirements

### Functional Requirements

**FR-1: Correction recognition prompt in impl.md**
- **What**: Add behavioral guidance to `impl.md` that instructs Claude
  to recognize corrections and save structured observations
- **How**: Prompt addition — not code. When Claude detects a user
  correction (rejection, redirect, style fix, process suggestion),
  it saves an observation via the standard write+read pattern
- **Priority**: Critical
- **Rationale**: This is the data collection layer — without it,
  there's nothing to curate

**FR-2: Observation structure and categorization**
- **What**: Define the correction observation format
- **Categories**: `verification`, `code-style`, `workflow`, `approach`,
  `process`
- **Fields**: what-happened, what-user-wanted, category, workflow-step,
  severity
- **Tag**: `[TYPE: CORRECTION]`
- **Priority**: Critical

**FR-3: Curation command `/rlm-mem:support:improve`**
- **What**: New command file at
  `.claude/commands/rlm-mem/support/improve.md`
- **How**: Queries claude-mem for corrections, groups by category and
  frequency, walks user through accept/edit/reject for each group,
  assembles proposal
- **Priority**: Critical

**FR-4: Proposal formatting**
- **What**: Output a Markdown-formatted change proposal
- **Content**: Title, summary, per-group sections with pattern
  description, frequency, suggested file changes, examples
- **Format**: Copy-pasteable into GitHub issue
- **Priority**: High

**FR-5: Conditional suggestion in impl.md**
- **What**: At end of `/impl` or approaching context limits, check
  for uncurated corrections and suggest `/support:improve` only if
  material exists
- **How**: Lightweight claude-mem search for `[TYPE: CORRECTION]`
  with count
- **Priority**: High

**FR-6: Correction deduplication awareness**
- **What**: When presenting corrections in curation, identify
  duplicates (same pattern across sessions) and merge them
- **How**: Group by category + similar what-user-wanted text
- **Priority**: Medium

### Non-Functional Requirements

**NFR-1: Zero friction capture** — Correction observations must be
saved without interrupting the `/impl` flow. No confirmation dialogs,
no "I noticed you corrected me" messages. Silent capture.

**NFR-2: Lightweight curation** — `/support:improve` should complete
the query+grouping phase in under 10 seconds. The interactive curation
is user-paced.

**NFR-3: No false positives** — Not every disagreement is a correction.
User asking a clarifying question is not a correction. User changing
their mind about a feature is not a correction. Only capture when user
is correcting Claude's behavior or the workflow's behavior.

**NFR-4: Project-scoped** — Corrections from project A must not appear
in project B's curation. Use claude-mem project scoping.

**NFR-5: Idempotent curation** — Running `/support:improve` twice
should not produce duplicate proposals. Corrections already included
in a past proposal should be marked as "curated" and excluded from
future runs (unless explicitly re-included).

### Technical Constraints

- All changes are to `.md` command prompt files — no new scripts or
  binaries
- Correction observations use the existing PostToolUse hook mechanism
  (write file + read to trigger hook capture)
- The curation command uses existing claude-mem search and
  get_observations tools
- No new MCP tools or plugins required
- Must work without `gh` CLI (proposal is text output; GitHub
  submission is future work)

---

## Out of Scope

- **Auto-applying corrections** — The system captures and packages
  feedback; it never modifies command files automatically
- **Real-time behavior adaptation** — Corrections improve future
  sessions via workflow changes, not the current session (Claude
  can't reload its own prompts mid-conversation)
- **Cross-project correction aggregation** — Each project's
  corrections are independent; aggregating across projects is
  future work
- **GitHub issue auto-submission** — V1 produces text; auto-submit
  via `gh` is Story 6 (future)
- **Correction from other users' sessions** — Each user's claude-mem
  is local; sharing corrections between users is out of scope
- **Shared `_commons.md` or build-inject system** — Deferred per
  discussion; corrections target specific command files in the
  proposal, maintainer applies manually

---

## Gherkin Scenarios

```gherkin
Feature: Workflow Self-Improvement from User Feedback

  Scenario: Automatic correction capture during impl
    Given the user is running /rlm-mem:develop:impl
    And Claude starts reading source code to guess an API signature
    And the user says "no, use Context7 to look up the docs"
    When Claude corrects course and uses Context7
    Then a correction observation is saved to claude-mem
    And the observation category is "verification"
    And the observation includes what Claude did and what user wanted
    And the /impl flow continues without interruption

  Scenario: Code style correction captured
    Given the user is running /rlm-mem:develop:impl
    And Claude adds docstrings to functions it didn't modify
    And the user says "don't add comments to code you didn't change"
    When Claude acknowledges and continues
    Then a correction observation is saved with category "code-style"

  Scenario: Workflow improvement suggestion captured
    Given the user is running /rlm-mem:develop:impl
    And the user says "this step should always check for existing
    tests before writing new ones"
    When Claude acknowledges the suggestion
    Then a correction observation is saved with category "process"

  Scenario: Normal disagreement NOT captured as correction
    Given the user is running /rlm-mem:develop:impl
    And the user says "actually, let's implement feature B first
    instead of feature A"
    When Claude switches to feature B
    Then no correction observation is saved
    Because this is a scope change, not a behavior correction

  Scenario: Curation with accumulated corrections
    Given 6 correction observations exist in claude-mem
    And 3 are category "verification" and 2 are "code-style"
    And 1 is "workflow"
    When the user runs /rlm-mem:support:improve
    Then corrections are grouped by category
    And "verification" group shows frequency 3 and is listed first
    And the user can accept, edit, or reject each group
    And accepted groups form a Markdown proposal

  Scenario: Curation produces copy-pasteable proposal
    Given the user has accepted 2 correction groups
    When the curation process completes
    Then a Markdown-formatted proposal is displayed
    And it includes a title, summary, and per-group sections
    And each section has: pattern, frequency, suggested file change,
    examples
    And the text is suitable for pasting into a GitHub issue

  Scenario: No corrections — no suggestion
    Given the user completes /impl with zero corrections
    When the session is wrapping up
    Then /rlm-mem:support:improve is NOT suggested
    And no message about corrections appears

  Scenario: Corrections exist — suggest at end of impl
    Given 3 corrections were captured during the current /impl session
    When the session is wrapping up or context is running low
    Then the workflow suggests: "3 workflow corrections captured —
    run /rlm-mem:support:improve to review"

  Scenario: Idempotent curation
    Given the user ran /support:improve and produced a proposal
    And those corrections were marked as curated
    When the user runs /support:improve again with no new corrections
    Then the command reports "No new corrections to review"
```

---

## References

### From Codebase
- `.claude/commands/rlm-mem/develop/impl.md` — Primary target for
  correction recognition prompt (FR-1, FR-5)
- `.claude/commands/rlm-mem/support/improve.md` — New command (FR-3)
- `.claude/commands/rlm-mem/README.md` — Needs new Support phase entry

### From Industry Research (2026-03-20)
- **Windsurf Cascade Memories**: Auto-generates memories during
  conversation; separates "memories" (evolving) from "rules" (stable).
  Validates our two-tier approach (capture + curate)
- **Augment Code RLDB**: Captures implicit accept/reject signals.
  Gold standard but requires model-level training; we approximate
  via prompt-level recognition
- **GitHub Copilot Memory**: Auto-discovers repo patterns, 28-day
  expiry. Validates auto-capture; we add user curation instead of
  auto-expiry
- **Addy Osmani "Self-Improving Agents"**: AGENTS.md accumulator
  pattern — persistent file updated after each task with learnings.
  Our approach is similar but routes through user curation before
  changes reach command files
- **arXiv 2504.15228**: Academic validation of self-improving agent
  pattern (17% → 53% on SWE-Bench via self-editing)

### From Discussion (2026-03-20)
- User explicitly rejected proactive preference loading at session
  start — corrections must go through curation, not auto-apply
- User clarified that CLAUDE.md is not part of the delivered workflow;
  corrections target command prompt files
- User clarified that project users can't modify the repo directly;
  curation produces a proposal for submission upstream
- Command name: `/rlm-mem:support:improve`
- Conditional suggestion: only when corrections exist, at end of
  `/impl` or approaching context limits

### From IDEAS.md
- "Workflow Self-Improvement from User Corrections" entry (2026-03-20)
- `_commons.md` build-inject deferred — corrections target specific
  command files in the proposal

---

**Next Steps:**
1. Review and approve this PRD
2. Run `/rlm-mem:plan:tech-design` to design the observation structure
   and curation flow
3. Run `/rlm-mem:plan:tasks` to break down into tasks
