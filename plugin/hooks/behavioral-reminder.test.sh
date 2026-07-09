#!/usr/bin/env bash
# Plain-bash unit tests for behavioral-reminder.sh (no framework).
# Run: bash .claude/hooks/behavioral-reminder.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/behavioral-reminder.sh"

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *)
      FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' \
        "$desc" "$needle" "$hay"
      ;;
  esac
}

run_hook() {
  printf '{"prompt":%s}' "$1" | bash "$HOOK"
}

# A neutral prompt triggers no keyword reminders, so output is the
# baseline tag list plus the JSON envelope.
OUT="$(run_hook '"hello there"')"

assert_contains "baseline lists CHALLENGE-INSTRUCTION" \
  "CHALLENGE-INSTRUCTION" "$OUT"
assert_contains "baseline lists CAPTURE-OUTPUT" \
  "CAPTURE-OUTPUT" "$OUT"
assert_contains "baseline lists AVOID-APPROVAL" \
  "AVOID-APPROVAL" "$OUT"
assert_contains "baseline lists RESEARCH-VERIFY" \
  "RESEARCH-VERIFY" "$OUT"
assert_contains "baseline lists DECIDE-OR-ASK" \
  "DECIDE-OR-ASK" "$OUT"

# The closing-choice checklist is extracted verbatim from
# commands/start.md (single source of truth) and appended to the
# baseline on every prompt.
assert_contains "checklist header injected" \
  "CLOSING-CHOICE checklist" "$OUT"
assert_contains "checklist carries the kinds" \
  "combinable" "$OUT"
assert_contains "checklist mandates AskUserQuestion" \
  "AskUserQuestion" "$OUT"
assert_contains "checklist keeps decide-first test" \
  "obvious best answer" "$OUT"

# A git-related prompt additionally triggers the DEV-GIT reminder.
GITOUT="$(run_hook '"please git commit my changes"')"
assert_contains "git prompt triggers DEV-GIT reminder" \
  "REMINDER:DEV-GIT" "$GITOUT"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
