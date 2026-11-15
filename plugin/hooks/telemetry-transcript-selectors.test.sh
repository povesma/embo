#!/usr/bin/env bash
# Plain-Bash probe tests for the telemetry transcript jq selectors.
# Run: bash plugin/hooks/telemetry-transcript-selectors.test.sh
# Exits non-zero if any assertion fails.
#
# Purpose (task 065, story 1.0): the telemetry hooks parse a Claude
# Code session transcript to count tool calls, build a per-tool
# breakdown, count failed calls, and extract embo command names. The
# existing capture-correction fixtures contain only `text` content
# blocks, so the `tool_use` / `tool_result` parse paths were never
# exercised. This file pins the confirmed transcript shapes as
# synthetic fixtures and proves the four selectors return the expected
# values BEFORE any hook is built against them.
#
# Confirmed shapes (verified against a real transcript 2026-09-09):
#   assistant tool call:
#     {"message":{"role":"assistant","content":[
#        {"type":"tool_use","name":"Bash","input":{"command":"..."}}]}}
#   user tool result (failure):
#     {"message":{"role":"user","content":[
#        {"type":"tool_result","is_error":true,"content":"..."}]}}
#   user tool result (success): same, is_error absent or false.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
CURRENT_TEST=""

assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s / %s\n  expected: [%s]\n  actual:   [%s]\n' \
      "$CURRENT_TEST" "$desc" "$exp" "$act"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Fixture writers ------------------------------------------------

# Append one assistant text block.
tx_text() {
  local out="$1" role="$2" text="$3"
  jq -c -n --arg r "$role" --arg t "$text" \
    '{message: {role: $r, content: [{type: "text", text: $t}]}}' >> "$out"
}

# Append one assistant tool_use block.
tx_tool_use() {
  local out="$1" name="$2" command="${3:-}"
  if [ -n "$command" ]; then
    jq -c -n --arg n "$name" --arg c "$command" \
      '{message: {role: "assistant", content: [
        {type: "tool_use", name: $n, input: {command: $c}}]}}' >> "$out"
  else
    jq -c -n --arg n "$name" \
      '{message: {role: "assistant", content: [
        {type: "tool_use", name: $n, input: {}}]}}' >> "$out"
  fi
}

# Append one user tool_result block; second arg "error" sets is_error.
tx_tool_result() {
  local out="$1" kind="$2"
  if [ "$kind" = "error" ]; then
    jq -c -n '{message: {role: "user", content: [
      {type: "tool_result", is_error: true, content: "boom"}]}}' >> "$out"
  else
    jq -c -n '{message: {role: "user", content: [
      {type: "tool_result", is_error: false, content: "ok"}]}}' >> "$out"
  fi
}

# ---- Selectors under test (mirror tech-design parse block) ----------

sel_tool_count() {
  jq -c 'select(.message.role == "assistant")
         | .message.content[]? | select(.type == "tool_use")' "$1" | wc -l | tr -d ' '
}

sel_tool_breakdown() {
  jq -r 'select(.message.role == "assistant")
         | .message.content[]? | select(.type == "tool_use") | .name' "$1" \
    | sort | uniq -c | awk '{print $2":"$1}' | sort | tr '\n' ',' | sed 's/,$//'
}

sel_failed_calls() {
  jq -c 'select(.message.role == "user")
         | .message.content[]? | select(.type == "tool_result" and .is_error == true)' "$1" \
    | wc -l | tr -d ' '
}

sel_commands() {
  jq -r 'select(.message.role == "assistant")
         | .message.content[]? | select(.type == "tool_use" and .name == "Bash")
         | .input.command' "$1" 2>/dev/null \
    | grep -oE '/embo:[a-z:]+|embo-[a-z-]+' | sort -u | tr '\n' ',' | sed 's/,$//'
}

# ---- Tests ----------------------------------------------------------

test_tool_count() {
  CURRENT_TEST="tool_count"
  local f="$TMP/tc.jsonl"; : > "$f"
  tx_text "$f" assistant "hello"
  tx_tool_use "$f" Bash "ls"
  tx_tool_use "$f" Read
  tx_tool_use "$f" Bash "git status"
  tx_tool_result "$f" success
  assert_eq "3 tool_use blocks counted" "3" "$(sel_tool_count "$f")"
}

test_tool_count_ignores_text_only() {
  CURRENT_TEST="tool_count_text_only"
  local f="$TMP/tct.jsonl"; : > "$f"
  tx_text "$f" assistant "no tools here"
  tx_text "$f" user "me neither"
  assert_eq "text-only transcript counts 0" "0" "$(sel_tool_count "$f")"
}

test_tool_breakdown() {
  CURRENT_TEST="tool_breakdown"
  local f="$TMP/tb.jsonl"; : > "$f"
  tx_tool_use "$f" Bash "ls"
  tx_tool_use "$f" Bash "pwd"
  tx_tool_use "$f" Read
  assert_eq "Bash:2 Read:1" "Bash:2,Read:1" "$(sel_tool_breakdown "$f")"
}

test_failed_calls() {
  CURRENT_TEST="failed_calls"
  local f="$TMP/fc.jsonl"; : > "$f"
  tx_tool_use "$f" Bash "false"
  tx_tool_result "$f" error
  tx_tool_use "$f" Bash "true"
  tx_tool_result "$f" success
  tx_tool_result "$f" error
  assert_eq "2 error tool_results" "2" "$(sel_failed_calls "$f")"
}

test_failed_calls_not_in_tool_count() {
  CURRENT_TEST="failed_calls_separate"
  local f="$TMP/fcs.jsonl"; : > "$f"
  tx_tool_use "$f" Bash "false"
  tx_tool_result "$f" error
  # tool_count sees only the tool_use (1), not the error result
  assert_eq "tool_count excludes results" "1" "$(sel_tool_count "$f")"
  assert_eq "failed_calls counts result" "1" "$(sel_failed_calls "$f")"
}

test_commands() {
  CURRENT_TEST="commands"
  local f="$TMP/cmd.jsonl"; : > "$f"
  tx_tool_use "$f" Bash "embo-profile show"
  tx_tool_use "$f" Bash "echo /embo:start hi"
  tx_tool_use "$f" Bash "ls -la"
  tx_tool_use "$f" Read
  assert_eq "embo commands extracted" "/embo:start,embo-profile" "$(sel_commands "$f")"
}

test_commands_empty_when_none() {
  CURRENT_TEST="commands_none"
  local f="$TMP/cmd0.jsonl"; : > "$f"
  tx_tool_use "$f" Bash "ls -la"
  assert_eq "no embo commands -> empty" "" "$(sel_commands "$f")"
}

# ---- Runner ---------------------------------------------------------

run_all() {
  test_tool_count
  test_tool_count_ignores_text_only
  test_tool_breakdown
  test_failed_calls
  test_failed_calls_not_in_tool_count
  test_commands
  test_commands_empty_when_none
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
