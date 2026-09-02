# 055: Subagent Rule Inheritance — Technical Design

**Status**: Draft
**PRD**: [2026-09-02-055-subagent-rule-inheritance-prd.md](./2026-09-02-055-subagent-rule-inheritance-prd.md)
**Created**: 2026-09-02

## Overview

Deliver the main agent's behavioral rules to every spawned subagent by
registering a **`SubagentStart` hook** (`plugin/hooks/subagent-rules.sh`)
that injects a filtered, salience-structured rule block into the
subagent's context via `hookSpecificOutput.additionalContext`, and by
setting a **calibrated `permissionMode` (`acceptEdits`)** on the shipped
agent definitions. The hook reuses the `behavioral-reminder.sh` extraction
pattern: it pulls the `CHECKLIST` regions from `start.md`, drops the ones
that assume a human channel, and prepends a short subagent preamble for the
two include-list rules that have no `CHECKLIST` region. Fail-open
throughout.

All three blocking assumptions are resolved: 1 (root cause) and 3
(salience) by live probe (Story 0, 2026-09-02, Claude Code 2.1.146), 2
(injection support) by authoritative sources plus the same probe. The
Story 0 gate is passed — implementation may proceed as designed, with no
re-scope and no D2/D3 changes required.

## Current Architecture (RLM-verified)

**Rule delivery to the main agent** — `plugin/hooks/behavioral-reminder.sh`
extracts every `CHECKLIST` region from `start.md` with:
```awk
/<!-- \/CHECKLIST -->/{f=0} f{print} /^\[.*checklist/{f=1;print}
```
and emits them as `hookSpecificOutput.additionalContext` on
`UserPromptSubmit` — verified via `behavioral-reminder.sh:110-121,138-144`,
`hooks.json:14-27`, 2026-09-02.

**The six `CHECKLIST` regions in `start.md`** (verified via
`grep -n 'CHECKLIST:' plugin/commands/start.md`, 2026-09-02):

| Line | Region | Subagent verdict |
|---|---|---|
| 92 | WITHSTAND-CRITICISM | **include** |
| 155 | CLEAR-OPTIONS | **exclude** — mandates `AskUserQuestion`; a subagent has no human channel → would stall |
| 225 | RESTATE-CORRECTION | **exclude** — `[correction]` marker has no capture target in a subagent turn |
| 388 | AVOID-APPROVAL | **include** |
| 515 | FOLD-FIRST | **exclude** — docs-authoring rule, irrelevant to most subagents |
| 597 | DELEGATE | **exclude** — a subagent must not spawn its own subagents (unsupported, risks recursion) |

**Gap found**: DECIDE-OR-ASK and RESEARCH-VERIFY — both on the PRD
include-list — have **`RULE:` blocks but no `CHECKLIST` region**
(verified: they are absent from the grep above). The main agent receives
them via the always-on `[RULES ACTIVE: …]` baseline line
(`behavioral-reminder.sh:97`) plus their full `RULE:` prose, not an
extractable checklist. So "extract the 6 and filter" alone cannot deliver
them — see Design decision D2.

**`PreToolUse` auto-approval already reaches subagents** —
`approve-compound.sh` is a stateless `PreToolUse:Bash` hook
(`approve-compound.sh:1-27`); docs confirm `PreToolUse` fires in subagents.
So subagent Bash shaping is already handled; this feature adds the
*judgment* rules only — verified 2026-09-02.

**Resolved PRD assumptions**:

1. **Root cause (`UserPromptSubmit` doesn't fire in subagents)** —
   **CONFIRMED by live probe** (Story 0.1, 2026-09-02, Claude Code
   2.1.146). A headless session with a logging `UserPromptSubmit` hook
   spawned a Task subagent; the hook fired exactly once — for the main
   prompt — and never for the subagent's prompt, while the transcript
   proves the subagent ran. Note: the 2.1.146 `UserPromptSubmit` payload
   carries no `agent_id` field (only `session_id`, `transcript_path`,
   `cwd`, `permission_mode`, `hook_event_name`, `prompt`), so the verdict
   rests on prompt-content matching. **Proceed as designed** — the
   feature does not collapse into filtering the existing injection.
2. **`SubagentStart` `additionalContext` injection** — **CONFIRMED, GA**.
   Issue #87411 quotes the hooks reference ("SubagentStart hooks can inject
   context via `hookSpecificOutput.additionalContext`") and reports it
   "verified working on 2.1.233"; issue #23885 corroborates "SubagentStart
   hook only supports `additionalContext` output." Verified 2026-09-02.
3. **Salience / placement** — **PASSED by live probe** (Story 0.3–0.4,
   2026-09-02, Claude Code 2.1.146). A temporary `SubagentStart` hook
   injected a bare one-line canary into an agent with a 420-line `.md`
   body; across 5 spawns the canary arrived in every subagent's own
   transcript and every first output line was `EMBOCANARY_7Q-SEEN` —
   arrival and salience both 5/5, with NO salience header needed. The
   pruning risk from issue #23885 ("appends to user context... may be
   dropped") did not materialize at this body length on this version.
   Keep D3's header as cheap insurance, not as a load-bearing mitigation.
   Two bonus facts from the probe: `additionalContext` works on 2.1.146
   (older than the 2.1.233 GA confirmation), and the `SubagentStart`
   payload carries `agent_id` + `agent_type` as the data contract states.

## Past Decisions (Claude-Mem)

- **Task 047 / obs #28979, #35679** — the verbatim-checklist extraction and
  "emit the artifact, then enforce" pattern. Reused here, retargeted to
  `SubagentStart`. Its core lesson — a rule NAME triggers memory
  reconstruction that drops atypical clauses, so inject verbatim TEXT — is
  why D3 injects the full checklist text, not rule names.
- **Task 044 / obs #30645** — delegation (when to spawn). This is its
  complement (how the spawned agent behaves).
- **obs #2063** — `approve-compound.sh` is stateless with filter
  decomposition; the new hook follows the same stateless, fail-open shape.
- **obs #30461** — no embo hook maintains cross-call state; keep this hook
  stateless too.

## Proposed Design

### Architecture

One new hook, one manifest entry, and a frontmatter edit to each shipped
agent. No change to `behavioral-reminder.sh` or the main-agent checklist
regions (so main-agent behavior is untouched).

```
SubagentStart event
   │
   ▼
subagent-rules.sh                         (new; PreToolUse-style, fail-open)
   ├─ extract 6 CHECKLIST regions from start.md   (reuse awk)
   ├─ drop CLEAR-OPTIONS, RESTATE-CORRECTION, FOLD-FIRST, DELEGATE
   │     → keep WITHSTAND-CRITICISM, AVOID-APPROVAL
   ├─ prepend static SUBAGENT PREAMBLE
   │     (DECIDE-OR-ASK "decide, don't stall" + RESEARCH-VERIFY "check
   │      docs first", worded for a no-human-channel agent)
   ├─ wrap in a salience header  (D3)
   └─ emit {hookSpecificOutput:{hookEventName:"SubagentStart",
                                additionalContext: <block>}}
```

### Design decisions

- **D1 — new hook file, not an extension of `behavioral-reminder.sh`.**
  The two hooks fire on different events (`UserPromptSubmit` vs
  `SubagentStart`) and inject different content (full 6 vs filtered subset
  + preamble). Sharing one file would couple them and risk main-agent
  regressions. Ship `subagent-rules.sh` separately; it MAY source a shared
  extraction function if one is factored out, but that refactor is optional
  and out of scope for v1.
- **D2 — deliver the include-list via extract-and-filter PLUS a static
  preamble** [resolves the D2 gap]. The user chose "extract all 6, filter
  out excluded." Filtering yields WITHSTAND-CRITICISM + AVOID-APPROVAL.
  DECIDE-OR-ASK and RESEARCH-VERIFY have no region, so the hook **prepends
  a short static preamble** carrying their subagent-appropriate directives.
  This honors "don't author new main-agent checklists" (no change to
  `start.md`'s main-agent-facing blocks) while still meeting the PRD
  include-list. The preamble text lives in `subagent-rules.sh` as the ONE
  place it is authored (single source for the subagent-only lines);
  WITHSTAND/AVOID-APPROVAL remain sourced from `start.md` (single source
  for shared rules).
- **D3 — structure the injection for salience** [mitigates assumption 3].
  Because `additionalContext` appends to prunable user context, the block
  opens with an imperative, high-salience header, e.g.:
  `=== BINDING SUBAGENT RULES (you are a subagent; you have NO channel to
  ask the human — DECIDE, do not stall) ===`, followed by the preamble and
  the two verbatim checklists. Imperative framing + front-loading is the
  documented mitigation for low-salience appended context. Story 0
  measures whether it survives pruning in the installed version.
- **D4 — `permissionMode: acceptEdits` on shipped agents** [FR-2]. Set in
  each agent's frontmatter. Auto-allows reads/edits; leaves Bash and
  irreversible actions gated by the harness. NOT `bypassPermissions`.
  Caveat (docs-verified): a parent session in `bypassPermissions`/
  `acceptEdits` overrides a subagent's `permissionMode` — so the ceiling
  the subagent runs at is `max(parent, self)` in permissiveness; the design
  cannot lower a permissive parent. This bounds the NFR-2 claim to
  "does not exceed the main agent's own configured mode."
  **Scope caveat (docs-verified 2026-09-02, post-review):** Claude Code
  ignores `permissionMode` (with `hooks`, `mcpServers`) in agents loaded
  from a plugin, for security — the field is inert on the
  `/plugin install` path and effective only in the standalone
  (`~/.claude/`) install, where agents are user-level. Kept anyway: it
  costs nothing on the plugin path and delivers FR-2 on the standalone
  path. README states the split.

### Components

**New**:
1. **`plugin/hooks/subagent-rules.sh`** (`SubagentStart` hook)
   - **Purpose**: inject the filtered rule block into every subagent.
   - **Pattern**: follows `behavioral-reminder.sh` (runtime extraction from
     `start.md`, `jq -n` JSON output) and `approve-compound.sh` (stateless,
     `trap 'exit 0'` fail-open).
   - **Dependencies**: `awk`, `jq`; reads `../commands/start.md`.

**Modified**:
1. **`plugin/hooks/hooks.json`** — add a `SubagentStart` entry (matcher
   `*`) invoking the new hook. Risk: low; additive.
2. **`plugin/agents/*.md`** (5 files) — add `permissionMode: acceptEdits`
   to frontmatter. Risk: low; per-agent, reversible.

**Unchanged**: `behavioral-reminder.sh`, all `CHECKLIST` regions in
`start.md`, `approve-compound.sh`.

### Data contract

`SubagentStart` hook input (stdin JSON) carries `agent_id`, `agent_type`
(docs-verified). The hook does not branch on them in v1 (universal
injection) but MAY read `agent_type` later for per-agent tailoring
(out of scope; see PRD).

Hook output (stdout JSON):
```json
{ "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "<salience header>\n<preamble>\n<2 checklists>" } }
```

### Error handling

- `trap 'exit 0' ERR` and a disable env switch, matching
  `behavioral-reminder.sh:8,11`.
- If `start.md` is unreadable or extraction yields empty: emit the preamble
  alone (still useful) or exit 0 silently — never block the spawn (FR-6).
- Malformed JSON is impossible via `jq -n` (it constructs valid JSON).

### Testing strategy

Follows the repo's `*.test.sh` fixture pattern (e.g.
`corrections-lib.test.sh`). Unit tests drive `subagent-rules.sh` with
synthetic stdin and assert on the emitted `additionalContext`:
- includes WITHSTAND-CRITICISM + AVOID-APPROVAL text,
- includes the DECIDE-OR-ASK + RESEARCH-VERIFY preamble,
- **excludes** CLEAR-OPTIONS, RESTATE-CORRECTION, FOLD-FIRST, DELEGATE,
- opens with the salience header,
- fails open (exit 0, no crash) when `start.md` is absent,
- one rule-edit to a kept region changes the output (single-source proof,
  FR-5).

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1 filtered injection | `auto-test` | unit | test asserts included/excluded rule text in output |
| FR-1 preamble delivers DECIDE-OR-ASK/RESEARCH-VERIFY | `auto-test` | unit | preamble lines present |
| FR-2 permissionMode | `code-only` | — | frontmatter shows `acceptEdits` on 5 agents |
| FR-2 ceiling (irreversible gated) | `manual-run-claude` | integration | subagent stops on force-push/merge/delete |
| FR-3 shipped-agent coverage | `code-only` | — | all 5 agents carry the frontmatter |
| FR-4 ad-hoc coverage | `manual-run-claude` | integration | `general-purpose` spawn shows rules in transcript |
| FR-5 single source | `auto-test` | unit | edit-changes-output test passes |
| FR-6 fail-open | `auto-test` | unit | missing `start.md` → exit 0, spawn proceeds |
| Assumption 1 (root cause) | `manual-run-claude` | spike | UserPromptSubmit hook log has/has-no subagent `agent_id` entry |
| Assumption 2/3 (inject + salience) | `manual-run-claude` | spike | canary echoed as first subagent line across ~5 runs |

### Story 0 — Blocking probe spike (run FIRST)

Before finalizing the hook, run the live probe (procedure from the PRD
assumptions, refined by the injection probe):

1. Register a temporary `UserPromptSubmit` hook that appends `agent_id` to
   a log; spawn a Task subagent; check whether the log gains a
   subagent-`agent_id` entry. **Answers Assumption 1** (does the main-agent
   mechanism already cover subagents?). If it DOES fire → the feature
   collapses to "filter the existing injection for subagents"; re-scope.
2. Register a temporary `SubagentStart` hook injecting a canary
   (`EMBOCANARY_7Q: reply with EMBOCANARY_7Q-SEEN as your first line`);
   give the target agent a long (400+ line) `.md` body; spawn it with a
   benign prompt. **Proof of arrival**: canary present in subagent input
   (via `claude --debug` hook log). **Proof of salience**: first output
   line is `EMBOCANARY_7Q-SEEN` across ~5 runs. If it echoes only with a
   short body → pruning risk confirmed; strengthen D3 (or await upstream
   `updatedPrompt`).
3. Record `claude --version` (behavior is version-gated; confirmed on
   2.1.233).

Story 0's outcome may adjust D2/D3 or, in the worst case (Assumption 1
false), re-scope the whole feature — hence it blocks implementation.

## Trade-offs

**Considered approaches for rule sourcing**:

1. **Purpose-built subagent rule block** (rejected by user). One dedicated
   region authored for subagents. Pro: no filtering, no interactivity
   risk. Con: a second place rules live → drift from the main-agent
   wording.
2. **Add CHECKLIST regions for the 2 missing rules, then allowlist**
   (rejected by user). Pro: pure extraction. Con: adds main-agent-facing
   checklist noise for rules that intentionally have none, changing
   main-agent behavior.
3. **Extract-all-6, filter, + static preamble (chosen)**. Pro: reuses the
   extraction mechanism, no main-agent change, shared rules stay
   single-sourced. Con: the 2 preamble rules are authored in the hook, a
   second (small, bounded) source — accepted because they are subagent-only
   directives with no main-agent equivalent to drift from.

**Considered mechanisms** (from PRD): SubagentStart-hook + permissionMode
(chosen); edit each `.md` (misses ad-hoc spawns); rules-only (not
deterministic); permissionMode-only (no judgment rules). Chosen per PRD.

## Implementation Constraints

- Stateless, fail-open, `awk`/`jq` only (no new deps) — repo convention.
- No rule prose in CLAUDE.md.
- Universal (static) injection — subagent task prompt not reliably
  available at `SubagentStart` (issue #87411 open).
- Cannot lower a permissive parent session's mode (D4 caveat).
- No internal task references in the shipped hook body beyond a plain
  rationale comment (repo rule); a `# See: tasks/055-…` header comment is
  permitted (hook scripts are exempt).

## Files to Create/Modify

**Create**:
- `plugin/hooks/subagent-rules.sh` — the `SubagentStart` hook.
- `plugin/hooks/subagent-rules.test.sh` — fixture tests.

**Modify**:
- `plugin/hooks/hooks.json` — register `SubagentStart`.
- `plugin/agents/rlm-subcall.md`, `session-scout.md`, `examine-advisor.md`,
  `approach-validator.md`, `visual-qa-reviewer.md` — add
  `permissionMode: acceptEdits`.

## Security Considerations

- The hook only reads `start.md` and writes JSON to stdout — no secrets, no
  network, no state file.
- `acceptEdits` deliberately does NOT auto-allow Bash or irreversible
  actions; the harness still gates them. `bypassPermissions` is never used.
- No agent message can grant a permission (docs-verified) — safety rests on
  harness settings + injected DECIDE-OR-ASK, never on subagent output.

## Performance Considerations

One `awk` pass over `start.md` (~600 lines) + one `jq -n` per subagent
spawn — comparable to `behavioral-reminder.sh` (~7ms class). Footprint
grows only by the injected block (2 checklists + preamble, a few hundred
tokens).

## Rollback Plan

Remove the `SubagentStart` entry from `hooks.json` (disables injection) and
revert the 5 frontmatter edits. Both are additive/reversible; no data
migration. The `BEHAVIORAL_REMINDER_DISABLED`-style env switch on the new
hook allows disabling without editing the manifest.

## References

- **Code**: `plugin/hooks/behavioral-reminder.sh` (extraction + JSON
  output pattern), `plugin/hooks/approve-compound.sh` (stateless fail-open
  shape), `plugin/commands/start.md` (the 6 CHECKLIST regions),
  `plugin/hooks/hooks.json`, `plugin/agents/*.md`.
- **History**: obs #28979/#35679 (verbatim-checklist pattern), #30645
  (delegation), #2063/#30461 (stateless hook shape).
- **Docs / issues (verified 2026-09-02)**:
  [hooks](https://code.claude.com/docs/en/hooks),
  [sub-agents](https://code.claude.com/docs/en/sub-agents),
  [#87411 SubagentStart additionalContext GA + agent_prompt request](https://github.com/anthropics/claude-code/issues/87411),
  [#23885 additionalContext appends to prunable user context](https://github.com/anthropics/claude-code/issues/23885),
  [#65495 Stop/SubagentStop additionalContext](https://github.com/anthropics/claude-code/issues/65495).

---

**Next Steps**:
1. Review and approve design.
2. Run `/embo:tasks` — Story 0 (probe spike) must be task 1 and block the
   rest.
