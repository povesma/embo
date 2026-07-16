#!/usr/bin/env bash
# Plain-Bash unit test for code-embo.build.jq (no framework).
# Run: bash plugin/claude-mem/code-embo-build.test.sh
# Exits non-zero if any assertion fails.
#
# Verifies the jq transform augments a claude-mem "code" mode with the
# `correction` observation type and the matching prompt edits. Runs
# against a synthetic fixture AND the actually-installed code.json (if
# present), so a claude-mem update that changes code.json's shape is
# caught here rather than silently breaking capture.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ_PROG="$HERE/code-embo.build.jq"

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

# ---- 4.1 minimal fixture code.json ----
# The fields the jq program reads: name, description, observation_types
# (6 entries), prompts.{recording_focus,type_guidance,skip_guidance}.
# type_guidance must contain the literal "EXACTLY one of these 6 options"
# for the sub() to fire.
cat > "$TMP/code.json" <<'JSON'
{
  "name": "Code Development",
  "description": "Software development work",
  "observation_types": [
    {"id": "bugfix",    "label": "Bug Fix"},
    {"id": "feature",   "label": "Feature"},
    {"id": "refactor",  "label": "Refactor"},
    {"id": "change",    "label": "Change"},
    {"id": "discovery", "label": "Discovery"},
    {"id": "decision",  "label": "Decision"}
  ],
  "prompts": {
    "recording_focus": "Record what changed and why.",
    "type_guidance": "Choose EXACTLY one of these 6 options for the type.",
    "skip_guidance": "Skip turns with no substantive change."
  }
}
JSON

# ---- 4.2 transform assertions (against the fixture) ----
OUT="$TMP/code-embo.json"
jq -f "$JQ_PROG" "$TMP/code.json" > "$OUT" 2>/dev/null
assert_eq "transform produced valid JSON" "true" \
  "$(jq -e 'type == "object"' "$OUT" >/dev/null 2>&1 && echo true || echo false)"

TYPE_COUNT="$(jq '.observation_types | length' "$OUT")"
assert_eq "7 observation types after transform" "7" "$TYPE_COUNT"

HAS_CORRECTION="$(jq '[.observation_types[].id] | contains(["correction"])' "$OUT")"
assert_eq "correction type present" "true" "$HAS_CORRECTION"

GUIDANCE_7="$(jq -r '.prompts.type_guidance | contains("7 options")' "$OUT")"
assert_eq "type_guidance says 7 options" "true" "$GUIDANCE_7"

GUIDANCE_NO_6="$(jq -r '.prompts.type_guidance | contains("6 options")' "$OUT")"
assert_eq "type_guidance no longer says 6 options" "false" "$GUIDANCE_NO_6"

RF_APPENDED="$(jq -r '.prompts.recording_focus | contains("correction")' "$OUT")"
assert_eq "recording_focus mentions correction" "true" "$RF_APPENDED"

SG_APPENDED="$(jq -r '.prompts.skip_guidance | contains("corrected how Claude works")' "$OUT")"
assert_eq "skip_guidance has the correction exception" "true" "$SG_APPENDED"

# ---- 4.3 run against the actually-installed code.json ----
CM_DIR="$HOME/.claude/plugins/cache/thedotmack/claude-mem"
if [ -d "$CM_DIR" ]; then
  VER="$(ls -1 "$CM_DIR" 2>/dev/null | sort -V | tail -1)"
  REAL="$CM_DIR/$VER/modes/code.json"
  if [ -f "$REAL" ]; then
    REAL_OUT="$TMP/real-code-embo.json"
    BASE_N="$(jq '.observation_types | length' "$REAL")"
    EXPECT_N="$((BASE_N + 1))"
    jq -f "$JQ_PROG" "$REAL" > "$REAL_OUT" 2>/dev/null
    assert_eq "installed transform adds exactly one type (v$VER: $BASE_N->$EXPECT_N)" \
      "$EXPECT_N" "$(jq '.observation_types | length' "$REAL_OUT" 2>/dev/null)"
    assert_eq "installed transform has correction type (v$VER)" "true" \
      "$(jq '[.observation_types[].id] | contains(["correction"])' "$REAL_OUT" 2>/dev/null)"
    # The guidance sub() must actually fire: the shipped text says "6
    # options" today. If a future version changes that wording, this
    # fails loud (the new type would be inert without the guidance edit).
    assert_eq "installed transform rewrote guidance to 7 options (v$VER)" "true" \
      "$(jq -r '.prompts.type_guidance | contains("7 options")' "$REAL_OUT" 2>/dev/null)"
  else
    printf 'SKIP: installed code.json not found at %s\n' "$REAL"
  fi
else
  printf 'SKIP: claude-mem cache not found (%s)\n' "$CM_DIR"
fi

# ---- summary ----
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
