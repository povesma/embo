---
description: >
  Generate git commit messages and PR descriptions, manage commit style, or
  rapidly deliver a change in one approval. Use when the user wants to commit
  changes, push a branch, open a pull request, or change their commit
  convention. `deliver` is the default delivery path: one commit of the
  needed files, pushed to the branch after ONE plan approval. Use the
  `commit`/`pr` modes instead only when the change needs the careful
  treatment — splitting into several commits, polished messages for human
  review, or genuinely large/mixed work. Examples: "deliver this", "push
  this fix", "just ship it", "commit my changes", "create a PR", "what
  commit style am I using".
argument-hint: "[commit|pr|style|deliver]"
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
| `/embo:git` | Interactive menu: commit / pr / style |
| `/embo:git commit` | Generate commit message for staged changes |
| `/embo:git pr` | Generate PR description for current branch |
| `/embo:git style` | List available styles; switch active style |
| `/embo:git deliver` | One-shot delivery: stage + commit + push (+ PR + merge) after a single plan approval |

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
- **body**: **optional and often unnecessary.** Goal of the whole
  message is to help someone find the right commit later — what
  and (when non-obvious) why. Add a body only when the diff cannot
  answer *why* on its own. Never restate file names, line numbers,
  or what the diff already shows. Keep it short — a sentence or two
  is usually enough. Bullet lists OK when each item adds context
  the diff doesn't provide. When in doubt, leave the body off.
- **footer**: optional; `BREAKING CHANGE: <description>` or
  `Closes #N`

Examples — prefer subject-only when the change is self-evident:

```
feat(profiles): add git.commit_style field
```

```
docs(check): guard ai-docs update step to existing dirs only
```

Add a body only when *why* is non-obvious from the diff:

```
fix(installer): skip symlink creation on Windows

Symlinks need admin rights on Windows; the install would fail
silently for non-admin users.
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

**Delegation checkpoint (per RULE:DELEGATE trigger 5).** If delivery
includes a deploy-then-verify loop, offer to run it in a subagent
(marker `[delegate:trigger-5]`). Routine stage/commit/push stays
inline.

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

  [1] feat(git): add /embo:git command
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

#### Step 5: Commit

Print the generated message in a fenced block, then immediately run `git commit -m "$(cat <<'EOF' ... EOF)"`.

**No skill-level confirmation gate.** Claude Code's harness already prompts "allow this command?" before every Bash tool call — that is the single confirmation point. Adding an AskUserQuestion before the commit would double-prompt the user for the same decision. The user can deny the harness prompt to reject or edit.

**Fallback**: if the harness is ever configured to auto-allow git commands (no permission prompt), re-add a skill-level AskUserQuestion gate before commit/push/PR-create to restore the safety checkpoint. The current design assumes the harness gate exists.

If the user asked for push (or push+PR) in the original invocation args, run `git push` (or `git push -u origin <branch>` if no upstream) after the commit succeeds. If multiple groups were selected (`1+2`), commit the next group before pushing. Otherwise just stop after commit.

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

- **Uncommitted changes exist** → run commit mode (grouping + per-group messages), then push, then continue into PR description — all in this turn. No confirmation prompt needed; the harness gates each individual command.
- **Unpushed commits, no uncommitted changes** → push, then continue into PR description.
- Both clean and pushed → proceed.

#### Step 3: Determine base branch

Default to `main`. If the user specified a base branch in args, use that instead. If the repo has no `main` branch, try `master`. Do NOT prompt for the base branch.

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

#### Step 6: Create PR

Print the generated description in a fenced block, then immediately run `gh pr create --title "..." --body "$(cat <<'EOF' ... EOF)"`. Same harness-gate principle as commit mode — no skill-level confirmation. The user sees the full command (including title + body) in the harness permission prompt and can deny it there.

If `gh` is not available, print the description with instruction: "gh CLI not found. Copy the description above and paste it when creating the PR manually."

---

### Mode: `deliver`

One-shot delivery: build a plan, get **one** approval, then run the whole
stage → commit → push → (open PR) → (merge) cycle with no further prompts.
**This is the default way to deliver code.** Use it whenever a change goes
to the repo as a single commit — regardless of size. Fall back to
`commit`/`pr` only when the change genuinely needs several commits, polished
messages for human review, or grouping of mixed concerns.

The cycle is executed by `plugin/bin/embo-deliver`, a bare command on the
Bash PATH. It makes no decisions — this skill builds the plan; the script
only executes it. Full contract:
`tasks/038-RAPID-DELIVER-one-shot-git/`.

**Prerequisite (one-time opt-in):** the user must add
`"Bash(embo-deliver *)"` to their `permissions.allow`. Without it the
script call prompts once (no worse than today); with it the single plan
approval below is the only interaction. If a `deliver` run triggers a
harness prompt for `embo-deliver`, tell the user to add that allow rule —
do not work around it.

#### Step 1: Build the delivery plan

**First, determine where the change must land to take effect.** Do not
reflexively default to the current branch. Read the surrounding context:
if it names a deploy / build / CI branch (e.g. `dev`, `staging`, a release
branch) that the change must reach for a build, deploy, or E2E run to
happen, THAT branch is the destination — reaching it means `pr` or
`pr-merge` with the correct `base` (or a direct push to it if that is the
repo's workflow), NOT leaving the commit on a personal feature branch via
`push`. A `push` to a feature branch that nothing builds from looks like
success but delivers nothing. When the destination is genuinely ambiguous
between the current branch and a deploy branch, surface the choice in the
plan (Step 3) — do not silently pick the current branch.

From the current development situation, determine:

- **branch** — the branch the change is delivered ON. For `push`, this is
  where the commit lands. For `pr`/`pr-merge`, this is the head branch the
  PR is opened FROM. Default to the current branch ONLY when no deploy
  branch is implicated (see above). This field is **authoritative**: the
  executor reconciles the working tree onto it before committing (see
  "Branch reconcile" below) — it does NOT commit on whatever branch you
  happen to be standing on. Name the real destination here; do not assume
  the checked-out branch is correct.
- **mode** — one of:
  - `push` — stage + commit + push. For a feature branch you own that
    nothing deploys from directly.
  - `pr` — push + open a PR into `base`. Use when the change must reach a
    protected or deploy branch (`dev`/`staging`/`main`), or needs review.
  - `pr-merge` — push + open a PR + merge it into `base`. Use when the user
    asked to land the change on the deploy branch in one go; merge is never
    implicit.
  - `release` — `pr-merge` + `git tag vX.Y.Z` + publish a GA GitHub
    Release. Choose it only when publishing a new version (version files +
    CHANGELOG changed); else prefer `pr-merge`.
- **base** — required for `pr`/`pr-merge`/`release`: the branch the PR
  merges into (default: `main`, or `master` if the repo has no `main`).
- **version** — required for `release`: no `v` prefix (e.g. `0.2.3`);
  executor tags `v<version>`. Confirm it is already set in the project's
  version files; never set or bump it yourself (ask if unclear).
- **release-notes** — required for `release`: the Release body block, per
  RULE:RELEASE-BODY-AUTHORING.
- **files** — the explicit set of files that make up this change, by name.
  Determine them from the work just done. **Never** stage `-A`/`.`; list
  every file deliberately. Files not part of this change are excluded. List
  the change's files even when the work is **already committed** and you
  only need to push + PR it to a deploy branch: the executor detects that
  nothing is left to stage, skips the commit with a loud warning, and
  delivers the existing commit. Do NOT invent an empty file list or re-list
  files to "satisfy" the executor — always name the change's real files.
- **message** — generate per the active `git.commit_style` (Step 0),
  exactly as in `commit` mode.

Inspect the working tree first (`git status --short`) so the file list is
accurate and unrelated dirty files are not swept in.

**Build the plan silently — do NOT present a draft.** Never show the
commit message or plan for review before writing the file; go straight
from Step 1 to Step 2. The plan-file Write dialog (Step 2) is the only
presentation and the only approval. A separate "here is my draft" turn
adds a second interaction, which defeats the point of `deliver` (the
whole flow costs the user exactly ONE approval).

#### Step 2: Write the plan file — this IS the approval gate

Write the plan to a **uniquely-named** file
`tmp/git-<timestamp>.txt` (e.g. `tmp/git-20260703-150210.txt`). Never
reuse a fixed name and never delete it — each delivery leaves its own
record. `tmp/` is gitignored.

**The Write permission dialog is the single approval.** It shows the
full plan file content — branch, mode, base, every file by name, the
verbatim commit message — so the user reviews the delivery in the
dialog itself. Approving the write authorizes the whole delivery;
rejecting it cancels the delivery. Do not show the plan in chat before
or after writing, and do not ask any follow-up question — either would
add a second interaction to a flow whose point is exactly one.

Format (line-oriented; scalar keys first, then block(s) — each block runs
to the next block header or EOF; `#` lines are ignored by the executor):

```
# pr-merge: PR will be MERGED into <base> — irreversible   <- REQUIRED
#                            comment for pr-merge / release plans
branch: <target-branch>
mode: push | pr | pr-merge | release
base: <base-branch>            # only for pr / pr-merge / release
version: <X.Y.Z>               # only for release (no v prefix)
file: <path>                   # one line per file, explicit names
file: <path>
release-notes:                 # only for release; the Release body
<release body, may span multiple lines>
message:
<commit message, verbatim, may span multiple lines>
```

For `pr-merge` and `release` plans the leading irreversibility comment is
mandatory — it warns the user that approval includes a merge (and, for
`release`, a public tag + Release).

**Branch reconcile (executor guarantee).** `plan.branch` is the single
source of truth for where the commit lands; the executor never trusts the
ambient checked-out branch. Before staging it:

1. **Refuses a protected base as a `push` commit target.** If `mode` is
   `push` and `branch` is `main`/`master`, delivery aborts (exit 7) — a
   commit must not land directly on a protected branch. To reach `main`,
   use `pr`/`pr-merge` with `base: main` (a protected branch is a valid PR
   *base*, never a `push` target).
2. **Reconciles the working tree onto `plan.branch`.** If you are on a
   different branch, it switches to `plan.branch`. If that branch does not
   exist, it is created from `base` (pr modes); in `push` mode there is no
   base, so an absent branch aborts (exit 7) with guidance rather than
   inventing the branch point from the current HEAD. A pre-existing branch
   is switched to as-is and never force-reset.
3. **Re-asserts** the branch immediately before commit; any drift aborts
   (exit 7) with no commit made.

Consequence for planning: name the true destination in `branch`. You do
not need to switch branches yourself before delivering — the executor
moves the working tree for you — but a `push` plan to a branch that does
not exist yet will abort, so create the branch first or use a `pr` mode.

**Zero-gate warning:** if the environment allowlists
`Write(tmp/git-*.txt)`, the write is silent and the delivery runs with
NO human gate (you cannot detect whether a dialog appeared). That rule
is a deliberate zero-click opt-in documented in the README; never
suggest adding it as a convenience.

#### Step 3: Execute (write approved) or stop (write rejected)

- **Write approved** → immediately run the bare command:

  ```bash
  embo-deliver --plan tmp/git-<timestamp>.txt
  ```

  Invoke it as a plain command exactly like this — no `${...}`, no
  `$(...)`, no redirects — or the compound-approve hook cannot
  auto-approve it. Relay the script's per-step result to the user
  (it reports which steps completed; a non-zero exit means it stopped at a
  failed step and did not undo prior steps).

- **Write rejected** → the delivery is cancelled. Nothing is staged,
  committed, pushed, or merged. Do NOT fall back to running git
  commands manually — a rejected plan means the user declined the
  delivery, not the method.

Do NOT add a confirmation question anywhere in this flow — the plan-file
Write approval in Step 2 is the single gate.

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
- Print: "No active profile. Run `/embo:profile use <name>` first,
  then use `/embo:git style` to change the git style."
- Stop.

If user selected "Keep current":
- Print: "Style unchanged: conventional"

---

<!-- RULE:CHANGELOG-AUTHORING -->
## CHANGELOG.md Authoring

*Audience: someone deciding whether to upgrade, and someone
reconstructing history later (downstream packagers, future-you,
anyone tracing a regression to a version).* Comprehensive but
ruthless with wording. Include all user-facing changes, categorised
by impact (Breaking, Security, Added, Changed, Fixed, Deprecated).
Each item: one sentence stating the change and its user impact. Add
a second sentence only when a reader must take action (migration
step, version range affected, workaround) — never to explain
rationale or implementation. Drop the *how* and the *why*; if
rationale matters, it lives in the commit message or PR.

<!-- RULE:RELEASE-BODY-AUTHORING -->
## GitHub Release Body Authoring

*Audience: someone glancing at the release page or a notification
feed, deciding whether this release needs their attention right
now.* Executive summary. Open with the most consequential change in
one sentence; if the release has a coherent theme, name it — if not,
don't invent one. Follow with a "Highlights" bullet list of anything
a reader of the release page needs to know without opening the
CHANGELOG. Breaking, security, deprecations, platform/dependency
shifts, and major features usually qualify; pure bug fixes and
internal changes do not. Link to the CHANGELOG for the rest.
Hand-written, not extracted mechanically from the CHANGELOG.

## Final Instructions

1. Determine mode from argument or show interactive menu
2. For `commit`: check staged diff → generate message → print message → run `git commit` (harness gate = user approval)
3. For `pr`: determine base branch → read commits + diff → generate description → print description → run `gh pr create` (harness gate = user approval)
4. For `style`: show styles → optionally write updated style to active profile
5. For `deliver`: build plan → write `tmp/git-<timestamp>.txt` → show plan + one AskUserQuestion → on Deliver run bare `embo-deliver --plan <path>` (single approval = the plan gate; requires the `Bash(embo-deliver *)` opt-in)
5. **No skill-level confirmation gates for non-destructive commands** (`git commit`, `git push`, `git add`, `gh pr create`). The Claude Code harness permission prompt is the single approval point. See Step 5 in commit mode for the design rationale and fallback instructions.
6. **DO use skill-level confirmation (AskUserQuestion) for destructive commands** (`git push --force`, `git reset`, `git rebase`) — explain what will happen and why before running. The harness prompt shows the command but not the context.
7. **Never use `git add -A` or `git add .`** — always stage files explicitly by name; briefly justify each file before staging
8. **Never read the full project codebase** — work from git output only

<!--
DORMANT SAFETY CHECKPOINTS — re-activate if the Claude Code harness ever auto-allows git/gh commands without a permission prompt.

Commit gate (insert before `git commit` in Step 5):
```
AskUserQuestion:
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
On Accept → run git commit. On Edit → apply changes, re-present. On Reject → stop.

Push gate (insert before `git push`):
```
AskUserQuestion:
  question: "Push to origin?"
  header: "Push"
  options:
    - label: "Push"
      description: "git push (or -u origin <branch> if no upstream)"
    - label: "Done"
      description: "Stop here, do not push"
```

PR create gate (insert before `gh pr create` in PR Step 6):
```
AskUserQuestion:
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
On Accept → run gh pr create. On Edit → apply changes, re-present. On Reject → stop.

Post-commit next-step gate (insert after successful commit):
```
AskUserQuestion:
  question: "Committed. What next?"
  header: "Next step"
  options:
    - label: "push"
      description: "git push"
    - label: "push + open PR"
      description: "Push, then generate PR description"
    - label: "done"
      description: "Stop here"
```
-->
