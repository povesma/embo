#!/usr/bin/env bash
# session-identity.sh — SessionStart hook that records the per-session
# state-file baseline.
#
# Why this exists: embo keeps per-session state on disk (a start/wrapup
# record the status line reads and the /embo:start fast path uses). The
# state file is keyed by `session_id`, which Claude Code provides on hook
# stdin. This hook writes the baseline (`phase: new`) from the real stdin
# id, so the id can never be empty or unsubstituted and the model cannot
# forget the write. On a re-fire (resume/compact) the writer preserves the
# existing phase, so a session that has already run /embo:start is not
# reset to `new`.
#
# This baseline write REPLACES the old session-identity.jsonl append; the
# diagnostic log has served its purpose.
#
# Input: JSON on stdin with:
#   - session_id:       current session id
#   - source:           startup | resume | clear | compact | fork
#
# Output: none to stdout (a SessionStart hook must not print to the
# harness channel). Never fails the harness: any error exits 0.

set -u

log_err() { printf '[session-identity] %s\n' "$*" >&2; }

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)" || {
  log_err "unparseable stdin JSON"
  exit 0
}
[ -n "$SESSION_ID" ] || exit 0
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null)"

# Resolve this script's directory (following symlinks) so the writer is
# found wherever the plugin is installed.
src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
hook_dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
STATE_BIN="$hook_dir/../bin/embo-session-state"

[ -x "$STATE_BIN" ] || { log_err "writer not found at $STATE_BIN"; exit 0; }

bash "$STATE_BIN" baseline "$SESSION_ID" "$SOURCE" >/dev/null 2>&1 || {
  log_err "baseline write failed for $SESSION_ID"
  exit 0
}

exit 0
