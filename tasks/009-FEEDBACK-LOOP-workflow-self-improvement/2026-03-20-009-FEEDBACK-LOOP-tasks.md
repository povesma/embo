# 009-FEEDBACK-LOOP - Task List

## Relevant Files

- [tasks/009-FEEDBACK-LOOP-workflow-self-improvement/
  2026-03-20-009-FEEDBACK-LOOP-prd.md](
  2026-03-20-009-FEEDBACK-LOOP-prd.md)
  :: Product Requirements Document
- [tasks/009-FEEDBACK-LOOP-workflow-self-improvement/
  2026-03-20-009-FEEDBACK-LOOP-tech-design.md](
  2026-03-20-009-FEEDBACK-LOOP-tech-design.md)
  :: Technical Design Document
- [.claude/commands/rlm-mem/develop/impl.md](
  ../../.claude/commands/rlm-mem/develop/impl.md)
  :: Modify — add Correction Capture + Session Wrap-Up
- [.claude/commands/rlm-mem/support/improve.md](
  ../../.claude/commands/rlm-mem/support/improve.md)
  :: Create — curation command
- [README.md](../../README.md)
  :: Add Support phase and /support:improve to commands list

## Notes

- TDD does not apply — all deliverables are markdown prompt files,
  not application code. Testing means invoking the commands and
  verifying behavior matches Gherkin scenarios in the PRD.
- The correction observation format uses claude-mem's native
  `save_memory` MCP tool directly — no write+read hook pattern.
- Curation state uses companion CORRECTION-STATUS observations
  because claude-mem observations are immutable (no update API).

## Tasks

- [~] 1.0 **User Story:** As a developer using `/impl`, I want
  Claude to silently recognize and save my behavioral corrections
  to claude-mem, so that my feedback survives the session [3/1]
  - [X] 1.1 Add "Correction Capture" section to
    `.claude/commands/rlm-mem/develop/impl.md` after the
    "Scope Verification" section (after line 48). Include:
    the correction vs not-a-correction distinction table,
    the five categories (verification, code-style, workflow,
    approach, process), the severity field (pattern vs one-off),
    and the `save_memory` call template with `[TYPE: CORRECTION]`
    and `[STATUS: pending]` tags. Use the exact prompt text
    from tech-design §Component 1.
  - [ ] 1.2 Verify: run `/rlm-mem:develop:impl` on a task in
    this repo, deliberately give a behavioral correction
    (e.g., "use Context7 instead of guessing"), and confirm
    a `[TYPE: CORRECTION]` observation appears in claude-mem
    via `search(query="[TYPE: CORRECTION]", limit=1)`
  - [ ] 1.3 Verify negative case: give a scope/design change
    (e.g., "let's do that task later") and confirm NO
    correction observation is saved

- [~] 2.0 **User Story:** As a developer finishing an `/impl`
  session, I want to be told about `/support:improve` only when
  corrections were captured, so that I'm not nagged when there's
  nothing to review [2/1]
  - [X] 2.1 Add "Session Wrap-Up Check" as Step 8 to `impl.md`
    after the existing Step 7 (after line 176). Include: a
    `search(query="[TYPE: CORRECTION] [STATUS: pending]",
    limit=1)` call, conditional suggestion text with count
    if results exist, and explicit "say nothing" instruction
    if no results
  - [ ] 2.2 Verify: after a session where corrections were
    captured, confirm the suggestion appears at wrap-up;
    after a session with zero corrections, confirm nothing
    is mentioned

- [X] 3.0 **User Story:** As a developer with accumulated
  corrections, I want `/rlm-mem:support:improve` to query, group,
  and present my corrections for curation, so that I can review
  them efficiently [4/3]
  - [X] 3.1 Create `.claude/commands/rlm-mem/support/improve.md`
    with file header, "When to Use" section, and Step 1:
    query claude-mem for `[TYPE: CORRECTION] [STATUS: pending]`
    (limit=50), fetch full observations via `get_observations`,
    then also query for `[TYPE: CORRECTION-STATUS]` to get
    already-curated IDs and exclude them from the pending set.
    If zero pending corrections remain, output
    "No pending corrections to review." and stop.
  - [X] 3.2 Add Step 2 to `improve.md`: grouping logic.
    Instruct Claude to parse `[CATEGORY: ...]` tags, group
    observations by category, merge near-duplicates within
    each group by semantic similarity of "What user wanted"
    text, sort categories by count descending, and select
    1-3 representative examples per group.
  - [X] 3.3 Add Step 3 to `improve.md`: interactive curation.
    For each category group, present via AskUserQuestion:
    category name, frequency count, representative examples,
    and suggested change (target file + section + rule text).
    Options: Accept, Edit (user provides modified text),
    Reject. Include the category-to-file mapping table from
    tech-design (verification→impl.md, code-style→impl.md
    §Code Style, etc.). Instruct Claude to read the target
    file during curation to provide specific section refs.
  - [ ] 3.4 Verify: seed claude-mem with 3-4 test correction
    observations (different categories), run
    `/rlm-mem:support:improve`, confirm they appear grouped
    by category with correct counts and examples

- [~] 4.0 **User Story:** As a developer who has curated
  corrections, I want the command to produce a Markdown change
  proposal and mark corrections as curated, so that I can submit
  feedback and not see them again [4/2]
  - [X] 4.1 Add Step 4 to `improve.md`: mark curated. After
    user finishes reviewing all groups, save one
    `[TYPE: CURATION-LOG]` observation with date, reviewed
    IDs, accepted/rejected counts. Then for each reviewed
    correction, save a `[TYPE: CORRECTION-STATUS]` observation
    referencing the original ID with `[STATUS: curated]` and
    `[DECISION: accepted|rejected]`.
  - [X] 4.2 Add Step 5 to `improve.md`: proposal assembly.
    Build Markdown output using the proposal template from
    tech-design: title, metadata (date, project, counts,
    date range), summary, per-group sections (pattern, freq,
    examples, suggested file+section+rule), collapsible raw
    corrections table, and footer with submission instructions.
    Output directly to conversation — user copies it.
  - [ ] 4.3 Verify idempotent curation: run `/support:improve`
    once, complete curation, then run it again — confirm the
    second run says "No pending corrections to review" (the
    CORRECTION-STATUS exclusion logic works)
  - [ ] 4.4 Verify proposal output: complete a curation with
    2+ accepted groups, confirm the Markdown proposal contains
    all required sections (title, summary, per-group detail,
    raw table, footer) and is valid Markdown suitable for a
    GitHub issue

- [X] 5.0 **User Story:** As a new user reading the docs, I want
  the README and command docs updated to reflect the new Support
  phase and `/support:improve` command [3/3]
  - [X] 5.1 Add Support phase row to the Available Commands
    table in `README.md`: `/rlm-mem:support:improve` with
    description "Review accumulated corrections and generate
    improvement proposal". Update command count if mentioned
    (9 → 10).
  - [X] 5.2 Update `CLAUDE.md` File Structure listing to
    include `support/improve.md` under the commands tree
  - [X] 5.3 Update `install.sh` if it copies command files —
    ensure the `support/` directory is included in the copy

- [ ] 6.0 **User Story:** As a developer, I want all PRD Gherkin
  scenarios manually verified so that the feature is confirmed
  working end-to-end [5/0]
  - [ ] 6.1 **Scenario: Automatic correction capture** — run
    `/impl` on a real task, give a "use Context7" redirect,
    verify `[TYPE: CORRECTION]` observation with category
    `verification` appears in claude-mem
  - [ ] 6.2 **Scenario: Normal disagreement NOT captured** —
    during `/impl`, say "let's do feature B instead", verify
    no correction observation is created
  - [ ] 6.3 **Scenario: Corrections exist — suggest at end** —
    after capturing corrections, wrap up `/impl`, verify the
    suggestion message appears with correct count
  - [ ] 6.4 **Scenario: Curation produces proposal** — run
    `/support:improve` with pending corrections, accept some,
    reject some, verify Markdown proposal output is complete
  - [ ] 6.5 **Scenario: Idempotent curation** — run
    `/support:improve` again after curation, verify "No
    pending corrections to review"
