# Verify RLM-Mem System Dependencies

Check that RLM state, claude-mem plugin, and PostToolUse hook are all
operational. Renders a combined summary table with fix instructions.

## When to Use

- After fresh install to confirm everything is wired correctly
- When commands behave unexpectedly, to diagnose the failure layer
- After system changes (OS upgrade, plugin updates, new shell profile)

## Process

**Run all three checks even if earlier ones fail. Collect results first,
then render the combined summary at the end.**

### Check 1 — RLM State

```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py status
```

| Outcome | `rlm_result` |
|---------|-------------|
| `Total files:` > 0 | pass · notes: `"{N} files indexed"` |
| `No such file or directory` | fail · notes: `"rlm_repl.py not found"` · fix: `"Run: bash install.sh from the rlm-mem repo root"` |
| Error / missing state.pkl | fail · notes: `"state.pkl not found or index error"` · fix: `"Run: /rlm-mem:discover:init"` |
| `Total files: 0` | fail · notes: `"Index is empty"` · fix: `"Run: /rlm-mem:discover:init"` |

### Check 2 — claude-mem Plugin

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

### Render Summary

```
## RLM-Mem Health Check

| Component         | Status | Notes                 |
|-------------------|--------|-----------------------|
| RLM state         | ✅/❌  | {rlm_result.notes}   |
| claude-mem plugin | ✅/❌  | {mem_result.notes}   |
| PostToolUse hook  | ✅/❌  | {hook_result.notes}  |
```

- **0 failures**: print `All systems operational. Ready for /rlm-mem:discover:start`
- **≥ 1 failure**: print `{N} issue(s) found:` then for each failed check:
  ```
  ❌ {name} — {notes}
     → {fix}
  ```
