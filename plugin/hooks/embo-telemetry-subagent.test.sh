#!/usr/bin/env bash
# Plain-Bash unit tests for embo-telemetry-subagent.sh and its merge
# into embo-telemetry-write.sh.
# Run: bash plugin/hooks/embo-telemetry-subagent.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUB_SCRIPT="$HERE/embo-telemetry-subagent.sh"
WRITE_SCRIPT="$HERE/embo-telemetry-write.sh"

PASS=0
FAIL=0
CURRENT_TEST=""

assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s / %s\n  expected: [%s]\n  actual:   [%s]\n' \
      "$CURRENT_TEST" "$desc" "$exp" "$act"
  fi
}

assert_true() {
  local desc="$1"; shift
  if "$@"; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); printf 'FAIL: %s / %s\n' "$CURRENT_TEST" "$desc"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

tx_tool_use() {
  jq -c -n --arg n "$2" \
    '{message:{role:"assistant",content:[
      {type:"tool_use",name:$n,input:{}}]}}' >> "$1"
}

new_project() {
  local d; d="$(mktemp -d "$TMP/proj.XXXXXX")"
  mkdir -p "$d/tmp"
  ( cd "$d" && git init -q 2>/dev/null )
  printf '%s' "$d"
}

run_subagent() {
  local proj="$1" transcript="$2" sid="$3"
  local input
  input="$(jq -c -n --arg t "$transcript" --arg s "$sid" \
    '{agent_transcript_path:$t,session_id:$s,hook_event_name:"SubagentStop"}')"
  ( cd "$proj" && printf '%s' "$input" | bash "$SUB_SCRIPT" )
}

run_writer() {
  local proj="$1" transcript="$2" sid="$3"
  local input
  input="$(jq -c -n --arg t "$transcript" --arg s "$sid" \
    '{transcript_path:$t,session_id:$s,hook_event_name:"Stop"}')"
  ( cd "$proj" && HOME="$proj/home" TMPDIR="$proj/tmp" \
    printf '%s' "$input" | HOME="$proj/home" TMPDIR="$proj/tmp" bash "$WRITE_SCRIPT" )
}

sub_path() { printf '%s/.claude/embo_state/telemetry/%s.sub' "$1" "$2"; }
record_path() { printf '%s/.claude/embo_state/telemetry/%s.jsonl' "$1" "$2"; }

# ---- Tests ----------------------------------------------------------

test_subagent_writes_sidecar() {
  CURRENT_TEST="sidecar_written"
  local p; p="$(new_project)"
  local at="$p/agent.jsonl"; : > "$at"
  tx_tool_use "$at" Grep
  tx_tool_use "$at" Grep
  tx_tool_use "$at" Read
  run_subagent "$p" "$at" "s1"
  local sf; sf="$(sub_path "$p" s1)"
  assert_true "sidecar exists" test -f "$sf"
  assert_eq "Grep count line" "Grep 2" "$(grep '^Grep ' "$sf")"
  assert_eq "Read count line" "Read 1" "$(grep '^Read ' "$sf")"
}

test_subagent_empty_transcript_noop() {
  CURRENT_TEST="empty_noop"
  local p; p="$(new_project)"
  run_subagent "$p" "$p/nope.jsonl" "s1"
  local rc=$?
  assert_eq "exits 0" "0" "$rc"
  assert_true "no sidecar" test ! -f "$(sub_path "$p" s1)"
}

test_writer_merges_sidecar() {
  CURRENT_TEST="merge"
  local p; p="$(new_project)"
  # Subagent made 2 Grep + 1 Read.
  local at="$p/agent.jsonl"; : > "$at"
  tx_tool_use "$at" Grep; tx_tool_use "$at" Grep; tx_tool_use "$at" Read
  run_subagent "$p" "$at" "s1"
  # Parent made 1 Bash + 1 Read + 1 Agent.
  local t="$p/t.jsonl"; : > "$t"
  tx_tool_use "$t" Bash; tx_tool_use "$t" Read; tx_tool_use "$t" Agent
  run_writer "$p" "$t" "s1"
  local rec; rec="$(record_path "$p" s1)"
  # Breakdown should sum parent + subagent: Read 1+1=2, Grep 2, Bash 1, Agent 1
  assert_eq "Read merged" "2" "$(jq -r '.tool_breakdown.Read' "$rec")"
  assert_eq "Grep from subagent" "2" "$(jq -r '.tool_breakdown.Grep' "$rec")"
  assert_eq "Bash parent" "1" "$(jq -r '.tool_breakdown.Bash' "$rec")"
}

# ---- Runner ---------------------------------------------------------

run_all() {
  test_subagent_writes_sidecar
  test_subagent_empty_transcript_noop
  test_writer_merges_sidecar
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
