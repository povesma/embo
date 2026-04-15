# 014-git-commit-pr-texts — Task List

## Relevant Files

- [2026-03-29-014-git-commit-pr-texts-prd.md](
  2026-03-29-014-git-commit-pr-texts-prd.md)
  :: PRD
- [2026-03-29-014-git-commit-pr-texts-tech-design.md](
  2026-03-29-014-git-commit-pr-texts-tech-design.md)
  :: Technical Design
- [2026-03-29-014-git-commit-pr-texts-test-plan.md](
  2026-03-29-014-git-commit-pr-texts-test-plan.md)
  :: Test Plan
- [.claude/commands/dev/git.md](../../.claude/commands/dev/git.md)
  :: Command file
- [.claude/skills/dev-git/SKILL.md](../../.claude/skills/dev-git/SKILL.md)
  :: Natural language trigger skill
- [.claude/skills/dev-git/commit-styles.md](../../.claude/skills/dev-git/commit-styles.md)
  :: Supporting file — commit style definitions
- [.claude/commands/dev/profile.md](
  ../../.claude/commands/dev/profile.md)
  :: Add git style line to activation output
- [.claude/profiles/quality.yaml](../../.claude/profiles/quality.yaml)
  :: Add git: block
- [.claude/profiles/fast.yaml](../../.claude/profiles/fast.yaml)
  :: Add git: block
- [.claude/profiles/minimal.yaml](../../.claude/profiles/minimal.yaml)
  :: Add git: block
- [.claude/profiles/research.yaml](
  ../../.claude/profiles/research.yaml)
  :: Add git: block
- [README.md](../../README.md)
  :: Add /dev:git row to Available Commands table

## Notes

- All deliverables are `.md` prompt files and `.yaml` config files.
  No scripts, no binaries — prompt engineering only.
- TDD does not apply. Testing means running the commands and
  observing behaviour.
- Verification methods per canonical taxonomy in `/dev:test-plan`.

## Tasks

- [X] 1.0 **User Story:** As a developer with staged changes, I want
  `/dev:git commit` to generate a quality commit message following
  the active style, so I get consistent commits without writing
  from scratch [6/6]
  - [X] 1.1 Create `.claude/commands/dev/git.md` with header, "When
    to Use", subcommand table, and no-subcommand interactive menu
    (commit / pr / style) [verify: code-only]
  - [X] 1.2 Add commit mode: read profile → run
    `git diff --staged --stat` → run `git diff --staged` +
    `git log --oneline -10` → generate message per active style
    [verify: code-only]
  - [X] 1.3 Embed all three style definitions (conventional,
    imperative, tim-pope) with subject format rules and body
    guidance inside `git.md` [verify: code-only]
  - [X] 1.4 Add review-before-commit gate: present message, ask
    accept / edit / reject; only run `git commit` on accept
    [verify: code-only]
  - [X] 1.5 Verify: run `/dev:git commit` on a real repo with
    staged changes; confirm diff is read and message matches
    conventional format [verify: manual-run-claude]
    → ran on this repo; empty staged detected, files grouped by
      intent, two conventional messages generated and committed
      [live] (2026-03-29)
  - [X] 1.6 Verify: confirm Claude does not auto-commit without
    explicit user approval [verify: manual-run-user]
    → user confirmed: commit only ran after explicit 'a' [live]
      (2026-03-29)

- [X] 2.0 **User Story:** As a developer opening a PR, I want
  `/dev:git pr` to generate a description from commits + diff,
  so reviewers understand the motivation immediately [8/8]
  - [X] 2.1 Add PR mode: always ask base branch → read
    `git log <base>..HEAD` + `git diff <base>...HEAD --stat`
    → read full diff only if <500 lines [verify: code-only]
  - [X] 2.2 Add PR output template: `## Summary` (prose) +
    `## Test plan` (specific checklist bullets) [verify: code-only]
  - [X] 2.3 Add review-before-create gate: present description,
    ask accept / edit / reject; on accept check for `gh` CLI
    [verify: code-only]
  - [X] 2.4 Add `gh` degradation: if `gh` not available, print
    description with paste instruction [verify: code-only]
  - [X] 2.5 Verify: run `/dev:git pr` on a branch with commits;
    confirm base branch prompt appears and description has both
    sections [verify: manual-run-claude]
    → ran on feature/014 branch; base branch prompted, Summary +
      Test plan sections generated, PR created at
      povesma/rlm-mem#8 [live] (2026-03-29)
  - [X] 2.6 Verify: confirm no PR created without explicit approval
    [verify: manual-run-user]
    → user approved every PR via accept gate; none created without
      explicit 'a' [live] (2026-04-05)
  - [X] 2.7 N/A — `gh` CLI is a required dependency; degradation
    path not needed [verify: n/a] (2026-04-06)
  - [X] 2.8 Add reviewer-friendliness check in `pr` mode: after
    reading diff, flag noise / oversized changeset / uncommented
    non-obvious logic / over-engineering; advise and proceed (never
    block); if issues flagged, append follow-up note to PR description
    [verify: manual-run-claude]
    → fired on oversized PR (#9) this session; noted large changeset,
      user chose continue as-is [live] (2026-04-06)

- [X] 3.0 **User Story:** As a developer with nothing staged, I want
  `/dev:git` to show unstaged files and offer to stage them, so I
  am not blocked by an empty diff [3/3]
  - [X] 3.1 Add empty-staged handler: run `git status --short`;
    if nothing at all → exit with message; if unstaged changes
    exist → show list and offer stage-all / stage-selected /
    cancel [verify: code-only]
    → implemented in git.md Step 2 with grouping, [?] for
      unrelated files, explicit staging [live] (2026-03-29)
  - [X] 3.2 Verify: run `/dev:git commit` with nothing staged but
    unstaged changes present; confirm file list shown and staging
    options offered [verify: manual-run-claude]
    → grouping flow used in multiple sessions; files grouped by
      intent, user selects groups, files staged explicitly [live]
      (2026-04-02)
  - [X] 3.3 Verify: user selects files to stage and generation
    proceeds [verify: manual-run-user]
    → user selected groups (1, 2, 1+3+4) across sessions; commit
      messages generated and committed for each [live] (2026-04-05)

- [X] 4.0 **User Story:** As a developer, I want `/dev:git style`
  to list available styles and let me switch the active one, so I
  can manage commit style without editing YAML manually [3/3]
  - [X] 4.1 Add style mode to `git.md`: read active profile →
    display three styles with subject examples + active marker →
    prompt for switch → write updated `git.commit_style` to
    `~/.claude/active-profile.yaml`; handle missing profile case
    [verify: code-only]
    → implemented in git.md Mode: style section [live] (2026-03-29)
  - [X] 4.2 Verify: run `/dev:git style`; confirm AskUserQuestion
    UI shown with active marker [verify: manual-run-claude]
    → AskUserQuestion displayed with 4 options, active marked;
      no text prompt [live] (2026-04-07)
  - [X] 4.3 Verify: switch style and confirm `active-profile.yaml`
    updated; run `/dev:git commit` and confirm new style used
    [verify: manual-run-user]
    → switched to imperative, active-profile.yaml updated;
      conventional restored after [live] (2026-04-07)

- [X] 5.0 **User Story:** As a developer or team lead, I want
  `git.commit_style` in my workflow profile so the whole team
  follows the same convention [2/2]
  - [X] 5.1 Add `git:` block with `commit_style: conventional`
    to all four profile files: quality.yaml, fast.yaml,
    minimal.yaml, research.yaml [verify: code-only]
    → added git: block to all four profiles (2026-04-06)
  - [X] 5.2 Verify: activate a profile and run `/dev:git commit`;
    confirm style from profile is used (not hardcoded default)
    [verify: manual-run-claude]
    → switched to imperative, confirmed commit style read from
      active-profile.yaml [live] (2026-04-07)

- [X] 6.0 **User Story:** As a developer checking the active
  profile, I want `/dev:profile use <name>` to show the git
  commit style, so I can confirm the style at a glance [2/2]
  - [X] 6.1 Add "Git: commit style: <value>" line to the `use
    <name>` confirmation output template in `profile.md`
    [verify: code-only]
    → added line to profile.md confirmation output (2026-04-06)
  - [X] 6.2 Verify: run `/dev:profile use quality`; confirm output
    includes the git style line [verify: manual-run-claude]
    → "Git: commit style: conventional" shown in activation output
      [live] (2026-04-06)

- [X] 7.0 **User Story:** As a user running `install.sh`, I want
  `git.md` available in `~/.claude/commands/dev/` and the README
  updated [2/2]
  - [X] 7.1 Confirm `install.sh` wildcard `cp -r commands/dev/*`
    covers `git.md` — no change needed; document as verified
    [verify: code-only]
    → install.sh uses `cp -r commands/dev/*` which covers git.md;
      also verified in 8.2 [live] (2026-03-30)
  - [X] 7.2 Add `/dev:git` row to the Available Commands table in
    `README.md` with description "Generate commit messages and PR
    descriptions; manage commit style" [verify: code-only]
    → added to Development Phase section in README (2026-04-06)

- [X] 8.0 **User Story:** As a developer, I want to say "commit my
  changes" or "create a PR" in natural language and have Claude
  auto-invoke `/dev:git`, so I don't need to remember the slash
  command for routine git operations [4/4]
  - [X] 8.1 Add frontmatter `description` to `git.md` so it
    auto-triggers on natural language — no separate SKILL.md needed
    since commands and skills are the same thing in Claude Code
    [verify: code-only]
    → added frontmatter with description + argument-hint to
      git.md; single /dev:git entry, auto-trigger via description,
      no duplicate entries [live] (2026-03-30)
  - [X] 8.2 Confirm `install.sh` wildcard covers `git.md` —
    no change needed [verify: code-only]
    → install.sh `cp -r commands/dev/*` already covers git.md;
      verified no skills directory needed [live] (2026-03-30)
  - [X] 8.3 Verify: type "commit my changes" without a slash
    command; confirm Claude auto-invokes `/dev:git` [verify:
    manual-run-user]
    → DEV-GIT reminder triggers and Claude invokes dev:git skill;
      confirmed across multiple sessions [live] (2026-04-05)
  - [X] 8.4 Verify: type "create a PR from current changes";
    confirm Claude auto-invokes `/dev:git pr` flow [verify:
    manual-run-user]
    → "let's create a PR" triggered DEV-GIT and routed to
      /dev:git pr flow [live] (2026-04-05)

