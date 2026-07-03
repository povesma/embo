# 038: Rapid Deliver — One-Shot Git Delivery - Technical Design

**Status**: Draft
**PRD**: [2026-07-03-038-RAPID-DELIVER-one-shot-git-prd.md](2026-07-03-038-RAPID-DELIVER-one-shot-git-prd.md)
**Created**: 2026-07-03

## Overview

A bare-command wrapper (`plugin/bin/embo-deliver`) executes a git delivery
cycle from a **plan file** whose path is its only meaningful argument. The
`/embo:git` skill builds the plan, writes it to a uniquely-named,
non-deleted file, shows its content to the user as the single approval,
then invokes the wrapper. Because the wrapper is a bare command with no
`${...}` expansion and (once the user opts in) carries an allow rule, the
compound-approve hook auto-approves the wrapper call; the git writes inside
it are child processes the hook never sees. Net result: one approval, whole
cycle.

## Current Architecture (RLM-verified)

- **PreToolUse gate scope**: `approve-compound.sh` is registered only for
  the `Bash` tool and reads only `tool_input.command` — verified via:
  `plugin/hooks/hooks.json:28-38` and `approve-compound.sh:421-424`,
  2026-07-03. **Consequence (load-bearing):** git commands spawned as child
  processes *inside* a wrapper script are not `Bash` tool calls, so the
  hook never evaluates them. The wrapper is the single gated call. This is
  what makes one-approval possible.
- **Bare-command wrapper pattern**: `plugin/bin/rlm_repl` resolves its own
  path via `BASH_SOURCE` + symlink walk and `exec`s the real script; it is
  invoked bare so no lexical `${...}` approval gate fires — verified via:
  `plugin/bin/rlm_repl:18-31`, 2026-07-03. `embo-deliver` copies this shape.
- **Allow-rule form the hook accepts**: `matches_rule` accepts
  `Bash(cmd *)` and `Bash(cmd:*)`; existing rules `Bash(rlm_repl exec *)`
  and `Bash(rlm_repl status *)` prove the `Bash(<name> <sub> *)` shape works
  — verified via: `approve-compound.sh:136-162` and
  `.claude/settings.local.json:108,115`, 2026-07-03.
- **Unsafe-construct bail**: the hook bails to a normal prompt on `$(...)`,
  backticks, `<(...)`, and heredoc `<<` — verified via:
  `approve-compound.sh:12-18`. **Consequence:** the wrapper must be
  invoked with a plain arg list (`embo-deliver --plan tmp/git-<ts>.txt`),
  never via a heredoc or command substitution, or auto-approval is lost.
- **`gh` fallback in existing skill** is prose-only ("gh CLI not found.
  Copy the description…") — verified via: `plugin/commands/git.md:331`,
  2026-07-03. The wrapper needs its own runtime `gh` check for PR/merge
  modes (resolves PRD NFR-2 assumption).
- **`git add -A` / `commit -a` prohibition**: user-global CLAUDE.md, carried
  as a hard constraint. The wrapper stages by explicit name only.

## Past Decisions (Claude-Mem)

- **Task 019** removed skill-level confirmation gates because they
  *duplicated* the harness prompt. Here the harness prompt is eliminated
  (allowlisted wrapper), so the skill-level plan confirmation is the
  **sole** gate — no duplication. This is the intended inverse of 019.
- **Task 032** established the `plugin/bin/` PATH-wrapper mechanism.

## Proposed Design

### Components

**New — `plugin/bin/embo-deliver`** (bash wrapper, the executor)
- **Purpose**: run stage → commit → push → (open PR) → (merge) from a plan
  file, with no decisions of its own.
- **Pattern**: models `plugin/bin/rlm_repl` (self-resolving path, bare
  command, `exec`). Implemented in bash directly (not a wrapper over a
  second script) since it only orchestrates `git`/`gh`.
- **Argument contract** (the trapdoor — fixed once the skill depends on it):
  - `--plan <path>` — required. Path to the plan file (below).
  - No other required args. `--dry-run` optional (prints the git/gh
    commands it would run, executes nothing) for testing.
- **Reads**, does not decide. Every choice is in the plan file.

**New — plan file** (`tmp/git-<timestamp>.txt`, written by the skill)
- **Uniquely named per delivery** (timestamp in the name), **never
  overwritten, never deleted** — each delivery leaves a durable record.
- The **content is the approval artifact**: it is exactly what the skill
  shows the user in the single confirmation.
- Location `tmp/` is already gitignored and already an allowed write target
  (`Write(tmp/**)`, settings.local.json:88), so the skill writes it with no
  prompt.

**Modified — `plugin/commands/git.md`** (the brain)
- Add a **`deliver`** mode: build plan → write plan file → show plan →
  single `AskUserQuestion` approval → invoke `embo-deliver --plan <path>`.
- The existing commit/pr/style modes are unchanged (PRD: preserve the
  multi-group review path).

### Plan file format (data contract)

A line-oriented text file — human-readable (it is shown verbatim) and
trivial for bash to parse without `$(...)`. Keys are line-prefixed; the
message is a trailing block so newlines survive.

```
branch: <target-branch>
mode: push | pr | pr-merge
base: <base-branch>            # present only when mode = pr | pr-merge
file: <path>                   # one line per file, explicit names only
file: <path>
message:
<commit message, verbatim, may span multiple lines, to EOF>
```

Contract rules:
- `mode` is exactly one of the three tokens. `pr-merge` is the only mode
  that merges; `merge` never happens otherwise (PRD story 3).
- `file:` lines are the complete, explicit stage set. The wrapper stages
  **only** these, by name. Zero `file:` lines → error, exit non-zero.
- `message:` must be the last key; everything after it is the message body.
- The wrapper rejects (exit non-zero, no writes) a plan with: no `file:`
  lines, missing `branch`/`mode`/`message`, an unknown `mode`, or `base`
  missing when mode needs it.

### Execution sequence (embo-deliver)

```
parse --plan; read + validate plan file      # invalid -> exit 2, no writes
git add -- <file> ...                         # explicit names ONLY
git commit -m <message-from-plan>             # never -a
git push (-u origin <branch> if no upstream)  # to plan.branch
if mode in {pr, pr-merge}:
    require gh present                         # absent -> stop, exit 3
    gh pr create --base <base> --head <branch> ...
if mode == pr-merge:
    gh pr merge --<method> ...                 # method: design default below
report per-step status; exit 0 only if all attempted steps succeeded
```

Staging uses `git add -- <file>...` (the `--` guards against a filename
that looks like a flag). No `git add -A`, `git add .`, or `git commit -a`
anywhere — verifiable by grepping the script (PRD success metric 3).

### Failure handling (resolves PRD FR-7 / assumption)

Enumerated failure surfaces and the wrapper's response — each stops the
cycle at that step, reports completed vs not, exits non-zero, undoes
nothing:

| Step | Failure surface | Detection | Exit | User sees |
|------|-----------------|-----------|------|-----------|
| validate | malformed/incomplete plan | parse checks | 2 | which field is wrong; no git ran |
| push | rejected (non-ff, protected) | `git push` exit ≠ 0 | 4 | "committed locally, push failed" |
| push | no upstream | probe branch upstream | — | adds `-u origin <branch>` (not a failure) |
| pr | `gh` not installed | `command -v gh` | 3 | "committed+pushed; open PR manually" |
| pr | `gh pr create` fails | exit ≠ 0 | 5 | "pushed; PR not created" |
| merge | blocked by protection/CI/review | `gh pr merge` exit ≠ 0 | 6 | "PR open; merge blocked, merge manually" |

The wrapper never rolls back a completed commit or push — the developer
sees the true partial state and recovers deliberately. (Rollback plan
below.)

### Skill flow (git.md `deliver` mode)

1. Determine, from the development situation: target branch, mode
   (push | pr | pr-merge), base (for pr modes), the explicit file set, and
   the commit message (generated per active `git.commit_style`).
2. Write plan to `tmp/git-<timestamp>.txt` (unique name; never reused).
3. Show the plan file's content to the user and present **one**
   `AskUserQuestion`: Deliver / Cancel. The displayed plan lists exact
   files, the verbatim message, branch, mode, and — for pr-merge — the base
   branch with an explicit note that merge is irreversible (PRD story 1).
4. On Deliver → run `embo-deliver --plan tmp/git-<timestamp>.txt` (bare
   command, auto-approved once the user has added the allow rule).
   On Cancel → stop; nothing staged (the plan file remains as a record of
   the cancelled intent).
5. Relay the wrapper's per-step result.

Timestamp source: the skill obtains it at plan-write time (the wrapper does
not need it). Uniqueness requirement is a correctness point — a fixed
`tmp/git.txt` would both race across overlapping deliveries and erase the
prior record; per-delivery unique names avoid both.

### Delivery model: rapid is the default

Rapid delivery is not a small-change exception — it is the **default way to
deliver code**. There are two paths, chosen by how the change must be
*handled*, not by its size:

1. **Rapid** (`deliver`) — one commit of the needed files, one plan
   approval, straight to the branch. The common case.
2. **Full commit** (`commit`/`pr`) — split into several commits, polished
   messages for human review. For review-critical or genuinely large/mixed
   work.

A large single-concern change is still a valid rapid delivery. The only
thing that routes to full-commit is the need for the careful treatment:
multiple logical commits, human review, or mixed concerns.

Two touch-points make this the default without the user typing
`/embo:git deliver`:

- **`git.md` frontmatter `description`** names `deliver` as the default
  path and `commit`/`pr` as the exception.
- **`impl.md` continuation guidance**: when an `/embo:impl` run pauses with
  work to deliver, CC offers both paths with rapid as the default; it
  chooses full only when the change needs the careful treatment. Both keep
  the plan/commit approval as the single gate.

### Merge method (pr-merge)

`gh pr merge` requires a method. Design default: `--squash` (single tidy
commit on base, matches the "one small change" use case). Overridable via a
plan `merge-method:` key in a later iteration; not exposed in v1 to keep the
contract minimal.

## Verification Approach

| Requirement (PRD story / metric) | Method | Scope | Expected Evidence |
|---|---|---|---|
| Wrapper stages only plan `file:` lines; never `add -A`/`commit -a` (metric 3) | `auto-test` | unit | `--dry-run` on a plan prints `git add -- a b` and `git commit -m`, no `-A`/`-a`; grep of script finds no forbidden forms |
| Invalid plan → no git writes, exit 2 (data contract) | `auto-test` | unit | `--dry-run` / stub on malformed plans exits non-zero, emits no `git add` |
| Mode routing: push vs pr vs pr-merge (story 3) | `auto-test` | unit | `--dry-run` shows push-only / +`gh pr create` / +`gh pr merge` per mode |
| `gh` absent in pr mode → stop after push, exit 3 (failure table) | `auto-test` | unit | with `gh` masked, dry-run/stub stops at PR step, exit 3 |
| One approval runs whole cycle, no per-command prompt (story 1, 4) | `manual-run-claude` | integration | live `/embo:git deliver`: single AskUserQuestion, then wrapper runs with no harness prompt (requires allow rule added) |
| Plan shows exact files + verbatim message + target + mode + merge risk (story 1, 2) | `manual-run-claude` | integration | the shown plan content contains all five |
| Plan file uniquely named, not deleted after run (user requirement) | `manual-run-claude` | integration | `tmp/git-<ts>.txt` present after delivery; second delivery makes a new file |
| Reject → nothing staged (story 1) | `manual-run-claude` | integration | Cancel leaves `git status` unchanged |

## Trade-offs

1. **Plan-file contract (chosen)** vs flags-and-positional-args.
   - Pro: multi-line commit message stays clean; short command line
     (avoids a long arg string that strains the approval view); the file
     doubles as the durable per-delivery record the user asked for; content
     is exactly the approval artifact.
   - Con: one extra file write per delivery; the approval shows file
     *content* which the skill must render, not the raw command.
   - Rejected flags-based: long messages become an unwieldy arg line and
     leave no history artifact.

2. **Documented manual allow-rule opt-in (chosen)** vs shipping the rule in
   plugin settings.
   - Pro: unattended git writes are a real power grant; requiring the user
     to add `Bash(embo-deliver *)` themselves makes the opt-in explicit and
     auditable. Also sidesteps the unresolved question of whether
     plugin-shipped allow rules propagate on install.
   - Con: one manual setup step; until it is added, `embo-deliver` prompts
     once (degrades to the same cost as today, never worse).

3. **No rollback of completed steps (chosen)** vs auto-undo on failure.
   - Pro: auto-undo (e.g. `git reset` after a failed push) is itself
     destructive and could lose work; showing the true partial state is
     safer and matches the safety rules.
   - Con: the developer must finish a partially-completed cycle by hand.

## Implementation Constraints

- No new dependencies: `git`, `gh` (already assumed by the skill's pr
  mode), bash only.
- Bare-command invocation only — no `$(...)`, backticks, heredoc, or
  redirects in the command string, or the hook bails and auto-approval is
  lost (verified: approve-compound.sh:12-18).
- Staging by explicit name only; forbidden git forms must not appear in the
  script.
- The wrapper makes no branch/mode decision — all logic is in the plan.

## Files to Create/Modify

**Create**:
- `plugin/bin/embo-deliver` — the executor (bash, `chmod +x`).
- `tasks/038-.../...-tech-design.md` — this file.

**Modify**:
- `plugin/commands/git.md` — add the `deliver` mode + plan-file flow;
  argument-hint update.
- `README.md` — document `/embo:git deliver`, the plan-file behaviour, and
  the **manual allow-rule opt-in** step (`Bash(embo-deliver *)`), with the
  security note that it authorizes unattended git writes after plan
  approval.
- `plugin/.claude-plugin/plugin.json` — version bump.
- `.gitignore` — confirm `tmp/` is ignored (plan files must never be
  committed). `[assumption, verify in tasks]`.

## Security Considerations

- The single power grant is: after plan approval, git writes run
  unattended. Bounded by (a) explicit user opt-in via the allow rule, (b)
  the plan being shown in full before approval, (c) the wrapper staging only
  named files, (d) no destructive operations in the wrapper.
- Plan files under `tmp/` may contain the commit message and file paths;
  `tmp/` is gitignored so they are not published. No secrets are written by
  the wrapper.

## Rollback Plan

- Feature is additive: a new `plugin/bin/` file, a new skill mode, doc
  updates. Reverting = remove the file, revert `git.md`, drop the README
  section. No data migration, no state.
- If the allow rule misbehaves, the user removes the one settings line;
  `embo-deliver` then falls back to prompting (never worse than today).

## References

### Code (RLM / direct read)
- `plugin/bin/rlm_repl:18-31` — wrapper template.
- `plugin/hooks/hooks.json:28-38` + `approve-compound.sh:12-18,136-162,421-424`
  — gate scope, unsafe-bail, allow-rule matching.
- `plugin/commands/git.md:220-228,327-329,331` — existing modes to preserve;
  `gh` fallback.
- `.claude/settings.local.json:88,108,115` — `tmp/` write allow, rlm_repl
  allow-rule precedent.

### History (Claude-Mem)
- Task 019 — gate-removal decision (this is its inverse).
- Task 032 — `plugin/bin/` wrapper mechanism.

---

**Next Steps**:
1. Review and approve design.
2. Run `/embo:tasks` for task breakdown.
