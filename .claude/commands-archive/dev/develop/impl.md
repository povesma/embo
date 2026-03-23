# Task List Management

**🔑 KISS Principle: Keep It Stupid Simple**
All solutions must follow the KISS principle - favor simplicity over complexity.

Guidelines for managing task lists in markdown files to track progress on completing a PRD.

## Content Guidelines
- **Reference code locations** - use `file_path:line_number` format
- **Self-documenting code** - clear names over comments
- **Essential sections only** - omit empty or placeholder content

## Task Implementation
- **One sub-task at a time:** Do **NOT** start the next sub‑task until you ask
  the user for permission and they say "yes" or "y"
- **Completion protocol:**
  1. When you finish a **sub‑task**, immediately mark it as completed by changing `[ ]` to `[X]`.
  2. If **all** subtasks underneath a parent task are now `[X]`, also mark the **parent task** as completed.
- Stop after each sub‑task and wait for the user’s go‑ahead.

## Task Completion Rules

- **`[X]`** — done: ONLY when tested AND passing, or explicitly confirmed by user
- **`[~]`** — coded, pending testing: implementation written but not yet verified
- **`[ ]`** — not started
- Never mark `[X]` based on writing code alone. Assume it doesn’t work until proven.

## Task List Maintenance
1. **Update the task list as you work:**
   - Mark tasks and subtasks as completed (`[X]`) per the protocol above.
   - Add new tasks as they emerge.

2. **Maintain the "Relevant Files" section:**
   - List every file created or modified.
   - Give each file a one‑line description of its purpose.

## AI Instructions
When working with task lists, the AI must:

1. Regularly update the task list file after finishing any significant work.
2. Follow the completion protocol:
   - Mark each finished **sub‑task** `[X]`.
   - Mark the **parent task** `[X]` once **all** its subtasks are `[X]`.
   - **Upon parent task completion**, trigger update of all `ai-docs` files to reflect newly implemented features:
     - `ai-docs/API.md` - Update with new external API endpoints and interfaces
     - `ai-docs/ARCHITECTURE.md` - Update system design, component relationships  
     - `ai-docs/DEVELOPMENT.md` - Add new development patterns, tools, workflows used
     - `ai-docs/PRD.md` - Update with completed requirements and features
     - `ai-docs/README.md` - Update project overview, installation, basic usage
     - `ai-docs/SCHEMA.md` - Update external database schemas and repository entities if modified
     - `ai-docs/USAGE.md` - Update user guides, examples for new features
3. Add newly discovered tasks.
4. Keep "Relevant Files" accurate and up to date.
5. Before starting work, check which sub‑task is next.
6. After implementing a sub‑task, update the file and then pause for user approval.
7. When a parent task is completed, create or update `ai-docs/` directory and all 8 documentation files based on actual implemented code.

## Code Style
- Focus on readability.
- Try and keep to 120 character row length.
- Trim empty characters in line ends.
- IMPORTANT: Always end files with an empty line.
- **Avoid  comments:** Write self-documenting code with clear variable/function names. Only add comments for complex business logic or non-obvious design decisions.
- **Architecture Terminology:** Use "handler" instead of "usecase" for application layer components that orchestrate business logic.

## Testing Guidelines (TDD)
When implementing each sub-task, follow Test-Driven Development principles:
- **Test External Interface Only:** Write tests that interact with public APIs, exported functions, and external interfaces. Never test internal implementation details, private methods, or internal state.
- **Test Functionality, Not Implementation:** Tests should verify what the code does (behavior and functionality), not how it does it (implementation details).
- **Focus on Module Contracts:** Test the contract between modules - inputs, outputs, side effects, and error conditions as seen from the outside.
- **Test First:** For each sub-task involving code, write the test before implementing the functionality.
- **Examples of What NOT to Test:**
  - Private/internal functions or methods
  - Implementation-specific details (e.g., how data is stored internally)
  - Internal state variables or class properties
  - Specific algorithms used (unless the algorithm choice affects external behavior)
- **Examples of What TO Test:**
  - Public function inputs and outputs
  - API endpoints and their responses  
  - Component props and rendered output
  - Error handling for invalid inputs
  - Side effects visible from outside the module

## Images
- DO NOT attempt to generate images, (e.g. SVG, favicon.ico, etc.).
- If an image is needed, add a placeholder with the image path and a descriptive
  `alt` tag.
- Then add the image to an image tasks file called
  `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-images.md` in the same folder as the PRD
  (`/tasks/[JIRA-ID]-[feature-name]/`), where `[feature-name]` matches the base name
  of the input PRD file and [YYYY-MM-DD] is the current date (e.g., if the input was
  in folder `ABC-123-user-profile-editing` and named `2025-05-25-ABC-123-user-profile-editing-prd.md`,
  the output is `2025-05-26-ABC-123-user-profile-editing-images.md`).
### Images Output Format
The generated task list _must_ follow this structure:

```org-mode
## Images
- [ ] =[path-to-image1]= :: Alt description of image 1
- [ ] =[path-to-image2]= :: Alt description of image 2
```
### Updating Generated Image Status
- If an image file exists in the path specified in the images tasks file. Marked
  it as completed with a `[X]` mark.
