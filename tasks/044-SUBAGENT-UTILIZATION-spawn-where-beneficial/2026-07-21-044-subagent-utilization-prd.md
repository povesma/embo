# 044: Subagent Utilization — Suggest Delegation Where It Beats In-Context Work — PRD

**Status**: Draft
**Created**: 2026-07-21
**Task**: 044-SUBAGENT-UTILIZATION

---

## Context

Claude Code decides on its own whether to delegate work to subagents,
and in practice it almost never does: exploration, critique, and
noisy troubleshooting run inline, filling the main context and letting
the model grade its own work. This task makes the embo workflow
recognize delegation-beneficial moments and **suggest** a properly
configured subagent — it does not create new specialized agents.

### Current State (observed)

- Subagents are spawned at exactly 4 prescribed points:
  `research:examine`, `research:verify`, `visual-impl` (judge), and
  `impl` (profile test agents) — verified via:
  `grep -n "Agent|subagent|spawn" plugin/commands/*`, 2026-07-21
- The other ~15 commands and all free-form turns contain no
  delegation guidance — verified via: same grep, 2026-07-21
- The 4 shipped agent descriptions state capabilities, not trigger
  conditions — verified via: `plugin/agents/*.md` frontmatter,
  2026-07-21
- Outside prescribed points the model almost never proposes a
  subagent — [user-reported, baseline unmeasured]

### Research Basis (2026-07-21, two independent passes: official
docs via claude-code-guide agent; web sweep via general-purpose agent)

- Official spawn signals: exploration of **≥10 files** or **≥3
  independent work items**; overhead recouped from ~5 files / ~2K
  tokens of exploration output (code.claude.com best-practices,
  claude.com subagents blog)
- Fresh-context review/verification is officially recommended: the
  agent doing the work must not grade it (best-practices,
  "adversarial review")
- Delegation levers, by reliability: trigger-phrased agent
  `description` fields < explicit command-file instruction <
  hook enforcement (community figure: prose followed ~70%, hooks
  100% — matches embo's Enforce-Don't-Ask principle; prior art:
  barkain/claude-code-workflow-orchestration PreToolUse nudge hook)
- Cost: heavy fan-out runs 7–15x session tokens (cold cache,
  duplicated reading, more total work). Disciplined single
  delegation with curated context can be net cheaper than letting
  the main window grow. Known limits: subagents cannot prompt the
  user mid-run; summaries describe intent, not effect.

## Problem Statement

**Who**: the embo user, in any command or free-form turn.
**What**: delegation-beneficial work runs inline because nothing
prompts the model to consider spawning.
**Why**: context fills early (compaction, degraded model quality),
self-review bias, serialized independent work.

## Goals

1. Significantly increase how often the workflow **suggests** a
   subagent at qualifying moments (primary).
2. Keep main-context budget for judgment; bulk reads and noisy
   loops return only conclusions.
3. Artifacts reaching an approval gate get critiqued by a context
   that did not author them; free-form artifacts rely on the session
   rule (the weaker lever) to surface trigger 2.
4. Zero suggestion noise on trivial work.

## Decision Framework (the core deliverable)

All numeric thresholds below (file counts, token counts, item
counts) are calibration starting points from the research basis;
tech-design may adjust them without a PRD revision.

**Spawn triggers** — suggest a subagent when any holds:

| # | Trigger | Benefit |
|---|---------|---------|
| 1 | Exploration expected to read ≥10 files (strong) or ≥5 files / ≥2K tokens of output (consider) | Context savings |
| 2 | Reviewing or judging an artifact authored in this session | Unbiased judgment |
| 3 | A load-bearing claim or chosen approach needs independent proof | Accuracy |
| 4 | ≥3 truly independent work items | Parallelism |
| 5 | Trial-and-error loop expected (troubleshooting, deploy/verify, sandbox experiment, flaky test) | Noise isolation |
| 6 | A shipped specialized agent matches the task | Specialization |

**Counter-triggers** — do not suggest when: steps are sequentially
dependent; edits touch the same files; a single targeted lookup
suffices; the work needs accumulated session context; the work needs
user approval mid-run (subagents cannot ask); or the expected token
cost is disproportionate to the artifact's stakes (a small or
low-risk artifact does not warrant a multi-agent critique).

**Suggestion protocol**: every spawn is proposed via AskUserQuestion
— trigger that fired, agent type, one-line rationale, rough cost.
No auto-spawn. (User decision, this PRD.) The question text carries a
fixed greppable marker (e.g. `[delegate:trigger-N]`) so suggestion
frequency is computable from transcripts. **Decline semantics**:
declining suppresses that same trigger for the rest of the session;
a different trigger firing later is still suggested.

**Handoff discipline** (cost control): curated minimal dispatch
context (task, in-scope paths, constraints, expected output shape,
explicit must-NOTs); fan out only over truly independent items; the
parent verifies resulting diffs/effects, never trusts the summary
alone.

## User Stories

1. **As a developer**, when my request would trip a trigger, I get a
   one-question suggestion to delegate, and declining costs me one
   click.
   - [ ] Framework loaded at session start; suggestion names the
     trigger and the dispatch plan
   - [ ] Trivial-work sessions see zero suggestions

2. **As a developer approving a PRD/tech-design/task list**, I can
   get a clean-context critique before the approval gate — offered,
   never auto-run, with its rough token cost stated.
   - [ ] `prd`, `tech-design`, `tasks` offer the critique step at
     their approval gates for substantial artifacts; findings are
     cited, not a rewrite
   - [ ] The offer is skipped when the cost-proportionality
     counter-trigger applies (small or low-stakes artifact)

3. **As the maintainer**, delegation decisions are observable so the
   framework can be corrected via `/embo:improve`.
   - [ ] Suggested/declined decisions appear in session output
     (captured by claude-mem's observer)

## Requirements

### Functional

1. **FR-1 (High)**: Decision framework shipped as a session rule in
   `start.md` (RULE + CHECKLIST block, existing salience pattern):
   triggers, counter-triggers, suggestion protocol, handoff
   discipline.
2. **FR-2 (High)**: Declare-before-explore restatement. Before
   beginning a bulk exploration (a search or multi-file read
   spanning several files), the model states one line —
   `Delegation: <delegating to X | not delegating, because
   <counter-trigger>>` — then proceeds. Modeled on
   RULE:RESTATE-CORRECTION: the statement is required before the
   reads, so a "delegate" decision keeps the bulk out of the main
   context entirely, and the spoken line is a claude-mem-visible
   trace that `/embo:improve` can mine for "should have delegated"
   corrections (Success Metric 2). Rationale for a declaration and
   not a hook: the intent to explore broadly lives only in the
   model, before the first tool call; no script can observe it
   without keyword-guessing, and a counting hook fires only after
   the reads are already paid for. A reactive hook was built,
   spiked, and rejected — see tech-design "Rejected: the reactive
   nudge hook".
3. **FR-3 (High)**: Prescribed suggestion checkpoints in
   high-leverage commands: `prd`/`tech-design`/`tasks` (approval-gate
   critique), `impl` (bulk discovery, parallel independent subtasks),
   `health`/`check` (troubleshooting loops), `git` (deploy/verify).
   In `impl`, the existing prescribed profile-test-agent spawn stays
   mandatory and unchanged; the new checkpoint covers only the
   additional moments not already prescribed.
4. **FR-4 (Medium)**: Extend the shipped agent descriptions so the
   model can recognize when a specialized agent applies in free-form
   turns *outside* its prescribed command (e.g. mid-troubleshoot,
   "this matches approach-validator's job"). Note: within their
   commands these agents are spawned by hardcoded name, so
   description phrasing changes nothing there; `rlm-subcall` is
   already trigger-phrased — this FR targets the free-form dispatch
   path only.
5. **FR-5 (Medium)**: Verification rule — after any delegated run
   with side effects, the parent performs a named minimum check
   before reporting success: re-read the changed files or `git diff`
   for claimed edits; re-run the check the agent claims passed
   (extends RULE:ASSUME-BROKEN).

### Non-Functional

1. **NFR-1**: Markdown/hook changes only; no new dependencies.
2. **NFR-2**: Degrades to the general-purpose agent when a named
   agent type is unavailable; never blocks a command.
3. **NFR-3**: No noise floor — counter-triggers enforced; trivial
   sessions get zero suggestions.

### Constraints

- Existing 4 prescribed spawn points remain unchanged.
- Suggestions use AskUserQuestion per RULE:CLEAR-OPTIONS.
- The embo dev environment runs with corrections capture enabled
  (dogfooding), so Success Metric 2 has data.
- The per-turn reminder banner gains one more CHECKLIST block; keep
  it a short pointer (≤60 tokens), not a verbatim copy of the full
  framework.

## Out of Scope

- New specialized agent definitions (task brief exclusion).
- Auto-spawning of any kind (user chose suggest-first).
- Rigid machine-validated handoff schema (no usage data yet).
- Agent teams / workflow orchestration beyond the Agent tool.
- Cost tiering mandates (taxonomy may mention cheaper models; no
  requirement).

## Success Metrics

Baseline is effectively zero suggestions outside prescribed points
[user-reported]; metrics are directional.

1. Every session containing qualifying work shows ≥1 explicit
   suggest/decline decision — computable by grepping transcripts for
   the `[delegate:…]` marker.
2. "Should have used a subagent" corrections (task 041 capture)
   trend to zero across releases. Conditional on corrections capture
   being enabled (see Constraints).
3. Trivial-edit sessions show zero suggestions (NFR-3 conformance).
4. Approval gates offer the critique step in 100% of doc-command
   runs on substantial artifacts (cost-proportionality skips are
   conformant, not misses).

## References

- Codebase: `plugin/commands/start.md` (rule + CHECKLIST pattern,
  esp. RULE:RESTATE-CORRECTION — FR-2's model),
  `plugin/hooks/behavioral-reminder.sh` (checklist injection),
  `plugin/agents/*.md`, checkpoint command files
- History: task 031 (thin-spawner), 040 (separate judge), 039 (rule
  salience — same prose-vs-mechanism problem), 041/042 (corrections
  loop that will measure this feature)
- Research: code.claude.com docs (sub-agents, best-practices,
  agent-sdk/subagents), claude.com subagents blog, anthropic.com
  multi-agent research system, barkain/claude-code-workflow-
  orchestration (nudge-hook prior art)

---

**Next Steps**: review → `/embo:tech-design` → `/embo:tasks`
