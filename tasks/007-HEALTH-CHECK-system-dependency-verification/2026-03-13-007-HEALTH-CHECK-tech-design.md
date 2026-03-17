# 007-HEALTH-CHECK: System Dependency Verification - Technical Design

**Status**: Draft
**PRD**: [2026-03-13-007-HEALTH-CHECK-prd.md](2026-03-13-007-HEALTH-CHECK-prd.md)
**Created**: 2026-03-13

---

## Overview

The health check is a single markdown command file
(`.claude/commands/rlm-mem/discover/health.md`) that instructs Claude
to execute three independent checks in sequence, collect pass/fail
results with diagnostic details, and render a summary table with
actionable fix instructions for any failures.

No new scripts, binaries, or MCP tools are introduced. All checks
use the same infrastructure as existing commands.

---

## Component Structure

### Single File: `discover/health.md`

The command is purely a Claude prompt. The "components" are logical
sections within the prompt that Claude executes as steps:

```
health.md
├── Check 1: RLM State        → Bash tool (rlm_repl.py status)
├── Check 2: claude-mem       → MCP search tool (minimal query)
├── Check 3: Hook E2E         → Write tool + sleep + MCP search
└── Render: Summary table     → Claude output
```

Each check is independent — failure in one does not skip the others.
Claude accumulates results and renders the summary only at the end.

---

## Check Contracts

Each check produces a result object that feeds the final table:

```
CheckResult {
  name:    string          // display name in table
  status:  "pass" | "fail" | "error"
  notes:   string          // detail shown in Notes column
  fix:     string | null   // fix instruction shown below table on fail
}
```

### Check 1 — RLM State

**Mechanism**: `Bash` tool

```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py status
```

**Pass condition**: Output contains `Total files:` with a value > 0
and `Context path:` matches cwd.

**Fail conditions**:

| Output | Diagnosis | Fix instruction |
|--------|-----------|-----------------|
| `No such file or directory` (script missing) | RLM script not installed | `bash install.sh` from the rlm-mem repo |
| `Error` / no state.pkl | Repo not indexed | `/rlm-mem:discover:init` |
| `Total files: 0` | Index empty | `/rlm-mem:discover:init` |

**Notes column on pass**: `{N} files indexed`

---

### Check 2 — claude-mem Plugin

**Mechanism**: MCP tool call

```
mcp__plugin_claude-mem_mcp-search__search(
  query="health check probe",
  limit=1
)
```

**Pass condition**: Tool call returns without error (any result, including
zero matches, is a pass).

**Fail condition**: Tool call throws / returns an error object.

**Fail instruction**: `Verify plugin is installed: /plugin list` →
look for `claude-mem`. If missing: `/plugin marketplace add thedotmack/claude-mem`

**Notes column on pass**: `Responding`

---

### Check 3 — PostToolUse Hook End-to-End

**Mechanism**: Write → sleep → MCP search

**Step 1**: Generate a unique token:
```
token = "hc-" + current unix timestamp (seconds)
```

**Step 2**: Write test file:
```
Write /tmp/claude-mem-{token}.md:
  # Health Check Probe
  [TYPE: HEALTH-CHECK]
  [TOKEN: {token}]
  This file was written by /rlm-mem:discover:health to verify
  the PostToolUse hook is capturing observations.
```

**Step 3**: Read the file (triggers the hook):
```
Read /tmp/claude-mem-{token}.md
```

**Step 4**: Wait ~2 seconds (hook processes asynchronously):
```bash
sleep 2
```

**Step 5**: Search claude-mem for the token:
```
mcp__plugin_claude-mem_mcp-search__search(
  query="{token}",
  limit=1
)
```

**Pass condition**: Search returns ≥ 1 result.

**Fail condition**: Search returns 0 results.
Fail notes: `Observation not found (may be timing or hook misconfigured)`
Fail instruction:
```
Verify PostToolUse hook in ~/.claude/settings.json:
{
  "hooks": {
    "PostToolUse": [{ "type": "command", "command": "..." }]
  }
}
See README.md §Hook Setup for the correct configuration.
```

**Why timestamp as token**: Guarantees uniqueness across repeated
runs. The observation persists in claude-mem as an audit trail
(tagged `[TYPE: HEALTH-CHECK]`), which is acceptable per NFR-2.

---

## Output Contract

### All passing

```
## RLM-Mem Health Check

| Component         | Status | Notes                  |
|-------------------|--------|------------------------|
| RLM state         | ✅     | 31 files indexed       |
| claude-mem plugin | ✅     | Responding             |
| PostToolUse hook  | ✅     | Observation captured   |

All systems operational. Ready for /rlm-mem:discover:start
```

### With failures

```
## RLM-Mem Health Check

| Component         | Status | Notes                               |
|-------------------|--------|-------------------------------------|
| RLM state         | ❌     | state.pkl not found                 |
| claude-mem plugin | ✅     | Responding                          |
| PostToolUse hook  | ❌     | Observation not found after 2s      |

2 issues found:

❌ RLM state — state.pkl not found
   → Run: /rlm-mem:discover:init

❌ PostToolUse hook — Observation not found (may be timing or hook misconfigured)
   → Verify PostToolUse hook in ~/.claude/settings.json
     See README.md §Hook Setup for the correct configuration.
```

---

## Failure Independence

All three checks run regardless of prior results. Claude must not
short-circuit on the first failure. This is explicit in the command
prompt: "run all three checks even if earlier ones fail, then render
the combined summary."

This matters because a user diagnosing a broken install may have
multiple things wrong simultaneously.

---

## Rejected Alternatives

### A: Check hook registration in settings.json instead of E2E probe

Check whether the PostToolUse hook entry exists in
`~/.claude/settings.json` rather than writing a test file and
searching.

**Rejected because**: A registered hook that is misconfigured or
pointing to the wrong command appears as a false ✅. The PRD
explicitly requires zero false positives (NFR). The E2E probe is the
only way to know the hook actually works.

### B: Retry loop (poll until timeout) for hook check

Poll claude-mem every 0.5s up to 10s before declaring failure.

**Rejected because**: Over-engineered for a diagnostic tool. A single
2s wait is simple and sufficient for normal operation. If the hook is
healthy it will have processed well within 2s. If it's broken, waiting
longer doesn't help. The fail message already notes timing as a
possible cause, so users can re-run if they suspect a false negative.

### C: Separate `health.sh` bash script

Move the check logic into a bash script that the command calls.

**Rejected because**: All other commands are self-contained markdown
prompt files. Introducing a script adds a new file type, a new
installation step, and a new failure mode (script not found, not
executable). The KISS principle and the existing pattern favour a
single prompt file.

---

## Files to Create/Modify

**Create**:
- `.claude/commands/rlm-mem/discover/health.md` — the command prompt

**Modify**:
- `.claude/commands/rlm-mem/README.md` — add health to Discovery Phase table
- `README.md` — add health to Available Commands §Discovery Phase
- `CLAUDE.md` — no change needed (count stays at 8+1=9 after this)

---

## Sequence Diagram

```
User invokes /rlm-mem:discover:health
       │
       ▼
[Check 1] Bash: rlm_repl.py status
       │  pass → notes = "{N} files indexed"
       │  fail → fix = "run /discover:init"
       │
       ▼
[Check 2] MCP: search("health check probe", limit=1)
       │  pass → notes = "Responding"
       │  fail → fix = "verify plugin install"
       │
       ▼
[Check 3a] Write /tmp/claude-mem-{token}.md
[Check 3b] Read /tmp/claude-mem-{token}.md
[Check 3c] Bash: sleep 2
[Check 3d] MCP: search("{token}", limit=1)
       │  pass → notes = "Observation captured"
       │  fail → fix = "verify settings.json hook"
       │
       ▼
Render summary table (all results)
If any failures → print fix instructions below table
```

---

## References

- `discover/start.md` — structural template: step-by-step checks +
  final summary output pattern
- `discover/init.md:Step 1` — existing RLM prerequisite check
  (`rlm_repl.py --help`) as prior art for Check 1
- `005-FIX-SAVE-MEMORY` — write+read+search pattern used for Check 3
