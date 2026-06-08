# 028 — Resolve REDIRECT-CMD-OUTPUT vs ZERO-PROMPT contradiction

**Status**: Draft · **2026-06-09** · defect fix · PRD skipped (problem
fully established below + verified live this session).

## Problem

Rule A (REDIRECT-CMD-OUTPUT, task 024) says to redirect output to a
file with `cmd > /tmp/out.log 2>&1; echo $?`
(`start.md:128-129`). Rule B (ZERO-PROMPT, task 022) says routine work
must never trigger a permission prompt. Obeying A triggers the prompt B
forbids. 024 post-dates 022 and never saw the conflict; neither task
owns it.

## Root cause (verified on Claude Code 2.1.153)

Two independent gates, not one:

| Gate | Fires on | Cleared by |
|------|----------|-----------|
| Filesystem sandbox | write path **outside** project (`/tmp`) | redirect to an **in-project** path |
| Bash compound | a chained cmd not on the allow-list (`; wc`, `\| tail`) | no chaining — inspect via Read/Grep tools |

Live tests this session: `grep ... > /tmp/f` **prompts**;
`grep ... > .scratch.log` (in-project) **does not**;
`grep ... > /tmp/f; wc -l` **prompts** (both gates). The redirect
*operator* does not prompt on 2.1.153 — the off-workspace **path** does.
Same class as 022's addendum (sandbox fired on the off-root read of
`~/.claude/active-profile.yaml`).

`approve-compound.sh` is correct and unchanged — it clears the compound
gate only; it cannot reach the sandbox.

## Resolution

Keep redirect-to-file (it correctly decouples one *capture* from many
*inspections* — needed because output can exceed the 30k-char tool
truncation, and re-running may be slow/unsafe). Change two things:

1. **Capture to in-project `tmp/`, never `/tmp`** — already gitignored
   (`.gitignore:33`). Shape: `<cmd> > tmp/<name>.log 2>&1`.
2. **No chaining** — drop `; echo $?` (exit code returns natively) and
   `| tail`/`| head`/`; wc`; read slices with the Read tool, search with
   Grep.

Structural, not just instruction: `/tmp` is blocked by the sandbox no
matter what the model does; inspection runs through tools that can't
flood context or re-run the command.

## Change

One file: `.claude/commands/dev/start.md`, the
`<!-- RULE:REDIRECT-CMD-OUTPUT -->` block (115-144) — swap `/tmp` →
`tmp/`, drop `echo $?`/filter-pipe examples, point inspection at
Read/Grep. Keep the lesson (a filter's exit code must not mask a
failure). No change to `.gitignore`, `approve-compound.sh`, the hook
baseline, or README.

## Open for /dev:tasks

1. Cross-version check: confirm in-project redirect clears the sandbox
   on a Claude Code older than the redirect-matching changelog
   (expected yes — sandbox is path-based and predates it).
2. Whether to repeat the in-project example in `/dev:impl` (recommend
   no — the rule is session-wide in start.md).

## Sources

Live tests (above); Context7 `/websites/code_claude` (redirect matching,
w15 compound hardening, hook cannot override deny/ask); 30k truncation
(anthropics/claude-code #19901, #12054); NotebookLM (recommended
dropping redirect — rejected: fails full-output + re-read-without-rerun).
