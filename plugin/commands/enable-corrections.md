---
description: >
  Turn on correction capture: configure claude-mem to record a
  `correction` observation whenever you redirect how Claude works, so
  `/embo:improve` has data to learn from. Opt-in, machine-wide, fully
  reversible with /embo:disable-corrections.
---

# Enable Correction Capture

Configure claude-mem's observer to add a `correction` observation type,
so `/embo:improve` can review the corrections you give Claude over time.
This performs every step itself — no manual file editing.

**This is machine-wide and opt-in.** claude-mem runs one shared worker
per machine, so this affects correction capture for every project, not
just the current one. It is fully reversible with
`/embo:disable-corrections`.

Verified against claude-mem **13.11.0**, worker runtime. The mechanism
relies on claude-mem internals (a custom mode file + a modes-dir env
var), not a documented public API — Step 1 warns on a version mismatch,
and Step 5 fails loud if the mode does not load, so breakage is visible
rather than silent.

## Step 0: Disclose and get consent

Tell the user exactly what becomes machine-wide and ask for explicit
confirmation before changing anything:

> Turning correction capture on adds a `correction` observation type to
> claude-mem's `code-embo` mode and selects that mode. Because claude-mem
> uses one shared worker for every project on this machine, this affects
> correction capture **everywhere**, not just this repo. It is fully
> reversible with `/embo:disable-corrections`. Proceed?

Use `AskUserQuestion` (exclusive: proceed / cancel). If the user
cancels, stop and change nothing.

## Step 1: Detect claude-mem and version-gate

Source the helper library and locate the installed claude-mem:

```bash
source "$CLAUDE_PLUGIN_ROOT/claude-mem/corrections-lib.sh"
```

Find the installed version and its shipped `code.json`:

```bash
ls -1 ~/.claude/plugins/cache/thedotmack/claude-mem
```

Take the highest version directory. Its mode source is
`~/.claude/plugins/cache/thedotmack/claude-mem/<version>/modes/code.json`.

**Version gate**: the mechanism was verified against **13.11.0**. If the
detected version differs, warn the user that the `code.json` structure
or the `CLAUDE_MEM_MODES_DIR` override may have changed, and ask (via
`AskUserQuestion`) whether to continue. Do not silently proceed. Export
the detected version so it is recorded in the enable-record:

```bash
export CORRECTIONS_CM_VERSION="<detected-version>"
```

## Step 2: Build the custom mode file

Always rebuild (even if `~/.claude-mem/modes/code-embo.json` exists), so
a stale mode from a prior claude-mem version cannot linger:

```bash
mkdir -p ~/.claude-mem/modes
jq -f "$CLAUDE_PLUGIN_ROOT/claude-mem/code-embo.build.jq" \
   ~/.claude/plugins/cache/thedotmack/claude-mem/<version>/modes/code.json \
   > ~/.claude-mem/modes/code-embo.json
```

## Step 3: Write the modes-dir env var (with conflict guard)

Check for a conflicting `CLAUDE_MEM_MODES_DIR` before writing:

```bash
corrections_modes_dir_conflict ~/.claude/settings.json
```

- `conflict` → **stop**. Report: another tool has set
  `CLAUDE_MEM_MODES_DIR` to a different path; this command will not
  overwrite it. Ask the user to resolve it manually.
- `same` → the key already holds our value; record
  `written=false` in Step 4 (this command did not write it, so disable
  must not remove it).
- `absent` → write it and record `written=true`:

```bash
corrections_merge_modes_dir ~/.claude/settings.json
```

## Step 4: Record prior state and select the mode

Record the current mode before changing it, then select `code-embo`:

```bash
jq -r '.CLAUDE_MEM_MODE // "code"' ~/.claude-mem/settings.json
```

Write the enable-record (prior mode from above; the written-bool from
Step 3's conflict result):

```bash
corrections_write_enable_record \
  ~/.claude-mem/embo-corrections-enable-record.json \
  "<prior-mode>" "<true|false>"
```

Set the mode:

```bash
jq '.CLAUDE_MEM_MODE = "code-embo"' ~/.claude-mem/settings.json > /tmp/cm.json \
  && mv /tmp/cm.json ~/.claude-mem/settings.json
```

## Step 5: Restart the worker and verify it loaded

The worker must be stopped so the next session spawns it fresh with the
new environment (a plain restart keeps the stale environment):

```bash
kill "$(jq -r .pid ~/.claude-mem/worker.pid)"
```

(`worker.pid` is a JSON object — read the `.pid` field, not the raw
file.) Then verify the day's log shows the mode loaded with no fallback:

```bash
grep -E "Mode loaded: code-embo|falling back" ~/.claude-mem/logs/claude-mem-$(date +%F).log
```

- `Mode loaded: code-embo` with **no** `falling back` line → success.
  Report what changed (mode file built, env var set if it was, mode
  selected) and that capture is now on machine-wide.
- A `falling back to 'code'` line → **failure**. Report the exact log
  path and that `CLAUDE_MEM_MODES_DIR` did not reach the worker. Do not
  claim success.

## What this did by hand (manual fallback)

If a step fails and the user must finish manually, the equivalent
actions are: build `~/.claude-mem/modes/code-embo.json` with the jq
program above; add `"CLAUDE_MEM_MODES_DIR": "~/.claude-mem/modes"` to the
`env` block of `~/.claude/settings.json` (Claude Code's own settings,
NOT a shell-profile export); set `"CLAUDE_MEM_MODE": "code-embo"` in
`~/.claude-mem/settings.json`; then start a fresh session. Undo with
`/embo:disable-corrections`.
