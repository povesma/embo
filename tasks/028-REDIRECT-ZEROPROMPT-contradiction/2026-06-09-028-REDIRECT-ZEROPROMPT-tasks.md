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
- [.claude/hooks/approve-compound.sh](../../.claude/hooks/approve-compound.sh)
  :: MODIFY (Story 3) — strip the reflexive `; echo "exit=$?"` /
  `; cat <same-file>` tail before permission matching so the habit
  cannot cause a prompt or a cat-back-into-context

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
- EVIDENCE (2026-06-09): the written rule does NOT stop the
  `<cmd> > file 2>&1; echo "exit=$?"; cat file` reflex. Observed three
  times in one external session; the agent quoted the rule correctly
  while violating it. Conclusion: instruction is insufficient for this
  pattern — enforcement must be structural. Captured as Story 3.0
  (no new PRD; this is the same concern as Stories 1-2).

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

- [X] 3.0 **User Story:** As a developer, I want the reflexive
  `<cmd> > file 2>&1; echo "exit=$?"; cat file` tail stripped
  structurally (not by instruction) so that the habit cannot cause a
  permission prompt or cat the captured file back into context, even
  when the agent ignores the written rule [5/5]
    > Rationale: three live repeats show instruction alone does not
    > bind this pattern (see Notes EVIDENCE). PreToolUse hooks can
    > rewrite the command via `updatedInput` before the permission
    > check; this is a new capability for our hooks (today they only
    > allow/deny, never modify) — design it carefully.
  - [X] 3.1 Decide and document the detection shape: a trailing
    `; echo "exit=$?"` / `; echo exit=$?` and/or `; cat <path>` where
    `<path>` equals the redirect target of the preceding `>`/`>>`.
    Define precisely what is stripped vs left alone (e.g. `cat` of a
    DIFFERENT file is left intact)
    [verify: code-only]
    → DESIGN (verified against official docs + current hook):
    →
    → JSON contract (Context7 /websites/code_claude): `updatedInput`
      REQUIRES `permissionDecision:"allow"` in the same
      hookSpecificOutput. So the hook may rewrite-and-allow ONLY when
      the surviving head command is itself allow-listed. If the head is
      NOT allowed, the hook MUST NOT rewrite-and-allow (that would
      auto-approve an unallowed command); it falls through unchanged and
      the command prompts normally.
    →
    → Detection target (the reflexive tail), matched on the ORIGINAL
      command string, anchored at the END:
      `<head> > <file> [2>&1] ; echo "exit=$?"` and/or `; cat <file>`
      where the `cat` argument path EQUALS the redirect target of the
      `>`/`>>` in <head>.
    → Strip rules:
      - strip a trailing `; echo "exit=$?"` / `; echo exit=$?` /
        `; echo "exit=${?}"` segment (the exit code returns natively)
      - strip a trailing `; cat <path>` ONLY when <path> == the
        redirect target captured from <head>
      - after stripping, the surviving command is `<head> > <file>
        [2>&1]`
    → Left ALONE (no rewrite, fall through unchanged):
      - `; cat <other-file>` where path != redirect target
      - no redirect present in <head> (nothing was captured, so cat is
        not a redundant read-back)
      - `$(...)`, backticks, heredoc anywhere → is_unsafe already bails
      - middle-of-command echo/cat (only a trailing tail is stripped)
    → Gate before emitting updatedInput:
      1. run the existing decide() on the STRIPPED command
      2. if decide()=="deny" → emit deny (unchanged behaviour)
      3. if decide()=="allow" → emit updatedInput{command:stripped} +
         permissionDecision:"allow"
      4. if decide()=="fallthrough" → emit NOTHING (normal prompt on the
         ORIGINAL command); do NOT rewrite, because we cannot allow it
    → Safety: this never approves anything decide() would not already
      approve; it only removes a redundant, prompt-/context-costing tail
      from an already-approvable command. Deny still wins; protected dirs
      and unallowed heads still prompt.
  - [X] 3.2 Write failing tests in `approve-compound.test.sh` for the
    transform: input with the reflexive tail → output command has the
    tail removed; `cat` of an unrelated file → unchanged; no redirect
    present → unchanged
    [verify: auto-test]
    → 12 new tests added (strip echo/cat variants, keep-unrelated,
      keep-no-redirect, updatedInput emit-allow + stripped-command,
      safety: unallowed-head no-stdout, deny-wins). Red run: 49 passed,
      12 failed — all 12 fail on `strip_redundant_tail: command not
      found`; pre-existing 49 unbroken; the two safety tests not
      depending on the new fn already pass [live] (2026-06-09)
  - [X] 3.3 Implement the strip in `approve-compound.sh`: emit
    `updatedInput.command` with the tail removed when the shape matches;
    fall through unchanged otherwise. Bash + jq only, fail-open
    [verify: auto-test]
    → added `strip_redundant_tail` (after strip_redirects); main block
      runs decide() on the stripped command and emits
      updatedInput.command only when stripping changed it AND result is
      allow. Green run: 61 passed, 0 failed (12 new + 49 existing)
      [live] (2026-06-09)
  - [X] 3.4 Live-verify: a command with the reflexive tail runs the
    stripped form with no prompt and no cat-back; the original exit code
    is still available natively
    [verify: manual-run-claude]
    → live hook invocation (stdin, kubectl allow-listed) on the exact
      transcript pattern `kubectl get cm ... > tmp/run.yaml 2>&1; echo
      "exit=$?"; cat tmp/run.yaml` → emitted permissionDecision:allow +
      updatedInput.command:"kubectl get cm poll -o yaml > tmp/run.yaml
      2>&1" (both tail segments stripped) [live] (2026-06-09)
  - [X] 3.5 Confirm the transform does not weaken safety: a denied
    subcommand in the head still blocks; an unrelated `cat` is not
    stripped; protected-dir writes still prompt
    [verify: manual-run-claude]
    → live stdin invocations (rm denied, ls/kubectl-get allowed):
      (1) `rm -rf x > tmp/x.log 2>&1; cat tmp/x.log` → deny;
      (2) `ls > tmp/x.log 2>&1; cat tmp/other.log` → no stdout
          (unrelated cat not stripped, not approved);
      (3) `kubectl delete cm > tmp/d.log 2>&1; cat tmp/d.log` → no
          stdout (unallowed head: no rewrite, normal prompt preserved)
      [live] (2026-06-09)

- [X] 4.0 **User Story:** As a developer extracting a value to reuse,
  I want the REDIRECT-CMD-OUTPUT rule to distinguish diagnostic capture
  from value extraction, so that I do not write stderr into a file I
  then feed to another command [2/2]
    > Surfaced 2026-06-09: the agent itself found that `> file 2>&1`
    > into a YAML file later fed to `kubectl create` corrupts the data
    > when stderr is present. The current rule only documents the
    > `2>&1` diagnostic case.
  - [X] 4.1 In the `start.md` REDIRECT-CMD-OUTPUT block, split the two
    purposes: diagnose (did it work? — `> tmp/out.log 2>&1`, then Read
    for errors) vs extract-a-value (clean stdout only — `> tmp/x.yaml`,
    NO `2>&1`, then Read). State: never `cat` the whole captured file
    back into the conversation — that defeats the purpose; Read the
    slice you need
    [verify: code-only]
    → also corrected a confidentiality bug: removed the false
      "(gitignored)" assertion (start.md ships into ANY project); the
      rule now requires the scratch dir be excluded from VCS and tells
      the agent to confirm/add the `.gitignore` entry before writing
  - [X] 4.2 Confirm the block now contains both cases and an explicit
    "do not cat the whole file back" line
    [verify: code-only]
    → re-read block (start.md:129-144): diagnose case (137-138),
      extract-value no-2>&1 case (139-141), "never cat the whole file
      back" (143), VCS-exclusion requirement (131-135) all present

