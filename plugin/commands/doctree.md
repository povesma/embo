---
description: >
  Builds a feature's whole planning doc tree — PRD, then technical
  design, then task list — with a team of spawned agents, each phase
  authored in its own context and reviewed by passes that did not write
  it. Resolves model and limits from your profile, reports the plan,
  refuses to start when it would stall, then runs. Invoke with
  /embo:doctree <feature-slug>.
---

# Build the Doc Tree with Agent Teammates

One command that produces a feature's PRD, technical design, and task
list as a reviewed sequence, without the document bulk entering your
session. This command is a **thin spawner**: it resolves configuration,
proves the run will not stall, and launches the orchestration; the
planning judgment lives in the `doctree-phase` agent and the two review
passes, not here.

## When to Use

- You are starting a new feature and want its full doc tree built in one
  invocation rather than three interactive commands.
- You want each phase authored by a fresh context and checked by
  reviewers that did not write it.

Use `/embo:prd`, `/embo:tech-design`, `/embo:tasks` individually when you
want to drive each phase interactively yourself.

## Arguments

```
/embo:doctree <feature-slug> [--model-prd <m>] [--model-tech-design <m>]
              [--model-tasks <m>] [--escalation collect|halt]
```

- `<feature-slug>` (required) — the feature's slug or a short description.
  A slug (lowercase letters, digits, hyphens) is used verbatim. A phrase or
  sentence is normalized into a slug and becomes the `feature_description`;
  both are shown in the pre-flight report before any agent runs.
- `--model-<phase> <m>` — override the model for one phase (alias or full
  ID). Wins over the profile value.
- `--escalation collect|halt` — override the escalation mode.

## Process

### Step 0 — Resume check

Before resolving configuration, check whether this feature's task
directory already holds phase documents from an interrupted run. Reading
the documents first (not a hidden cache) is how a resumed run recovers:
if the PRD exists but the tech-design does not, resume from tech-design;
if both exist, resume from tasks; if all three exist, the run is complete.
The round number and open findings come from the `doctree-run-state.yaml`
artifact beside the documents — report that the round was recovered from
it. A resumed run never re-writes a document that is already present.

### Step 1 — Resolve configuration

Read every doc-tree field from the active profile with bare
`embo-profile get` calls, then apply any argument overrides on top. Record
each value's **provenance** (argument / profile field / built-in default)
for the report:

```bash
embo-profile get doctree.models.prd
embo-profile get doctree.models.tech_design
embo-profile get doctree.models.tasks
embo-profile get doctree.escalation
embo-profile get doctree.round_cap
embo-profile get doctree.reviewer_model_family
embo-profile get doctree.budget.max_agents
```

An empty result means the field is absent; fall back to the built-in
default (prd/tech_design → opus, tasks → sonnet, escalation → collect,
round_cap → 2, reviewer family → sonnet, max_agents → 20) and mark the
provenance as "built-in default". An argument override replaces the
resolved value and is marked "argument". Resolve the task directory and
the run date here too — the workflow script cannot compute a date, so it
is resolved now and passed in.

**Normalize the argument into a slug and a feature description.** A slug
is a short lowercase-with-hyphens identifier (e.g. `main-branch-guard`).
If the argument looks like a slug already (all lowercase letters, digits,
and hyphens, no spaces), use it verbatim. If it is a sentence or phrase
(contains spaces or uppercase), derive the slug from it: lowercase,
replace spaces and punctuation with hyphens, collapse multiple hyphens,
strip leading/trailing hyphens, and truncate to 40 characters. The
original argument becomes the `feature_description` to pass to the
workflow. Show both the derived slug and the description in the pre-flight
report so the user can redirect before any agent runs.

**Resolve what the feature IS.** A phase agent starts with no context
beyond its brief, so the brief must say what is being built. Look in the
task directory for an existing seed or brief (`SEED.md` and the like); if
one is there, pass its path as `seed_doc`. Read it and pass a one- or
two-sentence `feature_description` as well. When neither exists, say so
in the pre-flight report — a run whose first phase must invent the
feature from its slug alone produces a document about the wrong thing,
and that is worth stopping for rather than discovering at the end.

### Step 2 — Pre-flight report (before any spawn)

Print the resolved plan and **stop for the user's go-ahead** — the one
upfront gate:

- phase order: PRD → tech-design → tasks
- model per phase, each with its provenance
- reviewer model family, escalation mode, round cap, max agents
- the target task directory and the three document paths
- a caveat line naming the silent-override paths this command cannot
  detect (`CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, local mods, an organization
  model allowlist) — a run that silently ignored your model choice is
  worse than one that warned.

### Step 3 — Refuse to start when the run would stall (FR-10)

These are **pre-flight** checks because their failures are undetectable
or costly after the run begins. Fail loudly and do not start if any fail.

**3a. Permissions.** An unattended phase that makes a tool call outside
the permission allowlist stalls waiting for a human — the opposite of
unattended. Confirm the allow rules a run needs are present, and if any is
missing, name exactly what to add to `.claude/settings.json` and stop:

- `Bash(embo-profile get *)` — configuration resolution
- `Write` and `Edit` on the task directory — the phases write the
  documents there
- `Bash(embo-profile show)` — the phases' context load

**3b. The review MCP server.** The two review passes use the
`examine-advisor` agent, whose research pass needs `gemini-notebook-mcp`.
A reviewer spawned while that server is disconnected receives none of its
tools and silently degrades to reasoning-only — a silently halved review.
This failure is undetectable after the fact, so check reachability now
(e.g. a cheap `mcp__gemini-notebook-mcp__notebook_list`). If it is not
reachable, **refuse to start**: tell the user to reconnect via `/mcp` or
re-auth via `nlm login`, then re-invoke.

**3c. claude-mem.** It is mandatory; if its search tools are unavailable,
fail with a clear error.

### Step 4 — Launch

Select the execution path and state in the report which one is running:

- **Workflow path (default).** Launch the doc-tree workflow (shipped at
  the plugin's default `workflows/` location, so it is namespaced by the
  plugin: invoke it as `embo:doctree`), passing the resolved configuration
  via `args`: task directory, feature slug, run date, seed document path
  and feature description, per-phase models, reviewer family, escalation
  mode, round cap, and max agents. The
  workflow owns the phase sequence, the round and budget counters, and the
  replay loop as runtime properties.
- **Sequential fallback.** When workflows are unavailable (disabled via
  `/config`, `disableWorkflows`, or managed settings), run the same phase
  agent (`doctree-phase`) directly in order — PRD, then tech-design, then
  tasks — honoring the same round cap and budget. This is a shipped
  alternative, not a downgrade; report that it is the path in use.

Every spawned phase runs with the environment variable
`EMBO_DOCTREE_UNATTENDED` set, which is what makes each phase command take
its unattended branch. Pass each phase its per-phase model, the task
directory, the feature slug, and the upstream documents already written.

**Review and gates after each phase.** No phase is graded only by a
context that shares its author's biases:

- **Two review passes**, spawned **by the lead, never by the authoring
  agent**, run different lenses on the just-written document — a research
  pass (prior art) and an internal pass (codebase / consistency) — using
  the configured reviewer model family. Both passes always run; a
  silently halved review is forbidden (if one degrades mid-run, lead with
  a loud line and ask whether to fix-and-re-run or proceed with one, never
  emit a verdict in the same turn).
- **Deterministic gates** then run — checks that need no model judgement
  and cannot be talked past: every PRD requirement maps to an acceptance
  criterion, every requirement appears in the tech-design verification
  table, every `file:line` citation resolves, every `AMEND` record is
  grounded and names a real section, no open `infeasible` finding
  references a PRD requirement, and every phase given skip-steps returned
  `decisions_taken > 0`. A failed gate is reported like a high-severity
  finding but is not open to reviewer disagreement.
- A **significant** finding (severity `high` or `infeasible`) becomes an
  amendment and may trigger a section-scoped replay of the affected
  upstream phase, up to the round cap; `medium`/`low` are recorded but
  never replay. A review is expected to **fix** the document, not just
  describe what is wrong with it, so a significant finding must name the
  target document and section and carry resolvable evidence, the proposed
  replacement text, and the section's current text. One that arrives
  without them cannot be applied: it is dropped, and the run says so
  rather than letting it pass as a review that found nothing.

### Step 5 — Closing report

When the run finishes, report together, in one place:

- the three document paths produced;
- **all blocked items from every phase, gathered into one list**, so the
  user answers them in one sitting (they also live under an "Open
  Questions for the User" heading in each document);
- the number of review rounds taken;
- the token cost of the run;
- if `cap_hit_with_findings` is true in the workflow result: a prominent
  notice that the round cap was reached with significant findings still
  open, naming the findings, and asking the user whether to re-invoke
  with a higher `--round-cap` or accept the open findings as recorded
  items.

## Degradation (loud, never silent)

A degraded run must be loud, and only the user authorizes a fallback.
Select the execution path up front and **state in the report which path is
running**: if the Workflow tool is unavailable (workflows disabled via
`/config`, `disableWorkflows`, or managed settings), announce that and run
the sequential fallback — the same `doctree-phase` agent spawned directly
in phase order, honoring the same round cap and budget. The fallback is a
shipped alternative, not a silent downgrade, and it produces the same
three documents.

The degradation matrix, each failing loudly with its reason:

- **A phase's spawn fails** → STOP, report which phase and the error, name
  the interactive fallback (`/embo:prd` → `/embo:tech-design` →
  `/embo:tasks`). Never silently run fewer phases.
- **A phase returns no document**, or a document with zero decisions while
  its question steps were skipped → treat as failure, report, offer
  re-spawn.
- **A review pass degrades mid-run** → do not emit a verdict in the same
  turn; lead with a loud line and ask whether to fix-and-re-run or proceed
  with one pass. Both passes cannot be silently reduced to one.
- **A requested model is force-substituted** (`CLAUDE_CODE_SUBAGENT_MODEL_FORCE`,
  an organization allowlist) → report the substitution if detectable;
  the pre-flight caveat line stands for the cases this command cannot see.
- **Workflows disabled** → named degradation: report it, run the
  sequential fallback.
- **The review MCP server unreachable** → caught by the Step 3b
  pre-flight; refuse to start rather than run a silently halved review.
- **A required permission rule missing** → caught by the Step 3a
  pre-flight; refuse to start rather than stall on a prompt.
- **Interrupted mid-run** → documents on disk stay valid; re-invoking
  resumes from the first missing phase (Step 0) and reports that the round
  number was recovered from the run-state artifact.
