#!/usr/bin/env bash
# Plain-Bash unit tests for fix-hooks.sh (no framework).
# Run: bash plugin/hooks/fix-hooks.test.sh
# Exits non-zero if any assertion fails.
#
# fix-hooks.sh detects (and, with --fix, removes) duplicate embo hook
# registrations across settings files, preventing the undocumented
# PreToolUse double-fire (task 032, FR-5b). These tests operate ONLY on
# synthetic temp settings files — never the user's real ~/.claude config.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/fix-hooks.sh"

PASS=0
FAIL=0

assert_eq() {
  # assert_eq <description> <expected> <actual>
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' \
      "$desc" "$exp" "$act"
  fi
}

# Write a synthetic settings file with a single embo PreToolUse
# registration (the manual-install shape: tilde path). Echoes the path.
mk_single_settings() {
  local f="$1"
  cat > "$f" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/approve-compound.sh" }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/context-guard.sh" }
        ]
      }
    ]
  }
}
JSON
}

# ---- 2.1 detect: single registration per handler, clean ----
# fix_hooks_detect <settings-file>  -> one line per embo registration:
#   "<token>\t<command-string>". No output if none found.

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mk_single_settings "$TMP/settings.json"

DETECT_OUT="$(fix_hooks_detect "$TMP/settings.json")"

# Two distinct embo handlers present (approve-compound + context-guard),
# each registered exactly once.
LINE_COUNT="$(printf '%s\n' "$DETECT_OUT" | grep -c . )"
assert_eq "detect finds 2 embo registrations" "2" "$LINE_COUNT"

APPROVE_COUNT="$(printf '%s\n' "$DETECT_OUT" | grep -c 'approve-compound.sh')"
assert_eq "detect finds approve-compound once" "1" "$APPROVE_COUNT"

GUARD_COUNT="$(printf '%s\n' "$DETECT_OUT" | grep -c 'context-guard.sh')"
assert_eq "detect finds context-guard once" "1" "$GUARD_COUNT"

# A non-embo entry must NOT be reported (token specificity).
NOISE_COUNT="$(printf '%s\n' "$DETECT_OUT" | grep -c 'behavioral-reminder.sh')"
assert_eq "detect omits absent handler" "0" "$NOISE_COUNT"

# Single, clean registration set: no duplicates. Run the full script
# (report-only, no --fix) on the single-settings file via SETTINGS_FILES
# override and assert exit 0.
SETTINGS_FILES="$TMP/settings.json" fix_hooks_main >/dev/null 2>&1
assert_eq "clean set exits 0" "0" "$?"

# ---- 2.2 detect DUPLICATE: same handler twice by different paths ----
# A duplicate = the SAME embo handler registered >=2 times (here by two
# different command paths, which Claude Code does NOT dedupe). Detector
# must surface both; the script must exit 1 in report-only mode.

mk_dup_settings() {
  local f="$1"
  cat > "$f" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/approve-compound.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash /abs/plugin/hooks/approve-compound.sh" }
        ]
      }
    ]
  }
}
JSON
}

mk_dup_settings "$TMP/dup.json"
DUP_OUT="$(fix_hooks_detect "$TMP/dup.json")"
DUP_APPROVE="$(printf '%s\n' "$DUP_OUT" | grep -c 'approve-compound.sh')"
assert_eq "detect finds approve-compound twice" "2" "$DUP_APPROVE"

# fix_hooks_count_dups <detect-output>  -> number of handlers registered
# more than once (the thing we must prevent).
DUP_N="$(fix_hooks_count_dups "$DUP_OUT")"
assert_eq "one handler is duplicated" "1" "$DUP_N"

# Report-only run on a file with duplicates: exit 1, file UNCHANGED.
BEFORE="$(cat "$TMP/dup.json")"
SETTINGS_FILES="$TMP/dup.json" fix_hooks_main >/dev/null 2>&1
assert_eq "duplicates report-only exits 1" "1" "$?"
assert_eq "report-only leaves file unchanged" "$BEFORE" "$(cat "$TMP/dup.json")"

# ---- 2.3 --fix removal: consent removes stale entry; backup; exit 2 ----
# With --fix and consent ("y"), the stale ~/.claude entry is removed,
# leaving exactly one approve-compound registration, a .bak is written,
# and exit is 2. With "n", nothing changes and exit stays 1.

# Consent = "n": no change, exit 1.
mk_dup_settings "$TMP/fix_no.json"
BEFORE_NO="$(cat "$TMP/fix_no.json")"
printf 'n\n' | SETTINGS_FILES="$TMP/fix_no.json" fix_hooks_main --fix >/dev/null 2>&1
assert_eq "declined --fix exits 1" "1" "$?"
assert_eq "declined --fix leaves file unchanged" "$BEFORE_NO" "$(cat "$TMP/fix_no.json")"

# Consent = "y": stale tilde entry removed, one approve-compound left.
mk_dup_settings "$TMP/fix_yes.json"
printf 'y\n' | SETTINGS_FILES="$TMP/fix_yes.json" fix_hooks_main --fix >/dev/null 2>&1
FIX_RC=$?
assert_eq "accepted --fix exits 2" "2" "$FIX_RC"

AFTER_APPROVE="$(fix_hooks_detect "$TMP/fix_yes.json" | grep -c 'approve-compound.sh')"
assert_eq "one approve-compound remains after fix" "1" "$AFTER_APPROVE"

# The removed one is the tilde (~/.claude) path; the plugin/abs one stays.
TILDE_LEFT="$(fix_hooks_detect "$TMP/fix_yes.json" | grep -c '~/.claude')"
assert_eq "stale tilde entry removed" "0" "$TILDE_LEFT"

# A backup must exist next to the edited file.
assert_eq "backup written" "yes" \
  "$([ -f "$TMP/fix_yes.json.bak" ] && echo yes || echo no)"

# Backup preserves the pre-edit content (both entries).
BAK_APPROVE="$(grep -c 'approve-compound.sh' "$TMP/fix_yes.json.bak")"
assert_eq "backup holds both pre-edit entries" "2" "$BAK_APPROVE"

# Idempotent: re-running --fix on the now-clean file exits 0, no change.
CLEAN="$(cat "$TMP/fix_yes.json")"
printf 'y\n' | SETTINGS_FILES="$TMP/fix_yes.json" fix_hooks_main --fix >/dev/null 2>&1
assert_eq "re-run on clean exits 0" "0" "$?"
assert_eq "re-run on clean leaves file unchanged" "$CLEAN" "$(cat "$TMP/fix_yes.json")"

# ---- 2.7 advise stale manual-install command/agent files ----
# fix_hooks_advise_stale_files <claude-home> -> prints a removal hint
# (containing the stale path) if ~/.claude/commands/dev exists; silent
# and returns 1 if nothing stale. Advisory only — never removes files.

# No stale dir: silent, returns nonzero (nothing to advise).
mkdir -p "$TMP/home_clean/.claude"
ADVISE_CLEAN="$(fix_hooks_advise_stale_files "$TMP/home_clean/.claude")"
assert_eq "no advice when clean" "" "$ADVISE_CLEAN"

# Stale commands/dev present: advice names the path.
mkdir -p "$TMP/home_stale/.claude/commands/dev"
: > "$TMP/home_stale/.claude/commands/dev/impl.md"
ADVISE_STALE="$(fix_hooks_advise_stale_files "$TMP/home_stale/.claude")"
STALE_HIT="$(printf '%s\n' "$ADVISE_STALE" | grep -q 'commands/dev' && echo yes || echo no)"
assert_eq "advice names stale commands/dev" "yes" "$STALE_HIT"

# Advisory must NOT delete the files it warns about.
assert_eq "advice leaves files intact" "yes" \
  "$([ -f "$TMP/home_stale/.claude/commands/dev/impl.md" ] && echo yes || echo no)"

# ---- summary ----
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
