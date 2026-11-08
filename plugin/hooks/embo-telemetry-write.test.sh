#!/usr/bin/env bash
# Plain-Bash unit tests for embo-telemetry-write.sh.
# Run: bash plugin/hooks/embo-telemetry-write.test.sh
# Exits non-zero if any assertion fails.
#
# Operates ONLY on synthetic temp transcripts and isolated temp project
# dirs — never a real Claude Code transcript or project.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/embo-telemetry-write.sh"

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

assert_true() {
  local desc="$1"; shift
  if "$@"; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); printf 'FAIL: %s / %s\n' "$CURRENT_TEST" "$desc"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Fixture writers (confirmed transcript shapes) ------------------

tx_tool_use_ts() {
  local out="$1" name="$2" command="$3" ts="$4"
  jq -c -n --arg n "$name" --arg c "$command" --arg ts "$ts" \
    '{message:{role:"assistant",content:[
      {type:"tool_use",name:$n,input:{command:$c}}]},timestamp:$ts}' >> "$out"
}

tx_tool_use() {
  local out="$1" name="$2" command="${3:-}"
  jq -c -n --arg n "$name" --arg c "$command" \
    '{message:{role:"assistant",content:[
      {type:"tool_use",name:$n,input:{command:$c}}]}}' >> "$out"
}

tx_tool_result() {
  local out="$1" kind="$2" iserr
  if [ "$kind" = error ]; then iserr=true; else iserr=false; fi
  jq -c -n --argjson e "$iserr" \
    '{message:{role:"user",content:[
      {type:"tool_result",is_error:$e,content:"x"}]}}' >> "$out"
}

# Build hook stdin.
hook_input() {
  jq -c -n --arg t "$1" --arg s "$2" \
    '{transcript_path:$t,session_id:$s,hook_event_name:"Stop"}'
}

# Isolated project (fake main tree) + HOME so profile/telemetry paths
# are controlled. Runs the hook from inside the project dir.
run_writer() {
  local proj="$1" transcript="$2" sid="$3" home="$4"
  local input; input="$(hook_input "$transcript" "$sid")"
  (cd "$proj" && HOME="$home" TMPDIR="$proj/tmp" \
    printf '%s' "$input" | HOME="$home" TMPDIR="$proj/tmp" bash "$SCRIPT")
}

new_project() {
  local d; d="$(mktemp -d "$TMP/proj.XXXXXX")"
  mkdir -p "$d/tmp"
  ( cd "$d" && git init -q 2>/dev/null )
  printf '%s' "$d"
}

record_path() { printf '%s/.claude/embo_state/telemetry/%s.jsonl' "$1" "$2"; }

# ---- Tests ----------------------------------------------------------

test_writes_record_with_schema() {
  CURRENT_TEST="writes_record"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"
  tx_tool_use "$t" Bash "ls"
  tx_tool_use "$t" Read
  run_writer "$p" "$t" "s1" "$p/home"
  local rec; rec="$(record_path "$p" s1)"
  assert_true "record file exists" test -f "$rec"
  assert_eq "schema is 1" "1" "$(jq -r '.schema' "$rec")"
  assert_eq "tool_call_count" "2" "$(jq -r '.tool_call_count' "$rec")"
  assert_eq "status ok" "ok" "$(jq -r '.status' "$rec")"
}

test_tool_breakdown() {
  CURRENT_TEST="tool_breakdown"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"
  tx_tool_use "$t" Bash "ls"
  tx_tool_use "$t" Bash "pwd"
  tx_tool_use "$t" Read
  run_writer "$p" "$t" "s1" "$p/home"
  local rec; rec="$(record_path "$p" s1)"
  assert_eq "Bash count" "2" "$(jq -r '.tool_breakdown.Bash' "$rec")"
  assert_eq "Read count" "1" "$(jq -r '.tool_breakdown.Read' "$rec")"
}

test_failed_calls_separate() {
  CURRENT_TEST="failed_calls"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"
  tx_tool_use "$t" Bash "false"
  tx_tool_result "$t" error
  tx_tool_use "$t" Bash "true"
  tx_tool_result "$t" success
  run_writer "$p" "$t" "s1" "$p/home"
  local rec; rec="$(record_path "$p" s1)"
  assert_eq "tool_call_count excludes results" "2" "$(jq -r '.tool_call_count' "$rec")"
  assert_eq "failed_calls counted" "1" "$(jq -r '.failed_calls' "$rec")"
}

test_commands_extracted() {
  CURRENT_TEST="commands"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"
  tx_tool_use "$t" Bash "echo /embo:start"
  tx_tool_use "$t" Bash "embo-profile show"
  tx_tool_use "$t" Bash "ls"
  run_writer "$p" "$t" "s1" "$p/home"
  local rec; rec="$(record_path "$p" s1)"
  assert_eq "commands" "/embo:start embo-profile" \
    "$(jq -r '.commands | join(" ")' "$rec")"
}

test_profile_default_when_absent() {
  CURRENT_TEST="profile_default"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"; tx_tool_use "$t" Read
  mkdir -p "$p/home/.claude"   # no active-profile.yaml
  run_writer "$p" "$t" "s1" "$p/home"
  assert_eq "profile default" "default" "$(jq -r '.profile' "$(record_path "$p" s1)")"
}

test_profile_from_file() {
  CURRENT_TEST="profile_from_file"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"; tx_tool_use "$t" Read
  mkdir -p "$p/home/.claude"
  printf 'name: fast\n' > "$p/home/.claude/active-profile.yaml"
  run_writer "$p" "$t" "s1" "$p/home"
  assert_eq "profile fast" "fast" "$(jq -r '.profile' "$(record_path "$p" s1)")"
}

test_duration_from_transcript() {
  CURRENT_TEST="duration_transcript"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"
  tx_tool_use_ts "$t" Bash "a" "2026-09-09T00:00:00Z"
  tx_tool_use_ts "$t" Bash "b" "2026-09-09T00:00:30Z"
  run_writer "$p" "$t" "s1" "$p/home"
  local rec; rec="$(record_path "$p" s1)"
  assert_eq "duration 30s" "30" "$(jq -r '.duration_s' "$rec")"
  assert_eq "duration_source" "transcript" "$(jq -r '.duration_source' "$rec")"
}

test_duration_null_when_none() {
  CURRENT_TEST="duration_null"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"; tx_tool_use "$t" Read
  run_writer "$p" "$t" "s1" "$p/home"
  local rec; rec="$(record_path "$p" s1)"
  assert_eq "duration null" "null" "$(jq -r '.duration_s' "$rec")"
}

test_overwrite_idempotent() {
  CURRENT_TEST="overwrite"
  local p; p="$(new_project)"
  local t="$p/t.jsonl"; : > "$t"; tx_tool_use "$t" Read
  run_writer "$p" "$t" "s1" "$p/home"
  run_writer "$p" "$t" "s1" "$p/home"
  local dir="$p/.claude/embo_state/telemetry"
  assert_eq "exactly one record file" "1" \
    "$(find "$dir" -name 's1.jsonl' | wc -l | tr -d ' ')"
  assert_eq "file has one line" "1" "$(wc -l < "$(record_path "$p" s1)" | tr -d ' ')"
}

test_transcript_unavailable() {
  CURRENT_TEST="transcript_unavailable"
  local p; p="$(new_project)"
  run_writer "$p" "$p/nonexistent.jsonl" "s1" "$p/home"
  local rec; rec="$(record_path "$p" s1)"
  assert_true "record still written" test -f "$rec"
  assert_eq "status unavailable" "transcript_unavailable" "$(jq -r '.status' "$rec")"
  assert_eq "tool_call_count null" "null" "$(jq -r '.tool_call_count' "$rec")"
}

test_retention_sweep() {
  CURRENT_TEST="retention_sweep"
  local p; p="$(new_project)"
  local dir="$p/.claude/embo_state/telemetry"
  mkdir -p "$dir"
  # Old records (mtime 100 days ago) and a recent one.
  printf '{}' > "$dir/old1.jsonl"
  printf 'Bash 1' > "$dir/old1.sub"
  printf '{}' > "$dir/recent.jsonl"
  touch -t "$(date -u -v-100d +%Y%m%d0000 2>/dev/null || date -u -d '100 days ago' +%Y%m%d0000)" \
    "$dir/old1.jsonl" "$dir/old1.sub" 2>/dev/null
  # Trigger the writer (its top-of-run sweep should delete the old files).
  local t="$p/t.jsonl"; : > "$t"; tx_tool_use "$t" Read
  run_writer "$p" "$t" "s1" "$p/home"
  assert_true "old .jsonl swept" test ! -f "$dir/old1.jsonl"
  assert_true "old .sub swept" test ! -f "$dir/old1.sub"
  assert_true "recent kept" test -f "$dir/recent.jsonl"
}

test_worktree_resolves_to_main() {
  CURRENT_TEST="worktree_main_tree"
  local p; p="$(new_project)"
  ( cd "$p" && git config user.email t@t.t && git config user.name t \
    && git commit -q --allow-empty -m init 2>/dev/null )
  local wt="$p/wt"
  ( cd "$p" && git worktree add -q "$wt" -b wtbranch 2>/dev/null )
  if [ ! -d "$wt" ]; then
    printf 'SKIP: %s / worktree add unavailable\n' "$CURRENT_TEST"
    return
  fi
  mkdir -p "$wt/tmp"
  local t="$wt/t.jsonl"; : > "$t"; tx_tool_use "$t" Read
  local input; input="$(hook_input "$t" "swt")"
  ( cd "$wt" && HOME="$p/home" TMPDIR="$wt/tmp" \
    printf '%s' "$input" | HOME="$p/home" TMPDIR="$wt/tmp" bash "$SCRIPT" )
  # Record must land in the MAIN tree, not the worktree.
  assert_true "record in main tree" test -f "$(record_path "$p" swt)"
  assert_true "record NOT in worktree" test ! -f "$wt/.claude/embo_state/telemetry/swt.jsonl"
}

# ---- Runner ---------------------------------------------------------

run_all() {
  test_writes_record_with_schema
  test_tool_breakdown
  test_failed_calls_separate
  test_commands_extracted
  test_profile_default_when_absent
  test_profile_from_file
  test_duration_from_transcript
  test_duration_null_when_none
  test_overwrite_idempotent
  test_transcript_unavailable
  test_retention_sweep
  test_worktree_resolves_to_main
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
