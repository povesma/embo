# Code Review

Help a code reviewer understand the structure of the project, a component, a
file, a function, or a part of the project.

## Process
1. **Identify Files:** Identify the main files which contain the functionality we
   need to review.
2. **Write List:** Show user list of files to review with a one line
   description.
3. **Wait for Confirmation:** Pause and wait for the user to respond with "Go".
4. **Review Files:** For each file, review the contents and identify overall
   purpose for the file and main functionality contained within.
5. **Generate Final Output:** Write out a list of files with a one line
   description for each and a paragraph describing the contents in more
   detail. **Always provide line numbers for functions, classes, or components.
   Include code snippets for important implementations to help reviewers
   understand the code structure.**

## Output Format
The generated task list _must_ follow this structure:

```markdown
# [feature-name] - Review

Detailed description of how the system works. Always reference specific
line numbers and include code snippets for clarity.

## [path/to/file1.js](path/to/file1.js) :: One line description
Paragraph long description explaining the file's purpose and structure.

**Main Components:**
- `MainController` class (line 10): Handles application flow
  ```javascript
  class MainController {
    constructor() {
      this.state = new Map();
    }
  }
  ```
- `validateInput()` function (line 45): Input validation logic
- `processData()` method (line 67): Core data processing

**Key Variables:**
- `CONFIG` (line 3): Application configuration object
- `currentUser` (line 8): Active user session data

## [path/to/file2.js](path/to/file2.js) :: One line description
Detailed explanation including specific line references and code examples
to help reviewers understand implementation details and design decisions.
```

## Interaction Model
The process explicitly requires a pause after generating initial file list to
get user confirmation ("Go") before proceeding to review file contents. This
ensures the high-level plan to review aligns with user expectations before
diving into details.


## Target Audience
Assume the primary reader of the task list is a **junior developer** who will
need to understand how this code works.
