# 027: Compound-Command Approval Hook — Technical Design

**Status**: Draft · **PRD**: [027-prd.md](./2026-06-07-027-COMPOUND-CMD-APPROVAL-HOOK-prd.md) · **Created**: 2026-06-07

## Overview

A `PreToolUse` hook on the Bash tool (`approve-compound.sh`, Bash + `jq`)
that normalizes each subcommand of a Bash command and auto-approves only
if every subcommand already matches the user's merged `permissions.allow`
and none matches `deny`. Otherwise it stays silent and Claude Code shows
the normal prompt. No new allow-list; deny and protected-dir checks are
untouched (they run regardless of the hook).

## Current Architecture (RLM-verified)

- `.claude/hooks/docs-first-guard.sh:5-57` — single `cat` stdin read;
  `set -euo pipefail` + `trap 'exit 0' ERR` fail-open; emits
  `hookSpecificOutput.{hookEventName,permissionDecision,permissionDecisionReason}`
  via `jq -n`. Direct template for this hook — verified via Read, 2026-06-07.
- `.claude/hooks/behavioral-reminder.sh:8,14,117` — same `trap`/`jq`
  conventions, `jq -r` stdin parse — verified via Read, 2026-06-07.
- Hook registration + install-to-`~/.claude` flow — CLAUDE.md
  "Installation Flow" / "File Structure".

## Proposed Design

### Component

**`.claude/hooks/approve-compound.sh`** (new) — PreToolUse, matcher `Bash`.
Stateless; decides fresh each call.

### Data contracts

- **stdin** (Claude Code → hook):
  `{ tool_name, tool_input: { command }, permission_mode, cwd }`.
- **stdout on approve** (exit 0):
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}`
- **stdout on deny** (exit 0):
  `…"permissionDecision":"deny","permissionDecisionReason":"<subcmd> matches a deny rule"`
- **fall-through**: exit 0, **no stdout** → normal prompt.

### Algorithm

1. Read stdin once. If `tool_name != "Bash"` or command empty → fall through.
2. If command contains `$(`, backtick, `<(`, or a heredoc (`<<`) → fall
   through (cannot parse safely in Bash+jq).
3. Split command on `&& || ; | |& &` and newlines → subcommand list.
4. Per subcommand, normalize: drop I/O redirections (`>`,`>>`,`2>&1`,`&>`,
   `<` and their targets), strip leading `WORD=val` env assignments, strip
   leading wrappers (`timeout time nice nohup stdbuf`). Take the resulting
   bare command + args.
5. Load merged permissions (see below) into allow[] and deny[].
6. Match each normalized subcommand against rule forms `Bash(cmd)`,
   `Bash(cmd *)`, `Bash(cmd:*)` (prefix/glob via `case`/`fnmatch`-style).
7. Decide: any deny match → `deny`; else all allow-matched → `allow`;
   else fall through.

### Permissions source

Merge `allow`/`deny` from all four standard layers, in Claude Code's
order: `~/.claude/settings.json`, `~/.claude/settings.local.json`,
`<project>/.claude/settings.json`, `<project>/.claude/settings.local.json`.
`jq -s` over the existing files; missing files skipped. `cwd` from stdin
locates the project layers.

### Error handling

`set -euo pipefail` + `trap 'exit 0' ERR`. Any failure (jq error, missing
field, unexpected construct) → exit 0 with no stdout = fall through.
**Invariant: the hook never emits `allow` for a subcommand it did not
positively match.**

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1 stdin parse / non-Bash skip | auto-test | unit | test.sh: non-Bash & empty → no stdout |
| FR-2 strip redirect/env/wrapper | auto-test | unit | `cmd > f` normalizes to `cmd` |
| FR-3 split on separators | auto-test | unit | `A && B` → [A,B] |
| FR-4 unsafe construct → fallthrough | auto-test | unit | `$(...)`,heredoc → no stdout |
| FR-5 merged-layer match | auto-test | unit | rule in ~/.claude matches |
| FR-6 deny-wins / all-allow / else | auto-test | unit | 3 cases → deny/allow/fallthrough |
| FR-7 live no-prompt | manual-run-claude | integration | allowed `cmd > tmp/x` runs silent |
| protected-dir still prompts | manual-run-claude | integration | `cmd > .claude/x` prompts |

## Trade-offs

1. **shfmt/Python full AST** (community approach) — complete subshell
   parsing, but adds a dependency. **Rejected**: PRD mandates Bash+jq.
2. **Bash+jq with conservative fall-through (recommended)** — no
   dependency, matches existing hooks; cost is that subshells/heredocs
   prompt instead of auto-approving. Acceptable: those are rare in the
   verification-command workflow, and falling through is safe.

## Implementation Constraints

- Bash 3.2-compatible (macOS default) — no `mapfile`/associative-array
  reliance unless guarded.
- Must not shell-out to run any part of the inspected command.
- `jq` only external tool (already a hook dependency).

## Files to Create/Modify

**Create**: `.claude/hooks/approve-compound.sh` — the hook.
**Modify**:
- shipped hook settings (where the repo registers PreToolUse hooks) — add
  `Bash` matcher entry.
- installer / docs (CLAUDE.md Installation Flow, README §Hooks) — add the
  new hook to the copy list and hooks table.

## Security Considerations

- Cannot widen permissions: only auto-approves what `allow` already grants;
  `deny` and hardcoded protected-dir prompts are evaluated by Claude Code
  regardless of hook output (verified, permissions doc).
- Bypass class (chained unallowed command hidden in `$()`/heredoc) is
  closed by FR-4 fall-through — the hook refuses to analyze those and
  defers to the prompt. Never add `bash`/`sh`/`zsh` to allow as a result.

## Rollback Plan

Remove the PreToolUse `Bash` matcher entry (or delete the hook file).
Behavior reverts to native prompting immediately; no state to unwind
(stateless hook).

## References

- Code: `docs-first-guard.sh:40-57` (schema), `behavioral-reminder.sh`
  (conventions), CLAUDE.md Installation Flow.
- Verified docs (2026-06-07): permissions & hooks docs
  (`code.claude.com/docs/en/{permissions,hooks}`), Context7
  `/anthropics/claude-code` hook SKILL.md + hookify `rule_engine.py`,
  GH #29491.
- Prior art: `approve-compound-bash`, `liberzon/claude-hooks`.

---

**Next**: `/dev:tasks`.
