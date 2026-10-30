#!/usr/bin/env bash
# session-identity.test.sh — fixture tests for session-identity.sh.
#
# Run: bash plugin/hooks/session-identity.test.sh
#
# Each case runs the hook against a temporary git repo so the hook's
# resolve_claude_dir() lands inside the fixture, never in the real tree.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/session-identity.sh"
PASS=0
FAIL=0

report() {
  local ok="$1" name="$2" detail="${3:-}"
  if [ "$ok" = "yes" ]; then
    PASS=$((PASS + 1))
    printf 'ok   %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$name"
    [ -n "$detail" ] && printf '       %s\n' "$detail"
  fi
}

# Make a throwaway git repo and cd into it. Echoes its path.
make_fixture() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q 2>/dev/null
  printf '%s' "$dir"
}

run_hook() {
  printf '%s' "$1" | (cd "$2" && bash "$HOOK")
}

out_file() { printf '%s/.claude/session-identity.jsonl' "$1"; }

test_records_a_startup_session() {
  local dir out
  dir="$(make_fixture)"
  run_hook '{"session_id":"sid-1","source":"startup","hook_event_name":"SessionStart"}' "$dir"
  out="$(out_file "$dir")"
  if [ -f "$out" ] && grep -q '"session_id":"sid-1"' "$out" \
     && grep -q '"source":"startup"' "$out" \
     && grep -q '"observer":"hook"' "$out"; then
    report yes "records a startup session"
  else
    report no "records a startup session" "no matching record in $out"
  fi
  rm -rf "$dir"
}

test_records_a_resume_separately() {
  local dir out lines
  dir="$(make_fixture)"
  run_hook '{"session_id":"sid-2","source":"startup","hook_event_name":"SessionStart"}' "$dir"
  run_hook '{"session_id":"sid-2","source":"resume","hook_event_name":"SessionStart"}' "$dir"
  out="$(out_file "$dir")"
  lines="$(wc -l < "$out" | tr -d ' ')"
  if [ "$lines" = "2" ] && grep -q '"source":"resume"' "$out"; then
    report yes "records a resume as its own line"
  else
    report no "records a resume as its own line" "expected 2 lines, got $lines"
  fi
  rm -rf "$dir"
}

test_empty_stdin_is_a_noop() {
  local dir out
  dir="$(make_fixture)"
  printf '' | (cd "$dir" && bash "$HOOK")
  out="$(out_file "$dir")"
  if [ ! -f "$out" ]; then
    report yes "empty stdin writes nothing"
  else
    report no "empty stdin writes nothing" "$out was created"
  fi
  rm -rf "$dir"
}

test_unparseable_stdin_is_a_noop() {
  local dir rc
  dir="$(make_fixture)"
  printf 'not json at all' | (cd "$dir" && bash "$HOOK")
  rc=$?
  if [ "$rc" = "0" ]; then
    report yes "unparseable stdin exits 0"
  else
    report no "unparseable stdin exits 0" "exit was $rc"
  fi
  rm -rf "$dir"
}

test_missing_session_id_records_unknown() {
  local dir out
  dir="$(make_fixture)"
  run_hook '{"source":"startup","hook_event_name":"SessionStart"}' "$dir"
  out="$(out_file "$dir")"
  if grep -q '"session_id":"unknown"' "$out"; then
    report yes "missing session_id records as unknown"
  else
    report no "missing session_id records as unknown" "no unknown record in $out"
  fi
  rm -rf "$dir"
}

test_records_a_startup_session
test_records_a_resume_separately
test_empty_stdin_is_a_noop
test_unparseable_stdin_is_a_noop
test_missing_session_id_records_unknown

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ]
