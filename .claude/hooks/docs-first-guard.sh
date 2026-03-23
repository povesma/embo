#!/usr/bin/env bash
set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)

PERM_MODE=$(echo "$INPUT" | jq -r '.permission_mode // "default"') || true

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0
[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  *.md|*.json|*.yaml|*.yml|*.toml|*.txt) exit 0 ;;
esac
case "$FILE_PATH" in
  */tasks/*|*/.claude/*) exit 0 ;;
esac

MARKER="$HOME/.claude/rlm_state/.impl-active"
if [ -f "$MARKER" ]; then
  STALE=$(find "$MARKER" -mmin +120 2>/dev/null)
  if [ -z "$STALE" ]; then
    exit 0
  else
    rm -f "$MARKER"
  fi
fi

WARN_MSG="⚠️ No /impl session active — this code edit is undocumented.

Consider:
  • /rlm-mem:develop:impl — start documented implementation
  • /rlm-mem:plan:prd — create docs first
  • Allow this edit if it is a quick fix

(docs-first-guard hook — see README §Hooks)"

case "$PERM_MODE" in
  acceptEdits|dontAsk|bypassPermissions)
    jq -n --arg msg "$WARN_MSG" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow"
      },
      systemMessage: $msg
    }'
    exit 0
    ;;
esac

jq -n --arg reason "$WARN_MSG" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $reason
  }
}'
