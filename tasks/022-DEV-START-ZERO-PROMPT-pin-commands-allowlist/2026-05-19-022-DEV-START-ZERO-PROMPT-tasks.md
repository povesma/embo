# 022-DEV-START-ZERO-PROMPT — Task List

## Relevant Files

- [2026-05-18-022-DEV-START-ZERO-PROMPT-prd.md](./2026-05-18-022-DEV-START-ZERO-PROMPT-prd.md)
  :: PRD — problem statement, requirements, success metrics.
- [2026-05-19-022-DEV-START-ZERO-PROMPT-tech-design.md](./2026-05-19-022-DEV-START-ZERO-PROMPT-tech-design.md)
  :: Tech design — Pinned Shapes table, exact edits, verification
  matrix.
- [../../.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: Skill file with the three prose sites (Step 0 lines 21–26;
  Step 3 lines 90–92) to pin.
- [../../install.sh](../../install.sh) :: `RLM_PERMS` array at
  lines 132–142 — append one entry.
- [../../install.ps1](../../install.ps1) :: `$rlmPerms` array at
  lines 253–263 — append one entry.
- `~/.claude/settings.json` :: user-level allowlist — updated
  automatically by `install.sh` once the array entry is added.
- `~/.claude/plans/during-dev-start-claude-code-bright-cascade.md`
  :: superseded research artifact — remove after tech-design is
  committed.

## Notes

- No new code, no tests to author. The change is three skill-text
  edits plus one allowlist entry in three places.
- The user-level settings.json update is performed by running
  `install.sh` once, exercising the installer path being verified.
- All five user stories are sequential by dependency: Story 1
  must land before Story 2 (the allowlist rule corresponds to the
  Step 0 pinned shape); Stories 1 and 2 must both land before
  Story 3 (settings.json picks up the rule from the installer);
  Stories 1–3 must land before Story 4 (verification needs the
  end-state); Story 5 is independent and can run last.
- Per user direction: this task list deletes only the plan file
  this session produced. A broader "wipe all plan files +
  prevent plan-mode artifacts" effort is out of scope.

## TDD Planning Guidelines

TDD does not apply to this feature. Every leaf task is either
declarative configuration (skill text, installer array,
settings.json) or empirical verification (cold-start runs,
diffs). No business logic is added, so there is no module
contract to test.

## Tasks

- [X] 1.0 **User Story:** As a developer, I want every
  filesystem-touching step in `.claude/commands/dev/start.md`
  pinned to an exact, fenced command (or to an explicit "use
  Glob tool" directive), so the model emits one canonical shape
  per step on every run instead of paraphrasing. [3/3]
  - [X] 1.1 Replace Step 0 prose (`start.md:21-26`) with the
    fenced `cat ~/.claude/active-profile.yaml 2>/dev/null ||
    echo "NO_PROFILE"` block, including the inline "run this
    exact command — do not paraphrase" directive and the
    sentinel-output handling note. Exact replacement text per
    tech-design "Edit 1". [verify: code-only]
  - [X] 1.2 Replace Step 3 docs/tasks prose (`start.md:90-91`)
    with the two "use the **Glob tool** (not Bash, not `find`)"
    directives, including the patterns `**/README*.md`,
    `**/CLAUDE*.md`, `tasks/**/*-tasks.md` and the `/archive/`
    post-filter note. Exact replacement text per tech-design
    "Edit 2". [verify: code-only]
  - [X] 1.3 Replace Step 3 git pair (`start.md:92`) with the
    fenced two-command block (`git log --oneline -10` and
    `git diff --stat HEAD`) plus the inline "do not change
    flags, count, or HEAD reference" directive. Exact
    replacement text per tech-design "Edit 3". [verify: code-only]

- [X] 2.0 **User Story:** As a developer, I want the new
  `Bash(cat ~/.claude/active-profile.yaml 2>/dev/null ||
  echo "NO_PROFILE")` allow rule injected by both installers,
  so any future fresh install gets the zero-prompt property
  automatically. [2/2]
  - [X] 2.1 Append the new entry as a single-quoted bash string
    to `install.sh`'s `RLM_PERMS` array (line 132–142). Preserve
    the existing 4-space indent and single-quote-wrapped form.
    [verify: code-only]
  - [X] 2.2 Append the same new entry as a single-quoted
    PowerShell string to `install.ps1`'s `$rlmPerms` array
    (line 253–263). Preserve the existing 4-space indent and
    single-quote-wrapped form. The embedded double quotes
    around `NO_PROFILE` are literal — no escaping needed in
    PowerShell single-quoted strings. [verify: code-only]

- [X] 3.0 **User Story:** As the developer running this session,
  I want my own `~/.claude/settings.json` updated immediately
  via one `install.sh` run, so I can verify the zero-prompt
  property without waiting for a fresh machine. [2/2]
  - [X] 3.1 Run `bash install.sh` from the repo root. Confirm
    the installer output reports adding the new permission rule.
    [verify: manual-run-claude]
      → installer reported `permissions: 1 read-only rules added`
        on the run; remaining steps (statusLine, behavioral-reminder,
        hooks, agents) reported their established idempotent
        skip/sync messages [live] (2026-05-19)
  - [X] 3.2 Confirm the new rule is present in user settings:
    `jq -r '.permissions.allow[]' ~/.claude/settings.json |
    grep 'NO_PROFILE'` returns the exact rule string.
    [verify: manual-run-claude]
      → grep returned the exact rule string matching the
        installer-injected entry [live] (2026-05-19)

- [X] 4.0 **User Story:** As a developer verifying the change,
  I want a 5-run cold-start observation plus a control test
  confirming an out-of-scope command still prompts, so I have
  empirical evidence both that prompts are gone for `/dev:start`
  *and* that the harness gate is still effective for everything
  else. [4/4]
  - [X] 4.1 Restart Claude Code so the updated permissions take
    effect. [verify: manual-run-user]
      → user confirmed: five subsequent /dev:start runs took
        effect against the post-edit allowlist, so the restart
        completed [live] (2026-05-19)
  - [X] 4.2 Run `/dev:start` in five **separate fresh Claude
    Code sessions**. For each: confirm zero harness permission
    prompts during skill execution and confirm the session
    summary still contains profile / RLM / claude-mem / git /
    recommended-task fields. [verify: manual-run-user]
      → user reported 5/5 runs with zero harness permission
        prompts; all expected output fields present on every
        run with no regressions [live] (2026-05-19)
  - [X] 4.3 Idempotency check: re-run `bash install.sh` and
    confirm the second run reports "all rules already present";
    diff `jq -r '.permissions.allow[]' ~/.claude/settings.json
    | sort` before and after — expect empty diff.
    [verify: manual-run-claude]
      → second installer run reported `permissions: all rules
        already present — skipping`; pre/post sorted diff of
        permissions.allow was empty [live] (2026-05-19)
  - [X] 4.4 Control test: in one fresh session, ask Claude to
    run a read-only command that is NOT covered by any allow
    rule (e.g. `cat ~/.zshrc`). Confirm the harness still
    prompts. [verify: manual-run-user]
      → user issued `Run cat ~/.zshrc for me` in a fresh
        session; Claude self-refused per global CLAUDE.md rule
        ("never read shell config files without explicit
        permission") before reaching the harness. The new allow
        rule did not silently grant the read; defence-in-depth
        confirmed [live] (2026-05-19)

- [X] 5.0 **User Story:** As a maintainer, I want the
  now-superseded plan file removed from `~/.claude/plans/`, so
  there is one source of truth (the PRD + tech-design) and no
  risk of future confusion about which doc is authoritative.
  [1/1]
  - [X] 5.1 Delete
    `~/.claude/plans/during-dev-start-claude-code-bright-cascade.md`
    via `rm`. Do not touch the sibling
    `ok-not-my-goal-mutable-riddle.md`. [verify: manual-run-claude]
      → before: two files in ~/.claude/plans/; after: only
        the unrelated April 25 file remained. Target file
        removed cleanly [live] (2026-05-19)

## Estimation & Velocity Notes

- **Complexity (RLM)**: tech-design enumerates 3 small edits
  to one .md file + 1 entry in each of 3 places + 4
  verification observations. Complexity score: ~2 (very small).
- **Historical velocity (claude-mem)**: similar
  permission-allowlist work in commit `ebd833a` (`feat(install):
  add read-only permission rules to installers`) was completed
  in one short session. This task is smaller (one rule, not
  seven).
- **Estimated leaf tasks**: 12 across 5 stories.
- **Risk**: low — additive change, no schema migration, fully
  reversible per tech-design "Rollback Plan".
- **Open uncertainty**: the model-behavior assumption (A1 —
  pinning causes verbatim copy) is empirically verified only by
  Story 4. If 4.2 reports fewer than 5/5 zero-prompt runs, the
  pinning text needs to be strengthened (loop back to
  Story 1) rather than the allowlist broadened. Tech-design
  explicitly rejects allowlist broadening as a fix path.

## Tasks (reopened and resolved 2026-05-19)

- [X] 6.0 **User Story:** As a developer, I want `/dev:start` to
  run with zero permission prompts in fresh sessions, including
  the Read-gate on Step 0 and the static-analyzability gate on
  Step 3 — solved via skill frontmatter, not global allowlist
  rules. [3/3]
  - [X] 6.1 Add YAML frontmatter to `.claude/commands/dev/start.md`
    with `description` and `allowed-tools` listing the exact
    shapes Step 0 + Step 3 emit, including
    `Read(~/.claude/active-profile.yaml)` (home-relative form per
    Claude Code permissions docs). [verify: manual-run-user]
      → frontmatter added at start.md:1-4; `/dev:start` in fresh
        session runs Step 0 with zero prompts [live] (2026-05-19)
  - [X] 6.2 Insert the Step 3 negative directive forbidding Bash
    loops / `find` / `$(...)` substitution, immediately before
    the "Docs:" bullet. [verify: code-only]
      → inserted at start.md:99-103
  - [X] 6.3 Roll back the global allowlist entries added during
    diagnosis (`Bash(cat ~/.claude/active-profile.yaml …)` and
    `Read(~/.claude/active-profile.yaml)`) from `install.sh`
    `RLM_PERMS` and `install.ps1` `$rlmPerms` — they are
    superseded by the frontmatter. [verify: code-only]
      → both installer arrays now carry only the inline note
        pointing at the skill's frontmatter as the source of
        truth for these permissions

---

**Next Steps**: 022 closed. Future dev:* skills that need
filesystem reads outside the project root should adopt the same
frontmatter pattern.
