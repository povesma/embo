#!/usr/bin/env bash
# Plain-Bash unit tests for embo-usage.
# Run: bash plugin/bin/embo-usage.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/embo-usage"

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

assert_contains() {
  local desc="$1" hay="$2" needle="$3"
  case "$hay" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1))
       printf 'FAIL: %s / %s\n  missing: [%s]\n  in: [%s]\n' \
         "$CURRENT_TEST" "$desc" "$needle" "$hay" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A fake main tree (git repo) with a telemetry dir; embo-usage resolves
# .claude via git, so run it from inside this repo.
new_project() {
  local d; d="$(mktemp -d "$TMP/proj.XXXXXX")"
  ( cd "$d" && git init -q 2>/dev/null )
  mkdir -p "$d/.claude/embo_state/telemetry"
  printf '%s' "$d"
}

# Write a telemetry record file.
put_record() {
  local dir="$1" sid="$2" ts="$3" profile="$4" tools="$5"
  jq -c -n --arg s "$sid" --arg ts "$ts" --arg p "$profile" \
    --argjson tc "$tools" \
    '{schema:1, ts:$ts, session_id:$s, profile:$p, duration_s:120,
      duration_source:"transcript", tool_call_count:$tc, failed_calls:0,
      tool_breakdown:{Bash:$tc}, commands:["start"], status:"ok"}' \
    > "$dir/.claude/embo_state/telemetry/${sid}.jsonl"
}

run_usage() { ( cd "$1" && shift && python3 "$BIN" "$@" ); }

# ---- Tests ----------------------------------------------------------

test_table_lists_sessions() {
  CURRENT_TEST="table"
  local p; p="$(new_project)"
  put_record "$p" aaaa1111 "2026-09-01T10:00:00Z" default 10
  put_record "$p" bbbb2222 "2026-09-02T10:00:00Z" fast 5
  local out; out="$(run_usage "$p")"
  assert_contains "shows default row" "$out" "default"
  assert_contains "shows fast row" "$out" "fast"
  assert_contains "shows session prefix" "$out" "aaaa1111"
}

test_last_limits() {
  CURRENT_TEST="last"
  local p; p="$(new_project)"
  put_record "$p" aaaa1111 "2026-09-01T10:00:00Z" default 10
  put_record "$p" bbbb2222 "2026-09-02T10:00:00Z" fast 5
  local out; out="$(run_usage "$p" --last 1)"
  assert_contains "keeps newest" "$out" "bbbb2222"
  case "$out" in
    *aaaa1111*) FAIL=$((FAIL + 1)); printf 'FAIL: last / oldest should be dropped\n' ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

test_profile_filter() {
  CURRENT_TEST="profile_filter"
  local p; p="$(new_project)"
  put_record "$p" aaaa1111 "2026-09-01T10:00:00Z" default 10
  put_record "$p" bbbb2222 "2026-09-02T10:00:00Z" fast 5
  local out; out="$(run_usage "$p" --profile fast)"
  assert_contains "keeps fast" "$out" "bbbb2222"
  case "$out" in
    *aaaa1111*) FAIL=$((FAIL + 1)); printf 'FAIL: profile / default should be filtered\n' ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

test_stats() {
  CURRENT_TEST="stats"
  local p; p="$(new_project)"
  put_record "$p" aaaa1111 "2026-09-01T10:00:00Z" default 10
  put_record "$p" bbbb2222 "2026-09-02T10:00:00Z" fast 20
  local out; out="$(run_usage "$p" --stats)"
  assert_contains "session count" "$out" "sessions:            2"
  assert_contains "mean" "$out" "mean tool calls:     15"
}

test_json_valid() {
  CURRENT_TEST="json"
  local p; p="$(new_project)"
  put_record "$p" aaaa1111 "2026-09-01T10:00:00Z" default 10
  local out; out="$(run_usage "$p" --json)"
  assert_eq "valid json sessions=1" "1" "$(printf '%s' "$out" | jq -r '.sessions')"
  assert_eq "median present" "10" "$(printf '%s' "$out" | jq -r '.median_tool_calls')"
}

test_empty_dir() {
  CURRENT_TEST="empty"
  local p; p="$(new_project)"
  local out; out="$(run_usage "$p")"
  assert_contains "empty message" "$out" "No telemetry records"
}

# ---- Runner ---------------------------------------------------------

run_all() {
  test_table_lists_sessions
  test_last_limits
  test_profile_filter
  test_stats
  test_json_valid
  test_empty_dir
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
