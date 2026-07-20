# 042: Make the `/embo:improve` Flow Deterministic (no model guesses)

Combined doc (problem + decisions + scope + tasks), compact style —
same convention as task 040. Records the guess-point audit found by
running the finished `/embo:improve` command (task 041, closed) and the
work to make its mechanical steps deterministic and testable.

## Problem

Task 041 shipped `/embo:improve` as a working command, but its flow
leans on the model to interpret prose steps, expand environment
variables, guess paths, and do set arithmetic in its head. Each such
point is where the run breaks or the model invents a rationale. Found
live on 2026-07-20:

**Guess-point audit** (verified against the real environment):

| # | Location | Defect | Evidence |
|---|---|---|---|
| G1 | Step 1 & 4: `source "$CLAUDE_PLUGIN_ROOT/claude-mem/corrections-lib.sh"` | `$CLAUDE_PLUGIN_ROOT` is unset in a plain Bash shell → path expands to `/claude-mem/...` → `source` fails. | `source` → exit 127; `printenv CLAUDE_PLUGIN_ROOT` → exit 1 (unset) |
| G2 | Step 1: `corrections_list <project-name>` | The project name is typed from the model's memory; no command derives it. | prose: "same value used elsewhere" |
| G3 | Step 0: `jq ... ~/.claude-mem/settings.json` | Missing file/key behaviour unstated → model interprets. | — |
| G4 | Step 1: "Remove any correction whose ID is in that list" | Set subtraction done in the model's head, not by a command. | prose only |
| G6 | Step 4: `corrections_curation_write ... <reviewed-id>...` | The model assembles the ID list by hand from its own memory. | prose only |

G1, G2, G4, G6 are mechanical and must never be model guesses. G5
(theme classification, Step 2) is genuinely semantic and stays with the
model. G3 is a missing-input edge case.

## Decisions

1. **A bin wrapper on PATH owns the mechanical work** — new
   `plugin/bin/embo-corrections`, following the existing
   `plugin/bin/rlm_repl` pattern exactly (self-resolves its own
   location via `BASH_SOURCE`, follows symlinks, finds
   `../claude-mem/corrections-lib.sh` as a sibling-relative path).
   Rationale: needs no env var and no absolute path, a bare-command
   invocation auto-approves, and it matches the two wrappers the plugin
   already ships (`rlm_repl`, `embo-deliver`). This directly retires G1
   (no `$CLAUDE_PLUGIN_ROOT` dependency) with no absolute paths.
2. **The project name is derived, not guessed** — the wrapper computes
   it from the caller's CWD basename (`basename "$PWD"`), the same value
   claude-mem keys observations by. Retires G2.
3. **ID subtraction moves into the lib** — a new
   `corrections_list_pending <project> <curation-file>` function reads
   corrections, reads curated IDs, and emits only the not-yet-curated
   set as JSON. The model never does the subtraction. Retires G4.
4. **The reviewed-ID list is emitted by the flow, not recalled** — the
   pending list already carries the IDs; the curation write is fed the
   IDs the wrapper surfaced, not a hand-assembled set. Retires G6.
5. **Every mechanical branch is fixture-tested** (profile = quality/TDD):
   the new lib function and the wrapper's project-derivation get tests
   in `corrections-lib.test.sh` before the impl, run against synthetic
   temp files — never the live worker (same convention as task 041).

## Acceptance criteria

- **AC-1 (no env-var dependency):** the `/embo:improve` command contains
  no `$CLAUDE_PLUGIN_ROOT` (or any env-var) expansion in a `source`/path
  position; browser-free, it runs in a plain shell with none set.
- **AC-2 (no absolute paths):** neither the command nor the wrapper
  hardcodes a path under the user's home or any absolute path; the
  wrapper resolves everything relative to its own location.
- **AC-3 (project name derived):** the project name reaches
  `corrections_list` from a command-derived value, never a model-typed
  literal.
- **AC-4 (subtraction in code):** the not-yet-reviewed set is produced
  by a lib function, asserted by a fixture test (first-run = all
  pending; after a write = curated excluded).
- **AC-5 (tests pass live):** `bash plugin/claude-mem/corrections-lib.test.sh`
  passes, including the new cases.

## Scope

- New `plugin/bin/embo-corrections` wrapper (list-pending + write
  subcommands), modelled on `plugin/bin/rlm_repl`.
- New `corrections_list_pending` in `corrections-lib.sh` + fixture tests.
- Rewrite `improve.md` Steps 0/1/4 to call the bare wrapper, dropping
  every `$CLAUDE_PLUGIN_ROOT` source and every in-head step.
- Out of scope: theme classification (Step 2) and the interactive
  curation dialogue (Step 3) stay model-driven; proposal assembly
  (Step 5) stays model-authored.

## Tasks

- [X] 1.0 **User Story:** As a plugin user, `/embo:improve` locates its
  helper code and my project name with no guesses, in any shell.
  [verified live 2026-07-20 against the real claude-mem DB]
  - [X] 1.1 Write fixture test for `corrections_list_pending`: first-run
    (no curation file) → all corrections pending; after a curation write
    → curated IDs excluded; unparseable curation file → all pending
    (never crash). [verify: auto-test]
      → RED verified: `corrections_list_pending: command not found`, 7
        new assertions failed, 41 prior passed.
  - [X] 1.2 Implement `corrections_list_pending <project> <curation-file>`
    in `corrections-lib.sh` to pass 1.1. [verify: auto-test]
      → GREEN: 48 passed, 0 failed. Also added `corrections_mode` (Step 0
        de-guessing, out of original plan) with 4 tests → 52 passed.
  - [X] 1.3 Create `plugin/bin/embo-corrections` (self-resolving,
    symlink-following, sibling-relative to `claude-mem/`), with
    `list-pending`, `write`, `mode`, `project` subcommands + its own
    test file (`embo-corrections.test.sh`, 12 passed). [verify: manual-run-claude]
  - [X] 1.4 Verify the wrapper runs as a bare command from an arbitrary
    CWD with `$CLAUDE_PLUGIN_ROOT` unset. [verify: manual-run-claude]
      → live: from repo CWD, env unset, `project`→embo, `mode`→code-embo,
        `list-pending`→12 real corrections; sibling-lib resolved, no
        exit-127.

- [X] 2.0 **User Story:** As a plugin user, the `/embo:improve` command
  text drives the deterministic flow with no env-var or absolute-path
  dependency. [verified: symlink-through-a-different-dir run with the var
  unset resolves the sibling lib, rc=0]
  - [X] 2.1 Rewrite `improve.md` Steps 0/1/4 to call the bare
    `embo-corrections` wrapper (`mode`/`list-pending`/`write`); remove
    every `$CLAUDE_PLUGIN_ROOT` source line. [verify: code-only]
  - [X] 2.2 Grep the command for `$CLAUDE_PLUGIN_ROOT` and absolute
    home paths → zero matches (AC-1, AC-2). [verify: code-only]
      → grep: the only `$CLAUDE_PLUGIN_ROOT` match is prose stating the
        wrapper needs none; zero source/path uses, zero home paths.
  - [~] 2.3 The wrapper needs a bare `Bash(embo-corrections *)` allow
    rule (same convention as `rlm_repl`). The user adds this at runtime
    when the feature stabilises — NOT auto-added to settings, to keep
    the allowlist under user control while unstable. Documented here as
    the required rule. [verify: code-only]
      → decided 2026-07-20: do not write to .claude/settings.local.json;
        user grants the rule interactively on first run.

- [~] 3.0 **User Story:** As the maintainer, the change is tested,
  documented, and committed. [tests + docs done; the full command run
  and the commit remain]
  - [X] 3.1 Run `corrections-lib.test.sh` + `embo-corrections.test.sh`;
    all pass incl. new cases (AC-5). [verify: auto-test]
      → lib 52 passed, wrapper 12 passed, jq transform unaffected.
  - [X] 3.2 Add `plugin/bin/embo-corrections` (+ `embo-deliver`, a prior
    omission) to the CLAUDE.md File Structure tree. [verify: code-only]
  - [~] 3.3 Live end-to-end: run `/embo:improve` with capture enabled;
    confirm zero guesses, corrections surface, a curated item does not
    resurface on a second run. [verify: manual-run-claude]
      → wrapper level VERIFIED live 2026-07-20 against the real DB:
        `mode`→code-embo, `list-pending`→12 real corrections (incl. this
        session's own, captured live), write id 29191 → pending 12→11,
        29191 excluded; symlink-through-other-dir run rc=0. The full
        `/embo:improve` COMMAND run (Steps 0-5 via the slash command) is
        still pending — mechanical flow proven, orchestration not yet.
      - [ ] 3.4 Commit task 042 (wrapper, lib+tests, improve.md,
        CLAUDE.md tree, this doc). [verify: manual]

## Related

- Task 041 (correction capture) — shipped the command this hardens; now
  closed. This task fixes robustness defects found by running it.
- `plugin/bin/rlm_repl` — the wrapper pattern to follow.
