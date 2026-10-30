# 069: Dead frontmatter fields in shipped agents — Seed

**Status**: Seed
**Created**: 2026-10-29
**Found during**: task 068 research into subagent spawn behaviour

---

## The finding

All five shipped agents declare `permissionMode: acceptEdits`:

- `plugin/agents/approach-validator.md:13`
- `plugin/agents/examine-advisor.md:14`
- `plugin/agents/rlm-subcall.md:6`
- `plugin/agents/session-scout.md:6`
- `plugin/agents/visual-qa-reviewer.md:14`

Per the Claude Code documentation, plugin subagents **ignore**
`permissionMode`, `hooks` and `mcpServers`:

> "For security reasons, plugin subagents don't support the hooks,
> mcpServers, or permissionMode frontmatter fields. These fields are
> ignored when loading agents from a plugin."

So every one of those five lines is a no-op. Harmless at runtime, but
misleading: a reader reasonably assumes the agent runs with
`acceptEdits`, and it does not.

## Why this matters beyond tidiness

An agent that appears to grant a permission mode but does not may lead a
future change to rely on a permission the agent never had. The fix is to
remove the dead lines, so the files state what is actually in effect.

## Before acting — confirm the source

This finding came from research fetched via WebFetch, which summarises
with a small model. Task 068 twice shipped fixes built on second-hand
claims about undocumented behaviour, and both failed. **Confirm the
quote against the live `code.claude.com/docs/en/sub-agents` page before
removing anything.**

Also worth checking in the same pass: whether any shipped agent declares
`hooks` or `mcpServers` (a grep found none, but the same grep only
covered those two names), and whether the `background` field has any
legitimate use in these agents.

## Scope

Small: confirm the doc claim, remove the five dead lines, verify no
agent behaviour changes. Not urgent.
