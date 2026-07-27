# wider-context-prd-higher-goal-question - Task List

## Relevant Files

- [2026-07-25-048-wider-context-tech-design.md](2026-07-25-048-wider-context-tech-design.md)
  :: Wider-Context Question - Technical Design
- [2026-07-25-048-wider-context-prd.md](2026-07-25-048-wider-context-prd.md)
  :: Wider-Context Question - Product Requirements Document
- [plugin/commands/prd.md](../../plugin/commands/prd.md)
  :: MODIFY - Step 4 gains the asked-first wider-context question (two
     inline lists + evaluation-order logic); Step 4 business-goal clause
     removed; Step 5 template gains the top "Wider Context / Higher Goal"
     section
- [plugin/.claude-plugin/plugin.json](../../plugin/.claude-plugin/plugin.json)
  :: MODIFY - patch version bump so a live test picks up the change from
     the version-keyed plugin cache

## Notes

- This feature is entirely a prompt-text edit to one shipped command
  file plus a version bump. No code, no new file, no new tool.
- All three stories edit the SAME file (`plugin/commands/prd.md`); they
  are grouped by the functional requirement each verifies, not by
  separate edits. Implement as one coherent change to the file.
- `code-only` subtasks are verified by reading the shipped file and
  confirming the text/logic/lists are present and internally
  consistent. `manual-run-claude` subtasks need a live `/embo:prd` run
  whose transcript shows the runtime behavior.
- The `## Wider Context / Higher Goal` phrase is a document HEADER only;
  the blocklist bans "higher goal" in the ASKED question. Keep the two
  distinct (tech-design "Header-vs-question disambiguation").

## Tasks

- [X] 1.0 **User Story:** As an embo user, I want the wider-context
  question asked first with non-offensive framing, so my PRD captures
  the motivation before anything else (FR-1, FR-2, FR-5). [5/0]
  - [X] 1.1 In `plugin/commands/prd.md` Step 4, add an asked-first
    wider-context sub-step that runs its OWN `AskUserQuestion` call
    BEFORE the existing clarifying-questions call [verify: code-only]
  - [X] 1.2 Remove ONLY the ` or "What is the main business goal we want
    to achieve?"` clause from the :103-104 bullet, leaving the bullet
    ending at `for the user?"` (sub-string removal, not a line deletion
    — a whole-line-104 deletion leaves a dangling `or`) [verify: code-only]
  - [X] 1.3 Add the inline approved-framing positive list and the
    blocklist to Step 4, plus the header-vs-question disambiguation line
    ("Wider Context / Higher Goal" is the section header only; never the
    spoken question) [verify: code-only]
  - [X] 1.4 Add the one-follow-up rule (shallow answer that only
    restates the feature → exactly one probing follow-up, then accept;
    never block; "skip"/"none" recorded as "none given") [verify: code-only]
  - [X] 1.5 Live-run `/embo:prd` on a bare feature description; confirm
    the transcript shows TWO distinct `AskUserQuestion` calls with the
    wider-context one first, using an approved framing and no blocklist
    phrase [verify: manual-run-claude]
    → user smoke-tested a fresh session: wider-context question fires
      first with approved framing; works [user-confirmed] (2026-07-26)

- [ ] 2.0 **User Story:** As an embo user, I want the command to suggest
  my JIRA parent and skip when context is already known, so I am not
  asked to restate what exists (FR-3, FR-4). [4/0]
  - [X] 2.1 Add the FR-4 redundancy check as evaluation step 1: wider
    context counts as known only on a motivation distinct from the
    feature's mechanism (a "so that"/"because"/"in order to" clause or a
    parent-goal/ticket reference); a bare feature restatement does not
    count; on known → skip, restate context in one line, proceed
    [verify: code-only]
  - [X] 2.2 Add the FR-3 JIRA-parent branch as evaluation step 2: on a
    JIRA-style ID (uppercase key, hyphen, digits) suggest consulting the
    parent/epic before asking; include the fallback — leaf ticket OR
    parent exists but yields no usable context → fall through to ask;
    never block on the parent [verify: code-only]
  - [X] 2.3 State the evaluation order explicitly (redundancy → JIRA →
    ask) and the precedence: redundancy-skip wins over the FR-5 follow-up
    when both could apply [verify: code-only]
  - [~] 2.4 Live-run two `/embo:prd` cases: (a) prompt with a "so that"
    motivation → question skipped, context restated, no follow-up fires;
    (b) prompt with an `AS-1234`-style ID → command suggests the parent
    [verify: manual-run-claude]
    → core question path smoke-tested and works; the redundancy-skip (a)
      and JIRA-parent (b) branches not specifically driven yet
      [pending branch-specific run] (2026-07-26)

- [ ] 3.0 **User Story:** As an embo user, I want the captured wider
  context recorded in the generated PRD, so it propagates to tech-design
  and tasks (FR-6). [3/0]
  - [X] 3.1 In `plugin/commands/prd.md` Step 5 template, insert the
    `## Wider Context / Higher Goal` section between the `---` separator
    and `## Context`, with the placeholder covering the three variants
    (captured context / "None given — feature described in isolation." /
    JIRA-parent-cited) [verify: code-only]
  - [X] 3.2 Patch-bump the version in
    `plugin/.claude-plugin/plugin.json` so a live test loads the change
    from the version-keyed plugin cache (0.2.3 → 0.2.4) [verify: code-only]
  - [~] 3.3 Live-run `/embo:prd` twice: one with a wider-context answer
    (section populated) and one with none (section shows "None given —
    feature described in isolation.") [verify: manual-run-claude]
    → populated-section path confirmed via smoke-test; "None given" empty
      variant not specifically driven yet [pending edge run] (2026-07-26)
