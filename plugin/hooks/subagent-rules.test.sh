#!/usr/bin/env bash
# Plain-Bash unit tests for subagent-rules.sh (no framework).
# Run: bash plugin/hooks/subagent-rules.test.sh
# Exits non-zero if any assertion fails.
#
# Drives the hook with synthetic SubagentStart stdin and asserts on the
# emitted hookSpecificOutput.additionalContext. Fixture runs copy the
# hook into a temp tree so the real ../commands/start.md resolution is
# exercised against controlled content.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/subagent-rules.sh"

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

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *)
      FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  missing: [%s]\n' "$desc" "$needle"
      ;;
  esac
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*)
      FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  must not contain: [%s]\n' "$desc" "$needle"
      ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STDIN_JSON='{"session_id":"s1","agent_id":"a1","agent_type":"fixture-agent","hook_event_name":"SubagentStart"}'

run_hook() {  # run_hook <hook-path> -> stdout
  printf '%s' "$STDIN_JSON" | bash "$1" 2>/dev/null
}

ctx_of() {  # ctx_of <hook-path> -> additionalContext string
  run_hook "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

# ---- 1.1 kept checklists are included ----

test_includes_kept_checklists() {
  local ctx
  ctx="$(ctx_of "$HOOK")"
  assert_eq "hookEventName is SubagentStart" "SubagentStart" \
    "$(run_hook "$HOOK" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
  assert_contains "includes WITHSTAND-CRITICISM checklist" "$ctx" "[WITHSTAND-CRITICISM checklist]"
  assert_contains "includes WITHSTAND-CRITICISM operative text" "$ctx" "Objection-check:"
  assert_contains "includes AVOID-APPROVAL checklist" "$ctx" "[AVOID-APPROVAL checklist]"
  assert_contains "includes AVOID-APPROVAL operative text" "$ctx" "Shape-check:"
}

# ---- 1.2 human-channel checklists are excluded ----

test_excludes_dropped_checklists() {
  local ctx
  ctx="$(ctx_of "$HOOK")"
  assert_not_contains "excludes CLEAR-OPTIONS text" "$ctx" "CLEAR-OPTIONS"
  assert_not_contains "excludes CLOSING-CHOICE checklist" "$ctx" "CLOSING-CHOICE"
  assert_not_contains "excludes RESTATE-CORRECTION text" "$ctx" "RESTATE-CORRECTION"
  assert_not_contains "excludes FOLD-FIRST text" "$ctx" "FOLD-FIRST"
  assert_not_contains "excludes DELEGATE checklist" "$ctx" "[DELEGATE checklist]"
  assert_not_contains "excludes Delegate-check artifact line" "$ctx" "Delegate-check:"
}

# ---- 1.3 salience header and preamble lead the block ----

test_preamble_leads() {
  local ctx starts prefix
  ctx="$(ctx_of "$HOOK")"
  starts="no"
  case "$ctx" in
    "=== BINDING SUBAGENT RULES"*) starts="yes" ;;
  esac
  assert_eq "salience header leads the block" "yes" "$starts"
  assert_contains "preamble carries DECIDE-OR-ASK directive" "$ctx" "[SUBAGENT DECIDE-OR-ASK]"
  assert_contains "preamble carries RESEARCH-VERIFY directive" "$ctx" "[SUBAGENT RESEARCH-VERIFY]"
  prefix="${ctx%%"[WITHSTAND-CRITICISM checklist]"*}"
  assert_contains "preamble precedes the checklists" "$prefix" "[SUBAGENT RESEARCH-VERIFY]"
}

# ---- 1.4 fail-open without start.md ----

test_fail_open_missing_startmd() {
  mkdir -p "$TMP/nostart/hooks"
  cp "$HOOK" "$TMP/nostart/hooks/subagent-rules.sh" 2>/dev/null
  local out rc ctx
  out="$(printf '%s' "$STDIN_JSON" | bash "$TMP/nostart/hooks/subagent-rules.sh" 2>/dev/null)"
  rc=$?
  assert_eq "missing start.md: exit 0" "0" "$rc"
  assert_eq "missing start.md: output is valid JSON" "SubagentStart" \
    "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
  ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
  assert_contains "missing start.md: preamble still emitted" "$ctx" "[SUBAGENT DECIDE-OR-ASK]"
  assert_not_contains "missing start.md: no checklist text" "$ctx" "WITHSTAND-CRITICISM"
}

# ---- 1.5 single source: editing a kept region changes output ----

write_fixture_startmd() {  # write_fixture_startmd <path> <token>
  cat > "$1" <<EOF
# fixture start.md
<!-- CHECKLIST:WITHSTAND-CRITICISM -->
[WITHSTAND-CRITICISM checklist] $2 kept-region wording.
<!-- /CHECKLIST -->
<!-- CHECKLIST:DELEGATE -->
[DELEGATE checklist] FIXTURE-DELEGATE-TEXT stays out.
<!-- /CHECKLIST -->
EOF
}

test_single_source_edit_changes_output() {
  mkdir -p "$TMP/fix/hooks" "$TMP/fix/commands"
  cp "$HOOK" "$TMP/fix/hooks/subagent-rules.sh" 2>/dev/null
  write_fixture_startmd "$TMP/fix/commands/start.md" "FIXTURE-TOKEN-V1"
  local ctx
  ctx="$(ctx_of "$TMP/fix/hooks/subagent-rules.sh")"
  assert_contains "fixture v1 token emitted" "$ctx" "FIXTURE-TOKEN-V1"
  assert_not_contains "fixture excluded region stays out" "$ctx" "FIXTURE-DELEGATE-TEXT"
  write_fixture_startmd "$TMP/fix/commands/start.md" "FIXTURE-TOKEN-V2"
  ctx="$(ctx_of "$TMP/fix/hooks/subagent-rules.sh")"
  assert_contains "edited fixture emits new token" "$ctx" "FIXTURE-TOKEN-V2"
  assert_not_contains "edited fixture no longer emits old token" "$ctx" "FIXTURE-TOKEN-V1"
}

# ---- run all tests ----

test_includes_kept_checklists
test_excludes_dropped_checklists
test_preamble_leads
test_fail_open_missing_startmd
test_single_source_edit_changes_output

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
