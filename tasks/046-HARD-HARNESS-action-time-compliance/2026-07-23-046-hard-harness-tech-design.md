# 046: Hard Harness for Action-Time Rule Compliance — Technical Design

**Status**: Draft
**PRD**: [2026-07-23-046-hard-harness-prd.md](2026-07-23-046-hard-harness-prd.md)
**Created**: 2026-07-23

## Overview

v1 ships three mechanisms as embo hooks, all reading rules from one
runtime config so a new rule is added by declaration, not code:

- **M3 (CLASS 1)** — a config-driven trigger→substitute check merged
  into the existing `approve-compound.sh` PreToolUse:Bash hook. On a
  matched trigger it denies with the substitute in the reason (the model
  re-emits the sanctioned command).
- **M1 (CLASS 2)** — an out-of-band state gate: a new PostToolUse
  matcher-`*` hook (`custodian-halt.sh`) detects a critical-failure
  signal and writes a marker; `approve-compound.sh` — now a **single
  PreToolUse matcher-`*` hook** — denies non-exempt tool calls while the
  marker exists; a human clears it via `/embo:custodian-clear`.
- **M9 (instrumentation)** — the PostToolUse hook also appends an NDJSON
  violation line. Measurement, not enforcement.

## Verified Claude Code hook-API facts (VQ-1..3)

Verified 2026-07-23 against CC docs + GitHub issues (via claude-code-guide
agent), current CC v2.1.215.

- **VQ-1 — multi-hook conflict is DENY-WINS** (most-restrictive:
  deny > ask > allow). A hold-deny would correctly beat an approve-allow.
  **CAVEAT (issue #75915):** when one PreToolUse hook returns `allow`
  **with `updatedInput`** and a sibling returns `ask`/deny, the
  `updatedInput` mutation is **silently discarded**. `approve-compound.sh`
  uses `updatedInput` for its capture-wrapper rewrite.
  **Design consequence (corrected after internal critique):** two
  `hooks.json` entries of the same script (matcher-`Bash` + matcher-`*`)
  would STILL be **two hooks firing** on a Bash call — that is exactly
  #75915, not an escape from it. The correct design is a **single
  PreToolUse registration, matcher-`*`, one script invocation per tool
  call**, branching internally on `tool_name`: the hold-check runs first
  for ALL tools; the Bash-only path (M3, `decide()`, capture rewrite)
  runs after, only when `tool_name == Bash`, and only if the hold-check
  did not already deny. One process, one decision — genuinely avoids
  #75915. → **Tracking note (`cc-bug-tracking.md`):** if #75915 is fixed,
  a separate hold hook becomes viable; until then, single-registration is
  required.
- **VQ-2 — PostToolUse matcher-`*` receives `tool_output` for ALL tool
  types** (MCP, Read, WebFetch, …), and root-level
  `{"decision":"block","reason":...}` is honored. Exit 2 in PostToolUse
  is blocking-error (tool already ran; blocks the model from seeing the
  result, adds stderr as reason). → M1 SET uses matcher-`*` + root-level
  `decision:block`, matching FR-1.
- **VQ-3 — PreToolUse `additionalContext` is silently dropped
  (issue #19432, closed "not planned").** Workaround: `systemMessage`.
  For a **deny**, `permissionDecisionReason` IS surfaced to the model —
  so M3's substitute-on-deny (a deny reason) works correctly. A general
  non-deny context injection would need `systemMessage`. Split schema
  (#19115) is permanent: PreToolUse nests `hookSpecificOutput`,
  PostToolUse uses root-level keys.

## Current Architecture (RLM/file-verified)

Verified by reading the files, 2026-07-23.

- **`plugin/hooks/hooks.json`** — registers SessionStart
  (statusline-refresh), UserPromptSubmit (context-guard,
  behavioral-reminder), PreToolUse matcher-`Bash` (approve-compound).
  **No PostToolUse registered** — M1/M9 add the first.
- **`plugin/hooks/approve-compound.sh`** — the integration point.
  Sourceable (`if [ "${BASH_SOURCE[0]}" = "${0}" ]` guard, line 417) so
  functions are unit-testable. Key reusable functions: `decide()`
  (line 182, returns allow|deny|fallthrough — **deny already
  short-circuits first**, line 197-201), `normalize_subcommand()`
  (line 96), `split_subcommands()` (line 22), `load_rules()` (line 167,
  the jq-over-4-settings-layers pattern). Emits PreToolUse
  `hookSpecificOutput` JSON. Fails open (`trap 'exit 0' ERR`, line 419).
- **`plugin/hooks/behavioral-reminder.sh`** — the fail-open + verbatim
  single-source pattern (reads CHECKLIST regions from start.md).
- **`*.test.sh`** — fixture harness: source the script, feed synthetic
  JSON, assert output. `approve-compound.test.sh`, `behavioral-reminder.test.sh`,
  `embo-capture.test.sh`, `fix-hooks.test.sh`.
- **`.claude/rlm_state/`** — RLM's `state.pkl` only; gitignored. Marker
  goes in a NEW sibling `.claude/embo_state/` (decision: clean
  separation; rlm_state may be absent if RLM never init'd).
- **`plugin/commands/`** — flat `/embo:*` command files; `custodian-clear.md`
  fits here.

## Past decisions (claude-mem)

- **Task 027** built `approve-compound.sh` — the merged deny path is a
  natural extension of its existing deny-wins `decide()`.
- **Task 039** established verbatim CHECKLIST injection (a rule NAME
  triggers lossy reconstruction; verbatim text survives). M9's log and
  any future JIT reminder follow this.
- **"No embo hooks maintain cross-call state" (obs 31505)** — confirms
  the marker-file approach is the established way to carry state across
  stateless hook invocations.

## Proposed Design

### Rule config schema (FR-config — the genericity mechanism)

One file read by both hooks at runtime:
`plugin/hooks/harness-rules.json` (shipped defaults) merged with an
optional project-level `.claude/embo_state/harness-rules.json`
(user rules), same 4-layer merge idea as `load_rules()`.

```json
{
  "class1": [
    { "id": "jq-not-python",
      "trigger": { "heads": ["python","python3","node"],
                   "arg_matches": "\\.(json|ya?ml)\\b",
                   "body_matches": "json\\.loads?|JSON\\.parse|yaml\\.safe_load" },
      "action": "deny",
      "substitute": "use jq/yq: jq -r '<expr>' <file>  (yq for YAML)" },
    { "id": "rg-not-grep",
      "trigger": { "heads": ["grep"], "arg_matches": "-r|-R|--recursive" },
      "action": "deny",
      "substitute": "use rg: rg '<pattern>' <path>" }
  ],
  "class2": [
    { "id": "auth-halt",
      "detector": { "signal": "stderr_matches",
                    "pattern": "401 Unauthorized|403 Forbidden|permission denied \\(publickey\\)|not logged in|authentication failed|token expired" },
      "report": "A critical tool failed authentication. Report this to the user and STOP — do not re-auth, retry, or use an alternate tool." },
    { "id": "destructive-precondition",
      "detector": { "signal": "exit_and_tool",
                    "tool_matches": "Bash",
                    "exit_code": 1,
                    "stderr_matches": "refusing to run|precondition failed|guard tripped" },
      "report": "A destructive-operation precondition failed. Report and STOP." }
  ]
}
```

**Why this proves genericity, not point-solution:**
- Two CLASS 1 rules with **structurally different triggers**
  (`jq-not-python` = interpreter+arg+body; `rg-not-grep` = head+flag).
- Two CLASS 2 rules with **structurally different detectors**
  (`auth-halt` = stderr regex; `destructive-precondition` = exit code +
  tool + stderr). The detector has a **`signal` type discriminant**
  (`stderr_matches` | `exit_and_tool` | future types), so a new signal
  shape is a new enum value + a small matcher, but a new *rule* of an
  existing shape is pure config.
- **FR-genericity-test:** a fresh context adds a 3rd rule per class
  (e.g. `uv-not-pip`; `missing-approval-halt`) editing only the JSON.
  Pass = zero `.sh` change.

### Component: M3 + M1-hold in `approve-compound.sh` (single matcher-`*` hook)

**`main()` is restructured** — the existing early exit
`[ "$TOOL" = "Bash" ] || exit 0` (line 423) becomes an if/else so the
hold-check reaches non-Bash tools. New control flow:

```
INPUT=$(cat); TOOL=$(jq .tool_name)
# 1. HOLD (all tools, first) — runs regardless of TOOL:
if marker_exists && ! is_exempt "$TOOL" "$INPUT"; then
    emit PreToolUse deny(marker.report); exit 0
fi
# 2. Bash-only path (M3 + existing allow/wrap), only when TOOL=Bash:
if [ "$TOOL" = "Bash" ]; then
    CMD=$(jq .tool_input.command)
    # 2a. M3: for each class1 rule, match trigger on normalized subcmds
    #     → deny(substitute) via permissionDecisionReason
    # 2b. existing decide()/final_command/updatedInput logic, unchanged
fi
exit 0
```

Because there is **one registration (matcher-`*`) and one invocation per
tool call**, the hold-deny and the Bash allow+rewrite are decided in the
same process — a denied call returns before `final_command`, so
`updatedInput` is never emitted alongside a deny. This is what actually
avoids #75915 (the earlier two-registration sketch did not — two entries
matching Bash are two hooks). The matcher-`Bash` entry is **removed**;
matcher-`*` subsumes it (the internal `TOOL = Bash` guard preserves the
Bash-only behavior for non-halt calls).

**Exemptions (`is_exempt`)** during a halt: read-only tools `Read`,
`Grep`, `Glob` (so the agent can still gather facts to write its report),
and the **clear command's actual tool call**. `/embo:custodian-clear` is
a slash command — it does NOT appear as a literal Bash head at the hook
boundary. Its `.md` implementation runs a **bin wrapper**
(`embo-custodian`, following the `embo-deliver`/`embo-corrections`
pattern); the exemption matches that wrapper's normalized head, not the
slash-command string. This is the only reliable hook-visible signal of
the clear path.

### Component: M1-set + M9, new `custodian-halt.sh` (PostToolUse matcher-`*`)

- Reads `tool_name`, `tool_input`, `tool_output` (stdout/stderr/exit).
- For each `class2` rule, evaluate its `detector.signal`:
  - `stderr_matches` → regex over stderr/stdout;
  - `exit_and_tool` → exit code + tool-name + optional stderr regex.
- On match: write `.claude/embo_state/custodian-halt.json`
  `{rule_id, ts, tool_name}` **atomically** (`printf … > f.tmp && mv
  f.tmp f`) so a crash mid-write never leaves a partial marker, and emit
  root-level `{"decision":"block","reason":<report>}`.
- **M9:** regardless of block, append one NDJSON line to
  `.claude/embo_state/harness-violations.log`:
  `{ts, rule_id, class, mechanism, tool_name, verdict}`.
- Fail open (`trap 'exit 0' ERR`).

### Component: `/embo:custodian-clear` + `embo-custodian` bin + flap guard

- `/embo:custodian-clear` (`.md` command) runs the **`embo-custodian`
  bin wrapper** (pattern of `embo-deliver`/`embo-corrections`) — this
  gives the clear path a stable, hook-visible normalized head that
  `is_exempt` can match. The wrapper deletes the marker and, before
  deleting, **appends** `{rule_id, cleared_ts}` as an NDJSON line to
  `.claude/embo_state/custodian-cleared.log`.
- **Flap guard (FR-3):** `custodian-halt.sh`, before writing a new
  marker, greps `custodian-cleared.log` **filtered by `rule_id`** (an
  append-log, not a single-object file — so a second CLASS 2 rule's
  clear never overwrites the first's history, the collision the critique
  caught given we ship 2 CLASS 2 rules): if the same `rule_id` was
  cleared within N turns/minutes, the report escalates to "possible
  false-positive signature for rule `<id>` — review its detector"
  instead of a silent identical re-halt.
- Human-only: no hook auto-clears. Ack-token-in-prompt clearing is
  **roadmap**, not v1.

### Marker lifecycle (SET / HOLD / CLEAR)

```
PostToolUse(any tool) --detector match--> SET marker + block(report)
   |
PreToolUse(any non-exempt tool) --marker exists--> DENY(report)   [HOLD]
PreToolUse(Read/Grep/Glob | clear-cmd) --exempt--> normal          [HOLD]
   |
/embo:custodian-clear (human, via embo-custodian bin)
   --> append rule_id to custodian-cleared.log + DELETE marker      [CLEAR]
   |
next detector match of same rule within N --> SET + escalated report [FLAP]
```

### Data contracts

- **Marker** `.claude/embo_state/custodian-halt.json` (written atomically):
  `{ "rule_id": str, "ts": iso8601, "tool_name": str }`
- **Cleared log** `.claude/embo_state/custodian-cleared.log` (NDJSON,
  append-only, keyed-by-rule on read): `{ "rule_id": str, "cleared_ts": str }`
- **Hook config** `harness-rules.json`: schema above.
- **Violation log** NDJSON line:
  `{ "ts": str, "rule_id": str, "class": 1|2, "mechanism": "M1"|"M3",
     "tool_name": str, "verdict": "denied"|"halted"|"captured" }`

### Error handling

Every hook: `set -uo pipefail`, `trap 'exit 0' ERR`, jq-guarded reads
(`|| exit 0`). A malformed `harness-rules.json` → fail open (no rule
enforced), logged. A missing marker dir → created on first write, or
treated as "no halt" on read.

**Asymmetric fail direction for M1 (critique finding).** The marker is
written atomically, so a corrupt marker should not occur — but if the
marker file **exists yet is unparseable**, the HOLD check treats it as
**halt-active** (fail-SAFE), NOT as no-halt (fail-open). Rationale: M1 is
the only deterministic CLASS 2 lever; silently disabling it on a
read-corruption would defeat its entire purpose. This differs from the
blanket fail-open of M3/behavioral-reminder, where fail-open only means
"no nudge this turn." The report in that case says "custodian marker
present but unreadable — treating as active; clear with
/embo:custodian-clear." Everywhere else, fail open — never break the
session.

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-config (config read at runtime) | auto-test | unit | fixture: rule from JSON drives decision |
| FR-1 (M1 SET, matcher-*) | auto-test | unit | synthetic PostToolUse (MCP + Bash) → block emitted |
| FR-2 (M1 HOLD + exemptions) | auto-test | unit | marker present → deny; Read exempt → allow |
| FR-3 (clear + flap guard) | auto-test | unit | clear removes marker; re-trip < N → escalated report |
| FR-5 (M3 trigger→substitute) | auto-test | unit | python-on-json → deny w/ jq substitute |
| FR-6 (M9 capture fields) | auto-test | unit | NDJSON line has v1 field set |
| FR-9 (single hook, both modes) | auto-test | unit | invoke `approve-compound.sh` ONCE per case: (a) marker present + non-Bash tool → deny; (b) marker present + Bash w/ trigger → deny, NO updatedInput emitted; (c) no marker + Bash allowed → allow+rewrite intact. Since it's one hook now, there is no two-script fixture — assert the single script's branch order |
| FR-first-rules (2 rules/class) | auto-test | unit | all 4 seed rules fire from config |
| FR-genericity-test (3rd rule, no code) | manual-run-claude | integration | fresh context adds rule via JSON only; works — **scope: proves config-level genericity for the two shipped signal shapes (trigger→substitute; stderr/exit detector) ONLY.** A genuinely NEW signal shape (e.g. "N consecutive failures") DOES need a new matcher in code — documented as a boundary, not hidden |
| genericity boundary (new signal shape needs code) | auto-test | unit | a rule with an unknown `signal` type → fails open + logs "unknown signal shape", proving the boundary is explicit, not silent |
| End-to-end compliance (POC) | manual-run-claude | e2e | control vs treatment delta, per PRD POC |

## Trade-offs

1. **Two separate hooks (rejected).** Clean separation, but CC #75915
   silently discards `approve-compound`'s `updatedInput` when a sibling
   hook returns deny/ask on the same event. Rejected until #75915 fixed.
2. **Two registrations of one script, matcher-`Bash` + matcher-`*` via
   env flag (rejected — was the first draft; internal critique caught
   it).** Two `hooks.json` entries both match a Bash call → still TWO
   hooks firing → still #75915. Does not achieve "one decision."
3. **Single matcher-`*` registration, internal `tool_name` branch
   (chosen).** One entry, one invocation per tool call; hold-check first
   (all tools), Bash path after (M3 + existing allow/wrap). Deny returns
   before `updatedInput` is ever emitted → genuinely avoids #75915. Cost:
   `main()` restructure (early-exit → if/else) and one script with two
   responsibilities; mitigated by the sourceable-function structure.
3. **Marker in new `.claude/embo_state/` (chosen)** vs reuse
   `rlm_state`. New dir = clean separation, present regardless of RLM
   init. Trivial cost of one more gitignored dir.

## Files to Create/Modify

**Create:**
- `plugin/hooks/harness-rules.json` — shipped default rules (2/class).
- `plugin/hooks/custodian-halt.sh` — PostToolUse matcher-`*` (M1 SET + M9).
- `plugin/hooks/custodian-halt.test.sh` — fixtures.
- `plugin/hooks/harness-rules.test.sh` — config-driven decision fixtures
  incl. the genericity 3rd-rule check + unknown-signal boundary test.
- `plugin/bin/embo-custodian` — clear-marker wrapper (stable hook-visible
  head for `is_exempt`; pattern of `embo-deliver`/`embo-corrections`).
- `plugin/commands/custodian-clear.md` — `/embo:custodian-clear`, runs
  `embo-custodian`.

**Modify:**
- `plugin/hooks/approve-compound.sh` — restructure `main()` early-exit
  into an if/else; add M1-hold check (all tools, first) + M3 check (Bash,
  after); read `harness-rules.json`; `is_exempt` for read-only tools +
  the `embo-custodian` head.
- `plugin/hooks/approve-compound.test.sh` — add hold/M3/branch-order cases.
- `plugin/hooks/hooks.json` — **change** the PreToolUse entry from
  matcher-`Bash` to matcher-`*` (single registration); **add** a
  PostToolUse matcher-`*` entry (custodian-halt). No second PreToolUse
  entry.
- `.gitignore` — add `.claude/embo_state/`.
- `CLAUDE.md` — document that the harness mechanism exists (same
  mechanism-level detail as the existing `approve-compound.sh` entry) —
  NOT the user-facing config/usage. Per CLAUDE.md's own "not a
  deliverable" rule, the `harness-rules.json` schema and
  `/embo:custodian-clear` usage go in README + the command file, not
  CLAUDE.md.

## Dependencies

- **External:** `jq` (already a hook dependency), POSIX shell. No new deps.
- **Internal:** reuse `approve-compound.sh` functions; `behavioral-reminder.sh`
  fail-open pattern.

## Security Considerations

Marker + config are local, gitignored. Detectors match tool output only
(no secret capture). M9 log records rule ids + tool names, not raw
output (avoids logging credentials that appeared in a failed auth call).

## Performance Considerations

All hooks on-violation-only or cheap-read: M1-hold is a file-exists
check per tool call (~ms); M3 is regex over normalized subcommands
(comparable to existing `decide()`); PostToolUse detector is jq + regex
over tool_output. No standing per-turn preamble → ~0 token overhead on
compliant turns (NFR-1).

## Rollback Plan

Every mechanism is behind an env disable switch (FR-8:
`CUSTODIAN_HALT_DISABLED`, `SUBSTITUTE_SUPPLY_DISABLED`). Removing the
PostToolUse registration from `hooks.json` fully disables M1/M9; the M3
addition to `decide()` is guarded by its env switch and fails open.

## References

### Code (verified 2026-07-23):
- `plugin/hooks/approve-compound.sh:182` — `decide()` deny-first structure
- `plugin/hooks/approve-compound.sh:96,22` — normalize/split reuse
- `plugin/hooks/approve-compound.sh:417` — sourceable test guard
- `plugin/hooks/hooks.json` — current registrations (no PostToolUse)

### CC hook API (verified 2026-07-23, v2.1.215):
- Issue #75915 (updatedInput discard on multi-hook) — drives the merge decision
- Issue #19432 (additionalContext drop) — drives systemMessage/deny-reason choice
- Issue #19115 (split output schema) — PreToolUse nested vs PostToolUse root

### History (claude-mem):
- Task 027 (approve-compound), Task 039 (verbatim CHECKLIST), obs 31505
  (no cross-call state → marker-file pattern)

---

**Next Steps:**
1. Review/approve design (VQ-1..3 verified; two forks decided)
2. `/embo:tasks` for breakdown
