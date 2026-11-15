#!/usr/bin/env bash
# Plain-Bash unit tests for embo-telemetry-start.sh.
# Run: bash plugin/hooks/embo-telemetry-start.test.sh
# Exits non-zero if any assertion fails.
#
# The SessionStart hook records a Unix epoch start time to
# $TMPDIR/embo-session-<session_id>.start so the Stop writer can
# compute session duration as a fallback. Integer epoch avoids all
# cross-platform ISO date parsing.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/embo-telemetry-start.sh"

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
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s / %s\n' "$CURRENT_TEST" "$desc"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Each test uses an isolated TMPDIR so start files never collide.
run_hook() {
  local sid="$1" tmpdir="$2"
  local input
  input="$(jq -c -n --arg s "$sid" '{session_id: $s, hook_event_name: "SessionStart"}')"
  TMPDIR="$tmpdir" printf '%s' "$input" | TMPDIR="$tmpdir" bash "$SCRIPT"
}

# ---- Tests ----------------------------------------------------------

test_writes_epoch_for_session() {
  CURRENT_TEST="writes_epoch"
  local d; d="$(mktemp -d "$TMP/t.XXXXXX")"
  run_hook "sess-abc" "$d"
  local f="$d/embo-session-sess-abc.start"
  assert_true "start file exists" test -f "$f"
  local val; val="$(cat "$f" 2>/dev/null)"
  # An epoch integer: all digits, plausibly 10 digits in this era.
  assert_true "content is an integer" test -n "$val"
  if printf '%s' "$val" | grep -qE '^[0-9]+$'; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s / content is digits, got [%s]\n' "$CURRENT_TEST" "$val"
  fi
}

test_no_session_id_writes_nothing() {
  CURRENT_TEST="no_session_id"
  local d; d="$(mktemp -d "$TMP/t.XXXXXX")"
  local input
  input="$(jq -c -n '{hook_event_name: "SessionStart"}')"
  TMPDIR="$d" printf '%s' "$input" | TMPDIR="$d" bash "$SCRIPT"
  local rc=$?
  assert_eq "exits 0" "0" "$rc"
  # No .start file should have been created.
  local count; count="$(find "$d" -name '*.start' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "no start file written" "0" "$count"
}

test_empty_stdin_noop() {
  CURRENT_TEST="empty_stdin"
  local d; d="$(mktemp -d "$TMP/t.XXXXXX")"
  TMPDIR="$d" printf '' | TMPDIR="$d" bash "$SCRIPT"
  local rc=$?
  assert_eq "exits 0 on empty stdin" "0" "$rc"
}

# ---- Runner ---------------------------------------------------------

run_all() {
  test_writes_epoch_for_session
  test_no_session_id_writes_nothing
  test_empty_stdin_noop
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
