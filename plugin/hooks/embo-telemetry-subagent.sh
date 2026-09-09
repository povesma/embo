#!/usr/bin/env bash
# embo-telemetry-subagent.sh - SubagentStop hook that records the tool
# calls a subagent made in its OWN transcript. A flat scan of the parent
# transcript sees only the Agent spawn, not the subagent's calls, so
# without this the per-tool breakdown systematically undercounts (embo
# spawns RLM, test, and examine subagents constantly).
#
# Wired via plugin/hooks/hooks.json to SubagentStop.
#
# Input: JSON on stdin with fields:
#   - agent_transcript_path: path to the subagent's transcript (JSONL)
#   - session_id:            parent session id
#
# Output: appends `<tool> <count>` lines to
#   .claude/embo_state/telemetry/<session_id>.sub
# which the Stop writer folds into tool_breakdown.
#
# Never fails the harness. Any error exits 0 after logging to stderr.

set -u

log_err() { printf '[embo-telemetry-subagent] %s\n' "$*" >&2; }

resolve_claude_dir() {
  local common main_root
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
    printf '.claude'; return
  }
  [ -n "$common" ] || { printf '.claude'; return; }
  main_root="$(dirname "$common")"
  printf '%s/.claude' "$main_root"
}

main() {
  local input transcript session_id claude_dir tel_dir sub_file
  input="$(cat 2>/dev/null || true)"
  [ -z "$input" ] && exit 0

  transcript="$(printf '%s' "$input" | jq -r '.agent_transcript_path // ""' 2>/dev/null)" || exit 0
  session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"

  [ -z "$transcript" ] && exit 0
  [ -s "$transcript" ] || exit 0

  claude_dir="$(resolve_claude_dir)"
  tel_dir="${claude_dir}/embo_state/telemetry"
  mkdir -p "$tel_dir" 2>/dev/null || { log_err "cannot create $tel_dir"; exit 0; }
  sub_file="${tel_dir}/${session_id}.sub"

  jq -r 'select(.message.role == "assistant")
         | .message.content[]? | select(.type == "tool_use") | .name' \
    "$transcript" 2>/dev/null | sort | uniq -c \
    | awk '{print $2, $1}' >> "$sub_file" 2>/dev/null || {
      log_err "cannot append to $sub_file"; exit 0;
    }
  exit 0
}

main
