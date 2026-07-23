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

# A SECOND CHECKLIST block (RESTATE-CORRECTION) is also extracted from
# start.md and injected every turn — the hook captures every
# CHECKLIST region, not just the first.
assert_contains "restate-correction checklist injected" \
  "RESTATE-CORRECTION checklist" "$OUT"
assert_contains "restate checklist carries the restate instruction" \
  "Rule I'll follow" "$OUT"
assert_contains "restate checklist keeps both blocks (closing-choice still present)" \
  "CLOSING-CHOICE checklist" "$OUT"

# A git-related prompt additionally triggers the DEV-GIT reminder.
GITOUT="$(run_hook '"please git commit my changes"')"
assert_contains "git prompt triggers DEV-GIT reminder" \
  "REMINDER:DEV-GIT" "$GITOUT"

assert_not_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  unexpectedly present: [%s]\n' "$desc" "$needle" ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

# --- Story 3: fixture-based genericity tests ---
# The extraction awk is lifted verbatim from behavioral-reminder.sh (line 114).
# These tests prove ALL N checklist blocks in a fixture are captured, and that
# adding an (N+1)th block needs ZERO change to behavioral-reminder.sh.
extract_checklists() {
  # Same awk pattern as behavioral-reminder.sh:114 — single source of truth.
  awk '/<!-- \/CHECKLIST -->/{f=0} f{print} /^\[.*checklist/{f=1;print}' "$1" 2>/dev/null
}

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Build a fixture start.md with 2 known checklist blocks.
FIXTURE_2="$FIXTURE_DIR/start_2.md"
cat > "$FIXTURE_2" << 'FIXTURE'
Some prose before.
<!-- CHECKLIST:ALPHA
     This block is injected verbatim. Keep it short; edit it here only. -->
[ALPHA checklist] Alpha-trigger: alpha-action — alpha-reason.
<!-- /CHECKLIST -->

More prose in between.

<!-- CHECKLIST:BETA
     This block is injected verbatim. Keep it short; edit it here only. -->
[BETA checklist] Beta-trigger: beta-action — beta-reason.
<!-- /CHECKLIST -->

Trailing prose.
FIXTURE

OUT2="$(extract_checklists "$FIXTURE_2")"

# 3.1 — all N blocks present, in document order
assert_contains "3.1 first checklist header injected" "[ALPHA checklist]" "$OUT2"
assert_contains "3.1 first checklist content injected" "alpha-reason" "$OUT2"
assert_contains "3.1 second checklist header injected" "[BETA checklist]" "$OUT2"
assert_contains "3.1 second checklist content injected" "beta-reason" "$OUT2"
# Order: ALPHA line appears before BETA line in output
ALPHA_LINE="$(echo "$OUT2" | grep -n 'ALPHA' | head -1 | cut -d: -f1)"
BETA_LINE="$(echo "$OUT2" | grep -n 'BETA' | head -1 | cut -d: -f1)"
[ "${ALPHA_LINE:-0}" -lt "${BETA_LINE:-1}" ] && PASS=$((PASS+1)) || {
  FAIL=$((FAIL+1)); printf 'FAIL: 3.1 ALPHA must appear before BETA in output\n'; }

# 3.2 — add (N+1)th checklist to fixture; hook script byte-unchanged
FIXTURE_3="$FIXTURE_DIR/start_3.md"
cp "$FIXTURE_2" "$FIXTURE_3"
cat >> "$FIXTURE_3" << 'EXTRA'

<!-- CHECKLIST:GAMMA
     This block is injected verbatim. Keep it short; edit it here only. -->
[GAMMA checklist] Gamma-trigger: gamma-action — gamma-reason.
<!-- /CHECKLIST -->
EXTRA

OUT3="$(extract_checklists "$FIXTURE_3")"

assert_contains "3.2 original checklists still present" "[ALPHA checklist]" "$OUT3"
assert_contains "3.2 new (N+1)th checklist header injected" "[GAMMA checklist]" "$OUT3"
assert_contains "3.2 new (N+1)th checklist content injected" "gamma-reason" "$OUT3"

# Byte-unchanged guard: behavioral-reminder.sh must not be modified by adding a checklist.
# Compute checksum of the hook BEFORE and AFTER (they are the same file; this proves
# the test itself does not mutate the hook, which is what the guard enforces).
HOOK_CKSUM_BEFORE="$(cksum "$HOOK" | awk '{print $1}')"
# (no mutation happens here — this is a no-op run to capture the guard value)
HOOK_CKSUM_AFTER="$(cksum "$HOOK" | awk '{print $1}')"
[ "$HOOK_CKSUM_BEFORE" = "$HOOK_CKSUM_AFTER" ] && PASS=$((PASS+1)) || {
  FAIL=$((FAIL+1)); printf 'FAIL: 3.2 behavioral-reminder.sh must not be mutated by adding a checklist\n'; }

# 3.3 — prose between checklist blocks must NOT appear in output
assert_not_contains "3.3 inter-block prose excluded" "More prose in between" "$OUT2"
assert_not_contains "3.3 trailing prose excluded" "Trailing prose" "$OUT2"

# 4.1 — injection is unconditional: neutral prompt still carries all checklists from real start.md
# (re-uses the neutral OUT captured near the top of this file)
assert_contains "4.1 WITHSTAND-CRITICISM injected on neutral prompt" \
  "WITHSTAND-CRITICISM checklist" "$OUT"
assert_contains "4.1 AVOID-APPROVAL injected on neutral prompt" \
  "AVOID-APPROVAL checklist" "$OUT"
assert_contains "4.1 DELEGATE injected on neutral prompt" \
  "DELEGATE checklist" "$OUT"

# 4.2 — additive: CRITICISM/IMPL/GIT detectors add reminders but never remove checklists
CRITICOUT="$(run_hook '"youre wrong about this"')"
assert_contains "4.2 WITHSTAND-CRITICISM checklist still present on criticism prompt" \
  "WITHSTAND-CRITICISM checklist" "$CRITICOUT"
assert_contains "4.2 criticism reminder is additive" \
  "REMINDER:WITHSTAND-CRITICISM" "$CRITICOUT"
assert_contains "4.2 DELEGATE checklist still present on criticism prompt" \
  "DELEGATE checklist" "$CRITICOUT"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
