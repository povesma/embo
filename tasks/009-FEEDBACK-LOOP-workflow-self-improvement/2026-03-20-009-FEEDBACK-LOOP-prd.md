# 009-FEEDBACK-LOOP: Workflow Self-Improvement from User Feedback - PRD

**Status**: Draft (v2 — rewritten 2026-04-07)
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

1. **Correction capture**: During `/dev:impl` sessions, Claude
   recognizes when the user corrects, redirects, or improves its
   behavior, and appends a structured record to a local corrections
   file.

2. **Curation command**: `/dev:improve` analyzes accumulated
   corrections, groups them by pattern, and walks the user through a
   curation process that produces a concrete change proposal — text the
   user can submit as a GitHub issue, paste into a discussion, or send
   to the maintainer.

Users of this project cannot modify the repo directly. The feedback loop
closes when curated proposals reach the maintainer and get incorporated
into command prompts, workflow steps, or behavioral rules.

### Persistence constraint

claude-mem's MCP plugin provides **read-only** tools (`search`,
`get_observations`, `timeline`). There is no write/save API.
Observations are created only by claude-mem's internal hooks watching
Claude's tool usage — this is not controllable from prompt files.

Corrections must therefore be persisted to a **local file**
(`.claude/corrections.jsonl`) using the Write tool. The curation
command reads from this file directly. claude-mem may independently
capture observations about correction activity through its hooks, but
the corrections file is the authoritative source.

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
  during normal `/dev:impl` workflow
- Running `/dev:improve` produces a reviewable, editable proposal when
  corrections exist
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
User is running `/dev:impl`. Claude starts reading a file to understand
an API. User says "no, use Context7 to look up the current docs."
Claude corrects course AND appends a correction record to
`.claude/corrections.jsonl` noting: category `verification`, what
happened, what user wanted.

**UC-2: End-of-session improvement proposal**
After a productive `/dev:impl` session with 4 corrections captured,
the user runs `/dev:improve`. The command reads `.claude/corrections.jsonl`
and shows:
- 2 corrections about verification (use web/Context7 before guessing)
- 1 about code style (don't add comments to unchanged code)
- 1 about workflow (don't ask permission for obvious next steps)

User reviews each, edits wording on one, rejects another as a
one-off misunderstanding, and gets a formatted proposal text.

**UC-3: Cross-session accumulation**
Over 5 sessions across 2 weeks, 12 corrections accumulate in the
corrections file. User runs `/dev:improve`. The command groups them:
"Context7/web verification" appeared 5 times across 3 sessions — this
is clearly a pattern, not a one-off. It gets priority in the proposal.

**UC-4: Nothing to report**
User had a smooth session with zero corrections. At the end of
`/dev:impl`, the workflow checks the corrections file — finds no
pending entries — and does NOT suggest running `/dev:improve`.
No noise.

---

## User Stories

### Story 1 — Automatic correction capture during /dev:impl

**As a** developer using `/dev:impl`,
**I want** Claude to automatically recognize when I correct, redirect,
or improve its behavior and append a structured record to the
corrections file,
**so that** my feedback is preserved without extra effort.

**Acceptance Criteria:**
- [ ] When user rejects Claude's approach (e.g., "no, do X instead"),
  a correction record is appended to `.claude/corrections.jsonl`
- [ ] When user redirects to external verification (e.g., "check the
  web," "use Context7"), a correction record is appended
- [ ] When user corrects code style or testing approach, a correction
  record is appended
- [ ] When user suggests a workflow improvement (e.g., "this step
  should also do X"), a correction record is appended
- [ ] Record includes: what Claude did, what user wanted, category,
  which workflow step was involved, timestamp
- [ ] Capture happens without user explicitly requesting it
- [ ] Normal `/dev:impl` flow is not interrupted or slowed down

---

### Story 2 — Correction record structure

**As a** system processing corrections downstream,
**I want** each correction record to follow a consistent JSON structure,
**so that** they can be grouped, analyzed, and presented meaningfully.

**Acceptance Criteria:**
- [ ] Each correction record is one JSON line in
  `.claude/corrections.jsonl` containing:
  - **what_happened**: What Claude did or was about to do
  - **what_user_wanted**: The correction or redirect
  - **category**: One of: `verification`, `code-style`, `workflow`,
    `approach`, `process`
  - **workflow_step**: Which command/phase was active (e.g., `impl`,
    `start`, `prd`)
  - **severity**: `pattern` (likely repeatable) vs `one-off` (likely
    context-specific) — Claude's best judgment, user can override
    during curation
  - **timestamp**: ISO 8601 date-time
  - **status**: `pending` (default) or `curated`
- [ ] File is created on first correction if it doesn't exist
- [ ] File is append-only during capture (no reads/rewrites)

---

### Story 3 — Curation command: `/dev:improve`

**As a** user who has accumulated corrections over one or more sessions,
**I want** to run a command that presents my corrections grouped by
pattern, lets me review/edit/reject each, and produces a change
proposal I can submit,
**so that** my feedback can reach the project maintainer in a
structured, actionable form.

**Acceptance Criteria:**
- [ ] Command reads `.claude/corrections.jsonl` and filters for
  `status: "pending"` records
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

### Story 5 — Conditional suggestion after /dev:impl

**As a** user finishing a `/dev:impl` session,
**I want** to be told about `/dev:improve` only when there are
corrections worth reviewing,
**so that** I'm not nagged when there's nothing to act on.

**Acceptance Criteria:**
- [ ] At the end of `/dev:impl` (or when session is about to end due
  to context limits), the workflow checks `.claude/corrections.jsonl`
  for pending entries
- [ ] If pending corrections exist: suggest running `/dev:improve`
  with a count (e.g., "3 workflow corrections captured this session —
  run `/dev:improve` to review")
- [ ] If no pending corrections or file doesn't exist: say nothing
- [ ] The check is a file read, not a heavy analysis

---

### Story 6 — Marking corrections as curated

**As a** user who has reviewed corrections,
**I want** curated corrections marked so they don't resurface in the
next `/dev:improve` run,
**so that** curation is idempotent.

**Acceptance Criteria:**
- [ ] After curation, each reviewed correction's `status` field is
  updated from `pending` to `curated` in `.claude/corrections.jsonl`
- [ ] Running `/dev:improve` again shows only new pending corrections
- [ ] The file rewrite preserves all records (curated ones stay for
  history, just filtered out of future curation)

---

### Story 7 — Future: automatic submission (out of scope for v1)

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
  to recognize corrections and append records to the corrections file
- **How**: Prompt addition — not code. When Claude detects a user
  correction (rejection, redirect, style fix, process suggestion),
  it appends a JSON line to `.claude/corrections.jsonl` via the
  Write tool (append mode) or Edit tool
- **Priority**: Critical
- **Rationale**: This is the data collection layer — without it,
  there's nothing to curate

**FR-2: Record structure and categorization**
- **What**: Define the correction record JSON format
- **Categories**: `verification`, `code-style`, `workflow`, `approach`,
  `process`
- **Fields**: what_happened, what_user_wanted, category, workflow_step,
  severity, timestamp, status
- **Storage**: `.claude/corrections.jsonl` (one JSON object per line)
- **Priority**: Critical

**FR-3: Curation command `/dev:improve`**
- **What**: Command file at `.claude/commands/dev/improve.md`
- **How**: Reads corrections file, filters pending, groups by category
  and frequency, walks user through accept/edit/reject for each group,
  assembles proposal, marks reviewed corrections as curated
- **Priority**: Critical

**FR-4: Proposal formatting**
- **What**: Output a Markdown-formatted change proposal
- **Content**: Title, summary, per-group sections with pattern
  description, frequency, suggested file changes, examples
- **Format**: Copy-pasteable into GitHub issue
- **Priority**: High

**FR-5: Conditional suggestion in impl.md**
- **What**: At end of `/dev:impl` or approaching context limits, check
  for pending corrections and suggest `/dev:improve` only if material
  exists
- **How**: Read `.claude/corrections.jsonl`, count pending entries
- **Priority**: High

**FR-6: Idempotent curation**
- **What**: Mark curated corrections so they don't resurface
- **How**: Rewrite `.claude/corrections.jsonl` updating `status` field
  from `pending` to `curated` for reviewed records
- **Priority**: High

### Non-Functional Requirements

**NFR-1: Zero friction capture** — Correction records must be appended
without interrupting the `/dev:impl` flow. No confirmation dialogs,
no "I noticed you corrected me" messages. Silent capture.

**NFR-2: Lightweight curation** — `/dev:improve` should read and
group corrections in under 5 seconds. The interactive curation is
user-paced.

**NFR-3: No false positives** — Not every disagreement is a correction.
User asking a clarifying question is not a correction. User changing
their mind about a feature is not a correction. Only capture when user
is correcting Claude's behavior or the workflow's behavior.

**NFR-4: Portable file** — `.claude/corrections.jsonl` lives in the
user's home directory, survives across projects and sessions. No
database dependency.

**NFR-5: Append-only capture** — During `/dev:impl`, the corrections
file is only appended to (never read or rewritten). This minimizes
tool calls and avoids mid-session file conflicts.

### Technical Constraints

- All command changes are to `.md` prompt files — no new scripts or
  binaries
- Correction records use `.claude/corrections.jsonl` (JSONL format)
- The curation command reads the file directly via Read tool
- Curation marks records via file rewrite (Read → modify → Write)
- claude-mem has **no write API** — observations are created only by
  its internal hooks. The corrections file is the authoritative store.
- Must work without `gh` CLI (proposal is text output; GitHub
  submission is future work)

---

## Out of Scope

- **Auto-applying corrections** — The system captures and packages
  feedback; it never modifies command files automatically
- **Real-time behavior adaptation** — Corrections improve future
  sessions via workflow changes, not the current session (Claude
  can't reload its own prompts mid-conversation)
- **Cross-project correction aggregation** — Each user's corrections
  file is local; aggregating across users is out of scope
- **GitHub issue auto-submission** — V1 produces text; auto-submit
  via `gh` is Story 7 (future)
- **Correction from other users' sessions** — Each user's corrections
  file is local; sharing corrections between users is out of scope

---

## Gherkin Scenarios

```gherkin
Feature: Workflow Self-Improvement from User Feedback

  Scenario: Automatic correction capture during impl
    Given the user is running /dev:impl
    And Claude starts reading source code to guess an API signature
    And the user says "no, use Context7 to look up the docs"
    When Claude corrects course and uses Context7
    Then a correction record is appended to .claude/corrections.jsonl
    And the record category is "verification"
    And the record includes what Claude did and what user wanted
    And the /dev:impl flow continues without interruption

  Scenario: Code style correction captured
    Given the user is running /dev:impl
    And Claude adds docstrings to functions it didn't modify
    And the user says "don't add comments to code you didn't change"
    When Claude acknowledges and continues
    Then a correction record is appended with category "code-style"

  Scenario: Workflow improvement suggestion captured
    Given the user is running /dev:impl
    And the user says "this step should always check for existing
    tests before writing new ones"
    When Claude acknowledges the suggestion
    Then a correction record is appended with category "process"

  Scenario: Normal disagreement NOT captured as correction
    Given the user is running /dev:impl
    And the user says "actually, let's implement feature B first
    instead of feature A"
    When Claude switches to feature B
    Then no correction record is appended
    Because this is a scope change, not a behavior correction

  Scenario: Curation with accumulated corrections
    Given .claude/corrections.jsonl contains 6 pending records
    And 3 are category "verification" and 2 are "code-style"
    And 1 is "workflow"
    When the user runs /dev:improve
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
    Given the user completes /dev:impl with zero corrections
    When the session is wrapping up
    Then /dev:improve is NOT suggested
    And no message about corrections appears

  Scenario: Corrections exist — suggest at end of impl
    Given 3 corrections were captured during the current /dev:impl
    session
    When the session is wrapping up or context is running low
    Then the workflow suggests: "3 workflow corrections captured —
    run /dev:improve to review"

  Scenario: Idempotent curation
    Given the user ran /dev:improve and produced a proposal
    And those corrections were marked as curated
    When the user runs /dev:improve again with no new corrections
    Then the command reports "No pending corrections to review"

  Scenario: Corrections file created on first capture
    Given .claude/corrections.jsonl does not exist
    When Claude captures the first correction
    Then the file is created with one JSON line
    And subsequent corrections are appended
```

---

## References

### From Codebase
- `.claude/commands/dev/impl.md` — Primary target for correction
  recognition prompt (FR-1, FR-5)
- `.claude/commands/dev/improve.md` — Curation command (FR-3),
  already exists but needs rewrite

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
  pattern (17% to 53% on SWE-Bench via self-editing)

### From Discussion (2026-03-20, updated 2026-04-07)
- User explicitly rejected proactive preference loading at session
  start — corrections must go through curation, not auto-apply
- User clarified that CLAUDE.md is not part of the delivered workflow;
  corrections target command prompt files
- User clarified that project users can't modify the repo directly;
  curation produces a proposal for submission upstream
- Command path updated: `/dev:improve` (was `/rlm-mem:support:improve`
  before task 011 rename)
- Persistence: claude-mem has no write API; corrections stored in
  `.claude/corrections.jsonl` (confirmed 2026-04-07)

---

**Next Steps:**
1. Review and approve this PRD
2. Run `/dev:tech-design` to design the file format and curation flow
3. Run `/dev:tasks` to break down into tasks
