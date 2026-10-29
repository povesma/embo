---
description: >
  Generate a Product Requirements Document informed by claude-mem
  history and RLM codebase analysis. Asks clarifying questions, then
  writes a sourced, reality-checked PRD to the task folder.
---

# Generate PRD with embo Hybrid Analysis

Create a Product Requirements Document informed by both historical
context (claude-mem) and current codebase capabilities (RLM).

## Process

### Step 0: Load Profile

Use the profile already loaded this session (from `/embo:start`). If
it is not in context, run `embo-profile show`. Skip RLM analysis
(Step 3) if `tools.rlm` is `false`. (claude-mem is always on.)

### Step 1: Gather Requirements from User

Ask the user for feature details:
- **JIRA ID**: (e.g., AS-1234) - required for file organization
- **Feature name**: Short descriptive name
- **User problem**: What problem does this solve?
- **Expected outcome**: What should the user be able to do?

### Step 2: Search Claude-Mem for Past PRDs

**2a. Find similar past features**:
```
mcp__plugin_claude-mem_mcp-search__search(
  query="{feature_name} requirements user stories similar features",
  project="{project_name}",
  type="PRD",
  limit=5
)
```

**2b. Get full details of best matches**:
```
mcp__plugin_claude-mem_mcp-search__get_observations(
  ids=[top_3_relevant_ids]
)
```

**Extract from past PRDs**:
- PRD structure and sections used
- Quality of user stories (format, detail level)
- Acceptance criteria patterns
- How requirements were scoped

### Step 3: RLM Analysis of Current Capabilities

**3a. Find related existing features**:

Write the probe to `tmp/rlm-probe.py`, then execute with
`rlm_repl exec -c "$(cat tmp/rlm-probe.py)"`. The `-c` flag is
required; heredoc syntax (`<<'PY'`) is not supported by `rlm_repl exec`.

```python
# tmp/rlm-probe.py
keywords = ['feature_term', 'related_concept']
relevant = []
for kw in keywords:
    relevant += find_symbol(kw, type='function')
    relevant += find_files_by_pattern(f'**/*{kw}*')
for f in list(set(relevant))[:5]:
    relevant += get_related_files(f)
paths = write_file_chunks(list(set(relevant))[:20], strategy='file')
import json; print(json.dumps(paths))
```

**3b. Analyze architecture patterns** (if relevant files found):

Use rlm-subcall subagent to analyze sample files:
- Query: "Identify existing architecture patterns, API structure, data models, and integration points that relate to this feature"
- Limit: Top 3-5 most relevant files
- Collect findings about current capabilities

**3c. Identify gaps**:
Based on files found in 3a and rlm-subcall analysis, explicitly list:
- **Existing**: components/patterns already present that this feature can build on
- **Missing**: what needs to be created or extended

### Step 4: Ask Clarifying Questions (MANDATORY)

**🚨 BEFORE writing the PRD, you MUST ask clarifying questions using the
AskUserQuestion tool.** The goal is to understand the "what" and "why" of the
feature.

#### Step 4a: Wider context first (its own preceding call)

Elicit the feature's *wider context* — motivation, parent goal, what the
result is used for — as its **own `AskUserQuestion` call that precedes**
the clarifying-questions call, so it anchors every later answer.

**Evaluation order — run in sequence:**

1. **Redundancy check.** Treat the context as *already known* only when
   the prompt states a motivation *distinct from the feature's own
   mechanism* — signalled by a "so that" / "because" / "in order to"
   clause, or a reference to a parent goal or ticket. A bare restatement
   of the feature's name does NOT count. If known: skip the question,
   restate the context in one line, proceed to 4b.
2. **JIRA-parent branch.** If not known AND the task text contains a
   JIRA-style ID (e.g. `AS-1234`): suggest consulting the ticket's
   parent / epic for the context. If a parent yields it, treat as known.
   Otherwise fall through to step 3. "Suggest the parent" never becomes
   "block on the parent."
3. **Ask**, using the approved framing list below.

**One follow-up rule.** If the answer only restates the feature, ask
exactly ONE probing follow-up, then accept whatever is given. **Never
block:** "skip" / "none" is accepted and recorded as "None given". The
redundancy skip takes precedence — if already known, do not ask.

**Approved framings (positive test)** — use one verbatim or close:
- "What is the result of this feature used for?"
- "What is the motivation for this task?"
- "What wider context does this fit into?"
- "Once this is built, what does it enable?"
- "What larger goal does this support?"

**Blocklist (negative test)** — the question MUST NOT contain:
- "higher goal"
- "why do you even want" / "why do you want this"
- "your request is incomplete" / "this is under-specified" / any wording
  implying the user's description is deficient

**Header-vs-question note.** The PRD section is titled "Wider Context /
Higher Goal" — that is the *document header only*. Never speak it as the
question.

#### Step 4b: The remaining clarifying questions

Adapt questions based on the prompt, but common areas to explore:

- **Problem/Goal:** "What problem does this feature solve for the user?"
- **Target Users:** "Who are the primary users of this feature?"
- **Success Metrics:** "How will we measure success? What metrics matter most?"
- **Use Cases:** "What are the main use cases this feature should support?"
- **Feature Scope:** "What should this feature include? What should it
  explicitly NOT include?"
- **Acceptance Criteria:** "What are the key acceptance criteria that define
  'done' for this feature?"
- **Dependencies:** "Does this feature depend on other systems or services?"
- **Risks:** "What are the main risks or potential blockers?"

**Technical Context Questions (informed by RLM findings from Step 3):**
- "I found [pattern from RLM]. Should this feature follow the same approach?"
- "Existing [similar feature] handles [X]. Should we integrate or build new?"
- "Current architecture uses [finding]. Any constraints for this feature?"

Always include an **"All clear, proceed"** option for users with clear
requirements. If user selects it, skip to Step 5.

**Take the user's answers and incorporate them into the PRD below. Do NOT leave
answered questions in an "Open Questions" section.**

### Step 5: Synthesize PRD

Create PRD combining insights + user's clarifications:

```markdown
# {JIRA-ID}: {Feature Name} - PRD

**Status**: Draft
**Created**: {date}
**JIRA**: [{JIRA-ID}](https://jira.example.com/browse/{JIRA-ID})
**Author**: Claude (via dev workflow analysis)

---

## Wider Context / Higher Goal

{The motivation / parent goal / what-the-result-is-used-for captured in
Step 4a. If the user gave nothing: "None given — feature described in
isolation." If drawn from a JIRA parent: state the context and cite the
parent ticket.}

## Context

{User-provided problem statement}

### Current State (observed)

Each factual claim about the codebase or runtime MUST be sourced:
append `— verified via: <file:line | command | host>, <date>` or
tag with `[assumption, verify in tech-design]`. Unsourced claims
are rejected by the reality-check pass (Step 5.5).

- {Observation 1} — verified via: `{source}`, {date}
- {Observation 2} — [assumption, verify in tech-design]

### Past Similar Features (from claude-mem)
{Reference to similar features we've built, what we learned}

## Problem Statement

**Who**: {Target user persona}
**What**: {Specific problem they face}
**Why**: {Impact of the problem}
**When**: {Context/triggers}

## Goals

### Primary Goal
{Main objective this feature achieves}

### Secondary Goals
- {Supporting objective 1}
- {Supporting objective 2}

## User Stories

### Epic
As a {user type}, I want to {capability}, so that {benefit}.

### User Stories
1. **As a** {user type}
   **I want** {specific functionality}
   **So that** {specific benefit}

   **Acceptance Criteria**:
   - [ ] {Testable criterion 1}
   - [ ] {Testable criterion 2}
   - [ ] {Testable criterion 3}

2. {Additional user stories following same pattern}

## Requirements

**Describe by class and sensitivity, not by concrete identifier.**
PRDs drift when they enumerate specific keys, column names, routes,
or env vars — those belong in tech-design, where they're validated
against code. Prefer "5 database connection parameters including
one high-sensitivity password" over listing each by name. Concrete
identifiers are allowed only when the identifier itself IS the
requirement (e.g. "expose endpoint `POST /v2/webhooks` for
backward compat").

### Functional Requirements
1. **FR-1**: {Requirement description}
   - **Priority**: High/Medium/Low
   - **Rationale**: {Why this is needed}
   - **Dependencies**: {What this depends on from RLM analysis}

2. **FR-2**: {Next requirement}

### Non-Functional Requirements
1. **NFR-1**: Performance - {Specific metric}
2. **NFR-2**: Security - {Specific requirement}
3. **NFR-3**: Usability - {Specific expectation}

### Technical Constraints
{Based on RLM analysis of existing architecture}
- Must integrate with: {Existing systems found via RLM}
- Should follow patterns: {Patterns discovered in codebase}
- Cannot change: {Constraints from existing architecture}

## Out of Scope

{What we explicitly won't do in this iteration}
- {Out of scope item 1}
- {Out of scope item 2}

## Success Metrics

**How we'll measure success**:
1. {Metric 1}: {Target value}
2. {Metric 2}: {Target value}
3. {Metric 3}: {Target value}

## References

### From Codebase (RLM)
- Relevant files: {List of files from RLM analysis}
- Existing patterns: {Patterns to follow}
- Integration points: {Where this connects}

### From History (Claude-Mem)
- Similar features: {Reference to past PRDs}
- Lessons learned: {What to avoid/replicate}

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/embo:tech-design` to create technical design
3. Run `/embo:tasks` to break down into tasks
```

### Step 5.5: Reality-Check Pass (MANDATORY)

Before saving, scan the draft for factual claims about the
codebase, runtime, or environment. Every such claim must be one of:

1. **Sourced** — followed by `— verified via: <file:line | command
   output | host>, <date>`. If the source is an RLM call, name the
   exact helper (`find_symbol`, `grep`) and the term queried.
2. **Tagged as assumption** — annotated
   `[assumption, verify in tech-design]`.

If neither: stop, surface the unsourced claim to the user, ask them
to confirm the source or tag it as an assumption, then retry.

Typical offenders: config key lists, column names, API routes,
version numbers, file counts, "the system currently does X"
statements. If you're tempted to enumerate identifiers, re-check
whether that list belongs in tech-design instead (per the
Requirements guidance above).

### Step 5.6: Sanitization Pass (MANDATORY)

Scan for private data (hostnames, IPs, account/tenant IDs, internal service names, paths, ticket numbers). Defer to CLAUDE.md "Documentation
Sanitization" rule if defined; otherwise replace with `<descriptor>` placeholders or RFC 5737/2606 examples. Drafts may carry private values
to keep reasoning concrete; sanitize before `Status: Complete`. Orthogonal to Step 5.5: 5.5 verifies claims are true, 5.6 verifies they are
shareable; both must hold. If unsure whether a value is private, mask it.

### Step 6: Save PRD to File System

```bash
# Create task directory
mkdir -p tasks/{jira_id}-{feature_name_slug}

# Write PRD file
# tasks/{jira_id}-{feature_name_slug}/{YYYY-MM-DD}-{jira_id}-{feature_name_slug}-prd.md
```

After writing, **Read the file back** — the PostToolUse hook captures it
as a claude-mem observation automatically. No explicit save call needed.

### Step 7: Report Completion

Report: the JIRA ID and feature name, the file path written, what was
drawn from claude-mem (how many past PRDs, which structure was followed,
which similar feature was referenced), what was drawn from RLM (files
analyzed, capabilities discovered, integration points, constraints), and
`/embo:tech-design` as the next step.

## Context7

When referencing any library, framework, or external API — use the Context7 MCP to look up current documentation rather than guessing. Call `mcp__context7__resolve-library-id` then `mcp__context7__get-library-docs`. Never invent API signatures or assume version-specific behaviour.

## Final Instructions

- Step 4 (clarifying questions via AskUserQuestion) is **mandatory**.
- Before approval, apply RULE:DELEGATE trigger 2: offer a clean-context
  `examine-advisor` critique of the draft (marker `[delegate:trigger-2]`).
- **DO NOT start technical design** — wait for user approval.
