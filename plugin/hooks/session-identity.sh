#!/usr/bin/env bash
# session-identity.sh — SessionStart hook that records the session id.
#
# Why this exists: embo wants per-session state on disk (a start/wrapup
# record the status line can read). That requires a key that is unique
# per session and stable for its lifetime. Claude Code documents
# `session_id` on both hook stdin and status-line stdin, but does NOT
# document two facts the design depends on:
#
#   1. whether the hook's session_id and the status line's are the same
#      value for the same session;
#   2. whether session_id is preserved across `claude --resume`.
#
# This hook records one line per session start so both can be answered
# from data instead of inference. `/embo:health` reads the file and
# reports what it found.
#
# Input: JSON on stdin with:
#   - session_id:       current session id
#   - source:           startup | resume | clear | compact | fork
#   - hook_event_name:  which event fired
#
# Output: one JSON line appended to .claude/session-identity.jsonl in the
# MAIN working tree (see resolve_claude_dir below).
#
# Never fails the harness. Any error exits 0.

set -u

log_err() { printf '[session-identity] %s\n' "$*" >&2; }

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

if ! SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)"; then
  log_err "unparseable stdin JSON"
  exit 0
fi
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null)"
EVENT_NAME="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"

# Resolve .claude to the MAIN working tree, so a record written from
# inside a git worktree survives that worktree's removal.
# --git-common-dir points at the main tree's .git from any worktree; its
# parent is the main root. Falls back to CWD-relative outside a repo.
resolve_claude_dir() {
  local common main_root
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
    printf '.claude'; return
  }
  [ -n "$common" ] || { printf '.claude'; return; }
  main_root="$(dirname "$common")"
  printf '%s/.claude' "$main_root"
}

OUT_DIR="$(resolve_claude_dir)"
OUT_FILE="$OUT_DIR/session-identity.jsonl"
mkdir -p "$OUT_DIR" 2>/dev/null || {
  log_err "cannot create $OUT_DIR in $(pwd)"
  exit 0
}

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || TS="unknown"

jq -n -c \
  --arg ts "$TS" \
  --arg observer "hook" \
  --arg event "$EVENT_NAME" \
  --arg source "$SOURCE" \
  --arg sid "$SESSION_ID" \
  '{ts: $ts, observer: $observer, event: $event, source: $source, session_id: $sid}' \
  >> "$OUT_FILE" 2>/dev/null || {
  log_err "cannot append to $OUT_FILE"
  exit 0
}

exit 0
