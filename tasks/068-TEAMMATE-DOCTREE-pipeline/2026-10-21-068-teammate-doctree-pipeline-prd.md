# 068: Build the Doc Tree with Agent Teammates — PRD

**Status**: Draft — amended after two independent critiques
**Created**: 2026-10-21
**Task**: 068-TEAMMATE-DOCTREE-pipeline
**Author**: Claude (via embo workflow analysis)

---

## Terminology (binding on the rest of this document)

Earlier drafts used "teammate" and "subagent" interchangeably. They are
different primitives with different model, resume and nesting rules, and
the difference is load-bearing here. This document uses:

- **Spawned agent** — the primitive-neutral term. Used wherever a
  requirement holds regardless of which primitive implements it.
- **Subagent** — an in-process agent spawned via the Agent tool.
- **Teammate** — a separate full session under
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.
- **Workflow stage** — an agent run by a Dynamic Workflow script.
- **Lead** — the session that spawns the others. It is the user's main
  session; there are no nested teams.

**Which primitive this feature uses is NOT decided in this PRD.** It is
the tech-design's first decision (see Open Decisions). Requirements are
written to hold whichever is chosen.

## Wider Context / Higher Goal

Producing a feature's doc tree (PRD → tech-design → tasks) with a team
of agents is already something the user does — by typing a bespoke
teammate brief into the closing choice of another command: which phase
gets which model, that every teammate must run `/embo:start` without
choosing a task, that the task phase must not stop for approval between
subtasks, and that both independent reviews always run.

The goal, in the user's stated priority order:

1. **A repeatable, enforced pipeline** (primary) — the brief becomes a
   shipped mechanism instead of prose retyped per feature. This is the
   "Enforce, Don't Ask" principle applied to the planning workflow: a
   procedure the user must restate every time is evidence of a missing
   mechanism.
2. **Better docs through independent review** — each phase is authored
   by a fresh context and checked by reviewers that did not write it, so
   no phase grades its own work.
3. **Main context stays free** — the doc-tree bulk never enters the
   user's session.
4. **Speed** — phases overlap instead of running strictly end to end.

## Context

The user's current workflow is to invoke `/embo:prd`, `/embo:tech-design`
and `/embo:tasks` in sequence, or to hand-write a multi-teammate brief
describing the same sequence. Each phase re-reads the repository in the
main session, and each approval gate is a separate interaction.

### Current State (observed)

**The three phase commands are interactive by construction.** This is
the central constraint and the earlier draft missed it:

- `plugin/commands/prd.md:99-102` makes `AskUserQuestion` MANDATORY
  ("you MUST ask clarifying questions"), and `prd.md:471-479` waits for
  user approval — verified via: those lines, 2026-10-21
- `plugin/commands/tech-design.md:133` and `:371`, and
  `plugin/commands/tasks.md:91`, also require `AskUserQuestion` —
  verified via: those lines, 2026-10-21
- `plugin/hooks/subagent-rules.sh:19-21` states that question tools
  "reach no one" from a spawned agent — verified via: those lines,
  2026-10-21
- `AskUserQuestion` is removed from every subagent, even when listed in
  its `tools` — verified via:
  https://code.claude.com/docs/en/sub-agents#available-tools, read
  2026-10-21 against Claude Code 2.1.306
- Whether an in-process teammate has `AskUserQuestion` is NOT documented
  — [assumption, verify by probe; two independent doc passes failed to
  settle it]

Consequence: a spawned agent running `/embo:prd` today either stalls or
silently skips a mandatory step. FR-1's "do not reimplement the phase
commands" and FR-2/FR-8's unattended operation cannot both hold without
an unattended mode (FR-11).

**Platform facts** (verified against Claude Code 2.1.306, docs read
2026-10-21):

- Per-invocation model override for a subagent EXISTS: precedence is
  (1) per-invocation parameter, (2) definition frontmatter, (3)
  `CLAUDE_CODE_SUBAGENT_MODEL`, (4) main model — verified via:
  https://code.claude.com/docs/en/sub-agents#choose-a-model. The
  precedence order is gated at v2.1.251+.
- Accepted values include `sonnet`, `opus`, `haiku`, `fable`, full model
  IDs and `inherit` — verified via: same source
- `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (v2.1.257+) DISABLES the
  per-agent override entirely — verified via: same source
- An organization `availableModels` allowlist can substitute a
  different model — [assumption, verify in tech-design]
- For teammates the model is named in the spawn prompt in natural
  language and fixed at spawn; precedence is spawn prompt > definition >
  `CLAUDE_CODE_SUBAGENT_MODEL` > lead model — verified via:
  https://code.claude.com/docs/en/agent-teams#specify-teammates-and-models
- Agent teams are EXPERIMENTAL, off by default
  (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), interactive sessions only
  (not `-p` or SDK), allow NO NESTED TEAMS (only the lead spawns
  teammates), and are not restored by `/resume` or `/rewind` — verified
  via: https://code.claude.com/docs/en/agent-teams#limitations
- Teammate permission prompts surface in the LEAD session mid-run —
  verified via: https://code.claude.com/docs/en/agent-teams#permissions
- **Dynamic Workflows** is a shipped primitive for this exact shape: a
  script holds the loop, branching and intermediate results so the
  caller's context holds only the final answer; it supports per-stage
  models, adversarial cross-review, resumable runs, a hard cap of 1,000
  agents per run, plugin-shipped `workflows/` directories, and `args`.
  Stages can write files (the script itself cannot); stages cannot use
  `AskUserQuestion` or nest workflows — verified via:
  https://code.claude.com/docs/en/workflows
- The JSON field name of the per-invocation model parameter is not
  documented — [assumption, verify against the installed Agent tool
  schema]

**Repository facts:**

- embo ships 18 flat commands plus 2 under `research/` — verified via:
  CLAUDE.md § Architecture, 2026-10-21 (an earlier draft cited
  `ls plugin/commands`, which also counts `research/` and
  `live-edit-panel.js` and does not establish the number)
- A shipped agent declares its model in YAML frontmatter, e.g.
  `model: haiku` — verified via: `plugin/agents/session-scout.md:5`,
  2026-10-21. Frontmatter PINS the model, so a per-run override must
  come through the spawn mechanism, not the definition.
- NO `model` key exists anywhere in `plugin/profiles/*.yaml`; the
  nearest existing field is `workflow.subagents` at
  `plugin/profiles/default.yaml:29-31` — verified via: grep over
  `plugin/profiles/`, 2026-10-21. An earlier draft claimed no new access
  mechanism was needed; that holds only for *reading* a field via
  `embo-profile get` (dotted paths, empty if absent —
  `plugin/bin/embo-profile:20-22`), and ignores the schema, the
  `/embo:profile` display, and its tests.
- `/embo:start` presents a next-action choice at
  `plugin/commands/start.md:705` — verified via: that line, 2026-10-21
- `plugin/commands/start.md` contains no teammate or inter-agent
  messaging concept — verified via: `grep -n "teammates\|team_name\|
  SendMessage" plugin/commands/start.md` returned no matches, 2026-10-21
- `plugin/commands/tasks.md` HAS an approval stop: Step 6 "Wait for
  Confirmation — Pause and wait for the user to respond with 'Go'" at
  `tasks.md:114-118`, restated at `:232` — verified via: those lines,
  2026-10-22. FR-11 must cover it. (Per-subtask gating during
  implementation is separate and lives in `impl.md`, which is out of
  scope.)
- `plugin/hooks/subagent-rules.sh:13` FAILS OPEN (`trap 'exit 0' ERR`),
  so a failure to inject rules is silent — verified via: that line,
  2026-10-22
- The rule-injection hook DOES fire for subagents and the rules DO
  arrive: a probe subagent reported the block "=== BINDING SUBAGENT
  RULES (you are a subagent: you have NO channel to ask the human —
  DECIDE, do not stall) ===" present in its context, delivered as
  SubagentStart hook context rather than in its prompt — verified via:
  probe run, 2026-10-22 (P-2)
- A spawned subagent does NOT have `AskUserQuestion`, in either its
  loaded or deferred tool list — verified via: probe run, 2026-10-22
  (P-1)
- A spawned subagent has NO mechanism to invoke a slash command
  directly; `Skill(skill="embo:start")` DOES load the command body into
  its context, so the Skill tool is the only path — verified via: probe
  run, 2026-10-22 (P-3)
- A spawned agent's permission prompts DO surface in the main session
  mid-run, so an un-allowlisted tool call stalls a phase and waits for a
  human — verified via:
  https://code.claude.com/docs/en/sub-agents, 2026-10-22. Consequently
  `subagent-rules.sh:21` ("Question tools and approval prompts reach no
  one") is accurate about questions and WRONG about approval prompts;
  correcting it affects every existing embo agent and is tracked
  separately from this feature.
- Task 044 excludes "Agent teams / workflow orchestration beyond the
  Agent tool" at `tasks/044-SUBAGENT-UTILIZATION-spawn-where-beneficial/2026-07-21-044-subagent-utilization-prd.md:201`,
  excludes new agent definitions at `:198`, and is suggest-first with no
  auto-spawn at `:199` — verified via: those lines, 2026-10-21. (An
  earlier draft cited `:16`, which describes 044's own approach rather
  than the exclusion.)
- Whether `SubagentStart` fires for teammates is NOT documented —
  [assumption, verify by probe]
- Whether a spawned agent can invoke a slash command such as
  `/embo:start` is NOT documented; subagents can invoke plugin skills
  via the Skill tool, but a definition's `skills` field is not applied
  to teammates — [assumption, verify by probe]

### Past Similar Features (from claude-mem)

- **Task 044 (Subagent Utilization)** established the delegation
  decision framework and the thresholds (≥10 files, ≥3 independent
  items) that justify spawning. **Relationship to this task:** 044 is
  suggest-first with no auto-spawn (`:199`) and excludes both agent
  teams / workflow orchestration (`:201`) and new agent definitions
  (`:198`). 068 is therefore not an amendment to 044 but its
  **explicit-invocation counterpart**: where 044 suggests a single
  spawn and waits for consent, 068 spawns roughly ten agents, and the
  user's single command invocation IS that consent.
- **Task 055 (Subagent Rule Inheritance)** shipped the `SubagentStart`
  hook that injects judgment rules into every spawned agent, and
  established the task-list convention of a blocking Story 0 probe for
  unverified harness assumptions. This feature depends on that hook for
  rule inheritance and reuses the Story 0 pattern for its own harness
  assumptions.

## Problem Statement

**Who**: the embo user starting a new feature.

**What**: building the doc tree requires either three sequential
commands with a separate approval gate each, or a hand-written teammate
brief that must restate the same six constraints (phase order, model per
phase, `/embo:start` without task choosing, no stop between subtasks,
both reviews always, follow embo rules) every single time.

**Why**: the brief is prose, so it is retyped, varies between runs, and
is silently dropped under load — the exact failure mode embo exists to
remove. Sequential phases also pay full main-context cost and serialize
work that partially overlaps.

**When**: at the start of every feature that needs a doc tree.

## Goals

### Primary Goal

One command produces a complete, internally consistent doc tree
(PRD, tech-design, task list) via agent teammates, with the phase
order, model assignment, and rule inheritance enforced by the
mechanism rather than by the user restating them.

### Secondary Goals

- Each phase is reviewed by two independent passes (internal and
  external) that did not author it.
- Findings flow backwards: a tech-design finding can amend the PRD, and
  a review finding can reopen any earlier phase, with a bounded number
  of replay rounds.
- The doc-tree bulk stays out of the user's main context.
- Phases overlap where the dependency allows, rather than running
  strictly end to end.

## The Pipeline (core deliverable)

The three phases form a dependency chain, so they run as a pipeline —
but not a strictly forward one. Two behaviors make it a pipeline with
feedback rather than a simple sequence:

1. **Back-pressure.** Tech-design regularly discovers that a PRD
   requirement is infeasible, or already satisfied by existing code.
   Those findings amend the PRD, and the PRD phase re-runs on just the
   affected sections. Without this channel the doc tree ends internally
   inconsistent — and `/embo:impl` then builds from the inconsistency.
2. **Partial replay from reviews.** Reviews deliver findings to every
   phase, so a finding on the task list can reopen tech-design and one
   on tech-design can reopen the PRD. Each replay re-runs only the
   affected sections, not the whole phase.

**Back-pressure is unproven prior art, and is conditional on
grounding.** No surveyed tool (GitHub Spec-Kit, Superpowers,
BMAD-METHOD, shinpr/claude-code-workflows) ships automated upstream
amendment; every one keeps a human gate between phases. Spec-Kit's
nearest equivalent inserts `[NEEDS CLARIFICATION]` markers that halt
the plan — the same idea as this PRD's blocked items (FR-8), but
without the automatic amendment.

So this is a differentiator with no reference design, and the known
failure mode is error cascade: an ungrounded reviewer finding amends
the PRD, and downstream agents then treat the amendment as established
fact. Back-pressure is therefore permitted ONLY with all three of
FR-6's grounding conditions (evidence citation, revert path, round
cap). Without them it is not a differentiator but the mistake the other
tools avoid.

**Early start was cut from v1.** An earlier draft had tech-design begin
on the "settled parts" of an unfinalized PRD. Combined with
back-pressure that creates an unaddressed ordering hazard: no single
writer per document, no staleness marker, no mechanical definition of
"settled", and no way to compute which downstream sections a changed
upstream section invalidates. It was the lowest-priority requirement,
so it is out of scope for v1 (see Out of Scope for what reinstating it
would require).

Inter-agent messaging may also contribute to quality by letting a later
phase ask an earlier one a clarifying question directly, rather than
guessing. This is a secondary benefit, not a requirement.

## User Stories

### Epic

As an embo user, I want one command to build a feature's whole doc tree
with a team of agents, so that the planning procedure I currently retype
is enforced by the tool and the result is reviewed by contexts that did
not write it.

### User Stories

1. **As an** embo user
   **I want** one command to run all three planning phases as teammates
   **So that** I do not restate the phase order and constraints per run

   **Acceptance Criteria**:
   - [ ] A single command invocation produces a PRD, a tech-design and a
         task list in the task directory
   - [ ] Every spawned agent loads session context (via the Skill tool
         or the chosen primitive's equivalent) and no agent emits a
         task-selection choice — asserted from the run transcript
   - [ ] The rule-injection hook's output is asserted present in each
         spawned agent's context by a test (not inferred from the hook
         being registered: `subagent-rules.sh:10` fails open, so a
         missing injection is otherwise silent)
   - [ ] No phase halts awaiting user input; a phase that would have
         asked records a blocked item instead

2. **As an** embo user
   **I want** the model for each phase to come from my profile, with a
   per-run override
   **So that** I can assign a strong model to design and a cheaper one
   to task breakdown without retyping it

   **Acceptance Criteria**:
   - [ ] Each phase's model is read from a profile field
   - [ ] A command argument overrides the profile for a single run
   - [ ] The shipped profiles each carry a per-phase assignment
   - [ ] The resolved assignment is reported before the run starts

3. **As an** embo user
   **I want** two reviews of each phase with different lenses, plus
   checks that need no judgement at all
   **So that** a phase is not graded only by contexts that share the
   author's biases

   **Acceptance Criteria**:
   - [ ] Both review passes run for each phase, always
   - [ ] The reviewers are the two passes of the `examine-advisor`
         agent (research and internal); `approach-validator` is a
         different kind of agent and is not one of them
   - [ ] The reviewers are spawned by the lead, never by the authoring
         agent (there are no nested teams, so an authoring teammate
         cannot spawn its own reviewers)
   - [ ] The two reviewers are given different lenses, not merely
         different contexts
   - [ ] Deterministic gates pass, requiring no model judgement: every
         requirement maps to at least one acceptance criterion, every
         cited `file:line` resolves, and every requirement appears in
         the tech-design's verification table
   - [ ] Review findings carry a phase, a target section, a severity
         and a status (open / resolved)
   - [ ] Findings are recorded in the doc tree, not only in chat

   - [ ] The reviewer model family is read from a profile field, so a
         profile may configure cross-family review

   **Known limit** (mitigated, not eliminated): reviewers of the same
   model family as the author show measurable self-preference bias
   (https://arxiv.org/html/2410.21819v1), and same-model generator and
   reviewer pairs can form agreement loops. Fresh context does not
   remove this. Two mitigations ship: the deterministic gates, which are
   immune to the bias entirely, and a profile field for the reviewer
   family, so a profile that values accuracy over cost can run the
   research pass on a different family.

4. **As an** embo user
   **I want** downstream findings to amend upstream documents, with
   evidence
   **So that** the doc tree converges on something true rather than
   propagating a plausible error

   **Acceptance Criteria**:
   - [ ] A tech-design finding that contradicts the PRD amends the PRD
   - [ ] Every amendment cites evidence — a `file:line` or a URL — and
         an amendment without one is rejected
   - [ ] The pre-amendment state is saved, so any amendment can be
         reverted
   - [ ] A replay re-runs only the sections the findings target, as
         identified by each finding's target-section field
   - [ ] No finding of severity "infeasible" remains open against a PRD
         requirement at the end of the run
   - [ ] Each amendment records which phase and which finding triggered
         it

5. **As an** embo user
   **I want** the run to stop for my approval rather than loop
   **So that** replays terminate predictably and within budget

   **Acceptance Criteria**:
   - [ ] "Significant" is defined as a severity threshold in the
         findings schema, and "one round" as one full pass of both
         reviewers over all three phases
   - [ ] Replays continue while reviews return findings at or above
         that threshold
   - [ ] After the second review round the run stops and asks for
         approval regardless of remaining findings
   - [ ] A token or agent budget is enforced outside the model, as a
         backstop independent of the round count
   - [ ] Unresolved findings at that point are written into the docs as
         open items; this closing write is bookkeeping and triggers no
         further review round
   - [ ] The number of rounds taken and the budget consumed are
         reported

6. **As an** embo user
   **I want** questions that need me collected rather than guessed
   **So that** an unattended run does not build on a wrong assumption

   **Acceptance Criteria**:
   - [ ] Spawned agents decide everything decidable without stopping
   - [ ] What an agent cannot resolve is recorded as an explicit
         blocked item
   - [ ] The run completes rather than stalling on a blocked item
   - [ ] All blocked items are presented together at the end
   - [ ] The escalation behavior is configured by a profile field

7. **As an** embo user
   **I want** the run to be genuinely unattended once it starts
   **So that** I am not interrupted by permission dialogs mid-run

   **Acceptance Criteria**:
   - [ ] The pre-launch report lists the exact permission rules the run
         needs (writes to the task directory, the Bash wrappers, the
         MCP tools)
   - [ ] The run refuses to start when a required rule is missing,
         naming what to add, rather than starting and stalling
   - [ ] A precondition check verifies that the review agents' required
         MCP server is reachable, because the research pass silently
         degrades to reasoning-only without it

## Requirements

### Functional Requirements

1. **FR-1**: One command runs the three planning phases as spawned
   teammates and writes their outputs to the feature's task directory.
   - **Priority**: High
   - **Rationale**: the primary goal
   - **Dependencies**: the three existing planning commands

2. **FR-2**: Every spawned agent loads session context before working,
   and no agent emits a task-selection choice.
   - **Priority**: High
   - **Rationale**: an agent that stops to choose a task defeats
     unattended running
   - **Dependencies**: the session-context load; the mechanism by which
     a spawned agent invokes it is a probe (slash-command invocation
     inside an agent is undocumented; the Skill tool is the documented
     path for plugin skills)

3. **FR-3**: Every spawned agent inherits the embo behavioral rules,
   and the injection is asserted rather than assumed.
   - **Priority**: High
   - **Rationale**: the rules are what make the output embo-shaped, and
     the injection hook fails open, so a missing injection is silent
   - **Dependencies**: the rule-injection hook; whether it fires for
     the chosen primitive is a probe

4. **FR-4**: Each phase's model is resolved from a profile field, with
   a command argument overriding it for one run. The profile schema is
   extended to carry the assignment, and the profile display is updated
   to show it.
   - **Priority**: High
   - **Rationale**: user's explicit choice. No model field exists in the
     profiles today, so this is a schema change across all shipped
     profiles, not just a read.
   - **Dependencies**: profile read/display/tests; the spawn
     mechanism's model override, whose form differs by primitive

5. **FR-5**: Two review passes with different lenses run for each phase,
   always, spawned by the lead and never by the authoring agent;
   supplemented by deterministic gates that require no model judgement.
   - **Priority**: High
   - **Rationale**: secondary goal 2; "always run both" is explicit in
     the user's brief. Same-family reviewers have measurable agreement
     bias, so fresh context alone does not deliver independence.
   - **Dependencies**: the `examine-advisor` agent's two passes

6. **FR-6**: Downstream findings amend upstream documents, re-running
   only the sections those findings target. Every amendment cites
   evidence (`file:line` or URL) and is revertible from saved
   pre-amendment state; an amendment without evidence is rejected.
   - **Priority**: High
   - **Rationale**: without the channel the tree ends inconsistent;
     without the grounding the channel propagates confident errors
     upstream. No surveyed tool ships this, so it is unproven.
   - **Dependencies**: FR-1, FR-7

7. **FR-7**: Replays continue while reviews return findings at or above
   a defined severity threshold; the run stops for approval after the
   second review round regardless; and a token or agent budget is
   enforced outside the model as an independent backstop. "Significant"
   and "round" are defined in the findings schema.
   - **Priority**: High
   - **Rationale**: the termination rule. A cap enforced in prose is
     not a cap — a published multi-agent system over-spawned until
     given explicit effort limits enforced outside the model.
   - **Dependencies**: FR-5, FR-6

8. **FR-8**: Spawned agents proceed on anything decidable and record
   what they cannot resolve as explicit blocked items, presented
   together at the end. The behavior is set by a profile field.
   - **Priority**: High
   - **Rationale**: no spawned agent can ask the user mid-run
   - **Dependencies**: profile read

9. **FR-9**: *Withdrawn in v1 — early start. See Out of Scope.*

10. **FR-10**: The resolved configuration (primitive, phase order, model
    per phase, escalation mode, round cap, budget) and the permission
    rules the run requires are reported before the run starts. The run
    refuses to start when a required permission rule or a required MCP
    server is missing.
    - **Priority**: High
    - **Rationale**: an unattended run must be inspectable before it
      burns tokens, and a missing permission rule turns an unattended
      run into a stalled one. Raised from Medium: without the refusal,
      FR-2 and FR-8 do not deliver unattended operation.
    - **Dependencies**: FR-4, FR-8

11. **FR-11**: Each phase runs in an unattended mode in which its
    mandatory clarifying question and its approval stop are replaced by
    recording a blocked item.
    - **Priority**: High
    - **Rationale**: the three phase commands mandate `AskUserQuestion`
      and an approval stop, so without this mode a spawned agent either
      stalls or silently skips a mandatory step. This is the blocker
      that makes FR-1, FR-2 and FR-8 jointly satisfiable.
    - **Dependencies**: the three phase commands
    - **Note**: this modifies the phase commands' *control flow*, not
      what they produce. See Out of Scope.

12. **FR-12**: A run-state artifact in the task directory records the
    round number, per-phase status, and open findings, and a resumed
    run reads it.
    - **Priority**: Medium
    - **Rationale**: NFR-4's resumability is otherwise undefined for the
      replay loop — a restart cannot tell which round completed
    - **Dependencies**: FR-7

### Non-Functional Requirements

1. **NFR-1**: Cost — the run's token cost is reported on completion, and
   the configuration is visible before launch. Published reference
   points, cited separately because they use different baselines:
   teammates in plan mode use roughly 7x a standard session
   (https://code.claude.com/docs/en/costs); Anthropic reports agents at
   roughly 4x a chat and multi-agent systems at roughly 15x a chat. No
   published figure covers this exact shape (3 authors, 6 reviews, up to
   2 replay rounds), so the real multiple is measured by a pilot run
   rather than asserted. Replay rounds are the dominant multiplier.
2. **NFR-2**: Graceful degradation — the command fails loudly, naming
   the reason and the sequential fallback, rather than silently running
   fewer phases or reviews. Covers at least: the experimental flag
   being off, a required MCP server unreachable, a missing permission
   rule, a model override suppressed by
   `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, and a model silently
   substituted by an organization allowlist.
3. **NFR-3**: Context economy — phase output reaching the lead session
   is a digest, not the full document bulk. The lead is the user's main
   session, so this is the only thing keeping the bulk out of it.
4. **NFR-4**: Resumability — a run interrupted between phases leaves the
   documents written so far intact and usable, and the replay-loop state
   recoverable from the run-state artifact (FR-12).

### Technical Constraints

- Must integrate with the three existing planning commands rather than
  reimplementing their content rules. FR-11's unattended mode changes
  their control flow only; if the chosen primitive cannot invoke them
  at all (P-3), a stage may *reference* a command file as its
  instructions, which is not a reimplementation.
- Must follow the existing agent definition pattern and the existing
  rule-inheritance hook. Note that frontmatter pins an agent's model,
  so a per-run override comes through the spawn mechanism instead.
- Must read configuration through the existing profile access tool; the
  profile *schema* is extended (FR-4), which is a change to the
  profiles, not a new access mechanism.
- No spawned agent can prompt the user mid-run; every question that
  needs the user is hoisted before the run (FR-10) or collected after
  it (FR-8). Permission prompts are the exception — they reach the lead
  mid-run, which is why FR-10 refuses to start without the rules
  pre-approved.
- Must not reference internal task numbers or `tasks/` paths in any
  shipped command or agent file.

## Out of Scope

- **Implementation phase.** The pipeline stops at the task list;
  `/embo:impl` remains user-driven. Its one-subtask evidence gating
  conflicts with unattended running and needs its own treatment.
- **A general-purpose orchestration mechanism.** The reusable runner
  that any phase sequence could configure is a follow-on, to be built
  on the basis of this task rather than inside it.
- **Changing what each planning phase produces.** Document content
  rules stay with the existing commands. FR-11's unattended mode is a
  deliberate, narrow exception: it changes how a phase handles a
  question it cannot ask, not what the phase writes.
- **Parallel execution of the three phases.** They are a dependency
  chain.
- **Early start (the withdrawn FR-9).** Reinstating it would require,
  at minimum: one designated writer per document, a section-level
  dependency map, a staleness marker that any upstream amendment sets
  on dependent downstream sections, and a mechanical definition of
  "settled". Out of scope until back-pressure is proven in practice.

## Success Metrics

1. A feature's doc tree is produced by one command invocation with one
   upfront configuration report and one closing review, replacing the
   current per-phase gates.
2. The six constraints currently retyped per run are read from the
   profile or the command, and none needs restating by the user.
3. Every phase in a completed run carries findings from both review
   passes, each tagged with phase, target section, severity and status.
4. A completed run has no open finding of severity "infeasible"
   referencing a PRD requirement.
5. Every run terminates within the round cap AND the budget, reporting
   the rounds taken and the budget consumed.
6. Every amendment in a completed run carries a resolvable evidence
   citation.

## Decisions Taken (2026-10-22)

**OD-1 — RATIFIED: Dynamic Workflows**, with named subagents as the
shipped fallback. Teammates are rejected: experimental and off by
default, interactive-only, no nested teams, and not restored by
`/resume` (which contradicts NFR-4). Workflows make FR-7's budget cap,
NFR-3's context economy and NFR-4's resumability runtime properties
rather than prose the model must follow — the PRD's own primary goal.
Probes P-2 and P-4 confirmed a stage both receives the injected embo
rules and can write into the task directory, which were the two risks
that could have overturned this.

**Round cap is GLOBAL, not per phase.** A per-phase counter would allow
up to six rounds, and replay rounds are the dominant cost multiplier
(NFR-1). The cap exists to bound total cost, so it counts total rounds.

**Command name: `/embo:doctree`**, matching the flat `/embo:<name>`
convention of the other commands.

**The run is GIVEN its task directory and run date; it creates
neither.** The existing PRD phase already establishes the task
directory, so creating it here would duplicate that and risk a second
numbering scheme. The date must be passed in regardless, because a
workflow script cannot call `new Date()`.

**Reviewer model family is a PROFILE FIELD.** The two passes are
already structurally different (research vs internal, the internal pass
barred from the external corpus) and backed by deterministic gates, but
same-family reviewers retain measurable self-preference bias. Making
the family configurable lets a quality profile pay for cross-family
review while a fast profile does not. This extends FR-4's profile
schema work rather than adding a separate mechanism.

**OD-2 — FR-6 IS BUILT IN v1, fully gated.** Back-pressure ships only
with all three mechanical conditions enforced: every amendment cites
resolvable evidence (`file:line` or URL) and an uncited amendment is
rejected; the pre-amendment state is saved so any amendment is
revertible; and the global round cap bounds the loop. If any one of the
three cannot be built mechanically, FR-6 is withdrawn rather than
shipped ungrounded — a smaller feature, not a broken one. The risk
accepted: no comparable tool ships automated upstream amendment, so
there is no reference design and the gates are what stand between the
differentiator and an error-propagation channel.

## Open Decisions (remaining)

**OD-1 (resolved above) — original candidate comparison retained for
the record:**

| Candidate | For | Against |
|---|---|---|
| **Dynamic Workflow** | The loop, round cap, phase order, per-stage model and resume are code, not prose — which is this PRD's primary goal and embo's Enforce-Don't-Ask principle. Hard 1,000-agent cap. Ships in a plugin `workflows/` directory. Stages can write files. | Stages cannot use `AskUserQuestion` or nest workflows. Slash-command invocation from a stage is undocumented. Not confirmed by a real run writing into a plugin-managed directory. |
| **Teammates** | Closest to the workflow the user runs by hand today. Per-teammate model via the spawn prompt. | Experimental and off by default; interactive sessions only; no nested teams; not restored by `/resume`; permission prompts interrupt the lead mid-run. |
| **Subagents** | Documented per-invocation `model` parameter; the rule-injection hook is known to apply. | No built-in loop, cap or resume — the orchestration logic would be prose in a command file, which is the thing this feature exists to replace. |

The external review's recommendation was to prototype a workflow before
settling the tech-design. The decision belongs in the tech-design with
its evidence, not here.

**OD-2 — RESOLVED above: FR-6 is built in v1, fully gated.** It is the
feature's differentiator and no comparable tool ships it; the
alternative was the human gate between phases that every surveyed tool
keeps. The three grounding conditions are the condition of shipping it,
and FR-6 is withdrawn if any one cannot be built mechanically.

**No open decisions remain.** All questions raised by the two critiques
and the tech-design are settled.

## Probe Gate — RESOLVED 2026-10-22

All six probes were run. None invalidated a requirement; two changed how
one is built.

| # | Question | Result |
|---|---|---|
| P-1 | Does a spawned agent have `AskUserQuestion`? | **No** — absent from both the loaded and the deferred tool list. FR-8 confirmed necessary. |
| P-2 | Does the rule-injection hook fire? | **Yes** — probe agents reported the "BINDING SUBAGENT RULES" block present, delivered as SubagentStart hook context. Confirmed for plain subagents AND for workflow stages. FR-3 is satisfiable; the assertion test remains required because the hook fails open. |
| P-3 | Can a spawned agent invoke a slash command? | **No direct mechanism**, but `Skill(skill="embo:start")` loads the command body into the agent's context. The Skill tool is the path; FR-2 is buildable. |
| P-4 | Can a workflow stage write into the task directory without a prompt? | **Yes** — a stage wrote the file; no approval dialog surfaced and the call did not block. Caveat: an agent cannot observe a prompt auto-approved before reaching it, so this confirms "did not stall", not "no rule was consulted". |
| P-5 | The per-invocation model parameter | **`model`**, taking `sonnet`/`opus`/`haiku`/`fable`; first in the resolution order, ahead of frontmatter. Confirmed by use. |
| P-6 | Can a phase command take an unattended mode? | **Yes, cheaply** — all interaction points are prose instructions in Markdown, enforced by nothing mechanical. FR-11 is a conditional branch per instruction. |

**Correction surfaced by the probes, affecting NFR-2 and FR-10:**
permission prompts for a spawned agent DO surface in the main session
mid-run. So a run is unattended only with respect to *questions*; any
un-allowlisted tool call stalls a phase until a human answers. This is
why FR-10 refuses to start without the required rules pre-approved.

**Follow-on, outside this feature:** `subagent-rules.sh:21` tells every
spawned agent that "Question tools and approval prompts reach no one".
That is correct for questions and wrong for approval prompts. It
misleads every existing embo agent, not just this feature's, so it is
tracked separately rather than bundled here.

## References

### From Codebase (RLM / grep)

- `plugin/commands/prd.md`, `tech-design.md`, `tasks.md` — the phases
  being orchestrated
- `plugin/commands/start.md` — the session-context load every teammate
  must run; also the source of the behavioral rules
- `plugin/agents/session-scout.md:5` — the frontmatter model-declaration
  pattern
- `plugin/agents/examine-advisor.md`, `approach-validator.md` — the two
  existing independent-review agents
- `plugin/bin/embo-profile` — profile field access
- `plugin/hooks/subagent-rules.sh` — rule inheritance into spawned agents

### From History (Claude-Mem)

- Task 044 — delegation thresholds; the explicit-invocation counterpart
  relationship (044 prd:198-201)
- Task 055 (Subagent Rule Inheritance) — the rule-injection hook and the
  blocking probe-gate convention for unverified harness assumptions

### External (verified 2026-10-21 against Claude Code 2.1.306)

- https://code.claude.com/docs/en/sub-agents — tool removal,
  per-invocation model precedence
- https://code.claude.com/docs/en/agent-teams — teammate models,
  permissions, limitations
- https://code.claude.com/docs/en/workflows — the Dynamic Workflow
  primitive
- https://code.claude.com/docs/en/costs — the 7x plan-mode figure
- https://www.anthropic.com/engineering/multi-agent-research-system —
  over-spawning without externally enforced effort limits
- https://arxiv.org/html/2410.21819v1 — same-family judge
  self-preference bias

### Prior art surveyed

- **GitHub Spec-Kit** — sequential phases through one agent, human
  review between steps, `[NEEDS CLARIFICATION]` markers that halt the
  plan (the nearest equivalent of FR-8's blocked items)
- **Superpowers** — two review gates per task (spec compliance, then
  code quality), human sign-off on the design
- **BMAD-METHOD** — role handoffs through files
- **shinpr/claude-code-workflows** — independent consistency review,
  then stop for approval
- **Oh-My-ClaudeCode** — not surveyed

None ships automated upstream amendment; all keep a human gate between
phases.

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/embo:tech-design` to create the technical design
3. Run `/embo:tasks` to break it down
