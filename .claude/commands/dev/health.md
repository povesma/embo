# Verify RLM-Mem System Dependencies

Check that RLM state, claude-mem plugin, and PostToolUse hook are all
operational. Renders a combined summary table with fix instructions.

## When to Use

- After fresh install to confirm everything is wired correctly
- When commands behave unexpectedly, to diagnose the failure layer
- After system changes (OS upgrade, plugin updates, new shell profile)

## Process

**Read `~/.claude/active-profile.yaml` if it exists.** Use its values
to determine which checks to run and which MCPs to validate.
If no profile, use defaults (rlm=true, memory_backend=claude-mem).

**Run all checks even if earlier ones fail. Collect results first,
then render the combined summary at the end.**

### Check 1 — RLM State

**(Skip if profile `tools.rlm` is `false` — mark as "skipped")**

```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py status
```

| Outcome | `rlm_result` |
|---------|-------------|
| `Total files:` > 0 | pass · notes: `"{N} files indexed"` |
| `No such file or directory` | fail · notes: `"rlm_repl.py not found"` · fix: `"Run: bash install.sh from the repo root"` |
| Error / missing state.pkl | fail · notes: `"state.pkl not found or index error"` · fix: `"Run: /dev:init"` |
| `Total files: 0` | fail · notes: `"Index is empty"` · fix: `"Run: /dev:init"` |

### Check 2 — claude-mem Plugin

**(Skip if profile `tools.memory_backend` is `none` — mark as "skipped")**

```
mcp__plugin_claude-mem_mcp-search__search(query="health check probe", limit=1)
```

- **Pass** (tool returns, even 0 results): notes `"Responding"`
- **Fail** (tool errors): notes `"MCP tool error"` · fix: `"Run /plugin list — look for claude-mem. If missing: /plugin marketplace add thedotmack/claude-mem"`

### Check 3 — PostToolUse Hook End-to-End

```bash
date +%s   # → token = "hc-{timestamp}"
```

Write `/tmp/claude-mem-{token}.md`:
```
# Health Check Probe
[TYPE: HEALTH-CHECK]
[TOKEN: {token}]
```

Read `/tmp/claude-mem-{token}.md` (triggers hook), then:

```bash
sleep 2
```

```
mcp__plugin_claude-mem_mcp-search__search(query="{token}", limit=1)
```

- **Pass** (≥ 1 result): notes `"Observation captured"`
- **Fail** (0 results): notes `"Observation not found (may be timing or hook misconfigured)"` · fix: `"Verify PostToolUse hook in ~/.claude/settings.json — see README.md §Hook Setup"`

### Check 4 — Profile MCP Requirements

**(Skip if no active profile or profile has empty `mcps` lists)**

Read `mcps.required` and `mcps.optional` from the active profile.
For each required MCP, attempt a basic tool call to verify it's
responsive:
- `context7`: call `mcp__context7__resolve-library-id` with a
  known library
- `playwright`: call `mcp__playwright__browser_snapshot` or similar
- Other MCPs: attempt any available tool from that server

| MCP | Required? | Status | Notes |
|-----|-----------|--------|-------|
| {name} | required/optional | ✅/❌/⚠️ | {result} |

- Required MCPs that fail → ❌ with fix suggestion
- Optional MCPs that fail → ⚠️ warning only

### Render Summary

```
## RLM-Mem Health Check

| Component         | Status | Notes                 |
|-------------------|--------|-----------------------|
| RLM state         | ✅/❌  | {rlm_result.notes}   |
| claude-mem plugin | ✅/❌  | {mem_result.notes}   |
| PostToolUse hook  | ✅/❌  | {hook_result.notes}  |
```

- **0 failures**: print `All systems operational. Ready for /dev:start`
- **≥ 1 failure**: print `{N} issue(s) found:` then for each failed check:
  ```
  ❌ {name} — {notes}
     → {fix}
  ```
