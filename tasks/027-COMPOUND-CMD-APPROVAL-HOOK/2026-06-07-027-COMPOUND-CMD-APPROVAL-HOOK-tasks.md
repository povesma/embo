# COMPOUND-CMD-APPROVAL-HOOK - Task List

## Relevant Files

- [2026-06-07-027-COMPOUND-CMD-APPROVAL-HOOK-tech-design.md](./2026-06-07-027-COMPOUND-CMD-APPROVAL-HOOK-tech-design.md)
  :: Technical Design
- [2026-06-07-027-COMPOUND-CMD-APPROVAL-HOOK-prd.md](./2026-06-07-027-COMPOUND-CMD-APPROVAL-HOOK-prd.md)
  :: PRD
- [.claude/hooks/approve-compound.sh](../../.claude/hooks/approve-compound.sh)
  :: New PreToolUse hook (Bash + jq).
- [.claude/hooks/approve-compound.test.sh](../../.claude/hooks/approve-compound.test.sh)
  :: Plain-Bash unit tests for the hook (no framework dependency).
- [.claude/hooks/docs-first-guard.sh](../../.claude/hooks/docs-first-guard.sh)
  :: Template for stdin read, fail-open trap, permissionDecision JSON.
- [CLAUDE.md](../../CLAUDE.md) :: Installation Flow + File Structure to update.
- [README.md](../../README.md) :: §Hooks table to update.

## Notes

- Bash + `jq` only; no shfmt/Python (PRD constraint). Bash 3.2-compatible
  (macOS default).
- Tests are a plain-Bash script (no framework, per repo's stdlib-only
  ethos); source the hook's functions and assert, exit non-zero on any
  failure. Run: `bash .claude/hooks/approve-compound.test.sh`.
- Core invariant under test: the hook never emits `allow` for a
  subcommand it did not positively match.
- Hook is stateless; reads merged allow/deny from all 4 settings layers.

## TDD Planning Guidelines

Apply TDD to the parsing/matching/decision logic (1.0-3.0) — pure
string transforms with clear inputs/outputs. Registration and docs
(4.0) are config/scaffolding, no TDD. Live verification (5.0) is
manual on this instance.

## Tasks

- [X] 1.0 **User Story:** As a developer, I want a tested
  command-normalization core so that any Bash command reduces to a clean
  subcommand list or safely bails out. [6/6]
  - [X] 1.1 Write tests: unsafe-construct detection returns "bail" for
    `$(...)`, backticks, `<(...)`, heredoc `<<`; "ok" otherwise.
    [verify: auto-test]
    → test.sh: 7 cases written, all fail vs stub (0 passed, 7 failed) —
      confirms tests exercise is_unsafe [live] (2026-06-07)
  - [X] 1.2 Implement unsafe-construct detection. [verify: auto-test]
    → test.sh: 7/7 pass [live] (2026-06-07)
  - [X] 1.3 Write tests: split on `&& || ; | |& &` and newlines yields
    the expected subcommand list (incl. nested mixes). [verify: auto-test]
    → test.sh: 7 split cases [live] (2026-06-07)
  - [X] 1.4 Implement separator split. [verify: auto-test]
    → test.sh: split cases pass [live] (2026-06-07)
  - [X] 1.5 Write tests: per-subcommand normalization strips redirects
    (`>`,`>>`,`2>&1`,`&>`,`<` + targets), leading `WORD=val` env
    prefixes, and wrappers (`timeout time nice nohup stdbuf`), leaving
    bare cmd+args. [verify: auto-test]
    → test.sh: 10 normalize cases [live] (2026-06-07)
  - [X] 1.6 Implement normalization. [verify: auto-test]
    → test.sh: 24/24 pass total [live] (2026-06-07)

- [X] 2.0 **User Story:** As a developer, I want permission matching
  against the merged 4-layer allow/deny lists so that a normalized
  subcommand is classified allowed, denied, or unknown. [4/4]
  - [X] 2.1 Write tests: merge allow/deny from the 4 settings layers
    (~/.claude + project, .json + .local.json); missing files skipped;
    project path from stdin `cwd`. [verify: auto-test]
    → test.sh: 4 merge cases via temp HOME [live] (2026-06-07)
  - [X] 2.2 Implement merged-layer loading via `jq`. [verify: auto-test]
    → test.sh: merge cases pass [live] (2026-06-07)
  - [X] 2.3 Write tests: rule-form matching for `Bash(cmd)`,
    `Bash(cmd *)`, `Bash(cmd:*)` — exact, prefix, and glob; non-Bash
    rules ignored. [verify: auto-test]
    → test.sh: 8 match cases [live] (2026-06-07)
  - [X] 2.4 Implement rule matching. [verify: auto-test]
    → test.sh: 36/36 pass total [live] (2026-06-07)

- [X] 3.0 **User Story:** As a developer, I want the decision + I/O
  wrapper so that the hook speaks the verified PreToolUse contract and
  fails open. [6/6]
  - [X] 3.1 Write tests: non-Bash tool_name and empty command produce no
    stdout (fall through). [verify: auto-test]
    → test.sh: non-Bash/empty/malformed → empty stdout [live] (2026-06-07)
  - [X] 3.2 Implement stdin read + early fall-through. [verify: auto-test]
    → test.sh: wrapper cases pass [live] (2026-06-07)
  - [X] 3.3 Write tests: decision logic — any deny match → `deny` JSON
    with reason; all subcommands allow & none deny → `allow` JSON; any
    unknown → no stdout (fall through). [verify: auto-test]
    → test.sh: 6 decide cases (allow/deny/fall) [live] (2026-06-07)
  - [X] 3.4 Implement decision + `jq -n` JSON emission matching
    `docs-first-guard.sh:40-57` schema. [verify: auto-test]
    → test.sh: allow path emits permissionDecision=allow [live] (2026-06-07)
  - [X] 3.5 Write tests: fail-open — malformed stdin / jq error / unsafe
    construct → exit 0, no stdout; never emits `allow` for an unmatched
    subcommand. [verify: auto-test]
    → test.sh: malformed/unsafe/unknown → fallthrough [live] (2026-06-07)
  - [X] 3.6 Implement `trap 'exit 0' ERR` and wire 1.0-2.0 together into
    `approve-compound.sh`. Fixed redirect-before-split ordering so `2>&1`
    `&` is not treated as a separator. [verify: auto-test]
    → test.sh: 47/47 pass total [live] (2026-06-07)

- [X] 4.0 **User Story:** As a user, I want the hook registered and
  shipped so that it auto-installs to `~/.claude` like the other hooks.
  [3/3]
  - [X] 4.1 Register the hook as a PreToolUse matcher on `Bash` via an
    install.sh registration block (mirrors behavioral-reminder).
    [verify: code-only]
  - [X] 4.2 Add `approve-compound.sh` to the installer (copy now excludes
    `*.test.sh`) and CLAUDE.md File Structure. [verify: code-only]
  - [X] 4.3 Add a row to the README §Hooks table + file-tree describing
    the hook. [verify: code-only]

- [X] 5.0 **User Story:** As a user, I want live end-to-end verification
  on this instance so that the fix is proven, not assumed. [4/4]
  - [X] 5.1 With an allow-listed base command, run `<allowed> > tmp/x.log
    2>&1` and confirm it runs with no permission prompt.
    [verify: manual-run-user]
    → user confirmed: `python3 rlm_repl.py status > tmp/x.log 2>&1` ran
      silently after restart, no prompt [live] (2026-06-07)
  - [X] 5.2 Run a compound of two allowed bases (`<A> && <B>`) and confirm
    no prompt. [verify: manual-run-user]
    → user confirmed: `ls && pwd` ran silently, no prompt [live] (2026-06-07)
  - [X] 5.3 Run a redirect into a protected dir (`<allowed> > .claude/x`)
    and confirm it still prompts. [verify: manual-run-user]
    → user confirmed: `ls > .claude/probe.log` prompted (hook did not
      override protected-dir check) [live] (2026-06-07)
  - [X] 5.4 Run a command with an un-allowed base and confirm it still
    prompts (fall through). [verify: manual-run-user]
    → user confirmed: `weirdunknowncmd` prompted (fall through) [live]
      (2026-06-07)

## Next

Run `/dev:impl` to implement, one subtask at a time.
