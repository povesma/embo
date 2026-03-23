# Check Task List Status

**🔑 KISS Principle: Keep It Stupid Simple**
All solutions must follow the KISS principle - favor simplicity over complexity.

Check each tasks against the code and see which are implemented and which are
not.

## Process
1. **Examine Project:** Read project overview file in the `/tasks` directory
    typically named `[project-name]-overview.md`.
2. **Examine Tasks:** Read and examine tasks in the feature folder structure
    (e.g., `/tasks/[JIRA-ID]-[feature-name]/[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-tasks.md`).
3. **Review Incomplete Tasks:** Review tasks in order. For each incomplete tasks
   `[ ]`, review the code to determine if the task has been implement in code.
4. **Update Task List:** Follow these marking rules strictly:
   - **`[X]`** — ONLY when tested AND passing, or explicitly confirmed by user
   - **`[~]`** — code found in review but not yet tested/verified (pending testing)
   - **`[ ]`** — not started or not found in code
   - Code analysis showing implementation exists → `[~]` at best, never `[X]`
   - Mark each finished and **verified** sub‑task `[X]`.
   - Mark the **parent task** `[X]` once **all** its subtasks are `[X]`.
   - **When parent task is verified complete**, update all `ai-docs` files to reflect verified implementation:
     - `ai-docs/API.md` - Document verified external API endpoints and interfaces
     - `ai-docs/ARCHITECTURE.md` - Update with confirmed system design changes
     - `ai-docs/DEVELOPMENT.md` - Add verified development patterns and tools
     - `ai-docs/PRD.md` - Update with confirmed completed requirements
     - `ai-docs/README.md` - Update project overview with verified features
     - `ai-docs/SCHEMA.md` - Document verified external database schemas and repository entities
     - `ai-docs/USAGE.md` - Update with verified user functionality
5. **Halt Condition:** While processing tasks marked incomplete in order, halt
   processing on the first task confirmed in code to be not implemented.
