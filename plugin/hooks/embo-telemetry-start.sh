#!/usr/bin/env bash
# embo-telemetry-start.sh - SessionStart hook that records a Unix epoch
# start time for the current session, so the Stop writer
# (embo-telemetry-write.sh) can compute session duration as a fallback
# when transcript timestamps are unavailable.
#
# Wired via plugin/hooks/hooks.json to SessionStart (second entry,
# beside statusline-refresh.sh).
#
# Input: JSON on stdin with fields:
#   - session_id: current session id
#
# Output: writes a single Unix epoch integer to
#   $TMPDIR/embo-session-<session_id>.start
#
# Never fails the harness. Any error exits 0 after logging to stderr.

set -u

log_err() { printf '[embo-telemetry-start] %s\n' "$*" >&2; }

read_session_id() {
  local input="$1"
  printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null
}

main() {
  local input session_id start_dir out_file
  input="$(cat 2>/dev/null || true)"
  [ -z "$input" ] && exit 0

  session_id="$(read_session_id "$input")"
  [ -z "$session_id" ] && exit 0

  start_dir="${TMPDIR:-/tmp}"
  out_file="${start_dir%/}/embo-session-${session_id}.start"

  if ! date -u +%s > "$out_file" 2>/dev/null; then
    log_err "cannot write start file $out_file"
    exit 0
  fi
  exit 0
}

main
