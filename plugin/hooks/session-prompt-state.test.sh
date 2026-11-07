#!/usr/bin/env bash
# session-prompt-state.test.sh — fixture tests for session-prompt-state.sh.
#
# Run: bash plugin/hooks/session-prompt-state.test.sh
#
# The UserPromptSubmit hook flips a `wrapped_up` session back to `started`
# on the first real prompt after a wrapup, touches `updated_at` otherwise,
# and is a no-op when no state file exists. Each case points HOME and
# XDG_STATE_HOME at a temp dir so no real user state is touched.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/session-prompt-state.sh"
STATE_BIN="$HERE/../bin/embo-session-state"
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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

env_run() {
  HOME="$TMP/home" XDG_STATE_HOME="$TMP/home/.local/state" "$@"
}

run_hook() {
  printf '%s' "$1" | env_run bash "$HOOK"
}

writer() { env_run bash "$STATE_BIN" "$@"; }

state_path() { writer path "$1"; }
field() { jq -r "$2" "$(state_path "$1")" 2>/dev/null; }

test_flips_wrapped_up_to_started() {
  writer baseline p1 startup >/dev/null 2>&1
  writer start p1 sha feat/x '~/x' >/dev/null 2>&1
  writer wrapup p1 >/dev/null 2>&1
  run_hook '{"session_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"keep going"}'
  local phase
  phase="$(field p1 '.phase')"
  if [ "$phase" = "started" ]; then
    report yes "a prompt after wrapup flips wrapped_up to started"
  else
    report no "a prompt after wrapup flips wrapped_up to started" "phase=$phase"
  fi
}

test_started_only_touches_updated_at() {
  writer baseline p2 startup >/dev/null 2>&1
  writer start p2 sha feat/y '~/y' >/dev/null 2>&1
  local before
  before="$(field p2 '.phase')"
  run_hook '{"session_id":"p2","hook_event_name":"UserPromptSubmit","prompt":"next"}'
  local after
  after="$(field p2 '.phase')"
  if [ "$before" = "started" ] && [ "$after" = "started" ]; then
    report yes "a prompt during started leaves phase started"
  else
    report no "a prompt during started leaves phase started" "before=$before after=$after"
  fi
}

test_no_file_is_a_noop() {
  run_hook '{"session_id":"p-nofile","hook_event_name":"UserPromptSubmit","prompt":"hi"}'
  if [ ! -f "$(state_path p-nofile)" ]; then
    report yes "no state file → hook creates nothing"
  else
    report no "no state file → hook creates nothing" "a file was created"
  fi
}

test_empty_stdin_is_a_noop() {
  printf '' | env_run bash "$HOOK"
  if [ "$?" = "0" ]; then
    report yes "empty stdin exits 0"
  else
    report no "empty stdin exits 0"
  fi
}

test_unsafe_id_is_a_noop() {
  run_hook '{"session_id":"../escape","hook_event_name":"UserPromptSubmit","prompt":"x"}'
  if [ "$?" = "0" ]; then
    report yes "unsafe session_id exits 0 (no crash)"
  else
    report no "unsafe session_id exits 0 (no crash)"
  fi
}

test_no_stdout() {
  writer baseline p-quiet startup >/dev/null 2>&1
  writer start p-quiet sha feat/q '~/q' >/dev/null 2>&1
  writer wrapup p-quiet >/dev/null 2>&1
  local out
  out="$(run_hook '{"session_id":"p-quiet","hook_event_name":"UserPromptSubmit","prompt":"go"}')"
  if [ -z "$out" ]; then
    report yes "hook prints nothing to stdout"
  else
    report no "hook prints nothing to stdout" "stdout=[$out]"
  fi
}

test_registered_in_hooks_json() {
  # The UserPromptSubmit entry must be present and well-formed.
  local hooks_json count
  hooks_json="$HERE/hooks.json"
  count="$(jq '[.hooks.UserPromptSubmit[].hooks[].command
                | select(test("session-prompt-state\\.sh"))] | length' \
            "$hooks_json" 2>/dev/null)"
  if [ "$count" = "1" ]; then
    report yes "registered once under UserPromptSubmit in hooks.json"
  else
    report no "registered once under UserPromptSubmit in hooks.json" "count=$count"
  fi

  local valid
  valid="$(jq -e 'type == "object"' "$hooks_json" >/dev/null 2>&1 \
           && echo true || echo false)"
  if [ "$valid" = "true" ]; then
    report yes "hooks.json is valid JSON after the edit"
  else
    report no "hooks.json is valid JSON after the edit"
  fi
}

test_flips_wrapped_up_to_started
test_started_only_touches_updated_at
test_no_file_is_a_noop
test_empty_stdin_is_a_noop
test_unsafe_id_is_a_noop
test_no_stdout
test_registered_in_hooks_json

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ]
