#!/usr/bin/env bash
# Plain-Bash tests for the embo-task-state wrapper.
# Run: bash plugin/bin/embo-task-state.test.sh
# Exits non-zero if any assertion fails.
#
# Verifies the wrapper's set/get/clear lifecycle, id-safety rejection,
# and absent/unreadable-state fallback, operating on a synthetic temp
# dir via EMBO_TASK_STATE_DIR — never the real project tmp/.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$HERE/embo-task-state"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' \
      "$desc" "$exp" "$act"
  fi
}
assert_status() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" -eq "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected exit: [%s]\n  actual exit:   [%s]\n' \
      "$desc" "$exp" "$act"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export EMBO_TASK_STATE_DIR="$TMP/embo-task-state"

# get on an absent session: empty output, exit 0.
out="$("$WRAPPER" get missing-session 2>/dev/null)"
status=$?
assert_eq "get on absent session prints nothing" "" "$out"
assert_status "get on absent session exits 0" 0 "$status"

# set then get round-trips the task number.
"$WRAPPER" set sess1 055 >/dev/null 2>&1
out="$("$WRAPPER" get sess1 2>/dev/null)"
assert_eq "get returns the task number just set" "055" "$out"

# set overwrites a prior value for the same session.
"$WRAPPER" set sess1 068 >/dev/null 2>&1
out="$("$WRAPPER" get sess1 2>/dev/null)"
assert_eq "set overwrites the prior value" "068" "$out"

# a second session's state is independent.
"$WRAPPER" set sess2 012 >/dev/null 2>&1
out1="$("$WRAPPER" get sess1 2>/dev/null)"
out2="$("$WRAPPER" get sess2 2>/dev/null)"
assert_eq "sess1 state unaffected by sess2 write" "068" "$out1"
assert_eq "sess2 state recorded independently" "012" "$out2"

# clear removes the state file; get then returns empty.
"$WRAPPER" clear sess1 >/dev/null 2>&1
out="$("$WRAPPER" get sess1 2>/dev/null)"
assert_eq "get after clear prints nothing" "" "$out"
[ -f "$EMBO_TASK_STATE_DIR/sess1.json" ]
assert_status "clear removes the state file" 1 "$?"

# clear on an absent session is a no-op (idempotent, exit 0).
"$WRAPPER" clear never-existed >/dev/null 2>&1
status=$?
assert_status "clear on absent session exits 0" 0 "$status"

# invalid ids are rejected on set and get.
"$WRAPPER" set "../escape" 055 >/dev/null 2>&1
status=$?
assert_status "set rejects an id containing .." 2 "$status"

"$WRAPPER" get "bad id" >/dev/null 2>&1
status=$?
assert_status "get rejects an id with a space" 2 "$status"

"$WRAPPER" set "" 055 >/dev/null 2>&1
status=$?
assert_status "set rejects an empty id" 2 "$status"

# set with no task_number argument is a usage error.
"$WRAPPER" set sess3 >/dev/null 2>&1
status=$?
assert_status "set with no task_number exits non-zero" 2 "$status"

# unknown subcommand is a usage error.
"$WRAPPER" bogus >/dev/null 2>&1
status=$?
assert_status "unknown subcommand exits non-zero" 2 "$status"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
