---
description: >
  Turn off correction capture and fully reverse what
  /embo:enable-corrections did: restore claude-mem's prior mode and
  remove the modes-dir env var it added. Corrections already saved are
  left in place.
---

# Disable Correction Capture

Reverse `/embo:enable-corrections`: restore claude-mem's prior mode and
remove the `CLAUDE_MEM_MODES_DIR` env var it wrote, then restart the
worker. Corrections already captured stay in claude-mem — this only
stops new ones being categorized as `correction`.

Source the helper library first:

```bash
source "$CLAUDE_PLUGIN_ROOT/claude-mem/corrections-lib.sh"
```

## Step 1: Read the enable-record

```bash
cat ~/.claude-mem/embo-corrections-enable-record.json
```

If the file does not exist, correction capture was not enabled by this
command. Report that and stop — do not guess at a prior state or change
anything.

## Step 2: Restore the prior mode

Set `CLAUDE_MEM_MODE` back to the value recorded in
`prior_claude_mem_mode`:

```bash
corrections_restore_mode ~/.claude-mem/settings.json "<prior-mode>"
```

## Step 3: Remove the modes-dir env var (only if we wrote it)

Remove `CLAUDE_MEM_MODES_DIR` from `~/.claude/settings.json` ONLY if
this command wrote it AND its current value is unchanged since:

```bash
corrections_should_remove_modes_dir \
  ~/.claude-mem/embo-corrections-enable-record.json \
  ~/.claude/settings.json
```

If that returns success (exit 0), remove it:

```bash
corrections_remove_modes_dir ~/.claude/settings.json
```

Otherwise leave it untouched (either the record shows we did not write
it, or another tool has since changed its value — do not clobber it).

## Step 4: Restart the worker and verify

Stop the worker so the next session spawns fresh (`worker.pid` is a
JSON object — read its `.pid` field):

```bash
kill "$(jq -r .pid ~/.claude-mem/worker.pid)"
```

Confirm the next session's log does NOT load `code-embo`:

```bash
grep -E "Mode loaded:" ~/.claude-mem/logs/claude-mem-$(date +%F).log
```

The loaded mode should be the restored prior mode, not `code-embo`.

## Step 5: Delete the enable-record last

Only after Steps 2-4 succeed, remove the record so a repeat run is a
clean no-op:

```bash
rm -f ~/.claude-mem/embo-corrections-enable-record.json
```

Deleting it last means a crash between steps leaves the record in
place, so re-running disable safely repeats the restore (the operations
are idempotent).

Report what was reversed (mode restored to its prior value; env var
removed if applicable). Corrections already saved are unaffected.
