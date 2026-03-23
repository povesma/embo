# Code Review

Review uncommitted or recently committed git changes and provide critical
feedback to the engineer who wrote the code.

## Output
- **Format:** Markdown (`.md`)
- **Location:** `/tasks/[JIRA-ID]-[feature-name]/`
- **Filename:** `[YYYY-MM-DD]-[JIRA-ID]-[feature-name]-review.md` (e.g., `2025-05-25-ABC-123-user-profile-editing-review.md`).
  [feature-name] should be determined based on summary of changes.
- **Style:** Try and keep to 80 character row length. Trim empty characters in
  line ends. VERY IMPORTANT: Always end files with an empty line.

## Process
1. **Request Jira Task ID:** If not provided in the request, ask the user for the
   Jira task ID for this review (e.g., "Please provide the Jira task ID for this
   feature review (e.g., ABC-123)").
2. **Identify Files:** Identify the files which you need to review by examining
   changed git files using command `git diff --name-only`. If no changes are
   available, examine the last commit instead using `git log --name-only -1`.
3. **Write List:** Show user list of files to review with a one line
   description of the changes.
4. **Wait for Confirmation:** Pause and wait for the user to respond with "Go".
5. **Review Files:** For each file, review the contents and identify overall
   purpose for the file and main functionality contained within. Run `git diff`
   commands to identify the changes made.
6. **Review Changes:** For each file, review the changes made since last commit
   or in the last commit. Also review code around the changes to ensure you have
   the right context.
7. **Provide Feedback:** For each file, create a list of improvements that
   should be made. **CRITICAL: Always include line numbers, file references, 
   code snippets, and specific fix suggestions.** Focus on:
   - Potential bugs
   - Performance issues
   - Code duplication
   - Making code easy to understand
   - Adherence to style conventions
   - Missing documentation
   - Missing tests
8. **Generate Final Output:** Write out a list of files with a one line
   description for each and list of feedback items. **For each feedback item,
   include: line number reference, code snippet, specific issue description,
   and exact fix suggestion.** Describe what needs to be done and why.
9. **Update ai-docs Upon Review Approval:** After code review feedback is
   addressed and changes are approved, update all `ai-docs` files to reflect
   the completed implementation:
   - `ai-docs/API.md` - Document finalized external API changes and interfaces
   - `ai-docs/ARCHITECTURE.md` - Update system design with reviewed components
   - `ai-docs/DEVELOPMENT.md` - Add validated development patterns
   - `ai-docs/PRD.md` - Update with verified completed requirements
   - `ai-docs/README.md` - Update project overview with reviewed features
   - `ai-docs/SCHEMA.md` - Document finalized external database schemas and repository entities
   - `ai-docs/USAGE.md` - Update user guides with reviewed functionality

## Output Format
The generated task list _must_ follow this structure:

```markdown
# [feature-name] - Review

High level description of the nature of the changes in this review.

- [ ] 1.0 [path/to/file1.js](path/to/file1.js) :: One line description [2/0]
  - [ ] 1.1 **Line 45:** Potential null pointer exception - add null check before `user.name.toLowerCase()`
    ```javascript
    // Current (problematic):
    const displayName = user.name.toLowerCase();
    
    // Fix:
    const displayName = user.name?.toLowerCase() || 'Unknown';
    ```
  - [ ] 1.2 **Lines 23-28:** Duplicate validation logic - extract to utility function
    ```javascript
    // Current (duplicate code in multiple places):
    if (!email || !email.includes('@')) { ... }
    
    // Fix: Extract to utils/validation.js:
    export const validateEmail = (email) => email && email.includes('@');
    ```
- [ ] 2.0 [path/to/file2.js](path/to/file2.js) :: One line description [1/0]
  - [ ] 2.1 **Line 12:** Missing error handling for async operation
    ```javascript
    // Current:
    const data = await fetchUser(id);
    
    // Fix:
    try {
      const data = await fetchUser(id);
      // handle success
    } catch (error) {
      console.error('Failed to fetch user:', error);
      // handle error
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
need to understand how to fix issues.

## Final instructions
- Do NOT start implementing the feedback.
