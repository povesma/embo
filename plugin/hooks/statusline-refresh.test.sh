#!/usr/bin/env bash
# Plain-Bash unit tests for statusline-refresh.sh (no framework).
# Run: bash plugin/hooks/statusline-refresh.test.sh
# Exits non-zero if any assertion fails.
#
# Drives the SessionStart hook against a throwaway HOME +
# CLAUDE_PLUGIN_ROOT so the real copy/compare logic runs against
# controlled fixture files. Verifies the auto-refresh token guard:
# a copy that still carries `embo:auto-refresh` is kept current; a copy
# that removed the marker (customized) is never overwritten.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/statusline-refresh.sh"

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

# Each run gets a fresh HOME + plugin root. The bundled source always
# carries the marker and is the "new" version the hook would install.
setup() {  # setup -> exports SRC/DEST, writes bundled source
  RUN="$(mktemp -d "$TMP/run.XXXXXX")"
  export HOME="$RUN/home"
  export CLAUDE_PLUGIN_ROOT="$RUN/plugin"
  mkdir -p "$HOME/.claude" "$CLAUDE_PLUGIN_ROOT"
  SRC="$CLAUDE_PLUGIN_ROOT/statusline.sh"
  DEST="$HOME/.claude/statusline.sh"
  printf '#!/usr/bin/env bash\n# embo:auto-refresh — marker\nBUNDLED_V2\n' > "$SRC"
}

run_hook() {  # run_hook -> exit code, output discarded
  bash "$HOOK" >/dev/null 2>&1
}

# ---- 1. token present + stale copy -> refreshes ----

test_token_present_stale_refreshes() {
  setup
  printf '#!/usr/bin/env bash\n# embo:auto-refresh — marker\nOLD_V1\n' > "$DEST"
  run_hook
  local got=kept
  grep -q BUNDLED_V2 "$DEST" && got=refreshed
  assert_eq "token present + differs -> refreshes" "refreshed" "$got"
}

# ---- 2. token removed (customized) -> preserved ----

test_token_absent_preserved() {
  setup
  printf '#!/usr/bin/env bash\n# my custom header, marker removed\nCUSTOM_CONTENT\n' > "$DEST"
  run_hook
  local got=overwritten
  grep -q CUSTOM_CONTENT "$DEST" && got=kept
  assert_eq "token absent (customized) -> preserved" "kept" "$got"
}

# ---- 3. no installed copy -> no-op, exit 0 ----

test_no_installed_copy_noop() {
  setup
  rm -f "$DEST"
  run_hook
  local rc=$?
  assert_eq "no installed copy -> exit 0" "0" "$rc"
  local exists=absent
  [ -f "$DEST" ] && exists=present
  assert_eq "no installed copy -> hook never creates one" "absent" "$exists"
}

# ---- 4. token present + identical -> exit 0, no error ----

test_identical_exit_zero() {
  setup
  cp "$SRC" "$DEST"
  run_hook
  local rc=$?
  assert_eq "token present + identical -> exit 0" "0" "$rc"
}

# ---- 5. fail-open: missing CLAUDE_PLUGIN_ROOT -> exit 0 ----

test_fail_open_no_plugin_root() {
  setup
  local rc
  env -u CLAUDE_PLUGIN_ROOT bash "$HOOK" >/dev/null 2>&1
  rc=$?
  assert_eq "no CLAUDE_PLUGIN_ROOT -> exit 0 (never blocks session)" "0" "$rc"
}

# ---- run all tests ----

test_token_present_stale_refreshes
test_token_absent_preserved
test_no_installed_copy_noop
test_identical_exit_zero
test_fail_open_no_plugin_root

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
