# 068: Build the Doc Tree with Agent Teammates — Technical Design

**Status**: Draft (v1)
**PRD**: [2026-10-21-068-teammate-doctree-pipeline-prd.md](./2026-10-21-068-teammate-doctree-pipeline-prd.md)
**Created**: 2026-10-21
**Verified against**: Claude Code 2.1.306 (`claude --version`, 2026-10-21)

> **PRD revision note.** The PRD was amended twice while this design was
> being written. This document is written against the final amended PRD
> (Status: "Draft — amended after two independent critiques"), and uses
> its binding **Terminology**: *spawned agent* is primitive-neutral,
> *subagent* / *teammate* / *workflow stage* are distinct, and *lead* is
> the user's main session. This design settles **OD-1** (which
> primitive) in **D1**, answers **OD-2** (is back-pressure worth
> building) in **D12**, and maps the PRD's blocking **Probe Gate
> (P-1…P-6)** onto Story 0.
>
> Where this design and the amended PRD reached the same conclusion
> independently — the `AskUserQuestion` removal, the model-override
> precedence, the agent-teams limitations, cutting FR-9, requiring an
> unattended phase mode and a run-state artifact — that agreement is
> noted rather than re-derived. Two PRD citations are corrected below
> (`tasks.md` approval stop; `subagent-rules.sh` fail-open line).

## Overview

Ship one command, `/embo:doctree`, that drives the three planning phases
(PRD → tech-design → tasks) as independently-spawned agents, each
authored by a fresh context and checked by two review passes that did
not write it. The command is a **thin orchestrator**: all document
content rules stay in the existing phase commands; the orchestrator owns
the state machine, the model resolution, the write targets, the budget
backstop, and the back-pressure channel.

Four facts resolved during this design shape everything below:

1. **PRD assumption (a) is PARTLY REFUTED.** A spawned agent genuinely
   cannot *ask a question* — `AskUserQuestion` is stripped from every
   subagent — but it *can* raise a **permission prompt**, which is
   surfaced to the user and blocks that agent until answered. "Cannot
   prompt the user mid-run" is true for questions and false for
   permissions; an unattended run can still stall on a permission gate.
   See **A1**, **D6**, and FR-10's refusal-to-start.
2. **PRD assumption (b) is CONFIRMED.** A per-invocation `model`
   parameter exists and is **first** in the resolution order. FR-4 is
   buildable, with three documented suppression paths. See **A2**.
3. **Agent teams are the wrong primitive**, and the amended PRD now
   agrees. Experimental, off by default, interactive-only, no nested
   teams, no `/resume`. See **A3**.
4. **Dynamic Workflows is the right primitive** — a shipped runtime
   purpose-built for this exact shape (a script holds the loop and the
   intermediate results; the caller's context holds only the final
   answer). It delivers FR-7's out-of-model cap, NFR-3's context economy
   and NFR-4's resumability *structurally*, where the subagent route
   delivers them by prose the model must follow. See **A4** and **D1**.

No Story 0 probe is required for assumptions (a) or (b): the docs settle
both. A narrower Story 0 remains for what the docs do **not** settle —
whether `SubagentStart` fires for workflow stages (FR-3 is unverifiable
without it), and whether a stage can invoke an embo phase command.

## Current Architecture (verified)

Every row below was re-read in this worktree on 2026-10-21. Claims about
harness behavior cite the docs, never memory.

### The three phases being orchestrated

| Phase | File | Lines | Interactive gate that must be suppressed |
|---|---|---|---|
| PRD | `plugin/commands/prd.md` | 479 | Step 4 "Ask Clarifying Questions (MANDATORY)" — `AskUserQuestion` (`prd.md:99-102`); Step 4a is its own preceding call (`prd.md:105-108`) |
| tech-design | `plugin/commands/tech-design.md` | 344 | Step 5 "Ask Technical Clarifying Questions (MANDATORY)" — `AskUserQuestion` (`tech-design.md:130-132`) |
| tasks | `plugin/commands/tasks.md` | 261 | Step 4 "Resolve Scope Uncertainties (MANDATORY)" (`tasks.md:87-91`) **and** Step 6 "Wait for Confirmation" — pause for the literal string "Go" (`tasks.md:114-118`) |

All three therefore **block by design** on a tool a subagent does not
have. This is the single largest piece of work in the feature and the
PRD does not name it. See **D3** and **Open question Q1**.

Each phase already writes to a predictable path:
`tasks/{jira-id}-{feature}/{date}-{jira-id}-{feature}-{phase}.md`
— verified `tech-design.md:352-356`, `prd.md:351` (Step 6 "Save PRD to
File System"), `tasks.md:149` (Step 9).

### The session-context load every phase must run

`plugin/commands/start.md` (740 lines) is the context load. Two
properties matter:

- Its closing step is **mandatory and interactive**: "Close the summary
  with the next-action choice via `AskUserQuestion` (per
  RULE:CLEAR-OPTIONS): the recommended task, plus at minimum 'review
  critically / wrap up / tell me what to do'" — `start.md:706-708`.
  This is exactly the "task-selection choice" FR-2 forbids, and it is
  unreachable in a subagent anyway.
- Its `allowed-tools` frontmatter lists `AskUserQuestion`
  (`start.md:3`).

So "every teammate runs `/embo:start`" (FR-2) cannot mean "runs it
unmodified": the last step is both impossible and forbidden for a
spawned phase. See **D4**.

`start.md` is also the single source of the behavioral rules: 6
`CHECKLIST:` regions at lines 92, 155, 225, 388, 515, 597 and ~14
`RULE:` blocks (verified via
`grep -n 'CHECKLIST:\|RULE:' plugin/commands/start.md`, 2026-10-21).

### Rule inheritance (FR-3) — already shipped, no work needed

`plugin/hooks/subagent-rules.sh` is a registered `SubagentStart` hook
(`plugin/hooks/hooks.json:28-38`). It extracts the `WITHSTAND-CRITICISM`
and `AVOID-APPROVAL` checklists from `start.md`, prepends a static
`[SUBAGENT DECIDE-OR-ASK]` / `[SUBAGENT RESEARCH-VERIFY]` preamble, and
emits them as `hookSpecificOutput.additionalContext`
(`subagent-rules.sh:19-26,47-56`). Its preamble already states the
exact FR-8 behavior:

> "Question tools and approval prompts reach no one. Resolve every
> recoverable choice yourself with evidence … and state the choice +
> reason in your report. Never perform an irreversible or destructive
> action … — report it as a blocker instead of acting."
> — `subagent-rules.sh:21-24`

**FR-3 is satisfied by existing code.** The hook fires on every spawn
with matcher `*`; no change is required. One correction is warranted:
the preamble's "approval prompts reach no one" is **inaccurate** per A1
— approval prompts *do* reach the user. See **D6**.

### Profile access (FR-4, FR-8)

`plugin/bin/embo-profile` supports `show | get <field> | set | reset |
list` (`embo-profile:60-77` usage block). `get` reads a dotted path via
`yq` and **prints nothing for an absent or null field**
(`embo-profile:92-101`). That empty-string-on-absent behavior is what
makes a new field safely additive: an older profile without it yields
`""`, and the command falls back to a built-in default.

Search order: `.claude/profiles` → `~/.claude/profiles` → the plugin's
shipped `profiles/` (`embo-profile:57`). `get` reads the active profile
if set, else `default.yaml` (`embo-profile:95-97`).

Shipped profiles and their current shape (all five re-read 2026-10-21):
`default.yaml` (canonical fallback, mirrors quality), `quality.yaml`,
`fast.yaml`, `minimal.yaml`, `research.yaml`. Top-level keys are
`name`, `description`, `rules`, `git`, `tools`, `mcps`; `research.yaml`
additionally carries `rules.tone`. Only `default.yaml` carries per-field
explanatory comments — the others are bare.

### The two review agents (FR-5)

Both already exist and both are `model: sonnet` with
`permissionMode: acceptEdits`:

- `plugin/agents/examine-advisor.md:14-15` — document/decision critique.
  Runs as **two named passes**, `pass=research` (prior art via
  NotebookLM) and `pass=internal` (codebase/consistency); "The command
  passes the pass name as `pass=research` / `pass=internal`"
  (`examine-advisor.md:81`).
- `plugin/agents/approach-validator.md:12-13` — proves load-bearing
  claims against independent sources.

`examine-advisor` already emits precisely the FR-5 artifact: a findings
table `| Severity | Finding | Why it matters | Suggested improvement / fix |`
with severity `high | medium | low`, ordered high→low, plus a
recommendation and a bottom line (`examine-advisor.md:105-120`).
**No new review agent is needed** — the severity vocabulary FR-5
requires is already defined.

**The two reviewers are `examine-advisor`'s two passes, not
`examine-advisor` + `approach-validator`.** The amended PRD now states
this; the codebase confirms it. The passes carry genuinely *different
lenses*, which is what independence requires: `pass=research` judges
against prior art via NotebookLM, `pass=internal` judges against the
codebase and is forbidden from touching the external corpus — "its
independence depends on staying off the external corpus"
(`examine-advisor.md:78-80`). `approach-validator` is a different kind
of agent: it proves acceptance criteria before implementation
(`approach-validator.md:3-11`), which is `/embo:research:verify`'s job,
not a phase review. **It is given no role in this pipeline.**

**Independence is weaker than "two fresh contexts" implies.** Both
passes run the same model family (`sonnet`), and same-family judges
show self-preference bias, so fresh context alone does not deliver
independence. Two consequences for the design, both adopted:
different lenses are load-bearing rather than incidental (above), and
the pipeline adds **deterministic gates that need no model judgement at
all** (D13) — those are worth more than a third reviewer.

Its input contract is strict and the orchestrator must honor it: the
command MUST supply the goal, the constraints, what was tried/ruled out,
and (internal pass) repo context, because "You run blind to everything
except what the command passes you, and you cannot ask follow-ups"
(`examine-advisor.md:84-96`).

### The existing two-pass spawn pattern to copy

`plugin/commands/research/examine.md:62-66` is the reference: "Spawn
`examine-advisor` twice in parallel (Agent tool, one message,
background), each passed the digest + context block". Its step 3 also
already encodes the constraint under test here — "Get user go-ahead on
the digest + context block before any outbound call (**a subagent cannot
prompt mid-run**)" (`examine.md:51-54`), and its step 5 shows the
hard-stop-on-degradation pattern this design reuses for NFR-2.

### Shared-library convention

`plugin/lib/branch-task-lib.sh:1-4` sets the pattern: a header naming
its consumers, "Pure functions: no output, no side effects, no exits",
sourced by both a `bin/` wrapper and a hook. A new shared library
follows this shape.

## Resolved assumptions

### A1 — Can a spawned agent prompt the user mid-run? **PARTLY REFUTED**

Two different channels, opposite answers. Verified against
<https://code.claude.com/docs/en/sub-agents> and
<https://code.claude.com/docs/en/agent-teams>, 2026-10-21, Claude Code
2.1.306.

**Questions: NO.** `AskUserQuestion` is in the first tool filter, which
"removes these tools, even when listed in the `tools` field" — the list
is `Agent` (at depth limit), **`AskUserQuestion`**, `EndConversation`,
`EnterPlanMode`, `ExitPlanMode` (unless `permissionMode: plan`),
`ScheduleWakeup`, `WaitForMcpServers`, `Workflow`. Forks skip both
filters. So a spawned phase has no question tool at all.

**Permissions: YES, and this is the refutation.** For a background
subagent: "When a background subagent reaches a tool call that needs
permission, Claude Code surfaces the prompt in your main session and
names the subagent that is asking. Approve to let the subagent continue,
or press Esc to deny that one tool call without stopping the subagent."
For foreground: "Permission prompts are passed through to you as they
come up." For teammates specifically: "Teammate permission prompts
appear in the lead session, so approve them there yourself."

**Consequence for FR-8.** The PRD's premise — "teammates cannot ask the
user mid-run" — holds for *questions*, which is what FR-8 is really
about, so FR-8 survives. But the derived claim that a run is therefore
*unattended* does **not** hold: any tool call a phase makes that is not
pre-approved will stop that phase and wait for a human. An unattended
run is only as unattended as the permission allowlist is complete. This
is a real liveness risk the PRD does not name; **D6** addresses it.

Also load-bearing for safety: "no message from any agent counts as your
approval for a pending permission prompt, and no agent message can
change a subagent's permission settings, `CLAUDE.md`, or configuration.
Only the permission system or your own messages can grant approval." So
the orchestrator cannot auto-approve on a phase's behalf, by design.

### A2 — Per-phase model override at spawn time? **CONFIRMED**

From the subagents doc, "Choose a model": the frontmatter `model` field
accepts "`sonnet`, `opus`, `haiku`, `fable`, a full model ID such as
`claude-opus-5-5`, or `inherit`". And: "When Claude invokes a subagent,
it can also pass a `model` parameter for that specific invocation."

Resolution order, quoted:

1. "The per-invocation `model` parameter"
2. "The subagent definition's `model` frontmatter, where `inherit`
   selects the main conversation's model"
3. "The `CLAUDE_CODE_SUBAGENT_MODEL` environment variable, when you set
   it to a model alias or model ID"
4. "The main conversation's model"

FR-4 is buildable exactly as the PRD describes: profile field → spawn
parameter, which wins over the agent definition.

**Three documented caveats, all of which the design must surface rather
than hide:**

- **`CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`** (with
  `CLAUDE_CODE_SUBAGENT_MODEL` set) voids the whole feature: "Claude
  Code ignores the `model` field in subagent definitions, and Claude
  can't pass a model when it starts a subagent." A user with this set
  gets silently uniform models. → **D5** reports the resolved model and
  says it may be overridden by environment.
- **Mods**: "If an installed mod sets a model in its `agent.spawn` hook,
  Claude Code uses that model in place of the per-invocation parameter."
- **Org allowlist**: a blocked model is silently substituted (newest
  permitted in the family, else the lead's model).
- **Version gate**: "Before v2.1.251, `CLAUDE_CODE_SUBAGENT_MODEL` came
  first and overrode both the per-invocation parameter and the
  frontmatter." Installed version is 2.1.306, so the modern order
  applies here; a user on <2.1.251 gets different behavior.

### A3 — Should this use agent *teams*? **NO** (new finding, not in the PRD)

The PRD says "teammates" throughout. Taken literally that means the
agent-teams feature, which carries gates that defeat the PRD's own
goals. Quoting the agent-teams doc:

- "Agent teams are experimental and disabled by default. Enable them by
  setting `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` … Without that
  variable, no team is set up at session start, no team directories are
  written, and Claude does not spawn or propose teammates."
- "Spawning teammates also requires an interactive session. In
  non-interactive mode with the `-p` flag, including Agent SDK sessions,
  Claude doesn't spawn teammates."
- "**No nested teams**: teammates cannot spawn their own teammates. Only
  the lead can manage the team." — this alone kills the architecture if
  a phase needed to spawn its own reviewers.
- "**No session resumption with in-process teammates**" — directly
  contradicts NFR-4 (resumability).
- "Letting a team run unattended for too long increases the risk of
  wasted effort." — the doc's own best practice argues against the
  PRD's unattended framing.

What the PRD actually needs from "teammates" — an independent context
per phase, a per-phase model, inherited rules, and messaging between
agents — is all available from plain **named subagents**: "Subagents
that Claude named when it spawned them can also message each other", and
a name "keeps working as a `SendMessage` address".

**Decision: build on named subagents (Agent tool), not agent teams.**
The design keeps the PRD's intent and drops the term. Nothing about
FR-1…FR-10 requires a team. This is the single most consequential
divergence from the PRD and is flagged as **Open question Q4** for the
user to ratify.

### A4 — Dynamic Workflows as the primitive **CONFIRMED available; chosen**

Verified against <https://code.claude.com/docs/en/workflows>, read
2026-10-21 against Claude Code 2.1.306. A dynamic workflow is "a
JavaScript script that orchestrates many subagents at once … a runtime
executes it in the background while your session stays responsive."

Why it fits this feature better than hand-rolled subagent orchestration —
each row is a PRD requirement this primitive satisfies structurally
rather than by prose:

| PRD requirement | What Workflows gives |
|---|---|
| NFR-3 context economy | "A workflow script holds the loop, the branching, and the intermediate results itself, so Claude's context holds only the final answer." The digest discipline becomes a property of the runtime. |
| FR-7 out-of-model budget backstop | Hard runtime caps: "1,000 agents total per run", "Up to 16 concurrent agents by default", "Up to 4,096 items in a single `parallel()` or `pipeline()` call". These are enforced by the runtime, not by asking the model to count — exactly the PRD's "a cap enforced in prose is not a cap". |
| NFR-4 resumability | "The runtime tracks each agent's result as the run progresses, which is what makes a run resumable." Completed agents "return their saved result" on relaunch. |
| FR-4 per-phase model | "A model the script names for a stage counts as the per-invocation model in that order." Same precedence as A2. |
| FR-5 adversarial review | A named design goal: "it can have independent agents adversarially review each other's findings before they're reported." |
| FR-1 phase sequencing | `phase()` groups agents under a title in the progress view; `agent()`, `parallel()`, `pipeline()` compose the sequence. |
| Distribution | "Place the script in a `workflows/` directory at the plugin root" — namespaced as `/<plugin>:<name>`, so it ships as `/embo:doctree` the same way commands do. |
| FR-6 structured hand-off | `schema` on an `agent()` call makes the stage "return JSON matching the shape instead of prose", validated before the stage starts — the AMEND record (D7) becomes a schema, not a convention. |

**Constraints this imposes, all documented:**

- **"No mid-run user input"** — and the doc's own prescription matches
  the PRD's design: "For sign-off between stages, run each stage as its
  own workflow." A run "pauses on its own only for agent permission
  prompts and a usage-limit wait", which **corroborates A1's
  permission-stall finding** from a second source.
- **Stages cannot use `AskUserQuestion`** (they are subagents; A1's
  filter applies) and **workflows cannot nest**.
- **The script cannot touch the filesystem**: "No direct filesystem or
  shell access from the workflow itself … Agents read, write, and run
  commands. The script coordinates the agents." So every document write
  happens inside a stage, never in the orchestration layer. This is a
  real constraint on D7's validation: a malformed-record check must run
  either in-script as pure JS (no file reads) or inside a stage.
- **No module loading**, so `doctree-lib.sh` cannot be imported by the
  script; shared logic is either inlined as JS or invoked from a stage.
- **`Date.now()`, `Math.random()`, and no-arg `new Date()` throw**
  inside the script, to keep a relaunch deterministic — "Pass a
  timestamp in through `args` instead." The date in the document
  filename must therefore come from `args`, not be computed.
- **Availability gates**: "available on all paid plans … On Pro, turn
  them on from the Dynamic workflows row in `/config`"; disabled by
  `disableWorkflows` / `CLAUDE_CODE_DISABLE_WORKFLOWS=1` / managed
  settings. Launch needs approval (`Workflow` or `Workflow(<name>)` in
  allow rules for an unattended run). NFR-2 must cover "workflows are
  disabled" as a named degradation.
- **Failure semantics**: an `agent()` awaited directly ends the run on
  failure; inside `parallel()`/`pipeline()` it yields `null` and the run
  continues. A failed stage reruns "and so does every agent the script
  starts after it" on relaunch.

**Unverified for Workflows (→ Story 0):** whether `SubagentStart` fires
for workflow stages. FR-3 (rule inheritance) depends entirely on it, and
the hook fails open, so a non-firing hook is **silent**. This is the
single highest-value probe in the feature.

*Citation correction:* the amended PRD places the fail-open at
`subagent-rules.sh:10`; the `trap 'exit 0' ERR` is at
**`subagent-rules.sh:13`** (verified via
`grep -n "trap 'exit 0'" plugin/hooks/subagent-rules.sh`, 2026-10-21).
The PRD's point stands — only the line number is off.

### A5 — Can a spawned agent run a slash command? **UNVERIFIED — Story 0**

FR-2 says each phase "runs `/embo:start`", and FR-1 implies each phase
runs `/embo:prd` etc. The docs confirm a background subagent keeps the
`Skill` tool, and embo's phases are exposed as skills
(`embo:prd`, `embo:start`, … per the session skill listing), which
*suggests* a phase can invoke them. But I found no authoritative
statement that a subagent can invoke a project slash command, nor that
invoking a skill whose body contains `AskUserQuestion` steps degrades
gracefully rather than stalling. **Marked provisional.** Story 0
probes it; **D3** gives the fallback that does not depend on it.

## Past Decisions (claude-mem)

Claimed from the PRD's history section and this repo's task tree; not
independently re-queried from claude-mem in this pass (noted as a gap).

- **Task 044** — delegation thresholds (≥10 files, ≥3 independent items)
  and the fan-out cost economics. This feature is well above the
  threshold; the cost figures are why NFR-1 (report cost) and D5 (report
  config *before* launch) are not optional niceties.

  **Scope relationship, with verified citations.** 044's Out of Scope
  excludes "New specialized agent definitions"
  (`044-…-prd.md:198`), "Auto-spawning of any kind (user chose
  suggest-first)" (`:199`), and "Agent teams / workflow orchestration
  beyond the Agent tool" (`:201`) — all three verified via
  `sed -n '196,202p'`, 2026-10-21. This design does all three things
  044 excluded, so the relationship must be stated rather than
  glossed: **068 is the explicit-invocation counterpart to 044's
  suggest-first framing.** 044 governs when Claude *proposes* a spawn
  unprompted; here the user's single command invocation *is* the
  consent for roughly ten spawns, reported before launch (D5) and
  budget-capped (D8). The exclusions bound 044's own deliverable, not
  the repo's future direction.
- **Task 055** — shipped `subagent-rules.sh` and established that a
  harness assumption gets a **blocking Story 0 probe** before any code.
  This design follows it, but narrows the probe: 055 probed what docs
  could not answer; here the docs answered (a) and (b), so only A4 and
  the permission-stall risk remain to probe.
- **Task 047** — inject verbatim rule *text*, not rule names, because a
  name triggers memory reconstruction that drops atypical clauses. The
  same logic applies to phase dispatch prompts: **D3** passes the
  suppression directives as explicit text, not "follow the usual rules".

## Proposed Design

### Architecture

The command resolves configuration and launches the workflow script; the
script holds the loop. Stages do all file I/O (A4).

```
/embo:doctree <feature-slug> [--model-<phase>=<alias>] [--escalation=<mode>]
   │
   ├─ 0. resolve config (embo-profile get + arg overrides)
   │     + FR-10 pre-flight: required allow rules, MCP servers, workflows enabled
   │                                              ──► report, REFUSE or STOP for go-ahead
   │
   ├─ 1. spawn phase: PRD          ─► doctree-phase agent (model: per-config)
   │        └─ writes  ...-prd.md
   │        └─ returns digest + BLOCKED[] + AMEND[]
   │
   ├─ 2. review round: examine-advisor ×2  (pass=internal, pass=research)
   │        └─ findings table (severity high/med/low)
   │        └─ high-severity finding naming an UPSTREAM phase ──► AMEND queue
   │
   ├─ 3. spawn phase: tech-design  ─► may emit AMEND targeting the PRD  (FR-6)
   │        └─ AMEND ──► re-spawn PRD phase in SECTION-SCOPED mode
   │
   ├─ 4. review round ×2  ──► same
   ├─ 5. spawn phase: tasks        ─► may AMEND tech-design or PRD
   ├─ 6. review round ×2
   │
   ├─ replay controller: while (significant findings) and (round < cap)
   │                      and (agents_spawned < budget.max_agents) → replay
   │                      at cap → STOP, ask approval                     (FR-7)
   │                      run-state artifact updated each round           (FR-12)
   │
   └─ 7. closing report: rounds taken, all BLOCKED[] items, token cost    (FR-8, NFR-1)
```

### Design decisions

- **D1 — a plugin-shipped Dynamic Workflow, with named subagents as the
  documented fallback** [resolves A3, A4]. The orchestration ships as
  `plugin/workflows/doctree.js`, running as `/embo:doctree`. Rationale:
  three of the PRD's hardest requirements — the out-of-model budget cap
  (FR-7), context economy (NFR-3) and resumability (NFR-4/FR-12) — are
  *properties of the workflow runtime* but are only *prose the model
  must follow* in a hand-rolled subagent orchestration. In a repo whose
  stated core principle is "convert every rule into an external,
  deterministic enforcement mechanism", a primitive that enforces the
  cap in the runtime beats one that asks the model to respect it.

  **The fallback is not hypothetical**: workflows can be disabled per
  user or per organization (A4), so the command must detect that and
  degrade. The design therefore keeps the phase work in a reusable agent
  definition (`doctree-phase.md`, D2) that *both* paths spawn — the
  workflow script calls it per stage, and the fallback path spawns it
  from a command body. Only the orchestration layer differs, so the
  fallback is a thinner command, not a second implementation.

  Flagged as **Q4** for ratification: this is a larger divergence from
  the PRD's original "teammates" wording than named subagents would be,
  and it trades a familiar primitive for a more capable but
  newer/gated one.

- **D2 — one phase-runner agent definition, parameterized, not three**.
  `plugin/agents/doctree-phase.md` takes the phase name in its dispatch
  prompt. Rationale: the three phases differ in *which command body they
  follow* and *what they write*, not in how they are driven; three
  near-identical definitions would drift. The agent's `model:`
  frontmatter is set to `inherit` so that the per-invocation parameter
  (always supplied by the orchestrator) is the only thing that decides
  the model, and an unset profile field degrades to the main model
  rather than to a hardcoded alias.

- **D3 — suppress interactive gates by explicit directive in the
  dispatch prompt, and require a decision log** [the core of FR-2/FR-8;
  mitigates A5]. **Amended-PRD note:** FR-11 now requires "an unattended
  mode in which its mandatory clarifying question and its approval stop
  are replaced by recording a blocked item", and notes this "modifies
  the phase commands' *control flow*, not what they produce". That is a
  stronger commitment than D3's dispatch-prompt directive: it puts the
  mode **in the phase commands**, where it is enforced for every caller,
  rather than in a prompt each caller must remember to send. Taking the
  amended PRD as binding, FR-11 supersedes the dispatch-only approach:
  each phase command gains an explicitly documented unattended mode
  (guarded so interactive use is unchanged), and the dispatch prompt
  *selects* that mode rather than describing the behavior from scratch.
  D3's directive text below remains the content of that mode. The
  mechanical `decisions_taken` check applies either way.

  **Mode signal (set during implementation).** The selector is the
  environment variable `EMBO_DOCTREE_UNATTENDED`: when set to a non-empty
  value, each phase command takes its unattended branch (replace the
  mandatory `AskUserQuestion`, and for `tasks.md` the Step 6 "Go" stop,
  with a Decisions-taken / BLOCKED record); when unset, the interactive
  path is unchanged. An environment variable, not prose in the prompt, was
  chosen so the branch condition is mechanical and grep-verifiable (the
  FR-11 "fires only when the mode is set" check), matching the repo's
  existing env-override pattern (`EMBO_PROFILE_*`). The orchestration must
  set this variable for every spawned phase: the workflow script's
  `agent()` calls and the sequential fallback both carry it.

  The phase commands' mandatory `AskUserQuestion` steps
  (Current Architecture table) cannot execute in a subagent. The
  dispatch prompt therefore carries, as verbatim text (per task 047's
  lesson, not as "follow the rules"):
  - the phase command file to follow, **by path**, with the named steps
    to skip and what to do instead: for each question the step would
    have asked, decide it from evidence and record it in a
    **Decisions-taken** block in the output document, stating the choice
    and the evidence;
  - for `tasks.md` Step 6 ("Wait for Confirmation"): treat it as
    satisfied and continue to Step 7 — this is the PRD's "task phase
    does not stop for approval between subtasks";
  - anything not decidable from evidence → a `BLOCKED` item, never a
    guess, never a stall.

  This is deliberately **prose-in-prompt**, which the repo's own
  "Enforce, Don't Ask" principle distrusts. It is the weakest part of
  the design and is called out as such in **Risks**; the mechanical
  backstop is that a missing Decisions-taken block fails the
  orchestrator's output contract check (below), so a phase that silently
  skipped the questions is detected rather than trusted.

- **D4 — a non-interactive context load, not `/embo:start` verbatim**
  [FR-2]. `start.md` ends in a mandatory `AskUserQuestion`
  (`start.md:706-708`) that is both impossible and forbidden here. The
  dispatch prompt instructs the phase to perform `start.md`'s Batch A and
  Batch B context loads and **stop before the closing choice**, emitting
  the session summary into its own context only. FR-2's "does not present
  a task-selection choice" is thereby satisfied structurally — the agent
  has no tool with which to present one — rather than by asking nicely.
  The feature's task is pre-determined by the command argument, so the
  recommend-a-task step has no purpose.

- **D5 — report the resolved configuration before spawning anything, and
  stop for go-ahead** [FR-10, NFR-1, mitigates A2's caveats]. The
  orchestrator prints: phase order, model per phase **with its
  provenance** (argument / profile field / built-in default), escalation
  mode, round cap, and the target task directory. It then stops for the
  user's go-ahead — the one upfront gate the PRD's success metric #1
  asks for. The report names the known silent-override paths
  (`CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, mods, org allowlist) as a caveat
  line, because the orchestrator cannot detect them and a run that
  silently ignored the user's model choice is worse than one that warned.

- **D6 — permission-stall is a named, mitigated risk, not a silent one**
  [corrects A1's refutation]. Because a phase's un-allowlisted tool call
  surfaces a prompt and waits:
  - the configuration report (D5) states plainly that the run is
    unattended **only** to the extent that the phases' tool calls are
    pre-approved, and names the allowlist entries the phases rely on
    (`Bash(embo-profile *)`, `Bash(rlm_repl *)`, the two claude-mem MCP
    search tools, `Read`, `Write`, `Edit`);
  - the dispatch prompt instructs a phase to prefer the pre-approved
    shapes already used by the phase commands (bare `rlm_repl`, bare
    `embo-profile`) — the repo's existing reason for those wrappers
    (CLAUDE.md § Architecture / Commands);
  - `subagent-rules.sh`'s preamble line "Question tools and approval
    prompts reach no one" is **factually wrong** per A1 and should be
    corrected to distinguish the two channels. Flagged as a small
    follow-on edit, not bundled into this feature's scope — it changes
    behavior for every existing agent and deserves its own change.

- **D7 — back-pressure as a typed `AMEND` record, with the amending
  phase naming the target section** [FR-6]. This is the PRD's hardest
  requirement and the one where "affected sections only" is
  underspecified. Chosen mechanism: a phase (or a reviewer) that finds
  an upstream document wrong emits a structured record:

  ```yaml
  AMEND:
    - target: prd            # which document
      section: "FR-3"        # the document's own heading or requirement ID
      finding: "<what is wrong>"
      evidence: "<file:line | command | doc URL>"   # REQUIRED; uncited → rejected
      proposed: "<the corrected statement>"
      origin: tech-design    # which phase found it
      severity: high | medium | low | infeasible
      status: open | resolved
      prior_state: "<verbatim pre-amendment text of the section>"  # revert path
  ```

  **Three hard conditions on every amendment** (FR-6, amended). An
  ungrounded upstream-amendment loop does not merely waste effort — it
  *cascades*: a reviewer accepts a plausible-but-wrong claim, the
  upstream document is edited to match, and every downstream phase then
  treats the error as established fact. FR-6 is a mechanism for
  propagating confident errors upstream unless all three hold:

  1. **Grounding** — `evidence` must be present and must resolve: a
     `file:line` that exists, a command that runs, or a reachable URL.
     An uncited amendment is **rejected**, not applied. This is
     mechanically checkable (D13).
  2. **Revert path** — `prior_state` captures the section verbatim
     before the edit, so a bad amendment can be rolled back without
     reconstructing it from memory. Stored in the run-state artifact
     (D11), which is why that artifact is not optional.
  3. **The round cap** (D8) — bounding how many times the loop can run
     at all.

  Without all three, the honest call is to withdraw FR-6 rather than
  ship it ungrounded; see **D12**.

  `severity: infeasible` is a distinct value, not a synonym for `high`:
  success metric 4 is "no open finding of severity 'infeasible'
  referencing a PRD requirement", which is only mechanically checkable
  if infeasibility has its own tag.

  **"Affected sections" is determined by the emitter, not inferred by the
  orchestrator.** The emitting phase must name the target section,
  because it is the only party that knows which claim it contradicted;
  an orchestrator guessing from text similarity would be a second,
  unreliable judgment layer. A record whose `section` does not match a
  heading or requirement ID in the target document is rejected back to
  the emitter as malformed — a mechanical check, not a judgment call.

  The re-spawned upstream phase runs in **section-scoped mode**: its
  dispatch prompt names the document, the sections, and the amendment
  records, and instructs it to rewrite only those sections and append an
  **Amendments** entry recording the origin phase. Everything outside the
  named sections is out of its remit.

- **D8 — replay/termination state machine** [FR-7]. Explicit states so
  the stop condition is mechanical, not a judgment:

  ```
  state       := CONFIG → PHASE(p) → REVIEW(p) → [AMEND*] → PHASE(p+1) … → CLOSE
  round       := count of completed REVIEW rounds across the whole run
  significant := any finding with severity == high
                 (examine-advisor's own vocabulary, examine-advisor.md:107-109)

  after each REVIEW round:
     if round >= 2            → CLOSE (stop for approval, regardless of findings)
     elif significant findings → enqueue AMEND records, replay affected sections
     else                      → advance to next phase
  ```

  **Both terms are defined in the findings schema, not left to
  judgement** (FR-7, amended):
  - **round** = one full pass of *both* reviewer lenses over *all
    three* documents. Not one reviewer, not one phase. The counter is
    global and lives in the run-state artifact (D11), so it survives a
    resume.
  - **significant** = `severity` in {`high`, `infeasible`}. Medium and
    low findings are recorded as open items but never trigger a replay.
    Reusing `examine-advisor`'s existing vocabulary avoids a second,
    parallel scale that would need its own reconciliation.

  **The closing amendment is bookkeeping and triggers no further
  review.** At `CLOSE`, unresolved findings are written into the owning
  document as open items (FR-5 AC "recorded in the doc tree, not only
  in chat"). That write is itself an edit to a reviewed document, so
  without this rule it would re-open the loop it was meant to end. It
  is explicitly exempt: it only *records* findings already attributed
  and severity-tagged, and adds no new claims. The round count and
  budget consumed are reported alongside.

  **The round cap is global, not per phase.** The PRD says "after the
  second review round" without saying which counter. Global is the
  conservative reading — it bounds total cost. Flagged as **Q2**.

  **Budget backstop (FR-7, amended).** The round cap bounds *rounds*;
  it does not bound *tokens*, and the PRD now requires a budget
  "enforced outside the model as an independent backstop". Two layers,
  both outside the model:
  - the workflow runtime's own hard caps (A4: 1,000 agents per run, 16
    concurrent) — these cannot be talked past by any script or prompt;
  - a script-level agent counter that stops scheduling new stages once
    the configured `budget.max_agents` is reached, since the runtime's
    1,000 is far above anything this feature should spend. Because the
    counter lives in script variables, not in a model's context, it is
    not subject to the model forgetting it.

  The `Large workflow` warning (>25 agents or >1.5M projected tokens)
  fires on top of both; a correctly-sized run of this feature should
  never trigger it, so if it does, that is signal.

- **D11 — run-state artifact in the task directory** [FR-12]. A
  `doctree-run-state.yaml` written beside the documents records the
  round number, per-phase status, and open findings. This supersedes
  D10's "no state file" position, which was written against the
  pre-amendment PRD: FR-12 now requires the artifact explicitly, and the
  reason is sound — the workflow runtime resumes *agents*, but nothing
  outside the run records which review round completed, so a resumed run
  would otherwise restart the counter (the cost D10 accepted).

  It stays consistent with the repo's "no hook maintains cross-call
  state" convention because the state lives in the **task directory**,
  as a reviewable document artifact beside the docs it describes — not
  in a hook or a hidden cache. It is written by a stage (A4: the script
  cannot write files). It also holds the findings schema and every
  amendment's `prior_state` (D7's revert path).

- **D12 — OD-2: build back-pressure in v1, under the three conditions,
  and withdraw it if they cannot be met.** No surveyed comparable tool
  (Spec-Kit, BMAD, Superpowers, shinpr) ships automated upstream
  amendment; every one keeps a human gate between phases. That cuts
  both ways and the PRD rightly asks which reading applies.

  **My reading: it is a genuine differentiator, and the absence of
  prior art is mostly an absence of evidence rather than evidence of
  failure** — no source reports trying it and failing either. But the
  cascade risk in D7 is real and well-attested, so the honest position
  is conditional: ship FR-6 **only** with grounding, a revert path and
  the round cap, all three mechanically enforced. If any one cannot be
  built, FR-6 should be withdrawn and replaced by the human gate every
  other tool keeps — the doc tree is then merely *reviewed* rather than
  *self-correcting*, which is a smaller feature but not a broken one.

  Worth noting as corroboration: Spec-Kit's `[NEEDS CLARIFICATION]`
  markers that halt a plan are the same idea as FR-8's blocked items,
  which is prior art for the part of this design that is *not* novel.

- **D13 — deterministic gates, which need no model judgement** [FR-5,
  amended]. Because reviewer independence is weaker than it looks, the
  pipeline runs checks that cannot be talked past by any agent. Each is
  a pure function over the documents:
  - every FR in the PRD maps to at least one acceptance criterion;
  - every FR appears in the tech-design's verification table;
  - every `file:line` citation in any document resolves to a real file
    and line;
  - every `AMEND` record carries resolvable `evidence` (D7 condition 1)
    and a `section` matching a real heading or requirement ID;
  - no open finding of `severity: infeasible` references a PRD
    requirement (success metric 4);
  - every phase that was given `skip_steps` returned
    `decisions_taken > 0`.

  These run after each phase and at `CLOSE`. A failed gate is reported
  like a high-severity finding but is not subject to reviewer
  disagreement. They live in `doctree-lib.sh` so both orchestration
  paths share one definition, and they are the feature's most testable
  surface.

- **D9 — phase output reaches the main session as a digest** [NFR-3].
  A phase's return value is a fixed-shape block, not the document:
  the path written, a ≤10-line summary, the `Decisions-taken` count, the
  `BLOCKED[]` items, and any `AMEND[]` records. The document bulk stays
  in the phase's own context and on disk. This mirrors
  `session-scout`'s contract ("your entire text output IS the return
  value … keep it compact", `session-scout.md:12-14`).

- **D10 — resumability reads the documents first, the state artifact
  second** [NFR-4, FR-12]. A run interrupted between phases leaves each
  completed document on disk; on re-invocation the orchestrator detects
  which documents exist and resumes from the first missing phase. The
  workflow runtime independently replays completed stages from saved
  results (A4). The run-state artifact (D11) supplies what neither of
  those carries: the round number and the open findings.

### Components

**New — shipped:**

0. **`plugin/workflows/doctree.js`** — the orchestration script (D1).
   - Purpose: holds the phase sequence, the replay loop, the round
     counter, the agent-budget counter, and the intermediate results.
   - Shape: `export const meta = { name, description }` first, then a
     body using `phase()`, `agent()`, `parallel()` and the `args` global
     (A4). Per-stage `model` named on the `agent()` call; `schema` on
     stages whose return must be machine-checked.
   - Constraints from A4: no filesystem access, no `import()`, no
     `Date.now()` / `Math.random()` — the run date arrives via `args`.
   - Auto-discovered from the default `workflows/` location at the plugin
     root (verified against current docs); the `workflows` manifest field
     is optional and only needed to point elsewhere.

1. **`plugin/commands/doctree.md`** — the entry command and the
   fallback orchestrator.
   - Purpose: resolve configuration, run the FR-10 pre-flight (including
     the refusal-to-start checks), report it, launch the workflow — and,
     when workflows are unavailable, run the sequential fallback by
     spawning the same phase agent directly.
   - Pattern: follows `research/examine.md` (thin spawner; judgment
     lives in the agent) and its hard-stop-on-degradation step.
   - Must not reference task numbers or `tasks/` paths (CLAUDE.md
     § Key Constraints).

2. **`plugin/agents/doctree-phase.md`** — the phase runner.
   - Frontmatter: `name`, `description`, `model: inherit` (per D2),
     `permissionMode: acceptEdits` (matching all five existing agents),
     `tools:` limited to what a planning phase needs — `Read`, `Write`,
     `Edit`, `Grep`, `Glob`, `Bash`, the two claude-mem search tools,
     the Context7 pair, `SendMessage`.
   - Body: the input contract (phase name, task dir, feature slug, mode
     = `full | section-scoped`, amendment records), the output contract
     (digest / Decisions-taken / BLOCKED / AMEND), and the standing
     instruction to decide-and-log rather than stall.

3. **`plugin/lib/doctree-lib.sh`** — shared pure functions, following
   `branch-task-lib.sh`'s shape (header naming consumers, no output, no
   side effects, no exits).
   - `doctree_resolve_model <phase>` — profile field → built-in default.
   - `doctree_phase_doc_path <taskdir> <run-date> <slug> <phase>` — the
     one definition of the write target, so the command and any future
     wrapper agree. Returns `<taskdir>/<run-date>-<slug>-<suffix>.md`
     (`tech_design` → `-tech-design.md`). The `<run-date>` argument was
     added during implementation: the path must match the established
     `<date>-<slug>-<suffix>.md` convention, and the workflow script
     cannot call `new Date()`, so the entry command resolves the date and
     passes it in (the run date already arrives via `args`).
   - `doctree_validate_amend` — the mechanical malformed-record check
     from D7.
   - Shipped with `plugin/lib/doctree-lib.test.sh` (fixture tests,
     following `plugin/claude-mem/corrections-lib.test.sh`).

**Modified — shipped:**

4. **`plugin/profiles/*.yaml`** (5 files) — the new `doctree:` block
   (below). Additive; an absent field yields `""` from
   `embo-profile get` and falls back to the built-in default, so older
   user profiles keep working untouched.

5. **`plugin/commands/{prd,tech-design,tasks}.md`** — add the FR-11
   unattended mode. This is a **control-flow** change only: each
   command's mandatory question step and (for `tasks.md`) its approval
   stop gain an explicit unattended branch that records a blocked item
   and continues. What each command *produces* is untouched, which is
   what keeps the PRD's "do not reimplement their content rules"
   constraint intact. Interactive invocation is unchanged — the branch
   is only taken when the mode is set.

   **Correction to the PRD's repository facts:** the amended PRD states
   that per-subtask approval gating "lives in `plugin/commands/impl.md`,
   NOT in `tasks.md` (whose only approval-adjacent lines are `:3` and
   `:91`…)". `tasks.md` does carry a second, distinct approval stop:
   Step 6 "Wait for Confirmation — Pause and wait for the user to
   respond with 'Go'" at `tasks.md:114-118`, with the prompting text at
   `:110-112` and a restatement at `:232`. That stop blocks a spawned
   phase and must be covered by FR-11.

**Explicitly unchanged:** what the three phase commands produce,
`subagent-rules.sh` (D6's correction is a separate change),
`hooks.json`, the two review agents.

### New profile fields

```yaml
doctree:
  # Model per planning phase. Aliases (sonnet/opus/haiku/fable) or a
  # full model ID. Overridden per-run by --model-<phase>.
  models:
    prd: opus
    tech_design: opus
    tasks: sonnet
  # What a phase does with something it cannot decide from evidence.
  # `collect` = record a blocked item and finish the run (default);
  # `halt` = stop the run at the first blocked item.
  escalation: collect
  # Review rounds before the run stops for approval regardless of
  # remaining findings.
  round_cap: 2
  # Out-of-model spend backstop. The orchestration stops scheduling new
  # stages at max_agents, below the runtime's own hard cap.
  budget:
    max_agents: 20
```

A baseline run is 3 phases + 6 review passes = 9 stages; `max_agents: 20`
leaves room for one full replay round plus amendments before the
backstop bites, and sits below the `Large workflow` warning threshold
of 25 (A4), so a run that trips the warning has exceeded its design
envelope.

Defaults across the shipped profiles — chosen to match each profile's
existing character (quality = rigor, fast = speed, minimal = bare,
research = skeptical):

| Profile | `prd` | `tech_design` | `tasks` | `escalation` | `round_cap` | `max_agents` |
|---|---|---|---|---|---|---|
| `default` | opus | opus | sonnet | collect | 2 | 20 |
| `quality` | opus | opus | sonnet | collect | 2 | 20 |
| `fast` | sonnet | sonnet | haiku | collect | 1 | 12 |
| `minimal` | sonnet | sonnet | haiku | collect | 1 | 12 |
| `research` | opus | opus | sonnet | halt | 2 | 24 |

Rationale for the two non-obvious rows: `fast`/`minimal` already set
`testing.approach` to `test-after`/`none` and `docs_first` to
`relaxed`/`off`, so a single review round matches their stated
trade-off. `research` sets `assessment: pessimistic` and
`confirmation: required`, so `halt` — stop rather than proceed on an
unresolved question — is the consistent choice. Only `default.yaml`
gets the explanatory comments, matching the existing convention that
the other four are bare.

**Note:** `doctree.models.tech_design` uses an underscore because
`embo-profile get` takes a dotted path (`embo-profile:99`) and a hyphen
in a `yq` path segment would need quoting.

### Data contracts

**Orchestrator → phase (dispatch prompt).** Required fields; a phase
that receives a partial brief reports it rather than guessing (the same
discipline `examine-advisor.md:93-96` states for itself):

```yaml
phase:        prd | tech-design | tasks
mode:         full | section-scoped
task_dir:     tasks/<nnn>-<SLUG>/
feature_slug: <slug>
command_file: plugin/commands/<phase>.md     # follow this, by path
skip_steps:   ["Step 4", "Step 4a"]          # the interactive gates, named
sections:     ["FR-3", "Goals"]              # section-scoped mode only
amendments:   [<AMEND records>]              # section-scoped mode only
upstream_docs: [<paths already written>]
```

**Phase → orchestrator (return digest).** Fixed shape, per D9:

```yaml
document:         <path written>
summary:          <= 10 lines
decisions_taken:  <count>      # must be > 0 when skip_steps was non-empty
blocked:          [{question, why_undecidable, what_it_blocks}]
amend:            [<AMEND records, per D7>]
```

The `decisions_taken > 0` rule is the mechanical check behind D3: a
phase told to skip N question steps that logged zero decisions either
had nothing to decide or silently skipped the work — either way the
orchestrator flags it rather than accepting it.

**Orchestrator → reviewer.** Exactly `examine-advisor`'s required
block (`examine-advisor.md:84-96`): the target document, the goal, the
constraints, what was tried/ruled out, repo context for the internal
pass, plus `pass=internal` / `pass=research`. Two passes spawned in
parallel in one message, per `examine.md:62-66`.

### Error handling and degradation (NFR-2)

Failure modes and the response to each. The principle throughout is the
one `examine.md:68-76` already applies: a degraded run must be loud, and
only the user authorizes the fallback.

| Failure | Response |
|---|---|
| A phase's spawn fails outright | STOP. Report which phase, the error, and name the sequential fallback (`/embo:prd` → `/embo:tech-design` → `/embo:tasks`). Never silently run fewer phases. |
| Requested model unavailable / substituted | Report the substitution if detectable; otherwise the D5 caveat line stands. Do not silently continue on a different model than the user approved. |
| A phase returns no document | Treat as failure, not as an empty phase. Report and stop. |
| A phase returns a document but no `decisions_taken` while `skip_steps` was set | Flag loudly: the phase may have skipped the questions without deciding them. Offer re-spawn. |
| NotebookLM MCP server not connected **at launch** | **Refuse to start** (FR-10). A reviewer spawned while `gemini-notebook-mcp` is disconnected receives none of its tools, so the research pass silently degrades to reasoning-only (`examine.md:45-60`) — and a silently halved review is exactly what FR-5 forbids. This is a pre-flight check, not a mid-run one, because the failure is undetectable after the fact. |
| One review pass degrades mid-run (`EXTERNAL-CHECK-UNAVAILABLE` / `-SKIPPED`) | Reuse `examine.md`'s hard stop: lead with a loud line, do **not** emit a verdict in the same turn, ask whether to fix-and-re-run or proceed internal-only. FR-5's "always both" cannot be silently reduced to one. |
| Workflows disabled (`/config`, `disableWorkflows`, managed settings) | Named degradation (NFR-2): report it and offer the subagent fallback path (D1), which is a shipped alternative rather than a downgrade. |
| Required allow rule missing (incl. `Write` on the task directory) | **Refuse to start** (FR-10). Without it the "unattended" run stalls on a permission prompt (A1, A4). |
| Amendment with unresolvable or absent evidence | **Reject the amendment** (D7 condition 1). The upstream document is not edited; the finding stays open and is reported. |
| A bad amendment needs undoing | Restore from `prior_state` in the run-state artifact (D7 condition 2). |
| Both review passes fail | STOP. The phase is unreviewed; FR-5 is unmet. |
| `AMEND` record names a non-existent section | Reject to the emitter as malformed (D7). Bounded: on a second malformed record for the same finding, record it as a blocked item. |
| Interrupted mid-run | D10: documents on disk stay valid; re-invocation offers resume. Round counter restarts, and that is reported. |
| claude-mem unavailable | Fail with a clear error — CLAUDE.md § Claude-Mem Integration makes it mandatory, not optional. |

### Blocked items and how they surface (FR-8)

A blocked item is recorded three times, deliberately redundantly,
because the PRD requires both "recorded in the doc tree" and "presented
together at the end":

1. In the phase's return digest (`blocked[]`), so the orchestrator sees
   it immediately.
2. In the document itself, under an **Open Questions for the User**
   heading — this is what survives after the session ends.
3. In the orchestrator's closing report, all phases' items gathered into
   one list, so the user answers them in one sitting.

With `escalation: halt`, the run stops at the first blocked item instead
of collecting; the already-written documents stay valid (D10).

### Testing strategy

Following the repo's existing split — shell fixture tests for
mechanical parts, `manual-run-claude` for anything whose behavior lives
in the model.

- **`doctree-lib.test.sh`** drives each pure function with fixtures:
  model resolution from a synthetic profile (including the
  absent-field → built-in-default path, which is the FR-4 backward
  compatibility guarantee), path construction, and `AMEND` validation
  accepting a real heading and rejecting a fabricated one.
- **Profile tests**: `embo-profile get doctree.models.prd` returns the
  expected value for each of the five shipped profiles, and returns
  empty (not an error) for a profile predating the field.
- **Integration** (`manual-run-claude`): a real run on a small feature,
  inspecting the transcript for the things only a live run shows — that
  no phase attempted `AskUserQuestion`, that the per-phase model took
  effect, that a seeded upstream contradiction produced an `AMEND` and a
  section-scoped re-spawn, and that the run stopped at the round cap.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1 three phases run, outputs written | `manual-run-claude` | integration | three documents exist in the task dir after one invocation |
| FR-2 context load without task-selection choice | `manual-run-claude` | integration | transcript shows the context load and **no** `AskUserQuestion` call; structurally guaranteed by A1 |
| FR-3 rule inheritance **asserted, not assumed** | `manual-run-claude` | integration | canary from the injected block echoed by a stage — the hook fails open, so absence of error is not evidence (Story 0.1) |
| FR-4 model from profile | `auto-test` | unit | `doctree_resolve_model` returns the profile value; absent field → built-in default |
| FR-4 argument override wins | `manual-run-claude` | integration | spawn call carries the argument's model; transcript shows that model ran |
| FR-4 shipped profiles carry assignments | `auto-test` | unit | `embo-profile get doctree.models.*` for all five profiles |
| FR-5 both passes always run | `manual-run-claude` | integration | two reviewer spawns per phase in one message; findings tables present |
| FR-5 reviewer is not the author | `code-only` | — | reviewers are `examine-advisor`, phases are `doctree-phase`; distinct definitions |
| FR-5 findings attributed + severity | `code-only` | — | reviewer output carries severity; orchestrator records phase + origin |
| FR-5 different lenses | `code-only` | — | `pass=research` uses NotebookLM, `pass=internal` is barred from it (`examine-advisor.md:78-80`) |
| FR-5 deterministic gates | `auto-test` | unit | each of D13's six gates passes on a good fixture and fails on a seeded-bad one — the most mechanically testable surface in the feature |
| FR-6 evidence required | `auto-test` | unit | an `AMEND` with absent or unresolvable evidence is rejected, and the target document is unchanged |
| FR-6 revert path | `auto-test` | unit | `prior_state` restores the section verbatim |
| Success metric 4 (no open infeasible finding) | `auto-test` | unit | the gate reports a seeded `severity: infeasible` finding against an FR |
| FR-6 finding amends upstream doc | `manual-run-claude` | integration | seeded contradiction → `AMEND` record → upstream doc's Amendments entry names the origin phase |
| FR-6 affected sections only | `manual-run-claude` | integration | `git diff` of the upstream doc touches only the named sections |
| FR-7 replay while significant findings | `manual-run-claude` | integration | a high-severity finding triggers a replay; medium/low do not |
| FR-7 stop at round cap | `manual-run-claude` | integration | run stops for approval at round 2 with findings still open |
| FR-7 rounds reported | `code-only` | — | closing report includes the count |
| FR-8 decide-don't-stall | `manual-run-claude` | integration | `decisions_taken > 0` with a populated Decisions-taken block |
| FR-8 blocked items collected + presented | `manual-run-claude` | integration | seeded undecidable question appears in the doc and the closing report |
| FR-8 escalation from profile | `auto-test` | unit | `embo-profile get doctree.escalation` per profile |
| FR-7 budget backstop outside the model | `auto-test` | unit | the script's agent counter stops scheduling at `max_agents`; asserted on the counter function, not on a live run |
| FR-9 | — | — | **withdrawn in the amended PRD** (early start); no verification needed |
| FR-10 config reported pre-run | `manual-run-claude` | integration | report shows primitive, order, models + provenance, escalation, cap, budget, before any spawn |
| FR-10 refusal to start | `manual-run-claude` | integration | with a required allow rule or MCP server missing, the run refuses rather than starting |
| FR-11 unattended mode in each phase command | `code-only` | — | each of the three commands documents the branch; interactive path unchanged |
| FR-11 question → blocked item | `manual-run-claude` | integration | a seeded undecidable question yields a blocked item, not a stall or a silent skip |
| FR-12 run-state artifact | `auto-test` | unit | artifact written with round, per-phase status, open findings; a resumed run reads it |
| NFR-1 cost reported | `manual-run-claude` | integration | closing report carries token usage; pilot run measures the real multiple (the PRD declines to assert one) |
| NFR-2 loud degradation | `manual-run-claude` | integration | forced failure stops the run and names the sequential fallback — covering workflows disabled, MCP unreachable, missing permission rule, `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, allowlist substitution |
| NFR-3 digest not bulk | `code-only` | — | intermediate results live in script variables (A4); the return contract is the fixed digest shape |
| NFR-4 resumability | `manual-run-claude` | integration | interrupt after phase 1; relaunch; phase-1 doc intact, round recovered from the state artifact |
| A1 permission-stall risk | `manual-run-claude` | spike | Story 0.3 — **CONFOUNDED** (live run under an auto-approving mode did not stall; a default-mode run is still needed); FR-10 pre-flight is load-bearing. See Story 0 Results |
| A4 `SubagentStart` fires for stages | `manual-run-claude` | spike | Story 0.1 — **CLOSED** (P-2), hook fires for stages; see Story 0 Results |
| A4 per-stage model takes effect | `manual-run-claude` | spike | Story 0.4 — **CLOSED** (P-5), parameter is `model`; see Story 0 Results |
| A5 slash command in a stage | `manual-run-claude` | spike | Story 0.2 — **CLOSED** (P-3), via the Skill tool; see Story 0 Results |

### Story 0 — blocking probe (narrowed, run FIRST)

Assumptions (a) and (b) are **resolved from documentation** (A1, A2), so
unlike task 055 they need no live probe. Four questions remain that the
docs do not settle, each of which changes the design if it fails:

1. **Does `SubagentStart` fire for workflow stages?** (highest value.)
   FR-3 depends on it entirely, and `subagent-rules.sh` fails open
   (`subagent-rules.sh:13`), so a non-firing hook injects nothing and
   says nothing. Probe: run a minimal workflow whose single stage is
   told to echo a canary string that only the injected block contains,
   and inspect the stage detail in `/workflows`. **If it does not
   fire**, FR-3 is unmet on the workflow path and the rules must travel
   in the stage prompt instead — which also makes the subagent fallback
   (D1) more attractive, since the hook is known to fire there
   (task 055 proved it for subagents).
2. **Can a stage invoke an embo phase command?** Have a stage attempt
   the `embo:prd` skill against a scratch feature; record whether the
   skill loads and what happens at the mandatory `AskUserQuestion` step
   (clean skip, error, or stall). **If it cannot**, the phase procedure
   must be inlined into the agent body, duplicating content rules the
   PRD says to leave alone — a real re-scope, hence blocking.
3. **Does a stage stall on a permission prompt?** Give a stage a tool
   call outside the allowlist and observe whether the run blocks (as
   A1 and A4's "pauses … only for agent permission prompts" both
   predict). **If it stalls**, FR-10's refusal-to-start must enumerate
   every required allow rule before the unattended claim holds at all.
4. **Does the per-stage model actually take effect?** The JSON field
   name of the per-invocation model parameter is undocumented (the
   amended PRD flags this too); in a workflow it is named on the
   `agent()` call. Probe: run two stages on different models and
   confirm from the `/workflows` agent detail.

Record `claude --version` with every result; this behavior is
version-gated throughout (A2 documents a precedence change at 2.1.251;
A4 cites gates at 2.1.216/2.1.269/2.1.271/2.1.305).

**Mapping to the PRD's Probe Gate.** The PRD's P-1…P-6 and this Story 0
are the same gate; the mapping, with what each probe resolves:

| PRD | This design | Status / note |
|---|---|---|
| P-1 teammate has `AskUserQuestion`? | — | **Moot under D1.** Only matters if OD-1 picks teammates; for subagents and workflow stages the docs settle it (A1: removed). FR-8 holds either way, as the PRD says. |
| P-2 rule hook fires for the chosen primitive? | Story 0.1 | **Blocking for FR-3.** Highest value: the hook fails open, so failure is silent. Known to fire for subagents (task 055); unverified for stages and teammates. |
| P-3 slash command vs skill? | Story 0.2 | **Blocking for FR-1/FR-2.** The PRD's constraint already grants the fallback: a stage may *reference* a command file as its instructions, which is not a reimplementation. That makes P-3 non-fatal — it changes the mechanism, not the scope. |
| P-4 stage writes to the task dir without a prompt? | Story 0.3 | **Blocking for OD-1's workflow candidate.** Docs confirm stages write files ("Agents read, write, and run commands"), but a real run into a plugin-managed directory is unconfirmed. Pre-approve `Write` on the task directory as part of FR-10's pre-flight. Same probe as the permission-stall check. |
| P-5 JSON field name of the model parameter? | Story 0.4 | **Blocking for FR-4's implementation.** In a workflow it is named on the `agent()` call; the Agent-tool field name is undocumented. Resolve by observation, not by guessing. |
| P-6 unattended mode without changing output? | Story 0.5 | **Blocking for FR-11**, and with it FR-1+FR-2+FR-8 jointly. Probe: add the mode to one phase command, run it both ways, and diff the produced document's structure. A passing probe is "same sections, same content rules, one extra Decisions-taken block". |

**Story 0 — Results.** Probes run against **Claude Code 2.1.306**. The
evidence for each closed probe is the PRD Probe Gate (RESOLVED
2026-10-22), by row.

| Probe | Status | Evidence | Outcome |
|---|---|---|---|
| P-1 | MOOT | PRD Probe Gate, row P-1 | `AskUserQuestion` absent from a spawned agent's loaded and deferred tool lists; moot under D1 (subagents/stages), FR-8 holds regardless. |
| P-2 | CLOSED | PRD Probe Gate, row P-2 | Rule-injection hook fires for plain subagents AND workflow stages; the "BINDING SUBAGENT RULES" block arrived as SubagentStart context. FR-3 satisfiable; the canary assertion (0.1 / FR-3) stays required because the hook fails open. |
| P-3 | CLOSED | PRD Probe Gate, row P-3 | No direct slash-command mechanism; `Skill(skill="embo:start")` loads the command body into the agent's context. FR-1/FR-2 buildable via the Skill path. |
| P-4 | CLOSED-WITH-CAVEAT | PRD Probe Gate, row P-4 | A stage wrote into the task directory with no approval dialog and the call did not block. Caveat: this confirms "did not stall" for an allowlisted write, NOT the permission-stall case the design asks for — an agent cannot observe a prompt auto-approved before it. The open part (a tool call OUTSIDE the allowlist) is Story 0.3 / tasks 1.2–1.3, still to run. |
| P-5 | CLOSED | PRD Probe Gate, row P-5 | The per-invocation model parameter is `model`, taking `sonnet`/`opus`/`haiku`/`fable`, first in the resolution order ahead of frontmatter. Confirmed by use. |
| P-6 | CLOSED | PRD Probe Gate, row P-6 | Every interaction point in the phase commands is a prose Markdown instruction, enforced by nothing mechanical; FR-11 is a conditional branch per instruction. (Structural output diff remains the 0.5 acceptance check.) |

**Permission-stall probe — CONFOUNDED, NOT CLEANLY CLOSED (Story 0.3).**
A live run was done against Claude Code 2.1.306: a single workflow stage
attempted `touch /Users/Shared/doctree-probe-marker-xyz` — a path outside
the worktree, matching no rule in `.claude/settings.local.json`. Result:
the call ran with no approval dialog, exit 0, and the file was created
(verified, then removed). This did NOT reproduce the predicted stall.

The result is confounded and does not settle A1, for a specific reason:
**a spawned stage inherits the parent session's permission mode**, and
the session that ran the probe was in an auto-approving mode (the same
mode under which this session's own un-allowlisted edits proceeded
without prompts). "No prompt" is therefore evidence about the *mode the
run was launched in*, not proof that a default-mode user's run skips the
prompt. What the probe DID establish: a stage can write outside the
project when the session's mode permits, so FR-10's pre-flight must still
enumerate the required allow rules — the unattended claim depends on the
rules being present OR the run being launched in an auto-approving mode,
and the pre-flight is what makes the first case safe.

**What a clean probe needs:** run the same single-stage workflow from a
session in the *default* permission mode (prompts active) and observe
whether the un-allowlisted `touch` stalls. That run cannot be performed
from an already-auto-approving session; it is left OPEN as the one
remaining Story 0 item. Per the task-1.4 rule, this does not invalidate a
requirement — FR-10 already assumes the stall is possible and guards it
with the pre-flight — but it means the A1 "stalls on permission prompt"
prediction is documented-but-not-live-confirmed, and FR-10's refusal-to-
start enumeration is load-bearing rather than belt-and-suspenders.

**Recommendation on sequencing.** The external review's advice was to
probe and prototype *before* writing the tech design. That advice is
sound and this document does not supersede it: **the primitive choice in
D1 is evidence-based but not probe-confirmed**, and P-2/P-4 in
particular can overturn it. Story 0 is therefore a hard gate — no
implementation story starts until it passes — and D1 is written so that
a P-2 or P-4 failure moves the design to the subagent fallback without
rewriting the phase agent, the profile schema, the findings schema, or
the deterministic gates. Those five pieces are primitive-independent by
construction, which is the main hedge this design buys.

## Trade-offs

**Mechanism for independent contexts** — the central decision:

1. **Agent teams** (the PRD's original wording) — rejected per A3:
   experimental, off by default, interactive-only, no nested teams, not
   restored by `/resume`. Would gate the whole feature behind a flag
   most users do not set, and its own docs advise against unattended
   running.
2. **Named subagents orchestrated from a command body** — viable, and
   retained as the **fallback** (D1). Pro: the familiar primitive, no
   availability gate beyond ordinary spawning. Con: the round cap,
   budget, digest discipline and resume logic all live as prose the
   model must follow — the pattern this repo's core principle exists to
   eliminate.
3. **Dynamic Workflow (chosen)** — the cap, the context economy and the
   resumability become runtime properties (A4). Con: a newer primitive;
   gated on paid plans and a `/config` toggle on Pro, disableable by
   managed settings; the script cannot touch the filesystem or import
   modules, so all shared logic must be inlined or pushed into a stage.
   The gating is why option 2 ships alongside it rather than being
   discarded.
4. **Sequential commands in the main session** (status quo) — rejected:
   it is the problem statement.

**Suppressing the interactive gates:**

1. **Directive in the dispatch prompt (chosen, D3)** — no change to the
   three phase commands, honoring the PRD's "integrate, don't
   reimplement". Con: it is prose the model must follow, which this
   repo's core principle distrusts. Mitigated by the mechanical
   `decisions_taken` check, not by trust.
2. **A non-interactive flag in each phase command** — would be genuinely
   enforced, but edits the three commands the PRD puts out of scope and
   risks regressing their interactive use. Deferred as the better
   long-term fix if D3 proves unreliable in practice.
3. **Duplicating the phase procedure into the agent body** — rejected
   unless Story 0 forces it; duplicates the content rules.

**Determining "affected sections":**

1. **Emitter names the target section (chosen, D7)** — the only party
   that knows which claim it contradicted. Mechanically validatable.
2. **Orchestrator infers from finding text** — rejected: a second
   unreliable judgment layer, and silently wrong amendments are worse
   than none.
3. **Re-run the whole upstream phase** — rejected by FR-6's explicit
   "only the affected sections", and costly.

## Implementation Constraints

- No internal task references in `plugin/commands/doctree.md` or
  `plugin/agents/doctree-phase.md` (CLAUDE.md § Key Constraints);
  `lib/` and test scripts are exempt.
- Profile fields must be read through `embo-profile`, never by reading
  the YAML directly (the approval-gate reason in `embo-profile:6-15`).
- Bash calls in the command use the bare wrappers (`embo-profile`,
  `rlm_repl`), never `${CLAUDE_PLUGIN_ROOT}/...`, which trips the
  expansion-obfuscation classifier (CLAUDE.md § Architecture).
- `jq` for JSON, `yq` for YAML; no Python (CLAUDE.md § Tool Usage).
- The orchestrator cannot approve a permission prompt on a phase's
  behalf — documented and by design (A1).
- Round cap and escalation must be readable before the first spawn, so
  the D5 report is accurate.

## Files to Create/Modify

**Create:**
- `plugin/workflows/doctree.js` — the orchestration script (D1).
- `plugin/commands/doctree.md` — entry command, FR-10 pre-flight,
  sequential fallback.
- `plugin/agents/doctree-phase.md` — the parameterized phase runner,
  shared by both orchestration paths.
- `plugin/lib/doctree-lib.sh` — model resolution, path construction,
  `AMEND` validation, budget counting (used by the fallback path and the
  tests; the workflow script inlines the equivalents, since A4 forbids
  `import()`).
- `plugin/lib/doctree-lib.test.sh` — fixture tests.

**Modify:**
- `plugin/commands/prd.md`, `tech-design.md`, `tasks.md` — the FR-11
  unattended mode (control flow only).
- `plugin/profiles/default.yaml` — add the commented `doctree:` block.
- `plugin/profiles/quality.yaml`, `fast.yaml`, `minimal.yaml`,
  `research.yaml` — add the bare `doctree:` block per the table.
- `plugin/commands/profile.md` (and its tests) — show the new fields;
  FR-4 requires the profile display to carry the assignment.
- `plugin/.claude-plugin/plugin.json` — no change needed: verified
  against current docs that a script at the default `plugin/workflows/`
  location auto-discovers, and the `workflows` manifest field only
  *replaces* the default scan. The workflow is namespaced by plugin name
  and invoked as `embo:doctree`.
- `CLAUDE.md` § File Structure and the command count (20 → 21) — repo
  bookkeeping, not a shipped behavior change.
- `README.md` — document the command, the new profile fields, the
  availability gates, and the manual sequential fallback (required by
  § Documentation Rules: automation must ship with equivalent manual
  steps).

**Deliberately unchanged:** what the phase commands produce,
`subagent-rules.sh` (see D6), `hooks.json`, both review agents.

## Security Considerations

- No new network surface. The research review pass sends a digest to
  NotebookLM, which `examine.md:38-44` already governs with a
  sanitization rule; the orchestrator must apply the same rule to any
  digest it forwards.
- Phase agents run `permissionMode: acceptEdits`, matching the five
  existing agents: reads and edits auto-allowed, Bash and irreversible
  actions still gated by the harness. Never `bypassPermissions`.
- A phase writes only inside the feature's task directory. Writing
  outside it is out of contract.
- Per A1, no agent message can grant a permission or change
  configuration; safety rests on harness settings plus the injected
  DECIDE-OR-ASK rule, never on agent output.

## Performance Considerations

Cost dominates latency here. A full run is 3 phases + 6 reviewer passes
= **9 agent contexts minimum**, before any replay; a 2-round run with
amendments can exceed a dozen. **Replay rounds are the dominant
multiplier**, which is why the round cap and the budget are enforced
mechanically (D8) rather than advisory.

**Published reference points, cited separately because they use
different baselines** (the PRD now does the same): teammates in plan
mode run at roughly 7x a standard session
(<https://code.claude.com/docs/en/costs>); Anthropic reports agents at
roughly 4x a chat and multi-agent systems at roughly 15x a chat. **No
published figure covers this exact shape** (3 authors, 6 reviews, up to
2 replay rounds), so NFR-1's verification is a **pilot measurement**,
not an asserted multiple. Several of the circulating figures come from
secondary sources; the design does not rest on any of them.

Cost controls, in order of effect:

1. **Budget backstop** (D8) — stops scheduling stages at `max_agents`,
   outside the model.
2. **Section-scoped replays** (D7) — a replay re-runs named sections,
   not a whole phase.
3. **End each author context when its phase ends.** An author's context
   has no further use once its document is written and its digest
   returned; keeping it alive pays for nothing. In the workflow path
   this is automatic — a stage ends when its `agent()` call resolves.
   In the subagent fallback the orchestrator must not hold authors open
   across phases.
4. **Reviewers as short, bounded passes.** They read one document and
   return a table; they need no long exploration budget.
5. **Parallel reviewer spawns** (`examine.md:62-66`) — two passes in
   one message.
6. **Prompt-cache sharing.** In a workflow fan-out, "agents that run
   with the same model, effort level, agent type, tools, output schema,
   and working directory" share a cache prefix (A4). The two reviewer
   passes per phase match on all of those, so spawning them together is
   also the cheaper shape.

A spawned agent's cache holds five minutes by default
(`subagentPromptCacheTtl` extends it to `1h` at a higher write rate);
a long run pays cold-cache cost on later phases. Not mitigated in v1.

## Rollback Plan

Every piece is additive and independently reversible: delete the command
file (the feature disappears; the three phase commands are untouched),
delete the agent definition, remove the `doctree:` blocks from the
profiles (absent fields already degrade to built-in defaults). No data
migration, no hook change, no state file to clean up.

## Open Questions for the User

The PRD is underspecified on these; I have taken the stated position to
keep v1 buildable, but each is the user's call to ratify or overturn.

- **Q1 — RESOLVED by the amended PRD** (FR-11 now mandates the
  unattended mode in the phase commands). One correction stands: the
  PRD's claim that `tasks.md` has no approval stop is wrong —
  `tasks.md:114-118` is one, and FR-11 must cover it.
- **Q2 — is the round cap global or per phase?** FR-7 says "after the
  second review round" without naming the counter. D8 assumes global
  (bounds total cost); per-phase would allow up to 6 rounds. Still open.
- **Q3 — RESOLVED by the amended PRD**: FR-9 (early start) is withdrawn,
  matching this design's recommendation.
- **Q4 — OD-1, which primitive?** The PRD leaves this to the
  tech-design. **D1 recommends Dynamic Workflows**, with subagents as
  the shipped fallback, because FR-7's cap, NFR-3's context economy and
  NFR-4's resumability become runtime properties instead of prose —
  which is the PRD's own primary goal. Teammates are rejected outright
  (A3). **The recommendation is evidence-based but not probe-confirmed:
  P-2 and P-4 can overturn it.** Needs ratification, and it sets how
  much of Story 0 is workflow-specific.
- **Q5 — command name.** `/embo:doctree` is assumed; the PRD never names
  it. Note a workflow's command name comes from the script's `meta.name`
  and is namespaced as `/embo:<meta.name>`.
- **Q6 — does the run create the task directory and pick the task
  number, or is it given one?** The PRD assumes the directory exists;
  `/embo:prd` currently establishes it. Also unspecified: where the run
  date comes from, which matters because a workflow script cannot call
  `new Date()` (A4) — this design assumes it arrives via `args`.
- **Q7 — should the two reviewer passes run on different model
  families?** FR-5 asks for different lenses (delivered:
  research/internal are structurally different, and the internal pass
  is barred from the external corpus) and deterministic gates
  (delivered: six, in D13). What this design does **not** do is change
  the reviewer *family* — both passes are `sonnet`, so self-preference
  bias is reduced but not eliminated. Running `pass=research` on a
  different family would cost a frontmatter change and some consistency;
  worth it or not is the user's call.
- **Q8 — OD-2, ship FR-6 in v1?** D12 recommends yes, but **only** with
  all three conditions (grounding, revert path, round cap) enforced. If
  the user would rather not carry the cascade risk at all in v1, the
  alternative is the human gate every comparable tool keeps — a smaller
  but sound feature. Confirm which.
- **Q9 — does `/embo:impl` stay untouched?** The PRD's "no stop between
  subtasks" acceptance criterion is aimed at per-subtask approval
  gating, which lives in `impl.md`, not `tasks.md` — and `impl.md` is
  out of scope. Under FR-11 this design reads that criterion as
  satisfied by `tasks.md`'s Step 6 approval stop becoming unattended.
  Confirm that reading, or say whether `impl.md` is meant to be in
  scope after all.

## References

### Code (re-read 2026-10-21, this worktree)

- `plugin/commands/prd.md:99-108,351`, `tech-design.md:130-132,352-356`,
  `tasks.md:87-91,114-118,149` — the phases and their interactive gates.
- `plugin/commands/start.md:3,92-597,620-708` — the context load, the
  `AskUserQuestion` close, the CHECKLIST/RULE regions.
- `plugin/commands/research/examine.md:29-76` — the thin-spawner,
  two-parallel-pass, hard-stop-on-degradation pattern.
- `plugin/agents/examine-advisor.md:14-15,81-120` — pass names, input
  contract, severity vocabulary.
- `plugin/agents/approach-validator.md:12-13`,
  `session-scout.md:12-14` — model/permission frontmatter, compact
  return-value contract.
- `plugin/hooks/subagent-rules.sh:19-26,47-56`, `hooks.json:28-38` —
  shipped rule inheritance (FR-3).
- `plugin/bin/embo-profile:6-15,57,60-77,92-101` — profile access and
  the empty-on-absent behavior.
- `plugin/lib/branch-task-lib.sh:1-4` — shared-library convention.
- `plugin/profiles/{default,quality,fast,minimal,research}.yaml` — the
  five shipped profiles.

### Docs (verified 2026-10-21, Claude Code 2.1.306)

- [Subagents](https://code.claude.com/docs/en/sub-agents) — the tool
  filter removing `AskUserQuestion`; background-subagent permission
  surfacing; the four-step model resolution order and the per-invocation
  `model` parameter; `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`; fork behavior.
- [Agent teams](https://code.claude.com/docs/en/agent-teams) —
  experimental and disabled by default; no spawning in non-interactive
  mode; no nested teams; no session resumption; teammate permission
  prompts appear in the lead session; agent messages are never approval.
- [Dynamic workflows](https://code.claude.com/docs/en/workflows) — the
  script/runtime split and "Claude's context holds only the final
  answer"; `agent()` / `parallel()` / `pipeline()` / `phase()` and the
  `args` global; per-stage model as the per-invocation model; `schema`
  for validated structured returns; runtime caps (1,000 agents per run,
  16 concurrent, 4,096 items per call); resumability and which agents
  rerun; "No mid-run user input" and "For sign-off between stages, run
  each stage as its own workflow"; no filesystem access from the script,
  no `import()`, no `Date.now()`/`Math.random()`; plugin distribution via
  a `workflows/` directory; availability and disable settings; the
  `Large workflow` warning thresholds.

### Prior art and evidence (relayed from the external critique)

Cited as the basis for D7's grounding rule, D12's verdict and the
reviewer-independence finding. **Not independently re-verified in this
pass** — relayed claims, marked provisional per the repo's
verify-don't-assume rule, and worth confirming before they are leaned
on further:

- Self-preference bias in same-family LLM judges —
  <https://arxiv.org/html/2410.21819v1>,
  <https://arxiv.org/html/2604.22891v4>. Basis for FR-5's different
  lenses + deterministic gates.
- Multi-agent systems over-spawning without explicit effort limits
  enforced outside the model —
  <https://www.anthropic.com/engineering/multi-agent-research-system>.
  Basis for D8's budget backstop.
- Comparable tools (Spec-Kit, BMAD, Superpowers, shinpr): sequential
  phases, role handoffs through files, two review gates per task, and
  **a human gate between phases in every case**; none ships automated
  upstream amendment. Spec-Kit's `[NEEDS CLARIFICATION]` halt markers
  are prior art for FR-8's blocked items. Basis for D12. Round-cap
  details for shinpr/Superpowers were not settled, and OMC was not
  checked at all.
- Cost baselines: <https://code.claude.com/docs/en/costs> (teammates in
  plan mode ≈7x a standard session) and Anthropic's reported ≈4x
  (agents) / ≈15x (multi-agent) against a chat baseline. Different
  baselines, hence cited separately; several circulating figures are
  secondary sources, which is why NFR-1 measures rather than asserts.

### History (claude-mem)

- Task 044 — delegation thresholds, 7–15x fan-out cost.
- Task 055 — the `SubagentStart` hook; the blocking-probe convention.
- Task 047 — inject verbatim text, not rule names.

*(Not independently re-queried from claude-mem in this pass; sourced
from the PRD's history section and the repo's task tree. A claude-mem
pass before approval would strengthen this section.)*

---

**Next Steps**:
1. Resolve Q1–Q6, then review and approve this design.
2. Run `/embo:tasks` — Story 0 must be task 1 and block the rest.
