# Generate a Task List from a PRD

**🔑 KISS Principle: Keep It Stupid Simple**
All solutions must follow the KISS principle - favor simplicity over complexity.

Create a detailed, step-by-step task list in Markdown format based on an
existing Product Requirements Document (PRD). The task list should guide a
junior developer through the implementation.

## Content Guidelines
- **Clear deliverables** - specific outcomes for each task
- **Reference implementation details** - use `file_path:line_number` when applicable

## Output
- **Format:** Markdown (`.md`)
- **Location:** `/tasks/[JIRA-ID]-[feature-name]/`
- **Filename:** `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-tasks.md` (e.g., `2025-05-25-ABC-123-user-profile-editing-tasks.md`)
- **Style:** Try and keep to 80 character row length. Trim empty characters in
  line ends. VERY IMPORTANT: Always end files with an empty line.

## Process
1. **Receive Technical Design Reference:** The user points the AI to a specific technical design document. Optionally, the user can also provide a PRD file for additional business context
2. **Extract Jira ID:** Extract the Jira task ID from the technical design filename or folder name.
   If not found, ask the user for the Jira task ID.
3. **Analyze Requirements Documents:** 
   - **Read Technical Design:** Analyze the system architecture, API design, components, and technical implementation details (REQUIRED)
   - **Read PRD (if available):** Analyze the functional requirements, user stories, acceptance criteria, and business objectives for additional context
   - **Combine Understanding:** Use technical requirements as primary source with business context from PRD to inform detailed task breakdown
4. **Phase 1: Generate Parent Tasks:** Based on the technical design analysis (and PRD context if available), create the
   file and generate the main, high-level tasks required to implement the
   feature. Each parent task should be structured as a **user story** with clear
   deliverable outcomes. Use your judgment on how many high-level tasks to use. It's likely
   to be about 5-10 user stories. Present these tasks to the user in the specified format
   (without sub-tasks yet). Inform the user: "I have generated the high-level
   tasks based on the technical design. Ready to generate the sub-tasks? Respond with 'Go' to
   proceed."
5. **Wait for Confirmation:** Pause and wait for the user to respond with "Go".
6. **Phase 2: Generate Sub-Tasks:** Once the user confirms, break down each
   parent task into smaller, actionable sub-tasks necessary to complete the
   parent task. Each sub-task should represent a deliverable outcome that can be
   independently verified and tested. Ensure sub-tasks logically follow from the parent task and cover
   the implementation details implied by the PRD.
7. **Identify Relevant Files:** Based on the tasks and PRD, identify potential
   files that will need to be created or modified. List these under the
   `Relevant Files` section, including corresponding test files if applicable.
8. **Generate Final Output:** Combine the parent tasks, sub-tasks, relevant
   files, and notes into the final Markdown structure.
9. **Save Task List:** Save the generated document in the same folder as the PRD
   with the filename `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-tasks.md`, where
   `[feature-name]` matches the base name of the input PRD file and [YYYY-MM-DD]
   is the current date (e.g., if the input was in folder `ABC-123-user-profile-editing`
   and named `2025-05-25-ABC-123-user-profile-editing-prd.md`, the output is
   `2025-05-26-ABC-123-user-profile-editing-tasks.md`).

## Output Format
The generated task list _must_ follow this structure:

```markdown
# [feature-name] - Task List

## Relevant Files
- [path/to/prd.md](path/to/prd.md) :: Feature Name - Product Requirements Document
- [path/to/potential/file1.ts](path/to/potential/file1.ts) :: Brief description of why this file is relevant (e.g., Contains the main component for this feature).
- [path/to/file1.test.ts](path/to/file1.test.ts) :: Unit tests for `file1.ts`.
- [path/to/another/file.tsx](path/to/another/file.tsx) :: Brief description (e.g., API route handler for data submission).
- [path/to/another/file.test.tsx](path/to/another/file.test.tsx) :: Unit tests for `another/file.tsx`.
- [lib/utils/helpers.ts](lib/utils/helpers.ts) :: Brief description (e.g., Utility functions needed for calculations).
- [lib/utils/helpers.test.ts](lib/utils/helpers.test.ts) :: Unit tests for `helpers.ts`.

## Notes
- Unit tests should typically be placed alongside the code files they are testing (e.g., `MyComponent.tsx` and `MyComponent.test.tsx` in the same directory).
- Use `npx jest [optional/path/to/test/file]` to run tests. Running without a path executes all tests found by the Jest configuration.

## TDD Planning Guidelines
When generating tasks, follow Test-Driven Development (TDD) principles where feasible:
- **Test External Functions Only:** Tests should interact with public APIs, exported functions, and external interfaces. Never test internal implementation details.
- **Focus on Functionality:** Tests should verify behavior and functionality, not how the code works internally.
- **Module-Level Testing:** Tests should cover modules of code (single file or group of related files working together) as cohesive units.
- **Small Trackable Chunks:** Break modules into small, user-trackable tasks that alternate between test writing and implementation.
- **Continuous Test-Code Cycle:** Each chunk should follow: write test → implement code → write test → implement code (repeat for each small functionality within the module).
- **TDD When Feasible:** Apply TDD for business logic, algorithms, API endpoints, and complex functionality. Skip TDD for simple tasks like:
  - Entity/model creation (basic data structures)
  - Simple configuration files
  - Basic scaffolding or boilerplate code
  - Static content or styling-only components

## Tasks
- [ ] 1.0 **User Story:** As a [user type], I want [functionality] so that [benefit/outcome] [4/0]
  - [ ] 1.1 Write tests for [specific functionality A] external interface
  - [ ] 1.2 Implement [specific functionality A] to pass tests
  - [ ] 1.3 Write tests for [specific functionality B] external interface
  - [ ] 1.4 Implement [specific functionality B] to pass tests
- [ ] 2.0 **User Story:** As a [user type], I want [functionality] so that [benefit/outcome] [4/0]
  - [ ] 2.1 Write tests for [module method X] behavior
  - [ ] 2.2 Implement [module method X]
  - [ ] 2.3 Write tests for [module method Y] behavior
  - [ ] 2.4 Implement [module method Y]
- [ ] 3.0 **User Story:** As a [user type], I want [functionality] so that [benefit/outcome] (may not require sub-tasks if purely structural or configuration)
```

## Interaction Model
The process explicitly requires a pause after generating parent tasks to get
user confirmation ("Go") before proceeding to generate the detailed
sub-tasks. This ensures the high-level plan aligns with user expectations before
diving into details.

## Target Audience
Assume the primary reader of the task list is a **junior developer** who will
implement the feature.
