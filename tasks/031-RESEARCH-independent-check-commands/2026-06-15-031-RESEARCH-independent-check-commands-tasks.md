# 031-RESEARCH-independent-check-commands - Task List

## Relevant Files
- [2026-06-15-031-RESEARCH-independent-check-commands-tech-design.md](2026-06-15-031-RESEARCH-independent-check-commands-tech-design.md)
  :: Technical Design
- [2026-06-15-031-RESEARCH-independent-check-commands-prd.md](2026-06-15-031-RESEARCH-independent-check-commands-prd.md)
  :: PRD
- [../../docs/VERIFICATION-DISCIPLINE.md](../../docs/VERIFICATION-DISCIPLINE.md)
  :: Vendored verification-discipline reference (new)
- [../../.claude/commands/dev/research/examine.md](../../.claude/commands/dev/research/examine.md)
  :: dev:research:examine command (new)
- [../../.claude/commands/dev/research/verify.md](../../.claude/commands/dev/research/verify.md)
  :: dev:research:verify command — thin spawner (new)
- [../../.claude/agents/approach-validator.md](../../.claude/agents/approach-validator.md)
  :: approach-validator agent — verify+advise; discipline prompt (new)
- [../../.claude/agents/examine-advisor.md](../../.claude/agents/examine-advisor.md)
  :: examine-advisor agent — examine+advise; one agent, two passes (new)
- [../../.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: add RESEARCH-VERIFY rule block
- [../../.claude/hooks/behavioral-reminder.sh](../../.claude/hooks/behavioral-reminder.sh)
  :: add RESEARCH-VERIFY to BASELINE
- [../../.claude/hooks/behavioral-reminder.test.sh](../../.claude/hooks/behavioral-reminder.test.sh)
  :: assert RESEARCH-VERIFY in baseline output
- [../../README.md](../../README.md)
  :: document new commands + rule tag

## Notes
- This is a markdown/prompt feature: no app test framework. The only
  automated test is the bash hook suite
  (`bash .claude/hooks/behavioral-reminder.test.sh`).
- Command/doc/README changes are `code-only` (no runtime to exercise);
  command behavior is verified `manual-run-claude` by running the
  command in a live session.
- Source doc to vendor: external
  `~/artec/infra/docs/VERIFICATION-DISCIPLINE.md` (read-only source).
- Subagents cannot prompt the user mid-run — digest approval is a
  main-agent step before spawning.

## Tasks
- [X] 1.0 **User Story:** As an embo user, I want
  `VERIFICATION-DISCIPLINE.md` vendored into the repo with minor
  refinements as a human-readable reference (the operational prompt
  lives in the verify-critic agent, not this doc) [3/3]
  - [X] 1.1 Create `docs/` dir; copy the source doc to
    `docs/VERIFICATION-DISCIPLINE.md`; confirm `.gitignore` does not
    exclude `docs/` [verify: code-only]
    → docs/ already existed (holds WHY.md); copied source verbatim
      (159 lines); shows untracked, not gitignored (2026-06-15)
  - [X] 1.2 Apply the additive tweaks: (a) top scope line — when
    the discipline applies (risky / complex / expensive-to-reverse);
    (b) section-A clause for "no independent source exists" → mark
    unproven, don't let reasoning fill the gap; (c) clarify section G
    with the patch-vs-reset contrast; (d) add "fresh agent in a clean
    context" as a fourth independent-source bullet in section A
    [verify: code-only]
  - [X] 1.3 Read the vendored doc back; confirm the three tweaks are
    present and the rest is unchanged from source [verify: manual-run-claude]
    → diff vs source: additive blocks only, 0 deletions, rest
      byte-identical; a 4th tweak (clean-context subagent as
      independent source) added after [live] (2026-06-15)
- [X] 2.0 **User Story:** As an embo user, I want `dev:research:verify`
  to check a chosen spec against its acceptance criteria using the
  verification-discipline process, so I catch flaws before implementing
  [5/5]
  - [X] 2.1 Create `.claude/commands/dev/research/verify.md` as a THIN
    spawner: frontmatter (discovery-only, no auto-run), input contract
    (spec/criteria from path or inline; ask if criteria missing), spawn
    the approach-validator agent, relay its verdict [verify: code-only]
  - [X] 2.2 Create `.claude/agents/approach-validator.md` (renamed from
    verify-critic) with embedded verification-discipline prompt; tools
    list incl. Context7 + NotebookLM MCP [verify: code-only]
  - [X] 2.3 Write the validator's process: extract claims/criteria →
    prove each against independent source (Context7 / live system /
    artifact / NotebookLM prior art; never memory) → exercise un-proven
    paths once → a resistant claim is itself a finding [verify: code-only]
  - [X] 2.4 Define output contract: per-criterion verdict (proven /
    unproven / contradicted) + constructive advice (alternatives if
    unconfirmed, evidence if proven); report-only [verify: code-only]
  - [X] 2.5 Live run: spawned approach-validator on a sample spec (031's
    own MCP-frontmatter claims) [verify: manual-run-claude]
    → agent ran its process, returned per-criterion verdict table with
      real sources, AND caught a real bug: declared
      `mcp__context7__get-library-docs` but live name is `query-docs`;
      fixed in frontmatter + body [live] (2026-06-16)
- [X] 3.0 **User Story:** As an embo user, I want `dev:research:examine`
  to run examine-advisor as two parallel passes on a document or option
  set and give me one reconciled report + recommendation, so I decide
  directions on evidence [7/7]
  - [X] 3.5 Create `.claude/agents/examine-advisor.md`: ONE agent that
    examines + advises (unified job, not split), run as two passes
    (research via NotebookLM MCP / internal via codebase); requires the
    command to pass surrounding context; output = findings table +
    recommendation [verify: code-only]
  - [X] 3.1 Create `.claude/commands/dev/research/examine.md` as a thin
    spawner: frontmatter (discovery-only) + description [verify: code-only]
  - [X] 3.2 Write input auto-detect: arg resolves to a readable file →
    document; else → inline options/decision [verify: code-only]
  - [X] 3.3 Write the digest + surrounding-context builder (goal,
    constraints, tried/ruled-out) + main-agent approval gate before any
    outbound call (hard-block secrets + user-identity; allow internal
    IPs; ask when unclear) [verify: code-only]
  - [X] 3.4 Write the spawn spec: `examine-advisor` ×2 in parallel
    (`pass=research` + `pass=internal`), each passed the digest +
    context; research pass uses NotebookLM MCP only, emits
    `EXTERNAL-CHECK-SKIPPED` on auth failure [verify: code-only]
  - [X] 3.6 Write await-both + reconcile logic (dedupe, severity rank,
    both-flagged vs one-flagged, combine the two recommendations);
    report-only [verify: code-only]
  - [X] 3.7 Live run: invoke on a sample target; confirm both passes ran
    in parallel and a reconciled report + recommendation is produced;
    then simulate MCP-down and confirm internal-pass-only report with
    the gap flagged [verify: manual-run-claude]
    → ran both passes in parallel on a real design decision (one-agent-
      two-passes vs alternatives); research pass hit live NotebookLM
      auth-expired and correctly emitted EXTERNAL-CHECK-SKIPPED (FR-5
      degradation proven), both returned findings+recommendation, main
      agent reconciled to one report; both converged on (a) and both
      flagged the internal-pass tool-boundary gap, which was then
      hardened in the agent [live] (2026-06-16)
- [X] 4.0 **User Story:** As an embo user, I want the `RESEARCH-VERIFY`
  rule shipped and wired into the reminder BASELINE, so the agent is
  steered toward independent checks (and Context7 on doubt) [3/3]
  - [X] 4.1 Add the `RESEARCH-VERIFY` rule block to `start.md` (trigger:
    above-average cost OR low confidence; two tiers: Context7 on slight
    doubt, examine/verify on real decisions) [verify: code-only]
  - [X] 4.2 Write a failing test asserting baseline output contains
    `RESEARCH-VERIFY`; then add `· RESEARCH-VERIFY` to the
    `behavioral-reminder.sh` BASELINE to pass it [verify: auto-test]
    → new behavioral-reminder.test.sh: red phase 5 passed / 1 failed
      (RESEARCH-VERIFY missing, correct reason) [live] (2026-06-16)
  - [X] 4.3 Run the hook suite; confirm green and the tag appears in
    emitted `additionalContext` [verify: auto-test]
    → after BASELINE edit: 6 passed, 0 failed [live] (2026-06-16)
- [X] 5.0 **User Story:** As an embo user, I want the new commands and
  rule reflected in README and resolving as skills, so the feature is
  documented and installable [3/3]
  - [X] 5.1 Add README entries: `dev:research:examine` and
    `dev:research:verify` rows in Available Commands (new Research
    phase) [verify: code-only]
    → no per-rule-tag table exists in README (rule tags live in
      start.md; README documents only the reminder hook), so no tag
      row to add — noted instead of invented (2026-06-16)
  - [X] 5.2 Reflect the new agents + `research/` command subdir in the
    file-structure tree; the vendored doc stays repo-only (human
    reference, not installed to ~/.claude/), so it is NOT in the
    ~/.claude/ tree [verify: code-only]
  - [X] 5.3 Confirm `dev:research:examine` and `dev:research:verify`
    resolve as skills in a fresh session (after install) [verify: manual-run-user]
    → both resolve as skills in this fresh session: the startup
      available-skills list includes `dev:research:examine` and
      `dev:research:verify`. Install confirmed live [live] (2026-06-17)
