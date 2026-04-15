# 015-behavioral-reminder-hook — Task List

## Relevant Files

- [2026-04-01-015-behavioral-reminder-hook-prd.md](
  2026-04-01-015-behavioral-reminder-hook-prd.md)
  :: PRD
- [2026-04-01-015-behavioral-reminder-hook-tech-design.md](
  2026-04-01-015-behavioral-reminder-hook-tech-design.md)
  :: Technical Design
- [.claude/hooks/behavioral-reminder.sh](
  ../../.claude/hooks/behavioral-reminder.sh)
  :: New hook script (to create)
- [.claude/commands/dev/impl.md](../../.claude/commands/dev/impl.md)
  :: Add CHALLENGE-INSTRUCTION, DOCS-FIRST, ONE-SUBTASK tags
- [.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: Add WITHSTAND-CRITICISM tag
- [.claude/commands/dev/git.md](../../.claude/commands/dev/git.md)
  :: Add GIT-SKILL tag
- [install.sh](../../install.sh)
  :: Add behavioral-reminder hook registration block
- [README.md](../../README.md)
  :: Document new hook in §Hooks section

## Notes

- All deliverables are shell scripts and markdown edits. TDD does not
  apply. Verification means running the hook directly and observing
  its JSON output.
- The hook must always exit 0 (fail-open). Any test that causes the
  hook to crash is a bug.
- `jq` is required on the test machine for JSON output verification.
- Verification shorthand: pipe test JSON into the hook and inspect
  stdout. Example:
  `echo '{"prompt":"commit my changes"}' | bash behavioral-reminder.sh`

## Tasks

- [X] 1.0 **User Story:** As a maintainer of the command files, I want
  each behavioral rule section to have a `<!-- RULE:X -->` HTML
  comment tag so that hook reminders can reference rules by stable
  identifier [5/5]
  - [X] 1.1 Add `<!-- RULE:CHALLENGE-INSTRUCTION -->` on its own line
    immediately before `## Critical Evaluation of Instructions`
    in `dev:impl` [verify: code-only]
  - [X] 1.2 Add `<!-- RULE:DOCS-FIRST -->` immediately before
    `## Scope Verification (Doc-First Development)` in `dev:impl`
    [verify: code-only]
  - [X] 1.3 Add `<!-- RULE:ONE-SUBTASK -->` immediately before
    `## Task Implementation Protocol` in `dev:impl`
    [verify: code-only]
  - [X] 1.4 Add `<!-- RULE:WITHSTAND-CRITICISM -->` immediately
    before the `### Defend positions under questioning` subsection
    in `dev:start` [verify: code-only]
  - [X] 1.5 Add `<!-- RULE:GIT-SKILL -->` immediately before
    `## When to Use` in `dev:git` [verify: code-only]
  - [X] 1.6 Rename `GIT-SKILL` → `DEV-GIT` in hook, baseline tag,
    and git.md anchor so the label matches the actual `dev:git` skill
    [verify: manual-run-user]
    → Claude in other projects now correctly resolves DEV-GIT to the
      dev:git skill; confirmed across multiple sessions [live] (2026-04-05)

- [X] 2.0 **User Story:** As a developer on any prompt, I want a
  1-line baseline tag-list always injected into Claude's context
  so that all rule tags stay in effective attention throughout the
  session [3/3]
  - [X] 2.1 Create `.claude/hooks/behavioral-reminder.sh` with
    `trap 'exit 0' ERR`, stdin parsing via `jq` (extract `.prompt`
    into `PROMPT_LOWER`), and a JSON output block that always
    emits the baseline tag-list line via `additionalContext`
    [verify: code-only]
  - [X] 2.2 Verify: pipe `'{"prompt":"what is the status"}'` into
    the script; confirm JSON output contains `hookEventName:
    UserPromptSubmit` and the baseline `[RULES ACTIVE: ...]` line
    [verify: manual-run-claude]
    → baseline tag-list returned, hookEventName correct [live] (2026-04-01)
  - [X] 2.3 Verify: pipe `'{}'` (malformed — no prompt field) into
    the script; confirm exit 0 and no crash [verify: manual-run-claude]
    → exit 0, baseline output returned [live] (2026-04-01)

- [X] 3.0 **User Story:** As a developer sending criticism or
  correction, I want WITHSTAND-CRITICISM and CHALLENGE-INSTRUCTION
  reminders injected before Claude responds so it evaluates the
  criticism instead of agreeing automatically [3/3]
  - [X] 3.1 Add `CRITICISM_PATTERNS` constant block and `case`
    classifier to `behavioral-reminder.sh`; set `CRITICISM=1` flag
    when matched; append `[REMINDER:WITHSTAND-CRITICISM]` and
    `[REMINDER:CHALLENGE-INSTRUCTION]` block with section refs to
    `additionalContext` when flag is set [verify: code-only]
  - [X] 3.2 Verify: pipe `'{"prompt":"youre wrong about this"}'`;
    confirm both WITHSTAND-CRITICISM and CHALLENGE-INSTRUCTION appear
    in output [verify: manual-run-claude]
    → both reminders injected alongside baseline [live] (2026-04-01)
  - [X] 3.3 Verify: pipe `'{"prompt":"looks good, continue"}'`;
    confirm no WITHSTAND-CRITICISM in output (only baseline)
    [verify: manual-run-claude]
    → baseline only returned [live] (2026-04-01)

- [X] 4.0 **User Story:** As a developer requesting implementation,
  I want DOCS-FIRST and ONE-SUBTASK reminders injected so Claude
  checks the task list and asks subtask-by-subtask approval before
  coding [3/3]
  - [X] 4.1 Add `IMPL_PATTERNS` constant block and classifier;
    set `IMPL_REQUEST=1` flag; append `[REMINDER:DOCS-FIRST]` and
    `[REMINDER:ONE-SUBTASK]` block when flag is set
    [verify: code-only]
  - [X] 4.2 Verify: pipe `'{"prompt":"implement the login feature"}'`;
    confirm DOCS-FIRST and ONE-SUBTASK appear in output
    [verify: manual-run-claude]
    → both reminders injected alongside baseline [live] (2026-04-01)
  - [X] 4.3 Verify: pipe `'{"prompt":"what files exist here"}'`;
    confirm no DOCS-FIRST in output [verify: manual-run-claude]
    → baseline only returned [live] (2026-04-01)

- [X] 5.0 **User Story:** As a developer asking for a commit or PR,
  I want a GIT-SKILL reminder injected so Claude uses `/dev:git`
  instead of running git commands directly [3/3]
  - [X] 5.1 Add `GIT_PATTERNS` constant block and classifier;
    set `GIT_REQUEST=1` flag; append `[REMINDER:GIT-SKILL]` block
    with `/dev:git` reference when flag is set [verify: code-only]
  - [X] 5.2 Verify: pipe `'{"prompt":"commit my changes"}'`; confirm
    GIT-SKILL appears in output [verify: manual-run-claude]
    → GIT-SKILL injected, no false positives [live] (2026-04-01)
  - [X] 5.3 Verify: pipe `'{"prompt":"create a PR from this branch"}'`;
    confirm GIT-SKILL appears in output [verify: manual-run-claude]
    → GIT-SKILL only; fixed false DOCS-FIRST from broad "create a"
      pattern [live] (2026-04-01)

- [X] 6.0 **User Story:** As an installer running `install.sh`, I want
  `behavioral-reminder.sh` copied and registered in `settings.json`
  automatically so the hook is active without manual configuration
  [7/7]
  - [X] 6.1 Add hook registration block to `install.sh` after the
    statusLine block: copy `behavioral-reminder.sh`, `chmod +x`,
    then use `jq` to add to `hooks.UserPromptSubmit` in
    `settings.json` with idempotency check [verify: code-only]
  - [X] 6.2 Verify: run `install.sh` on a clean `settings.json`;
    confirm `behavioral-reminder.sh` entry appears under
    `hooks.UserPromptSubmit` [verify: manual-run-claude]
    → entry added correctly to hooks.UserPromptSubmit [live] (2026-04-01)
  - [X] 6.3 Verify: run `install.sh` a second time; confirm no
    duplicate entry is added [verify: manual-run-claude]
    → idempotency check returns true, skips on second run [live] (2026-04-01)
  - [X] 6.4 Make behavioral-reminder registration unconditional (no
    prompt — it is a core workflow component); change statusLine
    prompt default from `[y/N]` to `[Y/n]` [verify: code-only]
  - [X] 6.5 Add `--force` and `--yes` flags to `install.sh`:
    `--force` = non-interactive, all prompts default to no (safe);
    `--force --yes` = non-interactive, all prompts default to yes;
    print summary when prompts were skipped [verify: code-only]
  - [X] 6.6 Verify: run `install.sh --force`; confirm
    behavioral-reminder is registered, optional prompts skipped
    with summary printed [verify: manual-run-claude]
    → behavioral-reminder registered, 1 prompt skipped, summary
      printed [live] (2026-04-01)
  - [X] 6.7 Verify: run `install.sh --force --yes`; confirm all
    optional registrations applied [verify: manual-run-claude]
    → all applied, deprecated hook removed, no summary [live]
      (2026-04-01)

- [X] 8.0 **User Story:** As a developer using natural phrasing like
  "let's commit" or "commit and push", I want the hook to detect git
  intent without requiring exact phrases, so reminders fire reliably
  [3/3]
  - [X] 8.1 Replace bash `case` exact-phrase matching with awk
    weighted keyword scoring (AWSK): weighted keywords, thresholds,
    negative patterns for false-positive resistance (~7ms)
    [verify: code-only]
  - [X] 8.2 Verify: pipe test prompts into hook; confirm "let's
    commit" triggers DEV-GIT, "committed to this approach" does not
    [verify: manual-run-claude]
    → all four test cases pass: git, criticism, impl trigger
      correctly; "committed to" negative pattern cancels [live]
      (2026-04-02)
  - [X] 8.3 Verify: DEV-GIT reminder triggers correctly in live
    sessions across multiple projects [verify: manual-run-user]
    → confirmed: DEV-GIT triggered correctly many times across
      sessions [live] (2026-04-05)
    NOTE: CRITICISM and IMPL_REQUEST classifiers not yet thoroughly
    tested in live sessions — only verified via piped test prompts.

- [X] 9.0 **User Story:** As a researcher, I want the AWSK approach
  and alternatives documented so future work on ML-based classification
  has a baseline [1/1]
  - [X] 9.1 Create `awsk-research.md` with benchmark table, AWSK
    description, and ML daemon as future target [verify: code-only]

- [X] 7.0 **User Story:** As a new RLM-Mem user reading the README,
  I want the behavioral-reminder hook documented so I understand
  what it does and how to disable it [2/2]
  - [X] 7.1 Add `behavioral-reminder.sh` row to the hooks table in
    `README.md` §Hooks: event=`UserPromptSubmit`, purpose="Injects
    rule tag reminders before each prompt; targeted on criticism,
    implementation, and git requests" [verify: code-only]
  - [X] 7.2 Add disable instructions: set env var
    `BEHAVIORAL_REMINDER_DISABLED=1` in `settings.json` env block
    to suppress all output (add the guard to the hook script too)
    [verify: code-only]

