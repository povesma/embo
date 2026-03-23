# Shared Code Review

Help a code reviewer understand the structure of the project, a component, a
file, a function, or a part of the project.

## Output
- **Format:** Markdown (`.md`)
- **Location:** `/tasks/[JIRA-ID]-[feature-name]/`
- **Filename:** `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-shared-review.md` (e.g., `2025-05-25-ABC-123-user-profile-editing-shared-review.md`)
- **Style:** Try and keep to 80 character row length. Trim empty characters in
  line ends. VERY IMPORTANT: Always end files with an empty line.

## Process
1. **Request Jira Task ID:** If not provided in the request, ask the user for the
   Jira task ID for this shared review (e.g., "Please provide the Jira task ID
   for this feature (e.g., ABC-123)").
2. **Identify Files:** Identify the main files which contain the functionality we
   need to review.
3. **Write List:** Show user list of files to review with a one line
   description.
4. **Wait for Confirmation:** Pause and wait for the user to respond with "Go".
5. **Review Files:** For each file, review the contents and identify overall
   purpose for the file and main functionality contained within.
6. **Generate Final Output:** Write out a list of files with a one line
   description for each and a paragraph describing the contents in more
   detail. **Always include line numbers when referencing specific functions,
   classes, or components. Provide code snippets for key implementations.**

## Output Format
The generated task list _must_ follow this structure:

```markdown
# [feature-name] - Shared Review

Detailed description of how the system works. Whenever a component name,
function name, variable name, etc is mentioned, include the file reference
[path/to/file1.js](path/to/file1.js) and line number.

## [path/to/file1.js](path/to/file1.js) :: One line description
Paragraph long description with specific references:

**Key Functions:**
- `validateUser()` (line 15): Validates user input data
  ```javascript
  function validateUser(userData) {
    return userData.email && userData.name;
  }
  ```
- `processLogin()` (line 32): Handles authentication flow

## [path/to/file2.js](path/to/file2.js) :: One line description
Detailed explanation including:
- Main class/component: `UserComponent` (line 8)
- Key methods: `render()` (line 25), `handleClick()` (line 40)
- Important state variables: `isLoading` (line 12), `userData` (line 13)

```javascript
// Example from line 25:
render() {
  return this.isLoading ? 'Loading...' : this.userData.name;
}
```
```

## Interaction Model
The process explicitly requires a pause after generating initial file list to
get user confirmation ("Go") before proceeding to review file contents. This
ensures the high-level plan to review aligns with user expectations before
diving into details.


## Target Audience
Assume the primary reader of the task list is a **junior developer** who will
need to understand how this code works.
