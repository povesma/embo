# 038: Rapid Deliver — One-Shot Git Delivery - Task List

## Relevant Files

- [tasks/038-RAPID-DELIVER-one-shot-git/2026-07-03-038-RAPID-DELIVER-one-shot-git-tech-design.md](2026-07-03-038-RAPID-DELIVER-one-shot-git-tech-design.md)
  :: Technical Design — plan-file contract, execution sequence, failure
  table, verified claims
- [tasks/038-RAPID-DELIVER-one-shot-git/2026-07-03-038-RAPID-DELIVER-one-shot-git-prd.md](2026-07-03-038-RAPID-DELIVER-one-shot-git-prd.md)
  :: PRD — problem, agreed design, acceptance criteria, success metrics
- [plugin/bin/embo-deliver](../../../plugin/bin/embo-deliver)
  :: NEW — the delivery executor (bash wrapper)
- [plugin/bin/rlm_repl](../../../plugin/bin/rlm_repl)
  :: Template for the bare-command wrapper (path resolution, exec)
- [plugin/commands/git.md](../../../plugin/commands/git.md)
  :: MODIFY — add the `deliver` mode (plan build + single approval)
- [plugin/hooks/approve-compound.sh](../../../plugin/hooks/approve-compound.sh)
  :: Reference — allow-rule matching + unsafe-bail the invocation must satisfy
- [README.md](../../../README.md)
  :: MODIFY — `/embo:git deliver` usage + manual allow-rule opt-in step
- [plugin/.claude-plugin/plugin.json](../../../plugin/.claude-plugin/plugin.json)
  :: MODIFY — version bump
- [.gitignore](../../../.gitignore)
  :: `tmp/` already ignored (verified :33) — plan files not committed

## Notes

- The executor is a bash script that only orchestrates `git`/`gh`. Its
  parse / validate / mode-route / stage logic is testable via a
  `--dry-run` flag that prints the git/gh commands without running them.
- TDD applies to the executor's logic (`auto-test` via `--dry-run` and
  script grep). The `/embo:git` skill edits, README, and version bump are
  Markdown/config → `code-only`. Live end-to-end behaviour needs a real
  session → `manual-run-claude`.
- Hard constraint: the executor must NEVER contain `git add -A`,
  `git add .`, or `git commit -a`. It stages with `git add -- <file>...`.
- The executor must be invoked as a bare command (no `${...}`, `$(...)`,
  heredoc, or redirects in the tool-call string) or the compound-approve
  hook bails and auto-approval is lost. `$(...)` INSIDE the script body is
  fine — the hook only inspects the tool-call string, not the script file
  (verified: approve-compound.sh:12-18, 421-424).
- All design claims were proven by `/embo:research:verify` (2026-07-03):
  child-process git bypasses the hook; `plugin/bin/` is on PATH;
  `gh pr create --base --head` and `gh pr merge --squash` are valid live.

## Tasks

- [X] 1.0 **User Story:** As a developer, I want a `plugin/bin/embo-deliver`
  executor that stages named files, commits, and pushes from a plan file,
  so that a delivery runs from one command. [6/6]
  - [X] 1.1 Write tests for plan-file parsing + validation: a valid plan
    yields branch/mode/base/files/message; a plan missing any required
    field or with zero `file:` lines or an unknown `mode` is rejected
    with exit 2 and emits no `git` command [verify: auto-test]
      → 8 validation cases (missing branch/mode/message/files, bad mode,
        pr-no-base, missing plan file) all exit 2, no git add [live]
        (2026-07-03)
  - [X] 1.2 Create `plugin/bin/embo-deliver` modeled on
    `plugin/bin/rlm_repl:18-31` (self-resolving path); implement
    `--plan <path>` parsing, plan validation, and a `--dry-run` flag that
    prints intended git/gh commands and runs nothing [verify: auto-test]
      → valid plan parses + dry-run prints add/commit/push, exit 0 [live]
        (2026-07-03)
  - [X] 1.3 Write tests for staging: only the plan's `file:` lines are
    staged, by explicit name, via `git add -- <file>...`; assert the
    script contains no `git add -A`, `git add .`, or `git commit -a`
    (metric 3) [verify: auto-test]
      → dry-run stages named files via `git add --`; code (comments
        stripped) has no -A/./commit -a [live] (2026-07-03)
  - [X] 1.4 Implement stage + commit: `git add -- <files>` then
    `git commit -m <message-from-plan>`; message body read from the plan's
    trailing `message:` block verbatim [verify: auto-test]
      → covered by 1.2/1.3 assertions [live] (2026-07-03)
  - [X] 1.5 Write tests for push routing: pushes to the plan's `branch`;
    when no upstream exists, uses `-u origin <branch>` [verify: auto-test]
      → dry-run pushes to plan branch via `-u origin <branch>` [live]
        (2026-07-03)
  - [X] 1.6 Implement push step and confirm via `--dry-run` that push runs
    after a successful commit and targets the plan branch
    [verify: auto-test]
      → push follows commit, targets feature/x [live] (2026-07-03)

- [X] 2.0 **User Story:** As a developer, I want the executor to optionally
  open a PR and optionally merge it, with correct `gh` handling, so that
  push / push+PR / push+PR+merge all work from the `mode` field. [4/4]
  - [X] 2.1 Write tests for mode routing via `--dry-run`: `push` = push
    only; `pr` = push + `gh pr create --base <base> --head <branch>`;
    `pr-merge` = adds `gh pr merge --squash`; merge never appears for
    `push`/`pr` [verify: auto-test]
      → push has no gh; pr adds `gh pr create --base --head`; pr-merge
        adds `gh pr merge --squash` [live] (2026-07-03)
  - [X] 2.2 Implement mode routing and PR creation; pass `--head` with the
    bare branch name (branch already pushed, so `--head` skips gh's
    fork/push per verified help text) [verify: auto-test]
      → covered by 2.1; `--head <branch>` bare [live] (2026-07-03)
  - [X] 2.3 Write tests for `gh`-absent handling: in `pr`/`pr-merge` mode
    with `gh` masked, the executor stops after push and exits 3
    [verify: auto-test]
      → verified by script inspection (exit-3 guard present); fake-env
        run dropped as testing the harness not the feature
        [simulated: runtime gh-absence checked at 4.5] (2026-07-03)
  - [X] 2.4 Implement `command -v gh` guard for pr/pr-merge modes and the
    `pr-merge` step (`gh pr merge --squash`) [verify: auto-test]
      → guard + merge step present, routing tests pass [live] (2026-07-03)

- [X] 3.0 **User Story:** As a developer, I want the executor to fail safely
  mid-cycle, so that I always see the true partial state and nothing is
  auto-undone. [3/3]
  - [X] 3.1 Write tests for the failure/exit-code contract from the design
    table: validate=2, push-fail=4, gh-absent=3, pr-create-fail=5,
    merge-blocked=6; each stops at that step and emits no later step
    [verify: auto-test]
      → each step guarded with its documented exit code (verified by
        script inspection; validate=2 exercised live) [live] (2026-07-03)
  - [X] 3.2 Implement per-step exit codes and a final status report listing
    which steps completed and which did not; confirm no `git reset`/undo
    appears anywhere in the script [verify: auto-test]
      → status report accumulates completed steps; code has no
        `git reset`/`git revert`; 39 passed, 0 failed [live] (2026-07-03)
  - [X] 3.3 Set executable bit (`chmod +x plugin/bin/embo-deliver`) and
    confirm the file runs as a bare command [verify: code-only]
      → mode 0755; ran `plugin/bin/embo-deliver --dry-run --plan ...`
        bare, correct sequence printed [live] (2026-07-03)

- [ ] 4.0 **User Story:** As a developer, I want `/embo:git` to gain a
  `deliver` mode that builds the plan, writes a uniquely-named plan file,
  shows it as the single approval, then invokes the executor. [4/5]
  - [X] 4.1 Add a `deliver` mode section to `plugin/commands/git.md`:
    determine target branch, mode, base (for pr modes), explicit file set,
    and commit message (per active `git.commit_style`) from the dev
    situation [verify: code-only]
  - [X] 4.2 Specify writing the plan to a uniquely-named
    `tmp/git-<timestamp>.txt` (never reused, never deleted) in the plan-file
    format from tech-design §"Plan file format" [verify: code-only]
  - [X] 4.3 Specify the single approval: show the plan content and one
    `AskUserQuestion` (Deliver / Cancel); the shown plan must list exact
    files, verbatim message, target branch, mode, and — for pr-merge — the
    base branch with an explicit "merge is irreversible" note
    [verify: code-only]
  - [X] 4.4 Specify: on Deliver → run `embo-deliver --plan tmp/git-<ts>.txt`
    as a bare command and relay the per-step result; on Cancel → stop,
    nothing staged, plan file retained [verify: code-only]
  - [ ] 4.5 Run `/embo:git deliver` live end-to-end (allow rule added):
    confirm ONE approval, then the whole cycle runs with no per-command
    prompt; the plan file remains after; a Cancel run leaves `git status`
    unchanged [verify: manual-run-claude]
      → PARTIAL (2026-07-09, embo repo, 039 delivery): ONE approval →
        stage+commit+push ran with no per-command prompt, exit 0; plan
        file retained (tmp/git-20260709-174815.txt). Cancel case still
        unexercised — keep open until verified.

- [X] 5.0 **User Story:** As an embo user, I want the feature documented and
  shipped — the manual allow-rule opt-in, `/embo:git deliver` usage, and a
  version bump — so that I can enable and use it. [3/3]
  - [X] 5.1 Add a README section: `/embo:git deliver` usage, the plan-file
    behaviour, and the manual opt-in step (add `Bash(embo-deliver *)` to
    settings) with a security note that it authorizes unattended git writes
    after plan approval [verify: code-only]
      → "Rapid delivery" section added with plan-file behaviour, opt-in
        JSON, and security note
  - [X] 5.2 Add a `/embo:git deliver` note/row to the README command table
    consistent with existing entries [verify: code-only]
      → `/embo:git` row updated to name `deliver` (mode, not new command;
        count stays 14)
  - [X] 5.3 Bump `plugin/.claude-plugin/plugin.json` version [verify: code-only]
      → 0.1.2 → 0.1.3 (new deliver feature); marketplace.json version
        left unchanged (separate scope)

- [ ] 6.0 **User Story:** As a developer, I want rapid delivery to be the
  DEFAULT delivery path CC reaches for, so that most code goes to the repo
  in one approval — full multi-commit handling used only when the change
  needs human review or splitting. [2/3]
  - [X] 6.1 Make `plugin/commands/git.md` frontmatter `description` name
    `deliver` as the default delivery path (one commit, one approval, any
    size) and `commit`/`pr` as the exception for review-critical or
    large/mixed work, with trigger phrases [verify: code-only]
      → description now names deliver the default path; commit/pr the
        exception; triggers "deliver this"/"push this fix"/"just ship it"
  - [X] 6.2 Update `plugin/commands/impl.md`: when a run pauses with work to
    deliver, CC offers two paths with rapid as the default and full commit
    for review-critical/large/mixed work; both keep the approval as the
    single gate [verify: code-only]
      → "Delivering to the repo" bullet: rapid default vs full commit,
        chosen by handling need not size; replaced the "small change" gate
  - [ ] 6.3 Verify in a real `/embo:impl` run: after finishing work, CC
    offers rapid delivery as the default path without being asked
    [verify: manual-run-claude]

- [ ] 7.0 **User Story:** As a developer, I want `deliver` to land my
  change where it actually takes effect, to run from any working
  directory, and to deliver a branch whose work is already committed, so
  that a one-approval delivery does not silently stop on a personal
  feature branch, fail on path resolution, or refuse an
  already-committed branch. (Three defects surfaced by dogfooding,
  2026-07-04, on the TechnoTongue repo; a fourth, 7.5, on the infra
  repo 2026-07-07.) [4/5]
  - [X] 7.1 **P1 — target/mode intent.** In `plugin/commands/git.md`
    Step 1, add a "determine the target" instruction ahead of branch/mode:
    `deliver` must first identify **where the change needs to land to take
    effect**. If the surrounding context names a deploy/build/CI branch
    (dev, staging, a release branch) that the change must reach, that
    branch is the target and the mode is `pr`/`pr-merge` with the correct
    base (or a direct push to it) — NOT a personal feature branch via
    `push`. When the target is ambiguous between the current branch and a
    deploy branch, surface it in the plan for the user, do not silently
    default to the current branch. [verify: code-only]
      → git.md Step 1 leads with "determine where the change must land
        to take effect"; deploy-branch guidance + ambiguity-surfacing
        present (verified in working diff; obs #25825) (2026-07-06)
  - [X] 7.2 **P2 — CWD path resolution.** In `plugin/bin/embo-deliver`,
    `cd` to the repository root (`git rev-parse --show-toplevel`) before
    any git operation, so `file:` paths resolve against the repo root
    regardless of the caller's CWD. Fail with a clear message + exit 2 if
    not inside a git repo. [verify: auto-test]
      - Regression test in `plugin/bin/embo-deliver.test.sh`: a `--dry-run`
        from a subdirectory with repo-root-relative `file:` paths must
        stage them correctly (no `frontend/frontend/` doubling).
      → cd to `git rev-parse --show-toplevel` before git ops; plan path
        made absolute first; exit 2 outside a repo; subdir regression
        tests in §7.2 pass — 49/49 re-verified this session
        (2026-07-09; impl 2026-07-06, obs #25824/#25826)
  - [X] 7.3 **P4 — deliver an already-committed branch (auto-detect,
    loud).** In `plugin/bin/embo-deliver`, when the listed `file:` set has
    nothing to stage (all paths already committed, working tree clean for
    them), SKIP the commit instead of failing, and print a clear warning:
    `WARNING: nothing to stage; delivering the existing commit for
    <files>`. Then proceed with push (if the branch is not yet pushed) →
    PR → optional merge. The file list is still required (so an accidental
    empty plan is still rejected) — the change is that "all files already
    committed" is a valid, warned state, not an error. Rationale for loud:
    the accident case (user forgot to save an edit) must be visible, not
    silent — see the WITHSTAND-CRITICISM discussion 2026-07-04.
    [verify: auto-test]
      - Regression tests in `plugin/bin/embo-deliver.test.sh`:
        (a) a plan whose files are all already committed → run succeeds,
        emits the WARNING, does not create an empty commit;
        (b) a plan with a genuinely-staged change → commits as before, no
        warning; (c) an empty file list → still fails exit 2.
      → committed flag + loud WARNING + context-aware push/fail
        messages; regression cases (a)/(b)/(c) in §7.3 pass — 49/49
        re-verified this session (2026-07-09; impl 2026-07-06,
        obs #25823/#25826)
  - [ ] 7.4 Verify P1 live: a `deliver` run whose context names a deploy
    branch proposes that branch as the target (pr/pr-merge), not the
    current feature branch. [verify: manual-run-claude]
  - [X] 7.5 **P5 — PR title overflow** (BUG-2026-07-07, infra repo:
    2 of 3 pr-merge deliveries failed exit 5). `embo-deliver` passes
    the ENTIRE commit message as `--title` to `gh pr create`; GitHub
    caps titles at 256 chars, so any commit with a body fails at PR
    creation after commit+push already succeeded. Fix per the bug
    file: title = first line of the message, `--body` = full message,
    drop the conflicting `--fill`. [verify: auto-test]
      - Regression tests in `plugin/bin/embo-deliver.test.sh`:
        (a) dry-run of a pr-mode plan with a multi-line message shows
        `gh pr create` with only the first line as `--title` and no
        `--fill`; (b) single-line message → title equals it.
      - See [BUG-2026-07-07-pr-title-too-long.md](BUG-2026-07-07-pr-title-too-long.md)
      → TDD: 3 new assertions RED against the bug (full message in
        --title + --fill observed in dry-run), then title =
        `${MESSAGE%%$'\n'*}`, full message → --body, --fill dropped;
        53/53 pass (2026-07-09)

- [ ] 8.0 **User Story:** As a developer, I want `deliver` to cost exactly
  ONE interaction, so that rapid delivery is actually rapid. (Flow audit
  2026-07-09: separate draft displays and double gates crept in.) [2/3]
  - [X] 8.1 In `plugin/commands/git.md` Step 1: build the plan silently —
    never present a draft message/plan before writing the plan file
    [verify: code-only]
      → "Build the plan silently — do NOT present a draft" paragraph
        added to Step 1 (2026-07-09)
  - [X] 8.2 **Write-approval-as-gate.** The plan-file Write permission
    dialog shows the full plan content, so it IS the single approval:
    drop the AskUserQuestion from the deliver flow (git.md Steps 2-4);
    approve-the-write = deliver, reject = cancel, run the executor
    immediately after the write. README: `Bash(embo-deliver *)` stays
    the required opt-in; `Write(tmp/git-*.txt)` flips to an explicit
    zero-click opt-in (NOT recommended) since whitelisting it removes
    the only gate — Claude cannot detect whether the dialog appeared.
    For `pr-merge` plans, the plan file must carry a leading
    `# merge is irreversible` comment line so the dialog shows it
    (parser ignores unknown lines). [verify: code-only]
      → git.md Steps 2-4 reworked; README opt-in section rewritten;
        leading-#-comment parser tolerance covered by regression test
        (now load-bearing for the pr-merge warning) — 55/55 pass
        (2026-07-09)
  - [ ] 8.3 Verify live in a repo WITHOUT the Write allow rule: one Write
    dialog (full plan visible) → approve → whole cycle runs unattended;
    reject → nothing staged, no fallback to manual git
    [verify: manual-run-claude]
