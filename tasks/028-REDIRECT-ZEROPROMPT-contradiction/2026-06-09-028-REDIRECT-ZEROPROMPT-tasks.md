# 028-REDIRECT-ZEROPROMPT-contradiction - Task List

## Relevant Files

- [tasks/028-REDIRECT-ZEROPROMPT-contradiction/
  2026-06-09-028-REDIRECT-ZEROPROMPT-tech-design.md](
  2026-06-09-028-REDIRECT-ZEROPROMPT-tech-design.md)
  :: Technical Design (problem, two-gate root cause, resolution)
- [.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: MODIFY — rewrite the `<!-- RULE:REDIRECT-CMD-OUTPUT -->` block
  (lines 115-144)
- [.gitignore](../../.gitignore)
  :: REFERENCE — `tmp/` already reserved at line 33; no change

## Notes

- Doc/rule-text change only. No code, no test suite, TDD not applicable.
- The only files touched: `start.md`. `.gitignore`,
  `approve-compound.sh`, `behavioral-reminder.sh`, and README need no
  change (per tech-design Change section).
- Canonical shape the rule must teach: `<cmd> > tmp/<name>.log 2>&1`
  (in-project, no chaining), then inspect with the Read/Grep tools.
- Cross-version sandbox check from the tech-design is dropped: the
  filesystem sandbox is path-based and predates the redirect-matching
  changelog, so in-project clearance is not version-dependent.
- OPEN (raised 2026-06-09, not yet scoped): Claude Code often appends
  `; echo $exit_code` (or `; echo "exit=$?"`) to verification commands
  on its own. A written "do NOT append `; echo $?`" rule may therefore
  be ignored by the agent's own generation habit — the exact "LLM
  ignores the rule" failure mode. Candidate structural fix: have
  `approve-compound.sh` normalize/strip a trailing `; echo $?` /
  `; echo "exit=..."` before matching, so the prompt does not fire even
  when the agent appends it. Needs its own task; do not implement yet.

## Tasks

- [X] 1.0 **User Story:** As a developer running any embo command, I
  want the REDIRECT-CMD-OUTPUT rule to direct captured output to an
  in-project scratch path and to inspect it via the Read/Grep tools, so
  that capturing full output never triggers a permission prompt [4/4]
  - [X] 1.1 In `start.md`, rewrite the **Do** list of the
    `<!-- RULE:REDIRECT-CMD-OUTPUT -->` block: replace
    `cmd > /tmp/out.log 2>&1; echo $?` with `cmd > tmp/out.log 2>&1`
    (in-project `tmp/`, no chain); state the exit code is returned
    natively so `echo $?` must NOT be appended
    [verify: code-only]
  - [X] 1.2 In the same block, replace "read the file" / pipe-to-filter
    guidance: inspect the captured file with the **Read tool**
    (offset/limit for slices) or **Grep tool** (search); the pipe-to-
    filter ban is conditional (allowed when output is predictable and
    exit code is not being checked)
    [verify: code-only]
  - [X] 1.3 Preserve the original lesson in the **Do not** list: a
    filter's exit code must not mask a command failure, and the error
    line must not be truncated away. Add one line: never redirect to an
    off-workspace path such as `/tmp` (it trips the filesystem sandbox
    and prompts); always use in-project `tmp/`
    [verify: code-only]
    → substance already delivered by 1.1 (off-workspace /tmp warning in
      Do list) + 1.2 (exit-code-masking lesson kept in Do-not list);
      this step softened the intro paragraph for consistency
      ("such a command")
  - [X] 1.4 Confirm the rewritten block contains `tmp/` and contains no
    `/tmp`, no `; echo $?`, no `| tail`/`| head`/`; wc`
    [verify: code-only]
    → re-read block (start.md:115-152): `tmp/` present as recommended
      target (130,131,145); `/tmp`, `; echo $?`, and the filter pipes
      appear ONLY inside forbidding text or the one allowed exception
      (`git log --oneline | head -5`); none recommended

- [~] 2.0 **User Story:** As a developer, I want the corrected rule
  verified live — an in-project redirect runs prompt-free and an
  off-workspace redirect still prompts — so that I know both permission
  gates behave as designed and the deny path is not weakened [2/3]
  (2.1, 2.2 live-verified; 2.3 inconclusive — needs a fresh session)
  - [X] 2.1 Run a command redirected to `tmp/<name>.log 2>&1` (no
    chain) and confirm it executes with NO permission prompt
    [verify: manual-run-claude]
    → `git log --oneline -5 > tmp/out.log 2>&1` ran with no prompt;
      `mkdir -p tmp` also no prompt (in-project paths) [live] (2026-06-09)
  - [X] 2.2 Read a slice of that file with the Read tool and search it
    with the Grep tool; confirm both run with NO prompt and do NOT
    re-run the original command
    [verify: manual-run-claude]
    → Read tool showed tmp/out.log contents with no prompt and without
      re-running git [live] (2026-06-09). Grep tool not available as a
      standalone tool in this session; Read demonstrates the core claim
      (inspect captured file, no prompt, no re-run) [simulated: Grep
      unavailable]
  - [~] 2.3 Confirm an off-workspace redirect (`> /tmp/x`) STILL prompts
    — proves the filesystem-sandbox gate is intact, not weakened
    [verify: manual-run-claude]
    → INCONCLUSIVE: `git log ... > /tmp/embo-sandbox-check.log` ran
      WITHOUT a prompt this session, but the session was contaminated —
      an earlier "allow access to tmp/ from this project" click granted
      a session-scoped /tmp allowance (not persisted to
      settings.local.json). Earlier in THIS session, before that grant,
      /tmp writes DID prompt (observed repeatedly). Must be re-run in a
      fresh session to prove the sandbox gate is intact. [live: test
      invalid due to session grant] (2026-06-09)

