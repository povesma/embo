#!/usr/bin/env bash
# Plain-Bash tests for the embo-profile wrapper.
# Run: bash plugin/bin/embo-profile.test.sh
# Exits non-zero if any assertion fails.
#
# Verifies the wrapper owns the full profile lifecycle (show/get/set/
# reset/list) and runs as a bare command with CLAUDE_PLUGIN_ROOT unset
# from an arbitrary CWD. Operates on synthetic temp files only, via the
# EMBO_PROFILE_ACTIVE (active-file path) and EMBO_PROFILE_DIRS
# (colon-separated search dirs) overrides — never the real ~/.claude.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$HERE/embo-profile"

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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unset CLAUDE_PLUGIN_ROOT

# A synthetic active-profile path and a synthetic profiles search dir.
ACTIVE="$TMP/active-profile.yaml"
PROFILES="$TMP/profiles"
mkdir -p "$PROFILES"
printf 'name: quality\ndescription: Full workflow\ntools:\n  rlm: true\ngit:\n  commit_style: conventional\n' \
  > "$PROFILES/quality.yaml"
printf 'name: fast\ndescription: Speed mode\ntools:\n  rlm: false\n' \
  > "$PROFILES/fast.yaml"

# Run the wrapper from an arbitrary CWD with the overrides set.
run() {
  ( cd "$TMP" && EMBO_PROFILE_ACTIVE="$ACTIVE" EMBO_PROFILE_DIRS="$PROFILES" \
      "$WRAPPER" "$@" )
}

# ---- show: absent active file, no default → NO_PROFILE ----

test_show_absent_no_default() {
  rm -f "$ACTIVE" "$PROFILES/default.yaml"
  assert_eq "show: absent active + no default → NO_PROFILE" "NO_PROFILE" \
    "$(run show)"
}

# ---- show: absent active file, default.yaml present → default ----

test_show_falls_back_to_default() {
  rm -f "$ACTIVE"
  printf 'name: default\ndescription: canonical\ntools:\n  rlm: true\n' \
    > "$PROFILES/default.yaml"
  assert_eq "show: absent active + default present → default name" \
    "name: default" "$(run show | grep '^name:')"
  assert_eq "get: falls back to default when no active" "true" \
    "$(run get tools.rlm)"
  rm -f "$PROFILES/default.yaml"
}

# ---- set then show ----

test_set_then_show() {
  run set quality >/dev/null
  assert_eq "set: active file created" "true" \
    "$( [ -f "$ACTIVE" ] && echo true || echo false )"
  assert_eq "show: prints the active profile name line" "name: quality" \
    "$(run show | grep '^name:')"
}

# ---- get <field> ----

test_get_field() {
  run set quality >/dev/null
  assert_eq "get: top-level field" "quality" "$(run get name)"
  assert_eq "get: nested field (dotted)" "true" "$(run get tools.rlm)"
  assert_eq "get: nested field git.commit_style" "conventional" \
    "$(run get git.commit_style)"
  assert_eq "get: absent field → empty" "" "$(run get nope.missing)"
}

# ---- set unknown profile ----

test_set_unknown() {
  run set does-not-exist >/dev/null 2>&1
  assert_eq "set: unknown profile → rc 1" "1" "$?"
}

# ---- reset ----

test_reset() {
  run set quality >/dev/null
  run reset >/dev/null
  assert_eq "reset: active file removed" "false" \
    "$( [ -f "$ACTIVE" ] && echo true || echo false )"
  assert_eq "show after reset → NO_PROFILE" "NO_PROFILE" "$(run show)"
}

# ---- reset is idempotent ----

test_reset_idempotent() {
  run reset >/dev/null
  run reset >/dev/null 2>&1
  assert_eq "reset: idempotent (no error on absent)" "0" "$?"
}

# ---- unknown subcommand ----

test_unknown_subcommand() {
  run bogus >/dev/null 2>&1
  assert_eq "unknown subcommand → rc 2" "2" "$?"
}

# ---- runs bare with CLAUDE_PLUGIN_ROOT unset (AC-2) ----

test_bare_no_env() {
  run set fast >/dev/null
  assert_eq "bare run resolves and shows (env unset)" "fast" "$(run get name)"
}

# ---- run all tests ----

test_show_absent_no_default
test_show_falls_back_to_default
test_set_then_show
test_get_field
test_set_unknown
test_reset
test_reset_idempotent
test_unknown_subcommand
test_bare_no_env

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
