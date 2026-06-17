# 031: Independent-Check Research Commands — Technical Design

**Status**: Draft · **PRD**: [031-prd.md](2026-06-15-031-RESEARCH-independent-check-commands-prd.md) · **Created**: 2026-06-15

## Overview

Two namespaced commands plus one rule and one vendored doc, all built
from existing embo patterns (markdown command files, `general-purpose`
subagents, `behavioral-reminder.sh` BASELINE). No new runtime, no code —
this is workflow/prompt engineering.

- `dev:research:examine` — `examine-advisor` run as two parallel passes
  (research + internal) → reconciled report + recommendation.
- `dev:research:verify` — verification-discipline check of one spec.
- `docs/VERIFICATION-DISCIPLINE.md` — vendored reference.
- `RESEARCH-VERIFY` rule in `start.md` + BASELINE.
- Advisor prompts embedded in the two agent definitions.

## Current Architecture (RLM-verified)

- Commands are flat markdown in `.claude/commands/dev/`; skill name =
  `dev:<name>`. A nested dir yields a namespaced skill, so
  `.claude/commands/dev/research/examine.md` → `dev:research:examine`
  — verified via: `ls .claude/commands/dev/`, 2026-06-15.
- Agent definitions use frontmatter `name / description / tools /
  model`; `tools` is a comma-separated list (`tools: Read, Grep, Glob`)
  — verified via: `head .claude/agents/rlm-subcall.md`, 2026-06-15.
- A `general-purpose` subagent (`Tools: *`) reaches NotebookLM MCP via
  **deferred tool loading** (ToolSearch loads the schema, then the call
  succeeds); `claude-code-guide` cannot (no MCP in its tool list)
  — verified via: capability probe + claude-mem #21128, 2026-06-15.
- `behavioral-reminder.sh` holds a single `BASELINE` tag string and
  emits it (plus keyword-triggered reminders) as `additionalContext`
  — verified via: read of `behavioral-reminder.sh`, 2026-06-15.
- NotebookLM auth expires (~20 min); `refresh_auth` may report
  `expired` while direct MCP calls still succeed — verified via:
  observed this session, 2026-06-15.

## Past Decisions (Claude-Mem)

- #21128 — subagents access MCP via deferred loading (the load-bearing
  mechanism here).
- #21157 / #21154 / #21152 — 031 PRD scope decisions.
- `test-review` agent and `dev:improve` — adversarial-review and
  review-then-report prior art.

## Proposed Design

### File layout

```
.claude/commands/dev/research/examine.md   (new — thin spawner)
.claude/commands/dev/research/verify.md     (new — thin spawner)
.claude/agents/approach-validator.md        (new — verify+advise; discipline prompt)
.claude/agents/examine-advisor.md           (new — examine+advise; one agent, two passes)
docs/VERIFICATION-DISCIPLINE.md             (vendored — HUMAN reference only)
.claude/commands/dev/start.md               (modify — add RESEARCH-VERIFY rule)
.claude/hooks/behavioral-reminder.sh        (modify — add tag to BASELINE)
```

**Architecture: commands are thin spawners of specialized advisor
agents.** Each agent both analyzes AND advises (verify+recommend,
examine+recommend) — never bare criticism. The heavy prompt lives
**embedded in an agent definition** (`.claude/agents/*.md`), not in the
command and not read from a runtime doc. Rationale:

- **No runtime doc dependency** — the discipline is in the agent the
  harness loads by name; no fragile relative path, no install-copy of
  the doc to `~/.claude/docs/`. `VERIFICATION-DISCIPLINE.md` is vendored
  as a **human reference only**.
- **Context isolation** — the heavy prompt consumes the *subagent's*
  context; the main thread receives only the verdict/report.
- **Structural independence** — a subagent has a clean context by
  construction, which is exactly what verification discipline requires
  (doc §A "fresh agent in a clean context" — the mechanism IS the
  implementation).
- **Matches existing embo pattern** — `rlm-subcall`, `test-review` are
  specialized agents with embedded analysis prompts.

(Rejected: command-reads-doc — fragile path across installs, heavy
prompt in main context. Rejected: separate prompt files — an agent
definition already IS the prompt home.)

### `dev:research:examine`

**Input (auto-detect):** the argument is either a path to an existing
file (PRD/tech-design) or inline option text. Detection: if the arg
resolves to a readable file, treat as document mode; else treat the arg
(and any following prose) as the options/decision to weigh.

**Flow:**
1. Main agent builds a **sanitized digest** of the target (see Privacy)
   — a purpose-shaped summary, not the raw doc — AND assembles the
   **surrounding-context block** the agent requires: the goal the
   direction serves, its constraints, what has been tried/ruled out and
   why the author is unsure. (The agent runs blind and cannot ask; this
   block is a hard input contract, not optional.)
2. Main agent presents the digest + context block and gets user
   go-ahead **before** any outbound call (subagents cannot prompt
   mid-run).
3. Spawn the **`examine-advisor` agent twice in background**, in one
   message (parallel) — same agent, two **passes**:
   - **pass=research:** uses NotebookLM MCP (declared in the agent's
     `tools:` frontmatter — custom-agent MCP is verified, see
     trade-off 2) to judge against prior art. Degrades per FR-5 if
     MCP/auth fails (`EXTERNAL-CHECK-SKIPPED`).
   - **pass=internal:** judges against the codebase and internal
     consistency; reads real artifacts, no external research.
4. Await both completions, then **reconcile**: merge findings, dedupe,
   rank by severity, split "both flagged" (high-signal) vs "one
   flagged", and combine the two recommendations into one.
5. Emit a **report only** — never edits the target.

**Agent contract:** input = sanitized digest + surrounding-context
block (+ repo context for the internal pass); output = a findings table
`{severity, finding, why-it-matters, suggested-improvement}` PLUS a
recommendation (the strongest path forward). The agent both finds what
is wrong AND advises; it never returns bare criticism.

### `dev:research:verify`

**Input:** a chosen spec/approach + its acceptance criteria (from a
tech-design path or stated inline).

**Flow:** the command is a thin spawner — it gathers the spec +
criteria and spawns the **`approach-validator`** agent (embedded
verification-discipline prompt), which runs the steps below in its own
context and returns the verdict table. The command does not itself hold
the discipline prose.
1. Extract load-bearing claims and each acceptance criterion.
2. For each, find an **independent source** — current docs (Context7
   MCP), the live system/version, or the real artifact — never agent
   memory.
3. After any fix to the approach, re-verify (the back-edge).
4. Exercise only genuinely un-proven paths, once each.
5. On repeated failure, signal reset-don't-patch (doc §G).

**Output:** per acceptance criterion, a verdict —
**proven** (with source), **unproven** (no independent source found),
or **contradicted** (evidence disagrees). Each claim sourced or tagged
assumption. Report only; manual invocation in v1.

### NotebookLM auth + degradation (FR-3, FR-5)

The **research pass**, inside the subagent: attempt the NotebookLM MCP
query. On an auth/expired error or unreachable tool → the subagent
reports `EXTERNAL-CHECK-SKIPPED: notebooklm auth` instead of failing.
Main agent's reconciliation notes the external check was skipped and
proceeds on the **internal pass** alone. Auth recovery (`nlm login`) is
a **user action** the main agent surfaces — it cannot be done in a
subagent. (The agent uses NotebookLM MCP only, never the `nlm` CLI.)

### `RESEARCH-VERIFY` rule (start.md + BASELINE)

A remindable rule block (like AVOID-APPROVAL): don't accept your own
confidence as evidence. Trigger on **above-average cost OR low
confidence**. Two tiers: (cheap/always-on) slightest doubt on any
tool/API/approach — especially not-widely-used — check **Context7
MCP**; (heavyweight) a real decision/spec — run `examine` / `verify`.
Add `· RESEARCH-VERIFY` to the `behavioral-reminder.sh` BASELINE
string. Baseline-only (no keyword trigger) — like CLEAR-OPTIONS.

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1 examine: two parallel passes → reconciled report | `manual-run-claude` | integration | report shows both passes' findings deduped + ranked, plus a combined recommendation |
| FR-2 verify: per-criterion verdict | `manual-run-claude` | integration | each criterion marked proven/unproven/contradicted with source |
| FR-3 background + await both | `manual-run-claude` | integration | two background agents spawned, both awaited |
| FR-4 privacy digest | `manual-run-claude` | unit | digest with planted secret + external host → masked before send |
| FR-5 graceful degradation | `manual-run-claude` | integration | MCP-down → report from internal pass, gap flagged |
| RESEARCH-VERIFY rule in BASELINE | `auto-test` | unit | hook output contains `RESEARCH-VERIFY` |
| skill names resolve | `manual-run-user` | — | `dev:research:examine` / `:verify` appear in skill list |

## Trade-offs

1. **Dedicated critic agents vs. command-embedded prompt vs.
   command-reads-doc** — dedicated agents chosen. Removes the runtime
   doc-path fragility, isolates the heavy prompt in the subagent's
   context, and makes independence structural. (See Architecture
   section.)
2. **Custom agent vs. general-purpose for the NotebookLM critic** —
   custom agent chosen. Custom-agent MCP `tools:` frontmatter is now
   **verified** to work (installed test-e2e agents list MCP tools;
   approach-validator's live run confirmed NotebookLM/Context7 names
   resolve). So examine uses one dedicated `examine-advisor` agent
   (NotebookLM in its tools), run twice by the command — `pass=research`
   and `pass=internal`. One agent, not two, to avoid proliferation
   (KISS); the internal pass simply doesn't use the NotebookLM tool.
   Caveat learned live: declared `mcp__*` names must match the live tool
   surface (Context7 was `query-docs`, not `get-library-docs`) — verify
   names at ship time.
3. **Background-parallel vs. sequential** — background chosen; the two
   critics are independent, parallelism is free and matches the
   "don't block the user" goal.

## Implementation Constraints

- Subagents cannot prompt the user → digest approval happens in the
  main agent before spawning.
- NotebookLM auth is flaky/expiring → must detect and degrade, never
  hang.
- `docs/` is a new top-level dir — `.gitignore` must not exclude it
  (verify in impl).

## Files to Create/Modify

**Create:** `.claude/commands/dev/research/examine.md` (thin spawner),
`.claude/commands/dev/research/verify.md` (thin spawner),
`.claude/agents/approach-validator.md`, `.claude/agents/examine-advisor.md`,
`docs/VERIFICATION-DISCIPLINE.md` (vendored, human reference, + tweaks).

**Modify:** `.claude/commands/dev/start.md` (RESEARCH-VERIFY rule),
`.claude/hooks/behavioral-reminder.sh` (BASELINE tag),
`.claude/hooks/behavioral-reminder.test.sh` (assert new tag), `README.md`
(per-rule-tag row + new commands).

## Security Considerations

Outbound-to-NotebookLM digest: hard-block secrets (passwords, tokens,
keys) and user-identity (external IPs, public hostnames, local paths,
account markers). Internal IPs / non-identifying technical detail
allowed. Main agent runs the mask before showing the digest for
approval; ambiguous values → ask the user.

## Rollback Plan

All changes are additive markdown/doc files plus a one-token BASELINE
edit. Rollback = revert the commit; no state, no migration.

## References

- Code: `.claude/agents/rlm-subcall.md` (agent frontmatter),
  `.claude/hooks/behavioral-reminder.sh` (BASELINE), `dev:improve.md`,
  AVOID-APPROVAL block in `start.md` (rule pattern).
- History: claude-mem #21128, #21152.
- `docs/VERIFICATION-DISCIPLINE.md` (vendored).

---

**Next Steps**: review/approve → `/dev:tasks` for breakdown.
