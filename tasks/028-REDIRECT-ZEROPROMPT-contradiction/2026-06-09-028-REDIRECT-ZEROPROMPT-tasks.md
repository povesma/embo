# 028 Bash output capture wrapper - Task List

## Relevant Files

- [tasks/028-REDIRECT-ZEROPROMPT-contradiction/2026-06-09-028-REDIRECT-ZEROPROMPT-tech-design.md](2026-06-09-028-REDIRECT-ZEROPROMPT-tech-design.md)
  :: Technical Design — the auto-capture wrapper mechanism, marker
  contract, acceptance criteria, opt-outs.
- [.claude/hooks/embo-capture.sh](../../.claude/hooks/embo-capture.sh)
  :: NEW — the capture wrapper: run cmd, tee full output to a per-call
  scratch file, preserve exit code, print inline-or-marker.
- [.claude/hooks/embo-capture.test.sh](../../.claude/hooks/embo-capture.test.sh)
  :: NEW — plain-bash unit tests for the wrapper.
- [.claude/hooks/approve-compound.sh](../../.claude/hooks/approve-compound.sh)
  :: MODIFY — add the capture rewrite (PreToolUse `updatedInput`),
  coordinated with the existing reflexive-tail strip (one rewriter).
- [.claude/hooks/approve-compound.test.sh](../../.claude/hooks/approve-compound.test.sh)
  :: MODIFY — tests for capture-rewrite, opt-out skips, ordering.
- [install.sh](../../install.sh)
  :: MODIFY — ship wrapper, add `Bash(embo-capture *)` allow-rule,
  register/confirm hook; idempotent; manual fallback documented.
- [.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: MODIFY — collapse RULE:REDIRECT-CMD-OUTPUT to marker-based reading.
- [.gitignore](../../.gitignore)
  :: REFERENCE — scratch dir `tmp/` already covered (line 33); confirm.

## Notes

- **Bash + jq only**, fail-open (`trap 'exit 0' ERR`), matching the
  existing hooks. No new runtime deps (CLAUDE.md stdlib constraint).
- RLM complexity estimation skipped — RLM not initialized for this repo
  this session. Effort modeled on the reflexive-tail-strip work (Story 3
  of the superseded plan): same hook, same test harness, same
  `updatedInput` mechanism, built TDD with 61 passing tests.
- **Single-rewriter constraint** (tech-design Key risk): the capture
  rewrite and the existing tail-strip both emit `updatedInput` for Bash;
  docs say the last rewriter wins non-deterministically when separate.
  They MUST live in one hook with a defined order (strip tail first,
  then wrap). This is why the work extends `approve-compound.sh` rather
  than adding a second PreToolUse hook.
- **Marker contract** (stable): first ~5 lines, then
  `[embo-capture] truncated — <N> lines, <M> bytes. Full output:` /
  `  <path>  (exit=<code>)`. Inline (no marker) when ≤10 lines AND
  ≤300 bytes.
- **Permission matching is against the rewritten command** — without the
  `Bash(embo-capture *)` allow-rule every command prompts. Story 4 adds
  it; Story 6 proves it.

## TDD Planning Guidelines

- The wrapper's size decision, exit-code preservation, and marker
  formatting are pure logic → strict write-test-then-implement.
- The hook's opt-out detection and rewrite emission are logic → TDD via
  the existing `approve-compound.test.sh` harness.
- Installer edits and `start.md` rule text are config/docs → `code-only`
  plus a live check.
- Run wrapper tests: `bash .claude/hooks/embo-capture.test.sh`.
  Run hook tests: `bash .claude/hooks/approve-compound.test.sh`.

## Tasks

- [X] 1.0 **User Story:** As a developer, I want a capture wrapper that
  runs any command, saves full output to a per-call scratch file,
  preserves the real exit code, and prints inline-or-marker by the
  ≤10-line/≤300-byte rule, so output is always recoverable without a
  re-run [8/8]
  - [X] 1.1 Write tests for exit-code pass-through: wrapper around a
    command exiting N re-emits N (test N=0 and N!=0) [verify: auto-test]
    → embo-capture.test.sh exit-code cases written; red run failed on
      missing wrapper (127) [live] (2026-06-09)
  - [X] 1.2 Implement the wrapper core: accept `--b64 <base64>`, decode,
    run `bash -c "$decoded"`, tee full stdout+stderr to `tmp/cap/<id>.log`,
    capture and re-emit `$?` (invocation contract in tech-design)
    [verify: auto-test]
    → exit 0/7/3-via-child all propagate [live] (2026-06-09)
  - [X] 1.3 Write tests for the inline threshold: output ≤10 lines AND
    ≤300 bytes prints verbatim with NO marker; >either prints marker
    [verify: auto-test]
  - [X] 1.4 Implement the size decision + inline branch (print captured
    output unchanged when under both limits) [verify: auto-test]
    → small output inline no marker; 11 lines and >300 bytes both emit
      marker; 10-line edge stays inline [live] (2026-06-09)
  - [X] 1.5 Write tests for the marker branch: first ~5 lines present,
    then the exact `[embo-capture] truncated — <N> lines, <M> bytes`
    line, the path line, and `(exit=<code>)` [verify: auto-test]
  - [X] 1.6 Implement the marker branch with the stable contract string
    [verify: auto-test]
    → marker carries prefix, line/byte counts, path, (exit=N) with real
      code; preview is first lines only, not full output [live] (2026-06-09)
  - [X] 1.7 Write tests for the per-call file: unique path, contains the
    FULL output (more than the 5-line preview), survives for later Read
    [verify: auto-test]
  - [X] 1.8 Implement per-call file naming under `tmp/cap/`; create the
    dir if missing [verify: auto-test]
    → log holds first+last line of full output; two calls yield distinct
      files; 22 passed, 0 failed [live] (2026-06-09)

- [X] 2.0 **User Story:** As a developer, I want the PreToolUse Bash hook
  to rewrite eligible commands through `embo-capture` via `updatedInput`,
  coordinated with the existing reflexive-tail strip in one hook, so
  capture is automatic and prompt-free [6/6]
  - [X] 2.1 Write tests: an allow-listed plain command is rewritten to
    `embo-capture <cmd>` via `updatedInput` + permissionDecision allow
    [verify: auto-test]
  - [X] 2.2 Implement the capture rewrite in `approve-compound.sh`: after
    the existing decide()/strip logic, wrap the surviving command
    [verify: auto-test]
    → `ls -la` → updatedInput `embo-capture --b64 bHMgLWxh`, allow [live]
      (2026-06-09)
  - [X] 2.3 Write tests for ordering: a command WITH a reflexive tail is
    first stripped, THEN wrapped — one final `updatedInput`, not two
    competing rewrites [verify: auto-test]
  - [X] 2.4 Implement the defined order (strip tail → wrap) so a single
    `updatedInput` is emitted [verify: auto-test]
    → `ls -la; echo "exit=$?"` → strip → wrap survivor `ls -la`; a
      redirect-bearing survivor is stripped but not wrapped [live]
      (2026-06-09)
  - [X] 2.5 Write tests: a command whose head is NOT allow-listed is NOT
    wrapped-and-allowed (falls through to a normal prompt; deny still
    wins) [verify: auto-test]
  - [X] 2.6 Implement the gate: only wrap-and-allow when decide() on the
    bare head is allow; else fall through unchanged [verify: auto-test]
    → unallowed `kubectl get cm` → no stdout (normal prompt preserved)
      [live] (2026-06-09)

- [X] 3.0 **User Story:** As a developer, I want the hook to skip opt-out
  commands (interactive/streaming, already-redirected, value-extraction)
  so wrapping never hangs a command or corrupts reused data [8/8]
  - [X] 3.0 Write tests: a command already beginning with `embo-capture`
    is left unwrapped (re-entrancy guard — prevents infinite wrap)
    [verify: auto-test]
  - [X] 3.0b Implement the re-entrancy guard as the hook's FIRST check
    (skip + fall through when already wrapped) [verify: auto-test]
    → `embo-capture --b64 …` input → no stdout (not re-wrapped) [live]
      (2026-06-09)
  - [X] 3.1 Write tests: a command already containing `>`/`>>` is left
    unwrapped [verify: auto-test]
  - [X] 3.2 Implement the already-redirected skip [verify: auto-test]
    → `ls -la > tmp/keep.log 2>&1` → allow, no updatedInput (unwrapped)
      [live] (2026-06-09)
  - [X] 3.3 Write tests: known interactive/streaming heads (e.g. a
    configurable deny-wrap list — `ssh`, `vim`, `less`, `tail -f`, dev
    servers) are left unwrapped [verify: auto-test]
  - [X] 3.4 Implement the interactive/streaming skip via a maintainable
    no-wrap list; document how to extend it [verify: auto-test]
    → `ssh host` → allow, no updatedInput (CAPTURE_NOWRAP_HEADS list)
      [live] (2026-06-09)
  - [X] 3.5 Write tests: when classification is uncertain the command is
    left UNWRAPPED (conservative default — never hang) [verify: auto-test]
  - [X] 3.6 Implement the conservative default and confirm value-
    extraction (stdout-as-data) commands are not forced through `2>&1`
    [verify: auto-test]
    → compound/unsafe/`$()` commands fall through unwrapped; only
      simple single non-redirect non-interactive heads are wrapped; 70
      passed, 0 failed [live] (2026-06-09)

- [X] 4.0 **User Story:** As a developer, I want `install.sh` to ship the
  wrapper, add the allow-rule, and register the hook idempotently with a
  documented manual fallback, so a fresh install is prompt-free out of
  the box [3/3]
  - [X] 4.1 Add wrapper copy + `chmod +x` to `install.sh` (alongside the
    other hooks; exclude `*.test.sh`) [verify: code-only]
    → existing hooks loop already copies non-test `*.sh` and chmod +x;
      `embo-capture.sh` ships automatically, `embo-capture.test.sh`
      excluded
  - [X] 4.2 Add idempotent insertion of the allow-rule into
    `permissions.allow` (skip if present), with a jq-absent manual step
    printed [verify: code-only]
    → added `Bash(~/.claude/hooks/embo-capture.sh *)` to RLM_PERMS
      (matches the hook's default EMBO_CAPTURE_CMD); jq-absent branch
      prints all rules for manual add
  - [X] 4.3 Run `bash install.sh` on a temp HOME and confirm: wrapper
    copied, allow-rule present, re-run is a no-op (idempotent)
    [verify: manual-run-claude]
    → temp HOME: embo-capture.sh copied; allow-rule appears once; run 1
      "10 rules added", run 2 "all rules already present — skipping";
      both exit 0 [live] (2026-06-09)

- [X] 5.0 **User Story:** As a user, I want RULE:REDIRECT-CMD-OUTPUT in
  `start.md` collapsed to "run plainly; recognize the `[embo-capture]`
  marker; Read/Grep the file; never re-run", so the prose matches the new
  mechanism and no model-issued redirect remains [2/2]
  - [X] 5.1 Rewrite the `<!-- RULE:REDIRECT-CMD-OUTPUT -->` block: remove
    the manual `> tmp/` redirect guidance; document the `[embo-capture]`
    marker and the Read/Grep-the-file response; keep the
    pipe-masks-exit-code lesson [verify: code-only]
  - [X] 5.2 Confirm the block contains the marker prefix and no
    model-issued redirect recipe remains [verify: code-only]
    → block now shows the marker fence, "Read that file", "Never
      re-run"; no `> tmp/` recipe; pipe-masks-exit-code lesson kept

- [~] 6.0 **User Story:** As a developer, I want the whole path verified
  live so the acceptance criteria are proven, not assumed [4/5]
  (logic proven live via direct hook+wrapper invocation; the real-session
  "no prompt" claim (6.4) needs the hook installed to ~/.claude AND a
  fresh session — this session has a /tmp grant contamination, same as
  the old 2.3)
  - [X] 6.1 Large-output command → model receives preview+marker only;
    the failing lines are read from the file with NO second run
    [verify: manual-run-claude]
    → hook wrapped `grep -rn echo …` → executing the wrapped command
      printed 5 preview lines + `[embo-capture] truncated — 27 lines,
      2256 bytes` + path + `(exit=0)`; the file held all 27 lines; read
      via grep without re-running [live] (2026-06-09)
  - [X] 6.2 Tiny-output command → inline, no marker [verify: manual-run-claude]
    → no-match `grep -rn function …` (0 lines) printed inline-empty, no
      marker; wrapper unit tests cover the ≤10-line/≤300-byte inline
      branch [live] (2026-06-09)
  - [X] 6.3 Model-visible exit code equals the wrapped command's real
    exit code, in both inline and marker cases [verify: manual-run-claude]
    → no-match grep propagated exit 1 (inline); matching grep propagated
      exit 0 (marker, shown as `(exit=0)`) [live] (2026-06-09)
  - [~] 6.4 No prompt fires for the rewritten command (allow-rule
    installed) [verify: manual-run-claude]
    → CANNOT verify this session: updated hook not yet installed to
      ~/.claude, and a session-scoped /tmp grant contaminates prompt
      observations. Needs `bash install.sh` + a fresh session. The
      installed allow-rule `Bash(~/.claude/hooks/embo-capture.sh *)`
      matches the hook's default emitted command [simulated: install +
      fresh session pending] (2026-06-09)
  - [X] 6.5 Safety intact: a denied head still blocks; an interactive
    command is left unwrapped and still works [verify: manual-run-claude]
    → hook tests (live): `rm -rf x` → deny; `ssh host` → allow, not
      wrapped; unallowed `kubectl get cm` → no stdout (normal prompt)
      [live] (2026-06-09)

## Superseded (completed, retained for history)

The prior 028 plan shipped and is committed (504e354): the
RULE:REDIRECT-CMD-OUTPUT prose rework (manual `tmp/` redirect, since
superseded by this wrapper) and the reflexive-tail strip in
`approve-compound.sh` (Story 3 — 61 tests passing, still in force and
reused as the ordering partner in Story 2.3/2.4 above). That work is not
reverted; this plan builds on the tail-strip and replaces the manual-
redirect guidance with the wrapper.
