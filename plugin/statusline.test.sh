#!/usr/bin/env bash
# Plain-Bash unit tests for statusline.sh's embo_state_segment (no framework).
# Run: bash plugin/statusline.test.sh
# Exits non-zero if any assertion fails.
#
# Sources statusline.sh in library mode (STATUSLINE_LIB_ONLY=1 skips the
# main render body) and drives embo_state_segment against a temp HOME.
# Asserts the phase→label mapping, degrade cases, and that no git runs.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$HERE/statusline.sh"
STATE_BIN="$HERE/bin/embo-session-state"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$desc" "$exp" "$act"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_STATE_HOME="$TMP/home/.local/state"

# Source the statusline in library mode so only its functions load.
STATUSLINE_LIB_ONLY=1 source "$STATUSLINE"

writer() { bash "$STATE_BIN" "$@"; }

# Strip ANSI colour codes so assertions compare the visible text only.
plain() { printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'; }

# Call the segment for a session id (passed as its single argument).
seg() { plain "$(embo_state_segment "$1")"; }

test_no_file_is_question() {
  assert_eq "no state file → embo:?" "embo:?" "$(seg nofile-sid)"
}

test_phase_new_is_question() {
  writer baseline s-new startup >/dev/null 2>&1
  assert_eq "phase new → embo:?" "embo:?" "$(seg s-new)"
}

test_phase_started_is_play() {
  writer baseline s-run startup >/dev/null 2>&1
  writer start s-run sha feat/x '~/x' >/dev/null 2>&1
  assert_eq "phase started → embo:▶" "embo:▶" "$(seg s-run)"
}

test_phase_wrapped_up_is_check() {
  writer baseline s-done startup >/dev/null 2>&1
  writer start s-done sha feat/y '~/y' >/dev/null 2>&1
  writer wrapup s-done >/dev/null 2>&1
  assert_eq "phase wrapped_up → embo:✓" "embo:✓" "$(seg s-done)"
}

test_corrupt_file_is_question() {
  writer baseline s-bad startup >/dev/null 2>&1
  local path
  path="$(writer path s-bad)"
  printf 'not json{' > "$path"
  assert_eq "corrupt file → embo:?" "embo:?" "$(seg s-bad)"
}

test_empty_id_is_question() {
  assert_eq "empty session id → embo:?" "embo:?" "$(seg '')"
}

test_unsafe_id_is_question() {
  assert_eq "unsafe session id → embo:?" "embo:?" "$(seg '../escape')"
}

test_no_git_invoked() {
  # Shadow `git` with a stub that records any call; the segment must not
  # invoke it. Run from inside a real repo to make a git call tempting.
  local repo stub
  repo="$TMP/repo"; mkdir -p "$repo"; git -C "$repo" init -q
  stub="$TMP/bin"; mkdir -p "$stub"
  printf '#!/usr/bin/env bash\ntouch "%s/git-was-called"\n' "$TMP" > "$stub/git"
  chmod +x "$stub/git"
  writer baseline s-git startup >/dev/null 2>&1
  writer start s-git sha feat/g '~/g' >/dev/null 2>&1
  rm -f "$TMP/git-was-called"
  ( cd "$repo" && PATH="$stub:$PATH" embo_state_segment s-git >/dev/null 2>&1 )
  assert_eq "segment invokes no git" "false" \
    "$([ -f "$TMP/git-was-called" ] && echo true || echo false)"
}

# ---- save_cc_stdin: raw Claude Code stdin JSON → <id>.cc.json (ATC contract) ----

cc_path() {
    printf '%s/embo/session-state/%s.cc.json' "$XDG_STATE_HOME" "$1"
}

test_cc_writes_raw_json() {
    local blob='{"session_id":"cc1","model":{"display_name":"Opus 4.8"},"cost":{"total_cost_usd":0.5}}'
    save_cc_stdin "$blob" cc1
    local path
    path="$(cc_path cc1)"
    assert_eq "cc file is written" "true" \
        "$([ -f "$path" ] && echo true || echo false)"
    assert_eq "cc file is the raw blob, unchanged" "$blob" "$(cat "$path")"
}

test_cc_file_is_valid_json() {
    local blob='{"session_id":"cc2","model":{"display_name":"X"}}'
    save_cc_stdin "$blob" cc2
    assert_eq "cc file parses as JSON" "true" \
        "$(jq -e . "$(cc_path cc2)" >/dev/null 2>&1 && echo true || echo false)"
}

test_cc_no_tmp_left() {
    save_cc_stdin '{"session_id":"cc3"}' cc3
    local dir count
    dir="$(dirname "$(cc_path cc3)")"
    count="$(find "$dir" -name '*.cc.tmp*' 2>/dev/null | wc -l | tr -d ' ')"
    assert_eq "no cc temp file left behind" "0" "$count"
}

test_cc_unsafe_id_writes_nothing() {
    save_cc_stdin '{"x":1}' '../escape'
    assert_eq "unsafe id → no cc file escapes the dir" "false" \
        "$([ -f "$XDG_STATE_HOME/embo/session-state/../escape.cc.json" ] && echo true || echo false)"
}

test_cc_empty_id_is_noop() {
    save_cc_stdin '{"x":1}' ''
    assert_eq "empty id → save_cc_stdin exits 0 (no crash)" "0" "$?"
}

test_cc_empty_blob_is_noop() {
    save_cc_stdin '' cc4
    assert_eq "empty blob → no cc file written" "false" \
        "$([ -f "$(cc_path cc4)" ] && echo true || echo false)"
}

test_no_file_is_question
test_phase_new_is_question
test_phase_started_is_play
test_phase_wrapped_up_is_check
test_corrupt_file_is_question
test_empty_id_is_question
test_unsafe_id_is_question
test_no_git_invoked
test_cc_writes_raw_json
test_cc_file_is_valid_json
test_cc_no_tmp_left
test_cc_unsafe_id_writes_nothing
test_cc_empty_id_is_noop
test_cc_empty_blob_is_noop

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
