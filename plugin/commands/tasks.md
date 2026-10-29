---
description: >
  Break an approved technical design into a step-by-step task list with
  user-story parents, verifiable subtasks, and per-subtask verification
  tags. Pauses for confirmation before expanding sub-tasks.
---

# Generate Task List with embo Hybrid

**🔑 KISS Principle:** favor simplicity over complexity in every solution.

Create a step-by-step task list from an existing Technical Design and/or
PRD. Each task states a clear deliverable and references implementation
details as `file_path:line_number` where applicable.

## Output
- **Format:** Markdown (`.md`)
- **Location:** `/tasks/[JIRA-ID]-[feature-name]/`
- **Filename:** `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-tasks.md`
- **Style:** Try and keep to 80 character row length. Trim empty characters in
  line ends. VERY IMPORTANT: Always end files with an empty line.

## Process

### Step 0: Load Profile

Use the profile already loaded this session (from `/embo:start`). If
it is not in context, run `embo-profile show`. Skip RLM complexity
estimation (Step 3) if `tools.rlm` is `false`. (claude-mem is always
on.)

### Step 1: Load Context

**Read Tech Design / PRD**:
- From file: `tasks/{jira-id}-{feature}/...-tech-design.md`
- Or search claude-mem for recent tech design
- Optionally also load PRD for business context

**Extract Jira ID**: From tech design filename or folder name. If not found,
ask the user.

### Step 2: Search Historical Velocity (Claude-Mem)

```
mcp__plugin_claude-mem_mcp-search__search(
  query="task list estimates velocity similar features",
  type="TASK-LIST",
  limit=5
)
```

Extract:
- How long similar features took
- Common task patterns
- Estimation accuracy from past

### Step 3: RLM Complexity Estimation

Write the probe to `tmp/rlm-probe.py`, then run
`rlm_repl exec -c "$(cat tmp/rlm-probe.py)"`. The `-c` flag is required;
heredocs are not supported.

```python
# tmp/rlm-probe.py — score the files the tech design will touch
files_to_change = ['{list_from_design}']
complexity_score = 0
for file in files_to_change:
    if file in repo_index['files']:
        complexity_score += min(repo_index['files'][file]['size'] / 1000, 10)
    else:
        complexity_score += 3  # new file
print(f"Complexity score: {complexity_score}")
print(f"Estimated subtasks: {int(complexity_score / 2) + 2}")
```

### Step 4: Resolve Scope Uncertainties (MANDATORY)

**🚨 BEFORE generating the task list, resolve any unclear scope.**

Review the tech design and RLM analysis, then use AskUserQuestion to clarify:

- **Scope boundaries**: Is the scope clear enough to break down into tasks?
- **Complexity unknowns**: "Should we use existing X or build new?"
- **Dependencies**: Are all dependencies identified?
- **Estimation confidence**: Can we reasonably estimate these tasks?

Always include an "All clear, proceed" option. If user selects it, skip to
Step 5.

### Step 5: Phase 1 - Generate Parent Tasks

Use the tech design analysis to create the file and generate the main,
high-level tasks; use the RLM complexity estimate and historical velocity
(Steps 2-3) only to judge how finely to break down the work — neither
appears in the output. Each parent task should be structured as a **user
story** with clear deliverable outcomes. Use your judgment on how many -
likely 5-10 user stories.

Present these tasks to the user **without sub-tasks yet**. Inform the user:
"I have generated the high-level tasks. Ready to generate the sub-tasks?
Respond with 'Go' to proceed."

### Step 6: Wait for Confirmation

Pause and wait for the user to respond with "Go".

### Step 7: Phase 2 - Generate Sub-Tasks

Once the user confirms, break down each parent task into smaller, actionable
sub-tasks. Each sub-task should represent a deliverable outcome that can be
independently verified and tested.

**Assign `[verify: <method>]` tag to every leaf task** (not parent stories):

1. Check for a test plan: `Glob tasks/{id}-{name}/*-test-plan.md`
   - If found: read the Story Coverage table. Match subtasks by
     description and assign the method from the table.
   - If not found: infer from the task's nature using the assignment
     rules in `/embo:test-plan` (e.g. `.md`/config changes →
     `code-only`, logic changes → `auto-test`, CLI output checks →
     `manual-run-claude`, user confirms → `manual-run-user`).

Tag placement: **end of line**, after the description.
Format: `[verify: <method>]`
Parent story lines (1.0, 2.0, …) do NOT get tags.

Verification methods (`code-only`, `auto-test`, `manual-run-claude`,
`manual-run-user`, `docker`, `e2e`, `observation`) and the `live` vs
`simulated` distinction are defined in the canonical taxonomy in
`/embo:test-plan`.

### Step 8: Identify Relevant Files

Based on the tasks and tech design, identify potential files that will need to
be created or modified. List these under the `Relevant Files` section, including
corresponding test files if applicable.

### Step 9: Save to Claude-Mem and File

Save the generated document in the task folder and index in claude-mem.

## Output Format

The generated task list _must_ follow this structure:

```markdown
# [feature-name] - Task List

## Relevant Files
- [path/to/tech-design.md](path/to/tech-design.md) :: Feature Name - Technical
  Design
- [path/to/prd.md](path/to/prd.md) :: Feature Name - Product Requirements
  Document
- [path/to/potential/file1.ts](path/to/potential/file1.ts) :: Brief
  description of why this file is relevant (e.g., Contains the main component
  for this feature).
- [path/to/file1.test.ts](path/to/file1.test.ts) :: Unit tests for `file1.ts`.
- [path/to/another/file.tsx](path/to/another/file.tsx) :: Brief description
  (e.g., API route handler for data submission).
- [path/to/another/file.test.tsx](path/to/another/file.test.tsx) :: Unit tests
  for `another/file.tsx`.

## Notes
- Unit tests should typically be placed alongside the code files they are
  testing (e.g., `MyComponent.tsx` and `MyComponent.test.tsx` in the same
  directory).
- Use `npx jest [optional/path/to/test/file]` to run tests. Running without a
  path executes all tests found by the Jest configuration.

## TDD Planning Guidelines
Follow TDD where feasible:
- **Test external interfaces only** — public APIs, exported functions.
  Never test internal implementation details.
- **Test behavior, not mechanism.** Cover modules (a file or a group of
  related files) as cohesive units.
- **Alternate in small chunks:** write test → implement → write test →
  implement, one small piece of functionality at a time.
- **Apply TDD** to business logic, algorithms, API endpoints, and
  complex functionality. **Skip it** for entity/model creation, simple
  config files, scaffolding, and styling-only components.

## Tasks
- [ ] 1.0 **User Story:** As a [user type], I want [functionality] so that
  [benefit/outcome] [4/0]
  - [ ] 1.1 Write tests for [functionality A] external interface
    [verify: auto-test]
  - [ ] 1.2 Implement [functionality A] to pass tests [verify: auto-test]
  - [ ] 1.3 Write tests for [functionality B] external interface
    [verify: auto-test]
  - [ ] 1.4 Implement [functionality B] to pass tests [verify: auto-test]
- [ ] 2.0 **User Story:** … (a purely structural or configuration story
  may need no test-first pairs)
  - [ ] 2.1 Update configuration file [verify: code-only]
  - [ ] 2.2 Verify command output after change [verify: manual-run-claude]
```

The `[4/0]` suffix on a parent story is `[subtasks/done]`.

Tasks without `[verify: ...]` tags (from older task files) are treated
as `code-only` implicitly — no evidence required at completion.

## Target Audience
The primary reader is **Claude Code**, which implements the feature via
`/embo:impl`. Write subtasks explicit and self-contained enough that no
clarifying context is needed mid-implementation.

## No Effort/Time Estimates

**Never add a person-hours/days or story-points figure** to a task or a
closing summary — Claude Code implements these, not a person, and no
data here calibrates complexity to elapsed time. RLM complexity +
claude-mem velocity inform subtask granularity only. A summary line, if
used, states counts only (stories, subtasks).

## Final Instructions
- **Index in claude-mem:** read the tasks file back after writing — the
  PostToolUse hook captures it automatically, no explicit save call.
- **DO NOT start implementing** the task list.
- After the list is generated, apply RULE:DELEGATE trigger 2: offer a
  clean-context `examine-advisor` critique (marker `[delegate:trigger-2]`).
- Suggest `/embo:impl` as the next step.
