# Generate Task List with RLM-Mem Hybrid

**🔑 KISS Principle: Keep It Stupid Simple**
All solutions must follow the KISS principle - favor simplicity over complexity.

Create a detailed, step-by-step task list in Markdown format based on an
existing Technical Design and/or PRD. The task list should guide a junior
developer through the implementation. Uses RLM complexity analysis + claude-mem
historical velocity for realistic estimates.

## Content Guidelines
- **Clear deliverables** - specific outcomes for each task
- **Reference implementation details** - use `file_path:line_number` when
  applicable

## Output
- **Format:** Markdown (`.md`)
- **Location:** `/tasks/[JIRA-ID]-[feature-name]/`
- **Filename:** `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-tasks.md`
- **Style:** Try and keep to 80 character row length. Trim empty characters in
  line ends. VERY IMPORTANT: Always end files with an empty line.

## Process

### Step 0: Load Profile

Read `~/.claude/active-profile.yaml` if it exists. If not present,
use defaults: rlm=true, memory_backend=claude-mem. Skip claude-mem
velocity search (Step 2) if `tools.memory_backend` is `none`. Skip
RLM complexity estimation (Step 3) if `tools.rlm` is `false`.

### Step 1: Load Context

**Read Tech Design / PRD**:
- From file: `tasks/{jira-id}-{feature}/...-tech-design.md`
- Or search claude-mem for recent tech design
  (skip if profile `tools.memory_backend` is `none`)
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

```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py exec <<'PY'
# Estimate based on files to modify/create from tech design
files_to_change = ['{list_from_design}']

complexity_score = 0
for file in files_to_change:
    if file in repo_index['files']:
        meta = repo_index['files'][file]
        size = meta['size']
        # Larger files = more complex to modify
        complexity_score += min(size / 1000, 10)  # Cap at 10 points
    else:
        # New file creation
        complexity_score += 3

print(f"Complexity score: {complexity_score}")
print(f"Estimated subtasks: {int(complexity_score / 2) + 2}")
PY
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

Based on the tech design analysis, RLM complexity estimation, and historical
velocity, create the file and generate the main, high-level tasks. Each parent
task should be structured as a **user story** with clear deliverable outcomes.
Use your judgment on how many - likely 5-10 user stories.

Present these tasks to the user **without sub-tasks yet**. Inform the user:
"I have generated the high-level tasks. Ready to generate the sub-tasks?
Respond with 'Go' to proceed."

### Step 6: Wait for Confirmation

Pause and wait for the user to respond with "Go".

### Step 7: Phase 2 - Generate Sub-Tasks

Once the user confirms, break down each parent task into smaller, actionable
sub-tasks. Each sub-task should represent a deliverable outcome that can be
independently verified and tested.

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
When generating tasks, follow Test-Driven Development (TDD) principles where
feasible:
- **Test External Functions Only:** Tests should interact with public APIs,
  exported functions, and external interfaces. Never test internal
  implementation details.
- **Focus on Functionality:** Tests should verify behavior and functionality,
  not how the code works internally.
- **Module-Level Testing:** Tests should cover modules of code (single file or
  group of related files working together) as cohesive units.
- **Small Trackable Chunks:** Break modules into small, user-trackable tasks
  that alternate between test writing and implementation.
- **Continuous Test-Code Cycle:** Each chunk should follow: write test →
  implement code → write test → implement code (repeat for each small
  functionality within the module).
- **TDD When Feasible:** Apply TDD for business logic, algorithms, API
  endpoints, and complex functionality. Skip TDD for simple tasks like:
  - Entity/model creation (basic data structures)
  - Simple configuration files
  - Basic scaffolding or boilerplate code
  - Static content or styling-only components

## Tasks
- [ ] 1.0 **User Story:** As a [user type], I want [functionality] so that
  [benefit/outcome] [4/0]
  - [ ] 1.1 Write tests for [specific functionality A] external interface
  - [ ] 1.2 Implement [specific functionality A] to pass tests
  - [ ] 1.3 Write tests for [specific functionality B] external interface
  - [ ] 1.4 Implement [specific functionality B] to pass tests
- [ ] 2.0 **User Story:** As a [user type], I want [functionality] so that
  [benefit/outcome] [4/0]
  - [ ] 2.1 Write tests for [module method X] behavior
  - [ ] 2.2 Implement [module method X]
  - [ ] 2.3 Write tests for [module method Y] behavior
  - [ ] 2.4 Implement [module method Y]
- [ ] 3.0 **User Story:** As a [user type], I want [functionality] so that
  [benefit/outcome] (may not require sub-tasks if purely structural or
  configuration)
```

## Interaction Model
The process explicitly requires a pause after generating parent tasks to get
user confirmation ("Go") before proceeding to generate the detailed sub-tasks.
This ensures the high-level plan aligns with user expectations before diving
into details.

## Target Audience
Assume the primary reader of the task list is a **junior developer** who will
implement the feature.

## Final Instructions
1. **Create the task list file** as specified above
2. **Index in claude-mem:** Read the tasks file you just created —
   the PostToolUse hook captures it as a claude-mem observation
   automatically. No explicit save call needed.
3. DO NOT start implementing the task list
4. Use RLM complexity data + claude-mem velocity for realistic estimates
5. Suggest `/dev:impl` as next step
