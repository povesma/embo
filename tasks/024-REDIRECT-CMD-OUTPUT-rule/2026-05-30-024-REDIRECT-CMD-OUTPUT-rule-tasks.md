# 024-REDIRECT-CMD-OUTPUT-rule — Task List

## Relevant Files

- [.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: Add the `<!-- RULE:REDIRECT-CMD-OUTPUT -->` section under "Session
  Behavioral Rules", next to PLAIN-ENGLISH.
- [.claude/hooks/behavioral-reminder.sh](../../.claude/hooks/behavioral-reminder.sh)
  :: Append `· REDIRECT-CMD-OUTPUT` to the baseline tag-list.
- [README.md](../../README.md)
  :: Add a row only if a per-rule-tag list exists; otherwise skip
  with a one-line reason.

## Notes

- Same shape as SCAN-CHOICES (task 015) and PLAIN-ENGLISH (task 023):
  a rule section in `dev:start.md` plus a baseline token in the hook.
- Always-on baseline, not a triggered classifier. The habit can
  appear on any command, so a trigger does not fit.
- The defect this rule prevents: ending a verification command with
  `| tail -N` or `| head -N` (or truncating combined `2>&1` output)
  makes `$?` the filter's exit code, not the command's, so a failure
  reads as a pass; and the lines that explain the failure can be
  discarded.
- The rule is centered on preserving the exit code and the error
  text. Recommended technique: redirect to a file and read it; or
  set `pipefail` before piping to a filter.
- Depends on the PLAIN-ENGLISH section existing (task 023), since the
  new section is placed next to it. Task 023 changes are on branch
  feature/023-plain-english, not yet on this branch — confirm
  placement against whatever branch this is implemented on.
- Verification shorthand:
  `echo '{"prompt":"what is the status"}' | bash behavioral-reminder.sh`

## Tasks

- [X] 1.0 **User Story:** As a user of the workflow, I want a
  REDIRECT-CMD-OUTPUT rule always present in the baseline so the agent
  does not hide a command's exit code or error output behind a
  truncating filter when checking whether the command worked. [3/3]
  - [X] 1.1 Add `<!-- RULE:REDIRECT-CMD-OUTPUT -->` and a
    `### Do not hide a command's exit code or error output` subsection
    to `dev:start.md` under "Session Behavioral Rules", next to
    PLAIN-ENGLISH. Use the same Do / Do not format. State: read the
    command's own exit code; set `pipefail` before piping to a filter;
    for large output redirect to a file and read it; when a command
    fails read the lines that explain why; do not end a verification
    command with `| tail -N` / `| head -N` without `pipefail`; do not
    conclude success from a clean-looking truncated tail.
    [verify: code-only]
  - [X] 1.2 Append `· REDIRECT-CMD-OUTPUT` to the baseline
    `[RULES ACTIVE: ...]` line in `behavioral-reminder.sh`.
    [verify: code-only]
  - [X] 1.3 Verify: pipe `'{"prompt":"what is the status"}'` into the
    hook; confirm the baseline output contains `REDIRECT-CMD-OUTPUT`
    and the hook exits 0. Pipe `'{}'` (no prompt field); confirm exit 0
    and no crash. [verify: manual-run-claude]
    → normal prompt: baseline output contains REDIRECT-CMD-OUTPUT,
      hookEventName UserPromptSubmit, exit 0; malformed `{}`: baseline
      returned, no crash, exit 0 [live] (2026-05-30)

- [X] 2.0 **User Story:** As a new user reading the README, I want the
  REDIRECT-CMD-OUTPUT rule documented wherever the other rule tags are
  documented. [1/1]
  - [X] 2.1 Add a REDIRECT-CMD-OUTPUT row to the README per-rule-tag
    list if one exists; otherwise record a skip with a one-line reason,
    matching how task 015 subtask 10.4 handled the same case.
    [verify: code-only]
    → skipped: README §Hooks has no per-rule-tag list, only a file-tree
      line and a one-row hooks table entry that does not enumerate
      tokens; nothing to update, same as tasks 015 and 023 (2026-05-30)
