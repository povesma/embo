---
description: >
  Generate git commit messages and PR descriptions, or manage commit style.
  Use when the user wants to commit changes, push a branch, open a pull
  request, or change their commit convention. Examples: "commit my changes",
  "create a PR", "push and open a PR", "what commit style am I using".
argument-hint: "[commit|pr|style]"
---

# Git Commit & PR Description Generator

Generate high-quality commit messages and PR descriptions from staged
changes and branch history. Manage commit style via the active profile.

<!-- RULE:DEV-GIT -->
## When to Use

- Before every `git commit` — to get a well-structured message
- Before opening a PR — to generate a Summary + Test plan description
- When you want to check or change your commit style

## Arguments

| Invocation | Mode |
|------------|------|
| `/dev:git` | Interactive menu: commit / pr / style |
| `/dev:git commit` | Generate commit message for staged changes |
| `/dev:git pr` | Generate PR description for current branch |
| `/dev:git style` | List available styles; switch active style |

If no argument is provided, show the interactive menu.

## Style Definitions

Three built-in styles. The active style is read from
`~/.claude/active-profile.yaml` → `git.commit_style`.
Default when absent: `conventional`.

### `conventional`

Follows Conventional Commits 1.0.

```
<type>(<scope>): <subject>
                              ← blank line
<body>
                              ← blank line (if footer present)
<footer>
```

- **type**: `feat` | `fix` | `docs` | `refactor` | `test` |
  `chore` | `perf` | `ci` | `build` | `revert`
- **scope**: optional; the subsystem changed (e.g. `auth`, `profiles`).
  Omit if the change is cross-cutting.
- **subject**: imperative mood, ≤72 chars total line, no trailing period
- **body**: separated by blank line; explain *why*, not *what*;
  wrap at 72 chars; bullet lists OK when each adds context the diff
  doesn't provide
- **footer**: optional; `BREAKING CHANGE: <description>` or
  `Closes #N`

Example:
```
feat(profiles): add git.commit_style field

Teams need a way to standardise commit conventions without
per-session setup. Adding the field to all four profiles lets
users override via /dev:git style.
```

### `imperative`

```
<Verb> <what>
              ← blank line
<body>
```

- Subject: imperative verb, ≤50 chars, no trailing period, no prefix
- Body: motivation, context, trade-offs; same rules as `conventional`

Example:
```
Add git.commit_style to workflow profiles

Teams need a consistent commit convention without
per-session setup. The field defaults to conventional.
```

### `tim-pope`

Identical structure to `imperative`. Body wrapped strictly at 72 chars.
Reference: https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html

### `custom`

Read `git.custom_style.subject_template` and
`git.custom_style.body_guidance` from the active profile and use
them as generation guidance. If the block is missing, warn and fall
back to `conventional`.

---

## Process

### Step 0: Load profile (always, before any mode)

```bash
cat ~/.claude/active-profile.yaml 2>/dev/null
```

Extract `git.commit_style`. Default: `conventional` if absent or file missing.
Store as `<active_style>` — use throughout without re-reading the file.

---

### Mode: Interactive Menu (no argument)

Use `AskUserQuestion` to offer the three modes:

```
question: "What do you want to do?"
header: "Git action"
options:
  - label: "commit"
    description: "Generate commit message for staged changes"
  - label: "pr"
    description: "Generate PR description for this branch"
  - label: "style"
    description: "View or change commit style  [active: <active_style>]"
```

Then proceed with the selected mode.

---

### Mode: `commit`

#### Step 2: Check staged changes

```bash
git diff --staged --stat
```

**If output is empty**: check for unstaged changes:

```bash
git status --short
```

- Nothing at all → print "Nothing to commit. Stage your changes
  first." and stop.
- Unstaged changes exist → analyse all changed files and group them
  by intent. Each group = one logical commit. Name and number each
  group. **Never use `git add -A` or `git add .`** — every file
  must be staged explicitly by name.

Present the proposed groups:

```
Nothing is staged. I analysed the changes and suggest these commits:

  [1] feat(git): add /dev:git command
      .claude/commands/dev/git.md
      — new command implementing commit/pr/style workflow

  [2] docs(014): add PRD, tech design, test plan, tasks for feature 014
      tasks/014-git-commit-pr-texts/2026-03-29-014-git-commit-pr-texts-prd.md
      tasks/014-git-commit-pr-texts/2026-03-29-014-git-commit-pr-texts-tech-design.md
      tasks/014-git-commit-pr-texts/2026-03-29-014-git-commit-pr-texts-test-plan.md
      tasks/014-git-commit-pr-texts/2026-03-29-014-git-commit-pr-texts-tasks.md
      — planning docs for the git commit/PR feature

  [?] tasks/claude-mem-observation-verification-prd.md
      — unrelated file; not assigned to any group

Which group(s) to commit now? (e.g. 1, 2, 1+2, or 'cancel'):
```

Rules:
- Unrelated or ambiguous files go in `[?]` — never assigned
  to a group automatically
- If all changes clearly belong together, propose a single group
- User can select multiple groups (e.g. `1+2`) — commit them
  sequentially, generating a separate message for each
- On 'cancel': stop

After user selects a group, stage its files explicitly:
`git add <file1> <file2> ...`, then proceed to Step 3.

#### Step 3: Read full context

```bash
git diff --staged
git log --oneline -10
```

#### Step 4: Generate commit message

Using the active style definition above, generate a commit message:
- Infer type and scope from the diff (for `conventional`)
- Write a subject that summarises the *change*, not the ticket
- Write a body that explains *why* the change was made
- Do not restate file names or line numbers from the diff

#### Step 5: Present for review

Print the generated message in a fenced block, then use
`AskUserQuestion`:

```
question: "Commit with this message?"
header: "Commit review"
options:
  - label: "Accept"
    description: "Run git commit with this message"
  - label: "Edit"
    description: "Modify the message before committing"
  - label: "Reject"
    description: "Discard — do not commit"
```

- **Accept**: run `git commit -m "$(cat <<'EOF' ... EOF)"`
  After committing, check branch state:

  ```bash
  git log @{u}..HEAD --oneline 2>/dev/null || echo "NO_UPSTREAM"
  ```

  Use `AskUserQuestion`:
  ```
  question: "Committed. What next?"
  header: "Next step"
  options:
    - label: "push"
      description: "git push (or git push -u origin <branch> if no upstream)"
    - label: "push + open PR"
      description: "Push, then generate PR description"
    - label: "done"
      description: "Stop here"
  ```

  - "push" → run `git push` (or `git push -u origin <branch>`),
    print confirmation, stop.
  - "push + open PR" → push, then continue directly into PR mode
    (skip pre-flight checks — state is already known clean).
  - "done" → stop.

  If there are more groups left to commit (user selected `1+2`
  earlier), commit the next group first before offering "what next?".

- **Edit**: apply user changes, then commit (same "what next?" flow)
- **Reject**: stop, no commit

---

### Mode: `pr`

#### Step 1: Load profile

Same as commit — extract `git.commit_style` for style context.

#### Step 2: Pre-flight checks

Before generating anything, verify the branch is in a clean state:

```bash
git status --short
git log @{u}..HEAD --oneline 2>/dev/null || echo "NO_UPSTREAM"
```

- **Uncommitted changes exist** → use `AskUserQuestion`:
  ```
  question: "You have uncommitted changes. Run the full sequence
             (commit → push → PR)?"
  header: "Pre-flight"
  options:
    - label: "Yes, run full sequence"
      description: "Commit changes, push, then generate PR description"
    - label: "Cancel"
      description: "Stop here"
  ```
  - "Yes" → run commit mode (grouping + per-group messages), then
    push, then continue into PR description — all in this turn.
  - "Cancel" → stop.

- **Unpushed commits, no uncommitted changes** → use `AskUserQuestion`:
  ```
  question: "Branch has unpushed commits. Push first?"
  header: "Pre-flight"
  options:
    - label: "Push + open PR"
      description: "Push to remote, then generate PR description"
    - label: "Cancel"
      description: "Stop here"
  ```
  - "Push + open PR" → push, then continue into PR description.
  - "Cancel" → stop.

- Both clean and pushed → proceed.

#### Step 3: Ask for base branch

Use `AskUserQuestion`:

```
question: "Which base branch should this PR target?"
header: "Base branch"
options:
  - label: "main"
    description: "Merge into main (Recommended)"
  - label: "master"
    description: "Merge into master"
  - label: "develop"
    description: "Merge into develop"
```

User can also select "Other" to type a custom branch name.
Use the selected value as `<base>`.

#### Step 4: Read branch context

```bash
git log <base>..HEAD --oneline
git diff <base>...HEAD --stat
```

If `--stat` output is <500 lines:
```bash
git diff <base>...HEAD
```

#### Step 5: Reviewer-friendliness check

Before generating the description, scan the diff for issues that make
human review harder. Flag any of the following and advise the user —
do not block, let them decide whether to act:

- **Noise**: commented-out code, debug prints, unrelated whitespace/
  formatting changes, IDE artefacts
- **Oversized changeset**: many unrelated files changed together —
  suggest splitting into smaller PRs
- **Non-obvious logic without comment**: complex expressions, subtle
  side-effects, workarounds — suggest adding a brief inline comment
- **Unnecessary code added**: speculative abstractions, unused helpers,
  over-engineered solutions — suggest simplifying before review

Present findings concisely in text, then use `AskUserQuestion`:

```
question: "Address these before creating the PR?"
header: "Review notes"
options:
  - label: "Address first"
    description: "Stop here so you can fix the flagged issues"
  - label: "Continue as-is"
    description: "Generate the PR description now"
```

Track whether any issues were noted (even if user skips them) — used in Step 6.

#### Step 6: Generate PR description

```markdown
## Summary

<1-3 paragraphs of prose explaining what changed and why.
Draw from the commit messages and diff. Do not bullet-list
the summary — write connected prose.>

## Test plan

- [ ] <specific thing to verify, drawn from actual changes>
- [ ] <another specific check>
```

If issues were noted in Step 5 (whether addressed or not), append:

```markdown
---
*Some areas in this PR are marked for follow-up improvement. They are
functional but may benefit from further cleanup or optimisation in a
future PR.*
```

Rules:
- Summary: prose only, explains motivation, not file inventory; keep it brief
- Test plan: bullets must be specific to this PR's actual changes,
  not generic ("run tests", "check it works")
- Description should help a human reviewer understand motivation and
  risk — not restate the diff or list files

#### Step 6: Present for review

Print the generated description in a fenced block, then use
`AskUserQuestion`:

```
question: "Create PR with this description?"
header: "PR review"
options:
  - label: "Accept"
    description: "Create the PR now"
  - label: "Edit"
    description: "Modify the description before creating"
  - label: "Reject"
    description: "Discard — do not create PR"
```

#### Step 7: Create PR or print

- **Accept**:
  - Check if `gh` is available: `gh --version`
  - If available: derive title from first commit subject, then
    `gh pr create --title "..." --body "$(cat <<'EOF' ... EOF)"`
  - If not available: print the description with instruction:
    "gh CLI not found. Copy the description above and paste it
    when creating the PR manually."
- **Edit**: apply changes, then same branching as Accept
- **Reject**: stop

---

### Mode: `style`

#### Step 1: Read active style

```bash
cat ~/.claude/active-profile.yaml 2>/dev/null
```

Extract `git.commit_style`. Default: `conventional` if absent.

#### Step 2: Offer style selection via AskUserQuestion

Use the `AskUserQuestion` tool with four options — the three built-in
styles plus "Keep current". Mark the active style with "(active)" in
its label.

Example (active = conventional):
```
question: "Switch to a different commit style?"
header: "Commit style"
options:
  - label: "conventional (active)"
    description: "feat(scope): subject — Conventional Commits 1.0"
  - label: "imperative"
    description: "Add feature — imperative verb, no type prefix"
  - label: "tim-pope"
    description: "Add feature — same as imperative, 72-char body wrap"
  - label: "Keep current"
    description: "No change"
```

#### Step 3: Apply switch (if requested)

If user selected a style other than "Keep current":
1. Read `~/.claude/active-profile.yaml`
2. Update `git.commit_style: <new_style>` (add `git:` block if
   absent)
3. Write back the file
4. Print: "Style updated: conventional → imperative"

If no active profile exists:
- Print: "No active profile. Run `/dev:profile use <name>` first,
  then use `/dev:git style` to change the git style."
- Stop.

If user selected "Keep current":
- Print: "Style unchanged: conventional"

---

## Final Instructions

1. Determine mode from argument or show interactive menu
2. For `commit`: check staged diff → generate message → review gate
   → commit only on explicit accept
3. For `pr`: ask base branch → read commits + diff → generate
   description → review gate → create PR or print
4. For `style`: show styles → optionally write updated style to
   active profile
5. **Never run `git commit` or `gh pr create` without explicit
   user approval in the current turn**
6. **Never use `git add -A` or `git add .`** — always stage files
   explicitly by name; briefly justify each file before staging
7. **Never read the full project codebase** — work from git output
   only
