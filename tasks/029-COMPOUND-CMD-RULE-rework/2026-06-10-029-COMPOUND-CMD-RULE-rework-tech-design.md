# 029: Compound-Command Rule Rework + Compound Capture — Tech Design

**Status**: Draft · **Created**: 2026-06-10
**PRD**: [prd](2026-06-10-029-COMPOUND-CMD-RULE-rework-prd.md)

## Overview

(1) Relax `should_wrap` in `approve-compound.sh` so compounds get
embo-capture wrapping; (2) rewrite shipped prose rules to match hook
behavior; (3) triage the user's global `~/.claude/CLAUDE.md`.
`embo-capture.sh` needs **no changes** — `bash -c` already runs
compounds with native exit-code semantics.

## Verified Facts (both hook files read in full, 2026-06-10)

- `should_wrap` order: re-entrancy → redirect → unsafe → **compound →
  no** → interactive head — `approve-compound.sh:234-247`
- `wrap_command` base64-encodes the whole string; wrapper runs
  `bash -c "$CMD"` → `&&`/`||` short-circuit and `;`/`|` last-segment
  exit codes come for free — `approve-compound.sh:249-253`,
  `embo-capture.sh:27-41`
- `split_subcommands`, `normalize_subcommand`, `is_interactive_head`
  are reusable per-segment — `approve-compound.sh:20-28,95-113,214-225`
- `split_subcommands` eats a single `&`, so backgrounding must be
  detected on the raw string — `approve-compound.sh:25`
- Both test suites exist — `ls .claude/hooks`, 2026-06-10

## Design

### FR-2: `should_wrap` change (only code change)

```
1. re-entrancy ("embo-capture.sh ")        → no   (unchanged)
2. has_redirect(whole cmd)                 → no   (unchanged)
3. is_unsafe(whole cmd)                    → no   (unchanged)
4. NEW: raw cmd ends with "&"              → no   (async: capture undefined)
5. CHANGED: any segment with interactive
   head (per-segment normalize + check)    → no
6. else                                    → yes  (single AND compound)
```

`wrap_command`, `decide`, deny-wins, fail-open: untouched. Approval
and wrapping stay independent. No `pipefail` injection (NFR-2).

### FR-5: Strip leading `env` wrapper in `normalize_subcommand`

Added 2026-06-10 from a live case: `env VAR=x VAR=y npx ...` prompts
because bare assignments are stripped (`approve-compound.sh:100-103`)
but the `env` *command* is not in the wrapper strip list
(`approve-compound.sh:104-111`) — normalized head becomes `env`,
matching no allow-rule. Fix: strip a leading `env`, its flags
(`-i`, `-u NAME`, `--`), and its `VAR=val` assignments, then match
the real head. A bare `env` (no following command) normalizes to
empty → existing fallthrough. Same TDD suite as FR-2.

### FR-6: Allow-listable-invocation guideline (impl.md Code Style)

REVISED 2026-06-10 (user decision): hosted as a **Code Style item**
in impl.md, NOT a standalone `RULE:` block — it is a code-design
constraint applied while writing code, not a behavioral protocol;
RULE blocks are weakly enforced until task 026 ships, and the
reminder-hook classifier would not inject this one anyway.

Defense in depth (user, 2026-06-10): FR-5 is a runtime mitigation —
the hook can be unregistered, broken by a hook-API change, or absent.
Add a Code Style item to
`.claude/commands/dev/impl.md`: scripts, launchers, and documented
run commands implemented under the workflow must be invocable as one
plain command — parameters via flags, a config file, or an env file
the script loads itself; never by requiring callers to prepend
`VAR=x` assignments or an `env` wrapper. Applies to generated
deliverables only; it does not restrict what users type.

### FR-1: Rewrite `RULE:REDIRECT-CMD-OUTPUT` (start.md)

- Compounds (`&&` `||` `;` `|`) permitted, preferred over splitting
  into separate calls; hook auto-approves when all segments allowlisted.
- Still forbidden: `$(...)`, backticks, `<(...)`, heredocs (hook
  bails → prompt).
- Exit-code integrity kept: no truncating filters on checked
  commands; `;` reports last segment — use `&&` when failure matters.
- Marker contract + read-file-never-re-run: unchanged.
- NEW fallback clause (hook-failure redundancy, user 2026-06-10):
  the marker makes hook health observable — large output arriving
  inline *without* the `[embo-capture]` marker means the capture
  hook is not running. The rule instructs: flag the suspected hook
  breakage to the user and fall back to manual redirect discipline
  for subsequent large-output commands. No standing redundancy —
  fallback activates only on observed failure.

### FR-3: Global CLAUDE.md triage

User decisions: **move completely** (no stubs), **dedupe, keep style
rules personal**. Approval gate before editing = task step.

APPROVED with revisions (user, 2026-06-10) — final:

| # | Rule | Verdict | Reason |
|---|------|---------|--------|
| 1 | No `git add -A`/`commit -a` | keep | user: important, redundancy won't hurt |
| 2 | Pessimistic success assessment | move → dev:start | reusable |
| 3 | Stop after requested action | move → dev:start, MODIFIED | user: replace the yes/go next-subtask prompt with a 3-option continuation menu (next sub-task only / all sub-tasks of current story / all tasks until user contribution required); options 2-3 lean on DECIDE-OR-ASK to minimize prompts. Menu lands in impl.md ONE-SUBTASK protocol |
| 4 | Defend under challenge | remove | dup WITHSTAND-CRITICISM |
| 5 | Never read config/secret files | keep | user: extra safety in global scope |
| 6 | Scannable choices | remove | dup CLEAR-OPTIONS |
| 7 | Concise responses | COPY → dev:start | user: style, but improves performance — ship AND keep |
| 8 | Bold emphasis | COPY → dev:start | same |
| 9 | Never offer to pause | COPY → dev:start | same |
| 10 | Behaviour challenge = top priority | move → dev:start | NOT a dup (agent-challenges-user vs user-challenges-agent). Amended: (a) user may decline and continue; (b) fix paths = project/user CLAUDE.md, shipped files when in embo, or message to embo maintainer |
| 11 | CHANGELOG authoring | move → dev:git | release guidance |
| 12 | Release body authoring | move → dev:git | release guidance |
| 13 | Allow-listable Bash | remove | superseded by hooks + FR-1 |

Global file after triage keeps: 1, 5, 7, 8, 9 (7-9 also shipped).
Removed from global: 2, 3, 4, 6, 10, 11, 12, 13.

Moved rules become `<!-- RULE:... -->` blocks in the target file.
`~/.claude/CLAUDE.md` edits are in-place (personal, uncommitted);
before-state and applied table recorded in the task file.

> **Follow-up reconciliation (2026-06-19, task 032).** Rows 6
> (CLEAR-OPTIONS) and 9 (RESPONSE-STYLE) left the turn-ending
> ambiguous: RESPONSE-STYLE was over-corrected into a trailing inline
> "X or Y?" — the pattern CLEAR-OPTIONS forbids — seen repeatedly.
> Fix (rule text in `start.md`, not "try harder"): RESPONSE-STYLE now
> says close every turn with a structured next-step and points at
> CLEAR-OPTIONS, which gained a one-line "closing move" clause + a
> fallback (review / wrap up / tell me what to do). No hook yet.

### FR-4: Install docs (README)

Hook registration, wrapper copy, allow-rule (exact string from
installed settings, cf. claude-mem #18450), manual steps alongside
scripted ones. State: the user's own allowlist decides what runs
prompt-free; embo ships no allowlist beyond the wrapper rule.

## Verification

| FR | Method | Evidence |
|----|--------|----------|
| FR-5 `env`-wrapper normalization (flags, assignments, bare `env`) | auto-test, `approve-compound.test.sh` | all pass, exit 0 |
| FR-2 eligibility cases (compound, `&`, interactive segment, redirect, unsafe, re-entrancy) | auto-test, `approve-compound.test.sh` | all pass, exit 0 |
| FR-2 compound exec + exit codes (incl. failing segment) | auto-test, `embo-capture.test.sh` | all pass, exit 0 |
| FR-2 end-to-end | manual-run-claude | allowlisted compound → 0 prompts, marker correct |
| FR-1 rewritten rule | manual-run-claude | session chains commands, no violations |
| FR-3 triage | manual-run-user | table approved; both files match verdicts |
| FR-4 docs | code-only | manual steps present |
| FR-6 impl.md rule | code-only | rule block present, scoped to generated deliverables |

## Rejected Alternatives

1. **Per-segment capture** — re-implements shell control flow;
   whole-compound `bash -c` is free and native.
2. **`pipefail` injection** — silently diverges from unwrapped
   behavior.
3. **Stubs for moved rules** — user decision; accepted consequence:
   non-dev:start sessions lose them.
4. **Wrapping backgrounded commands** — async capture undefined.

## Files to Modify

| File | Change |
|------|--------|
| `.claude/hooks/approve-compound.sh` | `should_wrap` per above |
| `.claude/hooks/approve-compound.test.sh` | eligibility cases |
| `.claude/hooks/embo-capture.test.sh` | compound exit-code cases |
| `.claude/commands/dev/start.md` | FR-1 rewrite; moved rules #2 #3 #5 (#10?) |
| `.claude/commands/dev/git.md` | rules #11 #12 |
| `.claude/commands/dev/impl.md` | FR-6 Code Style item (allow-listable invocation) |
| `README.md` | FR-4 install section |
| `~/.claude/CLAUDE.md` | apply approved verdicts (uncommitted) |

## Risk / Rollback

Hook is installed globally (#18450): a `should_wrap` bug hits every
session. Mitigation: TDD first; hook stays fail-open (worst case =
prompt, never silent approval). Rollback: revert the one file,
re-sync to `~/.claude/hooks/`. Global CLAUDE.md is outside git:
record before-state in the task file before editing.

---

**Next**: review → `/dev:tasks`
