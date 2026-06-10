# 029-COMPOUND-CMD-RULE-rework - Task List

## Relevant Files
- [2026-06-10-029-COMPOUND-CMD-RULE-rework-tech-design.md](2026-06-10-029-COMPOUND-CMD-RULE-rework-tech-design.md)
  :: Tech design (should_wrap algorithm, FR-5/FR-6, triage table)
- [2026-06-10-029-COMPOUND-CMD-RULE-rework-prd.md](2026-06-10-029-COMPOUND-CMD-RULE-rework-prd.md)
  :: PRD (goals, user stories, follow-ups, out of scope)
- `.claude/hooks/approve-compound.sh` :: should_wrap (234-247) +
  normalize_subcommand (95-113) changes
- `.claude/hooks/approve-compound.test.sh` :: eligibility + env cases
- `.claude/hooks/embo-capture.test.sh` :: compound exit-code cases
- `.claude/commands/dev/start.md` :: FR-1 rule rewrite + moved rules
- `.claude/commands/dev/impl.md` :: FR-6 ALLOWLISTABLE-INVOCATION rule
- `.claude/commands/dev/git.md` :: CHANGELOG / Release authoring rules
- `README.md` :: FR-4 install docs
- `~/.claude/CLAUDE.md` :: personal file, triage applied in place
  (uncommitted)

## Notes
- Run suites: `bash .claude/hooks/approve-compound.test.sh`,
  `bash .claude/hooks/embo-capture.test.sh`.
- TDD for Stories 1.0-3.0 (hook logic); doc stories are code-only.
- The hook is installed globally — Story 8.0 re-syncs
  `~/.claude/hooks/` and verifies live before the task closes.
- Story 7.1 reads `~/.claude/settings.json` (user config): ask the
  user for permission in-turn before reading.

## Tasks
- [X] 1.0 **User Story:** As a developer, I want eligible compound
  commands wrapped by embo-capture, so that chained/piped output is
  captured instead of flooding the context [3/3]
  - [X] 1.1 Write failing tests for compound wrap eligibility:
    `&&`/`;`/`||`/`|` compounds of non-interactive segments → wrap;
    trailing `&` (backgrounding) → no wrap; compound with an
    interactive segment (e.g. `| less`, `| python3`) → no wrap
    [verify: auto-test]
    → red phase: 11 cases added, 6 fail as expected (5 compound-wrap
      + trailing-& latent bug confirmed: bg commands currently get
      wrapped); 75 pre-existing pass [live] (2026-06-10)
  - [X] 1.2 Write failing tests that existing opt-outs hold for
    compounds: explicit redirect, unsafe construct (`$(...)`,
    backticks, heredoc), re-entrancy (already-wrapped) → no wrap
    [verify: auto-test]
    → 6 guard cases added; all pass pre-change (trivially, via the
      compound exclusion) — serve as regression guards for 1.3;
      suite: 81 passed, 6 failed (the expected 1.1 red set) [live]
      (2026-06-10)
  - [X] 1.3 Implement should_wrap per tech-design (remove compound
    exclusion, add raw trailing-`&` opt-out, per-segment
    interactive-head loop) until 1.1-1.2 pass; full suite green
    [verify: auto-test]
    → approve-compound.test.sh: 87 passed, 0 failed (incl. trailing-&
      latent-bug fix) [live] (2026-06-10)
- [X] 2.0 **User Story:** As a developer launching tools with an `env`
  prefix, I want the normalizer to strip the `env` wrapper before
  allowlist matching, so that the underlying command's allow-rule
  applies and no prompt fires [2/2]
  - [X] 2.1 Write failing tests for normalize_subcommand:
    `env VAR=x VAR=y cmd args` → `cmd args`; flag forms `env -i`,
    `env -u NAME`, `env --`; bare `env` → empty (fallthrough)
    [verify: auto-test]
    → red phase: 8 cases added (incl. the live npx case shape), all
      8 fail as expected; 87 others pass [live] (2026-06-10)
  - [X] 2.2 Implement the `env`-wrapper strip in normalize_subcommand
    until 2.1 passes; full suite green [verify: auto-test]
    → approve-compound.test.sh: 95 passed, 0 failed [live]
      (2026-06-10)
- [X] 3.0 **User Story:** As a developer, I want compound exit-code
  semantics pinned by tests, so that wrapped execution provably equals
  unwrapped bash behavior [2/2]
  - [X] 3.1 Add embo-capture tests: `a && b` stops at failing `a` and
    reports its code; `a; b` and `a | b` report last-segment code;
    failing mid-segment case; marker `(exit=...)` field matches the
    real code [verify: auto-test]
    → 10 cases added; embo-capture.test.sh: 33 passed, 0 failed
      [live] (2026-06-10)
  - [X] 3.2 Confirm tests pass with the wrapper UNCHANGED; if any
    fail, stop and update tech-design before touching the wrapper
    [verify: auto-test]
    → same run as 3.1: wrapper untouched, 33 passed, 0 failed —
      design premise (bash-native compound semantics) holds [live]
      (2026-06-10)
- [X] 4.0 **User Story:** As a session model, I want the shipped
  REDIRECT-CMD-OUTPUT rule to permit compounds, so that related work
  runs in one call without rule violations or prompts [2/2]
  - [X] 4.1 Rewrite RULE:REDIRECT-CMD-OUTPUT in start.md per
    tech-design FR-1: compounds permitted/preferred; `$(...)`/
    backticks/heredocs still prompt; `;` vs `&&` exit-code note;
    marker contract unchanged; hook-failure fallback clause (large
    inline output without marker → flag breakage, fall back to
    manual redirects) [verify: code-only]
  - [X] 4.2 Sweep shipped command files for one-command-per-call
    language contradicting the new rule; align them
    [verify: code-only]
    → grep sweep of commands/dev + agents: only the new rule text
      mentions chaining; no contradictions found [live] (2026-06-10)
- [X] 5.0 **User Story:** As a developer using /dev:impl, I want
  generated scripts and launchers to be allow-listable by design, so
  that embo-built code never trips permission prompts even if the
  hook is absent or broken [1/1]
  - [X] 5.1 Add allow-listable invocation guidance to impl.md per
    tech-design FR-6 (flags / config file / self-loaded env file; no
    required `VAR=x` or `env` prefix; generated deliverables only)
    [verify: code-only]
    → REVISED per user: Code Style item, not a standalone RULE block
      (weak rule enforcement until 026; design constraint, not
      behavioral protocol)
- [X] 6.0 **User Story:** As the owner of ~/.claude/CLAUDE.md, I want
  the triage table verified, approved, and applied, so that the
  global file keeps only personal rules and reusable ones ship in
  commands [7/7]
  - [X] 6.1 Resolve verdict for rule #10: compare its text against
    CHALLENGE-INSTRUCTION as shipped (behavioral-reminder.sh /
    start.md); duplicate → remove, else → move [verify: code-only]
    → NOT a dup (opposite direction: agent-challenges-user vs
      user-challenges-agent) → move to dev:start with user
      amendments: declinable + three fix paths [live] (2026-06-10)
  - [X] 6.2 Record the before-state of ~/.claude/CLAUDE.md in this
    task file (rules list, not full private text) [verify: code-only]
    → 13-rule identifier list appended as Appendix (source: file
      content already present in session context — no config-file
      read needed) (2026-06-10)
  - [X] 6.3 Present the final 13-rule table for user approval
    [verify: manual-run-user]
    → approved with revisions: 1+5 keep, 3 move+menu-modification,
      7-9 copy (ship AND keep), rest as proposed; recorded in
      tech-design table (2026-06-10)
  - [X] 6.3b Update ONE-SUBTASK completion protocol in impl.md per
    revised rule #3: 3-option continuation menu (next sub-task only /
    all sub-tasks of current story / all tasks until user input
    needed); modes 2-3 emphasize DECIDE-OR-ASK [verify: code-only]
    → menu added; completion protocol now REFERS to Task Completion
      Rules instead of restating them (user corrections applied:
      [~] state, code-only exception, no duplication) (2026-06-10)
  - [X] 6.4 Apply moves: rule blocks #2 #3 #5 (#10 if moved) to
    start.md; #11 #12 to git.md [verify: code-only]
    → per approved table: start.md gets ASSUME-BROKEN (#2),
      STOP-AFTER-ACTION (#3, defers to continuation menu in impl),
      BEHAVIOUR-FIRST (#10, declinable + 3 fix paths),
      RESPONSE-STYLE (#7-9 copies); git.md gets CHANGELOG-AUTHORING
      (#11), RELEASE-BODY-AUTHORING (#12). #5 stays global per
      revised verdict (keep) (2026-06-10)
  - [X] 6.5 Apply removals and keeps to ~/.claude/CLAUDE.md per the
    approved table [verify: code-only]
    → file rewritten: kept #1, #5, #7, #8, #9; removed #2, #3, #4,
      #6, #10, #11, #12, #13 (all now shipped or superseded);
      before-state preserved in Appendix (2026-06-10)
  - [X] 6.6 User confirms the post-state of the global file
    [verify: manual-run-user]
    → user replied "confirmed" (2026-06-10)
- [X] 7.0 **User Story:** As an end user installing embo, I want
  install docs for the hook pair and allow-rule with manual steps, so
  that I can replicate the zero-prompt + capture setup [2/2]
  - [X] 7.1 With user permission, read the installed hook
    registration + wrapper allow-rule from ~/.claude/settings.json
    (cf. claude-mem #18450); record exact strings
    [verify: manual-run-claude]
    → user granted read via continue-mode answer; recorded: PreToolUse
      matcher "Bash" → `bash ~/.claude/hooks/approve-compound.sh`;
      allow-rule `Bash(~/.claude/hooks/embo-capture.sh *)` [live]
      (2026-06-10)
  - [X] 7.2 Write the README install section: hook registration,
    wrapper copy, allow-rule, manual steps alongside scripted ones,
    allowlist-ownership statement [verify: code-only]
    → Hooks table row + setup subsection added under README ### Hooks;
      initial draft falsely claimed an EMBO_CAPTURE_DISABLED switch —
      corrected to match actual hook behavior (2026-06-10)
- [X] 8.0 **User Story:** As the maintainer, I want the updated hook
  deployed to ~/.claude and verified live end-to-end, so that the
  change is proven in a real session before closing [5/5]
  - [X] 8.1 Sync updated approve-compound.sh to ~/.claude/hooks/
    (overwrites installed copy — state intent, harness gates the
    copy) [verify: manual-run-claude]
    → user ran ./install.sh (canonical path, not manual cp): hooks
      5 files synced, approve-compound + permissions already
      registered, commands/dev synced [live] (2026-06-10)
  - [X] 8.5 Fix installer re-copying the deprecated
    docs-first-guard.sh: remove the file from repo hooks/ (history
    stays in tasks/010), keep the installer removal prompt for old
    installs, update CLAUDE.md file listing; check install.ps1 for
    the same copy step [verify: manual-run-claude]
    → git rm done (user-approved), CLAUDE.md listing updated,
      install.ps1 checked (same blanket copy — fixed by file
      removal, no script change). User re-ran ./install.sh:
      removal prompt answered Y, second run clean (no re-copy,
      no prompt) [live] (2026-06-10)
  - [X] 8.2 Live: allowlisted compound producing >10 lines → 0
    prompts; marker with correct line/byte counts and exit code;
    full output readable from the capture file
    [verify: manual-run-claude]
    → `git log -30 && git diff --stat HEAD`: no prompt, marker
      38 lines (exit=0), capture file contains BOTH segments'
      output (verified by Read) [live] (2026-06-10)
  - [X] 8.3 Live: compound with a failing segment → marker
    `(exit=<nonzero>)`; reported as failure despite clean preview
    [verify: manual-run-claude]
    → `git log -15 && git diff --stat HEAD <missing>`: marker
      (exit=128), preview shows only clean log lines — failure
      detectable solely via marker. Bonus check: compound with a
      NON-allowlisted segment (git show) correctly fell through
      (no wrap, harness handled) [live] (2026-06-10)
  - [X] 8.4 Live: `env VAR=x <allowlisted-cmd>` → no prompt
    [verify: manual-run-claude]
    → `env FOO=bar DEMO=1 git log --oneline -3`: ran with zero
      prompts, small output inline (threshold behavior correct)
      [live] (2026-06-10)
- [X] 9.0 **User Story:** As the maintainer, I want the gaps found by
  the test-review subagent closed, so that the auto-approval path has
  no normalization bypasses and the wrap path cannot hang or lose
  output [4/4]
  - [X] 9.1 Fix glued `env -uNAME` flag handling in
    normalize_subcommand (G2): strip flag+value as one token; TDD
    (failing test first: `env -uPATH rm -rf /` must normalize with
    head `rm` so deny fires) [verify: auto-test]
    → G2 DISPROVED: glued flag already falls to the generic `-*`
      branch and strips correctly; 3 pin tests added, pass with no
      code change; suite 98 passed, 0 failed [live] (2026-06-10)
  - [X] 9.2 Strengthen backgrounding guard in should_wrap (G3+G4):
    after removing `&&`/`|&`/fd-dup forms, any remaining `&` → no
    wrap; trailing dangling operator (`&&`/`||`/`|`) → no wrap; TDD
    [verify: auto-test]
    → red 5 → green; `ls ;` and `|&` wrap preserved; suite 105
      passed, 0 failed [live] (2026-06-10)
  - [X] 9.3 Add `sudo` to CAPTURE_NOWRAP_HEADS (G5): `sudo <any>`
    never wrapped; explicitly NOT stripping sudo in normalize (an
    allow-rule for `cmd` must not authorize `sudo cmd`); TDD
    [verify: auto-test]
    → red 3 → green; norm pin confirms sudo kept as head (no
      privilege bypass); suite 109 passed, 0 failed [live]
      (2026-06-10)
  - [X] 9.4 Pin fail-safe behavior with tests (G1+G6): quoted
    separator never yields wrong approve (fallthrough/deny only);
    compound containing bare `env --` segment → decide fallthrough
    [verify: auto-test]
    → 3 decide-level pins pass with no code change: quoted `&&` →
      fallthrough, quoted `rm` → deny (overcautious, safe), `env --`
      segment → fallthrough; suite 112 passed, 0 failed [live]
      (2026-06-10)

## Appendix: ~/.claude/CLAUDE.md before-state (recorded 2026-06-10)

Rule list as of Story 6.0 start, in file order (identifiers only;
personal file, full text not reproduced). Numbering matches the
tech-design triage table.

1. No `git add -A` / `git commit -a` (explicit staging)
2. Pessimistic success assessment (assume broken until tested)
3. Stop after requested action (no follow-up chaining)
4. Defend position when challenged (question != counter-argument)
5. Never read system/user config or secret files without permission
6. Presenting choices: scannable options, one per line
7. Concise responses (cut filler, keep meaning)
8. Bold emphasis on decisions/blockers/actions
9. Never offer to pause/wait/stop; forward-action phrasing
10. User challenges Claude behaviour → top-priority fix
11. CHANGELOG.md authoring guidance
12. GitHub Release body authoring guidance
13. Bash commands: keep them allow-listable (one command per call,
    sub-bullets on redirect-to-file, -chdir flags, wrapper prefixes,
    no echo separators / `;`-chains)
