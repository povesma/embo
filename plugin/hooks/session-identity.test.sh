#!/usr/bin/env bash
# session-identity.test.sh — fixture tests for session-identity.sh.
#
# Run: bash plugin/hooks/session-identity.test.sh
#
# The hook now writes the per-session state file via embo-session-state
# (phase `new` on first fire, phase-preserving on a re-fire) in place of
# the old session-identity.jsonl append. Each case points HOME and
# XDG_STATE_HOME at a temp dir so no real user state is touched.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/session-identity.sh"
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

# Run the hook with a clean temp HOME / XDG_STATE_HOME.
run_hook() {
  printf '%s' "$1" | \
    HOME="$TMP/home" XDG_STATE_HOME="$TMP/home/.local/state" bash "$HOOK"
}

# Resolve the state-file path for a session id (via the writer itself).
state_path() {
  HOME="$TMP/home" XDG_STATE_HOME="$TMP/home/.local/state" \
    bash "$STATE_BIN" path "$1"
}

field() {
  jq -r "$2" "$(state_path "$1")" 2>/dev/null
}

test_startup_writes_new_baseline() {
  run_hook '{"session_id":"sid-1","source":"startup","hook_event_name":"SessionStart"}'
  local phase src
  phase="$(field sid-1 '.phase')"
  src="$(field sid-1 '.source')"
  if [ "$phase" = "new" ] && [ "$src" = "startup" ]; then
    report yes "startup writes a new baseline with source"
  else
    report no "startup writes a new baseline with source" "phase=$phase source=$src"
  fi
}

test_refire_preserves_phase() {
  # First fire → new; advance to started via the writer; re-fire the hook
  # with source=resume → the phase must be preserved, never reset to new.
  run_hook '{"session_id":"sid-2","source":"startup","hook_event_name":"SessionStart"}'
  HOME="$TMP/home" XDG_STATE_HOME="$TMP/home/.local/state" \
    bash "$STATE_BIN" start sid-2 sha feat/x '~/x' >/dev/null 2>&1
  run_hook '{"session_id":"sid-2","source":"resume","hook_event_name":"SessionStart"}'
  local phase src
  phase="$(field sid-2 '.phase')"
  src="$(field sid-2 '.source')"
  if [ "$phase" = "started" ] && [ "$src" = "resume" ]; then
    report yes "re-fire preserves the phase, records the new source"
  else
    report no "re-fire preserves the phase, records the new source" "phase=$phase source=$src"
  fi
}

test_no_jsonl_append() {
  # The old diagnostic jsonl must no longer be written.
  run_hook '{"session_id":"sid-3","source":"startup","hook_event_name":"SessionStart"}'
  if [ ! -f "$TMP/home/.claude/session-identity.jsonl" ]; then
    report yes "no session-identity.jsonl is written"
  else
    report no "no session-identity.jsonl is written" "stale jsonl present"
  fi
}

test_empty_stdin_is_a_noop() {
  printf '' | HOME="$TMP/home" XDG_STATE_HOME="$TMP/home/.local/state" bash "$HOOK"
  if [ "$?" = "0" ]; then
    report yes "empty stdin exits 0"
  else
    report no "empty stdin exits 0"
  fi
}

test_unparseable_stdin_is_a_noop() {
  printf 'not json at all' | HOME="$TMP/home" XDG_STATE_HOME="$TMP/home/.local/state" bash "$HOOK"
  if [ "$?" = "0" ]; then
    report yes "unparseable stdin exits 0"
  else
    report no "unparseable stdin exits 0"
  fi
}

test_hook_source_has_no_jsonl_append() {
  # The hook must no longer append to session-identity.jsonl; the only
  # permitted mention is the explanatory comment.
  if grep -qE 'session-identity\.jsonl"?\s*$|>>.*session-identity' "$HOOK" 2>/dev/null; then
    report no "hook source contains no jsonl append"
  else
    report yes "hook source contains no jsonl append"
  fi
}

test_gitignore_ignores_stale_jsonl() {
  # The repo .gitignore must ignore a stale .claude/session-identity.jsonl.
  # Verify with git check-ignore in a throwaway repo seeded with it.
  local repo gi
  gi="$HERE/../../.gitignore"
  [ -f "$gi" ] || { report no "repo .gitignore is present" "not found at $gi"; return; }
  repo="$TMP/gi-repo"
  mkdir -p "$repo/.claude"
  git -C "$repo" init -q
  cp "$gi" "$repo/.gitignore"
  : > "$repo/.claude/session-identity.jsonl"
  if git -C "$repo" check-ignore -q .claude/session-identity.jsonl; then
    report yes "gitignore ignores .claude/session-identity.jsonl"
  else
    report no "gitignore ignores .claude/session-identity.jsonl"
  fi
}

test_startup_writes_new_baseline
test_refire_preserves_phase
test_no_jsonl_append
test_empty_stdin_is_a_noop
test_unparseable_stdin_is_a_noop
test_hook_source_has_no_jsonl_append
test_gitignore_ignores_stale_jsonl

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ]
