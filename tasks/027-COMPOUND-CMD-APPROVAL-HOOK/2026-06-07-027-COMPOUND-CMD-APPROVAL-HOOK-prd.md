# 027: Compound-Command Approval Hook — PRD

**Status**: Draft · **Created**: 2026-06-07 · **JIRA**: 027 (internal)
**Author**: Claude (via dev workflow analysis)

---

## Context

Claude Code matches Bash allow-rules against the **whole command
string**. A redirect, pipe, or `;`-chain makes the string miss every
saved rule, so a command prompts even when its base is allow-listed.
The shipped REDIRECT-CMD-OUTPUT rule tells the agent to redirect output
to a file, which appends `> file` and triggers this prompt on otherwise
silent commands.

Proposed fix: a `PreToolUse` hook on Bash that strips redirects / env
prefixes / wrappers, splits compound commands, and checks each bare
subcommand against the user's **existing** `permissions.allow`/`deny`.
All allowed and none denied → auto-approve; otherwise fall through to
the normal prompt. No new allow-list; deny still wins.

### Current State (verified 2026-06-07)

- Bash rules match the full command string incl. the redirect; each
  subcommand must match independently — official permissions doc + GH
  issue #29491 (CLOSED) via `gh issue view 29491`.
- Live: `ls > /tmp/x 2>&1` and `ls > .claude/x 2>&1` prompted;
  `ls ; echo` and `ls | grep` did not — `Bash` runs this session.
- `Write(tmp/**)` did NOT suppress a redirect prompt (redirect is a
  `Bash` match, not `Write`) — live test this session.
- A PreToolUse hook auto-approves via
  `hookSpecificOutput.permissionDecision:"allow"` (exit 0); silence
  falls through; deny/exit 2 blocks — official hooks doc + Context7
  `/anthropics/claude-code` hook SKILL.md.
- The repo already emits this exact schema — `docs-first-guard.sh:40-57`.
- All existing hooks are Bash + `jq`, no parser dependency — `ls .claude/hooks/`.
- A hook `"allow"` cannot override a native `deny` or protected-dir
  check (`.git`,`.claude`,…) — official permissions doc.
- PostToolUse cannot hide a command's output (only append context), so a
  "capture + hide from context" hook is impossible — official hooks doc.

### Past similar (claude-mem)

015 fail-open hook (#15665); 026 LLM-judge hook (#17162); 022
zero-prompt (#16514); schema retrieval (#17922).

## Problem

Redirected and compound Bash commands prompt even when every base is
allow-listed. The REDIRECT rule makes this fire constantly, and "always
allow" only saves brittle exact-match rules that never match again.

## Goal

Auto-approve a Bash command when every normalized subcommand already
matches the user's existing allow-list and none matches deny — no new
list, no weakened deny, no new dependency.

## User Stories

1. **Redirected allowed command runs silently.**
   - [ ] `<allowed> > tmp/out.log 2>&1` runs with no prompt.
   - [ ] Base not allowed → falls through to prompt.
   - [ ] Redirect into a protected dir still prompts.

2. **Compound of allowed commands runs silently.**
   - [ ] `<A> && <B>` / `<A> | <B>` run with no prompt when both allowed.
   - [ ] Any subcommand denied → whole command denied.
   - [ ] Any subcommand unknown → falls through to prompt.

3. **Never approve what it cannot parse.**
   - [ ] Parse failure / `$(...)` / backticks / heredoc → exit 0 no JSON
     (fall through).
   - [ ] Never emits `"allow"` for an unmatched subcommand.

## Requirements

- **FR-1** Read stdin once; extract `tool_input.command`; non-Bash or
  empty → fall through.
- **FR-2** Strip per-subcommand: redirects (`>`,`>>`,`2>&1`,`&>`,`<`),
  leading `FOO=bar` env prefixes, wrappers (`timeout`/`time`/`nice`/
  `nohup`/`stdbuf`).
- **FR-3** Split on `&& || ; | |& &` and newlines.
- **FR-4** Detect `$(...)`, backticks, `<(...)`, heredocs → fall through.
- **FR-5** Read merged `permissions.allow`/`deny`; match each subcommand
  using `Bash(cmd)`, `Bash(cmd *)`, `Bash(cmd:*)` forms.
- **FR-6** Any deny → `"deny"`; all allow & none deny → `"allow"`; else
  fall through.
- **FR-7** Register as PreToolUse matcher on `Bash`; installer copies to
  `~/.claude/hooks/`.

### Non-Functional

- Bash + `jq` only; `set -euo pipefail` with fall-open trap (exit 0) on
  any error, like `docs-first-guard.sh`.
- Never approve an unmatched/unparseable subcommand; deny wins; do not
  touch protected-dir prompts.

## Out of Scope

- Full AST parser (`shfmt`) or Python rewrite — dependency.
- Auto-injecting redirects via `updatedInput` — investigated, rejected
  (cannot know output size; PostToolUse cannot hide output).
- Changing the REDIRECT-CMD-OUTPUT wording — separate concern.

## Success Metrics

1. Redirected allowed command: 0 prompts (was 1/run).
2. Compound of allowed bases: 0 prompts.
3. Any unallowed/denied/unparseable subcommand: still prompts/denied —
   0 false approvals in the test suite.

## References

- Code: `docs-first-guard.sh:40-57` (schema template); other hooks
  (conventions); CLAUDE.md Installation Flow.
- Verified docs: permissions doc, hooks doc
  (`code.claude.com/docs/en/{permissions,hooks}`); Context7
  `/anthropics/claude-code` hook SKILL.md + hookify `rule_engine.py`;
  GH #29491.
- Prior art: `approve-compound-bash` (shfmt+jq), `liberzon/claude-hooks`
  (python) — same normalize→split→match→fall-through algorithm; this
  ports the conservative subset to dependency-free Bash.

---

**Next**: `/dev:tech-design` → `/dev:tasks`.
