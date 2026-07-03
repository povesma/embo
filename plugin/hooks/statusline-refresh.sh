#!/usr/bin/env bash
# statusline-refresh.sh — SessionStart hook.
#
# The status line cannot be shipped by a plugin: Claude Code only reads
# `statusLine` from the user's settings.json, and ${CLAUDE_PLUGIN_ROOT}
# does NOT resolve inside a statusLine command (only in hook/MCP/LSP
# commands). So a plugin user enables the status line once with
# `install.sh --statusline-only`, which copies the script to the stable
# path ~/.claude/statusline.sh and points settings.json there.
#
# Problem this hook solves: that copied script goes stale when the plugin
# updates (the plugin ships a newer statusline.sh, but the user's copy is
# untouched). This hook is the documented refresh pattern — on session
# start it compares the plugin's bundled statusline.sh against the
# installed copy and re-copies when they differ.
#
# It ONLY refreshes a copy that already exists (i.e. the user opted in via
# --statusline-only). It never creates the copy or edits settings.json —
# enabling the status line stays an explicit user action.
#
# Fails open: any error path exits 0, never blocks the session.

trap 'exit 0' ERR

# ${CLAUDE_PLUGIN_ROOT} resolves here (hook runtime). Bundled source:
SRC="${CLAUDE_PLUGIN_ROOT:-}/statusline.sh"
DEST="$HOME/.claude/statusline.sh"

# Only act if the user opted in (DEST exists) and the bundled file is
# present. No copy, no settings edit, otherwise.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0
[ -f "$SRC" ] || exit 0
[ -f "$DEST" ] || exit 0

# Refresh only when the bundled script differs from the installed copy.
if ! cmp -s "$SRC" "$DEST"; then
    cp "$SRC" "$DEST" 2>/dev/null || exit 0
    chmod +x "$DEST" 2>/dev/null || exit 0
    printf '[embo] Refreshed ~/.claude/statusline.sh from the updated plugin.\n'
fi

exit 0
