# 023-PLAIN-ENGLISH-writing-rule — Task List

## Relevant Files

- [.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: Add the `<!-- RULE:PLAIN-ENGLISH -->` section under "Session
  Behavioral Rules", next to SCAN-CHOICES.
- [.claude/hooks/behavioral-reminder.sh](../../.claude/hooks/behavioral-reminder.sh)
  :: Append `· PLAIN-ENGLISH` to the baseline tag-list (line 97).
- [README.md](../../README.md)
  :: Add a PLAIN-ENGLISH row only if a per-rule-tag list exists;
  otherwise skip with a one-line reason.

## Notes

- This copies the SCAN-CHOICES change from task 015 (story 10.0).
  Two edits plus a README check. No tests to author; verification is
  reading the file and piping a test prompt into the hook.
- The rule is always-on, so it goes in the baseline, not in an AWSK
  classifier.
- Keep correct technical terms (for example "race condition",
  "OOMKilled"). The rule forbids idioms, metaphors, similes,
  analogies, and figurative phrases — not precise identifiers.
- The hook must keep its fail-open behavior (exit 0 on bad input)
  and the `BEHAVIORAL_REMINDER_DISABLED=1` switch.
- Verification shorthand:
  `echo '{"prompt":"what is the status"}' | bash behavioral-reminder.sh`

## Tasks

- [X] 1.0 **User Story:** As a user of the workflow, I want a
  PLAIN-ENGLISH rule always present in the baseline so the agent
  writes in plain, literal English on every turn, with correct
  technical terms kept. [3/3]
  - [X] 1.1 Add `<!-- RULE:PLAIN-ENGLISH -->` and a
    `### Write in plain English` subsection to `dev:start.md` under
    "Session Behavioral Rules", next to SCAN-CHOICES. Use the same
    Do / Do not format. State: use literal words; no idioms,
    metaphors, similes, analogies, or figurative phrases; keep
    correct technical terms. [verify: code-only]
  - [X] 1.2 Append `· PLAIN-ENGLISH` to the baseline
    `[RULES ACTIVE: ...]` line in `behavioral-reminder.sh` (line 97).
    [verify: code-only]
  - [X] 1.3 Verify: pipe `'{"prompt":"what is the status"}'` into the
    hook; confirm the baseline output contains `PLAIN-ENGLISH` and the
    hook exits 0. Pipe `'{}'` (no prompt field); confirm exit 0 and no
    crash. [verify: manual-run-claude]
    → normal prompt: baseline output contains PLAIN-ENGLISH,
      hookEventName UserPromptSubmit, exit 0; malformed `{}`: baseline
      returned, no crash, exit 0 [live] (2026-05-30)

- [X] 2.0 **User Story:** As a new user reading the README, I want the
  PLAIN-ENGLISH rule documented wherever the other rule tags are
  documented. [1/1]
  - [X] 2.1 Add a PLAIN-ENGLISH row to the README per-rule-tag list if
    one exists; otherwise record a skip with a one-line reason,
    matching how task 015 subtask 10.4 handled the same case.
    [verify: code-only]
    → skipped: README §Hooks has no per-rule-tag list, only a file-tree
      line (README.md:333) and a one-row hooks table entry
      (README.md:347) that does not enumerate tokens; nothing to update,
      same as task 015 subtask 10.4 (2026-05-30)
