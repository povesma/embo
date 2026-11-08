#!/usr/bin/env bash
# embo-telemetry-write.sh - Stop hook that writes one per-session
# telemetry record capturing tool-call counts, a per-tool breakdown,
# failed-call count, embo commands used, active profile, and session
# duration.
#
# Primary writer. Fires on Stop (per turn, 600s budget). Each turn it
# OVERWRITES .claude/embo_state/telemetry/<session_id>.jsonl, so the
# final turn's record is the complete one and re-runs are inherently
# idempotent (no scan, no dedup logic).
#
# Wired via plugin/hooks/hooks.json to Stop (second entry, beside
# capture-correction.sh).
#
# Input: JSON on stdin with fields:
#   - transcript_path: path to the session transcript (JSONL)
#   - session_id:      current session id
#
# Never fails the harness. Any error exits 0 after logging to stderr.

set -u

RETENTION_DAYS=90

log_err() { printf '[embo-telemetry-write] %s\n' "$*" >&2; }

# Resolve .claude to the MAIN working tree so a record written from
# inside a git worktree lands in the shared location, not the
# worktree's own .claude/ (which vanishes when the worktree is removed).
resolve_claude_dir() {
  local common main_root
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
    printf '.claude'; return
  }
  [ -n "$common" ] || { printf '.claude'; return; }
  main_root="$(dirname "$common")"
  printf '%s/.claude' "$main_root"
}

# Read the active profile name WITHOUT yq or embo-profile (both would
# add a dependency that violates the stdlib-only constraint). Reads the
# `name:` field from ~/.claude/active-profile.yaml.
#   present   -> its name
#   absent    -> "default"
#   unreadable -> "unknown"
read_profile() {
  local pf="${HOME}/.claude/active-profile.yaml"
  if [ ! -f "$pf" ]; then
    printf 'default'; return
  fi
  local name
  name="$(grep -E '^[[:space:]]*name:' "$pf" 2>/dev/null | head -1 \
    | sed -E 's/^[[:space:]]*name:[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//')"
  if [ -z "$name" ]; then
    printf 'unknown'; return
  fi
  printf '%s' "$name"
}

count_tool_calls() {
  jq -c 'select(.message.role == "assistant")
         | .message.content[]? | select(.type == "tool_use")' "$1" 2>/dev/null \
    | wc -l | tr -d ' '
}

count_failed_calls() {
  jq -c 'select(.message.role == "user")
         | .message.content[]? | select(.type == "tool_result" and .is_error == true)' \
    "$1" 2>/dev/null | wc -l | tr -d ' '
}

# Emit a JSON object {tool_name: count} from parent transcript + any
# subagent sidecar counts.
tool_breakdown_json() {
  local transcript="$1" sub_file="$2"
  {
    jq -r 'select(.message.role == "assistant")
           | .message.content[]? | select(.type == "tool_use") | .name' \
      "$transcript" 2>/dev/null
    # Sidecar holds one "tool count" pair per line; expand to `tool`
    # repeated `count` times so uniq -c below sums them together.
    if [ -f "$sub_file" ]; then
      local tool count i
      while read -r tool count; do
        [ -z "$tool" ] && continue
        i=0
        while [ "$i" -lt "${count:-0}" ]; do printf '%s\n' "$tool"; i=$((i + 1)); done
      done < "$sub_file"
    fi
  } | sort | uniq -c | jq -R -s '
    split("\n") | map(select(length > 0))
    | map(sub("^ +"; "") | split(" "; "") | {(.[1]): (.[0] | tonumber)})
    | add // {}'
}

# embo command names from Bash tool calls (slash form and bin form).
commands_json() {
  jq -r 'select(.message.role == "assistant")
         | .message.content[]? | select(.type == "tool_use" and .name == "Bash")
         | .input.command' "$1" 2>/dev/null \
    | grep -oE '/embo:[a-z:]+|embo-[a-z-]+' | sort -u \
    | jq -R -s 'split("\n") | map(select(length > 0))'
}

# python3 epoch-from-ISO helper; empty on failure.
iso_to_epoch() {
  python3 -c 'import sys,datetime
try:
    s=sys.argv[1].replace("Z","+00:00")
    print(int(datetime.datetime.fromisoformat(s).timestamp()))
except Exception:
    pass' "$1" 2>/dev/null
}

# Duration from transcript first/last timestamps (primary), else start
# file (fallback), else empty. Sets DURATION and DURATION_SOURCE.
compute_duration() {
  local transcript="$1" session_id="$2"
  DURATION=""
  DURATION_SOURCE="null"
  local first last fe le
  first="$(jq -r 'select(.timestamp) | .timestamp' "$transcript" 2>/dev/null | head -1)"
  last="$(jq -r 'select(.timestamp) | .timestamp' "$transcript" 2>/dev/null | tail -1)"
  if [ -n "$first" ] && [ -n "$last" ]; then
    fe="$(iso_to_epoch "$first")"
    le="$(iso_to_epoch "$last")"
    if [ -n "$fe" ] && [ -n "$le" ]; then
      DURATION=$((le - fe))
      DURATION_SOURCE="transcript"
      return
    fi
  fi
  local start_file="${TMPDIR:-/tmp}"
  start_file="${start_file%/}/embo-session-${session_id}.start"
  if [ -f "$start_file" ]; then
    local start_epoch now
    start_epoch="$(cat "$start_file" 2>/dev/null)"
    now="$(date -u +%s 2>/dev/null)"
    if printf '%s' "$start_epoch" | grep -qE '^[0-9]+$'; then
      DURATION=$((now - start_epoch))
      DURATION_SOURCE="start_file"
    fi
  fi
}

sweep_old_records() {
  find "$1" -type f \( -name '*.jsonl' -o -name '*.sub' \) \
    -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true
}

main() {
  local input transcript session_id claude_dir tel_dir out_file sub_file
  input="$(cat 2>/dev/null || true)"
  [ -z "$input" ] && exit 0

  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)" || exit 0
  session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"

  claude_dir="$(resolve_claude_dir)"
  tel_dir="${claude_dir}/embo_state/telemetry"
  mkdir -p "$tel_dir" 2>/dev/null || { log_err "cannot create $tel_dir"; exit 0; }
  out_file="${tel_dir}/${session_id}.jsonl"
  sub_file="${tel_dir}/${session_id}.sub"

  sweep_old_records "$tel_dir"

  local now_iso profile
  now_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  profile="$(read_profile)"

  # Transcript missing/empty: write a minimal record and stop.
  if [ -z "$transcript" ] || [ ! -s "$transcript" ]; then
    jq -c -n \
      --arg ts "$now_iso" --arg sid "$session_id" --arg prof "$profile" \
      '{schema: 1, ts: $ts, session_id: $sid, profile: $prof,
        duration_s: null, duration_source: "null",
        tool_call_count: null, failed_calls: 0,
        tool_breakdown: {}, commands: [],
        status: "transcript_unavailable"}' > "$out_file" 2>/dev/null
    exit 0
  fi

  local tool_count failed breakdown commands
  tool_count="$(count_tool_calls "$transcript")"
  failed="$(count_failed_calls "$transcript")"
  breakdown="$(tool_breakdown_json "$transcript" "$sub_file")"
  commands="$(commands_json "$transcript")"

  compute_duration "$transcript" "$session_id"
  local dur_json
  if [ -n "$DURATION" ]; then dur_json="$DURATION"; else dur_json="null"; fi

  jq -c -n \
    --arg ts "$now_iso" --arg sid "$session_id" --arg prof "$profile" \
    --argjson dur "$dur_json" --arg dsrc "$DURATION_SOURCE" \
    --argjson tc "${tool_count:-0}" --argjson fc "${failed:-0}" \
    --argjson bd "$breakdown" --argjson cmds "$commands" \
    '{schema: 1, ts: $ts, session_id: $sid, profile: $prof,
      duration_s: $dur, duration_source: $dsrc,
      tool_call_count: $tc, failed_calls: $fc,
      tool_breakdown: $bd, commands: $cmds, status: "ok"}' \
    > "$out_file" 2>/dev/null || { log_err "cannot write $out_file"; exit 0; }
  exit 0
}

main
