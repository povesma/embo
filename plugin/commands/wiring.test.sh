#!/usr/bin/env bash
# Plain-Bash assertions that the command bodies carry their
# session-state wiring (no framework).
# Run: bash plugin/commands/wiring.test.sh
# Exits non-zero if any assertion fails.
#
# These are static checks on the shipped command Markdown — they do not
# run the commands. Live behaviour is covered by the manual-run-claude
# subtasks in the task list.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" file="$2" needle="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  file:   %s\n  needle: [%s]\n' "$desc" "$file" "$needle"
  fi
}

assert_absent() {
  local desc="$1" file="$2" needle="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  file:   %s\n  found:  [%s]\n' "$desc" "$file" "$needle"
  else
    PASS=$((PASS + 1))
  fi
}

# ---- 3.1 start.md / wrapup.md wrapper calls ----

test_start_calls_start() {
  assert_contains "start.md calls embo-session-state start with the session id" \
    "$PLUGIN/commands/start.md" 'embo-session-state start ${CLAUDE_SESSION_ID}'
}

test_wrapup_calls_wrapup() {
  assert_contains "wrapup.md calls embo-session-state wrapup with the session id" \
    "$PLUGIN/commands/wrapup.md" 'embo-session-state wrapup ${CLAUDE_SESSION_ID}'
}

test_health_reads_state_file() {
  assert_contains "health.md reads the session-state file via the path form" \
    "$PLUGIN/commands/health.md" 'embo-session-state path ${CLAUDE_SESSION_ID}'
}

# ---- 5.2 marker string removed from plugin/ (grep check) ----

test_marker_gone_from_plugin() {
  # The marker string must not survive in any shipped command/hook/script.
  # Exclude this test file itself, which names the string to check for it.
  local hits
  hits="$(grep -rlF --exclude='*.test.sh' 'embo-start: complete' "$PLUGIN" 2>/dev/null \
          | wc -l | tr -d ' ')"
  if [ "$hits" = "0" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: the embo-start marker still appears in plugin/ (%s file[s])\n' "$hits"
    grep -rlF --exclude='*.test.sh' 'embo-start: complete' "$PLUGIN" 2>/dev/null
  fi
}

test_start_calls_start
test_wrapup_calls_wrapup
test_health_reads_state_file
test_marker_gone_from_plugin

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
