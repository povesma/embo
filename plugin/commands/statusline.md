---
description: >
  Enable the embo status line. A plugin cannot register a status line
  itself, so this sets it up once in your settings.
allowed-tools: Bash(statusline-setup)
---

# Enable the embo Status Line

Run the bundled helper (on PATH via the plugin's `bin/`), then tell the
user to **restart Claude Code**:

```bash
statusline-setup
```

It copies `statusline.sh` to `~/.claude/statusline.sh` and points
`settings.json` there, repairing a stale embo entry but leaving a custom
one alone. If `jq` is missing it says so — relay the hint.
