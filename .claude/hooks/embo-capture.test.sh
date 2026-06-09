#!/usr/bin/env bash
# Plain-bash unit tests for embo-capture.sh (no framework).
# Run: bash .claude/hooks/embo-capture.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAP="$HERE/embo-capture.sh"

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

assert_not_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*)
      FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  unexpected: [%s]\n  in: [%s]\n' \
        "$desc" "$needle" "$hay"
      ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

# b64 <string> -> base64 of the string (the hook's encoding step)
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

# run the wrapper in an isolated scratch dir; echo stdout; write the
# wrapper's exit code to RC_FILE so it survives $(...) subshell capture.
SCRATCH="$(mktemp -d)"
RC_FILE="$(mktemp)"
run() {
  # run <command-string> ; prints wrapper stdout; RC via rc() after.
  local enc; enc="$(b64 "$1")"
  ( cd "$SCRATCH" && bash "$WRAP" --b64 "$enc" )
  printf '%s' "$?" > "$RC_FILE"
}
rc() { cat "$RC_FILE"; }

# ---- 1.1 exit-code pass-through ----
run 'true' >/dev/null;  assert_eq "exit 0 propagates" "0" "$(rc)"
run 'exit 7' >/dev/null; assert_eq "exit 7 propagates" "7" "$(rc)"
run 'sh -c "exit 3"' >/dev/null; assert_eq "exit 3 via child" "3" "$(rc)"

# ---- 1.3 / 1.4 inline threshold (<=10 lines AND <=300 bytes) ----
OUT="$(run 'printf "hello\n"')"
assert_eq        "small: exit ok"        "0" "$(rc)"
assert_contains  "small: prints output"  "hello" "$OUT"
assert_not_contains "small: no marker"   "[embo-capture]" "$OUT"

# 11 lines -> exceeds line cap -> marker
OUT="$(run 'for i in $(seq 1 11); do echo line$i; done')"
assert_contains  "11 lines: marker present" "[embo-capture]" "$OUT"

# >300 bytes on a single line -> exceeds byte cap -> marker
OUT="$(run 'printf "%0.sX" $(seq 1 400); echo')"
assert_contains  ">300 bytes: marker present" "[embo-capture]" "$OUT"

# exactly at the edge: 10 lines, small bytes -> inline
OUT="$(run 'for i in $(seq 1 10); do echo s; done')"
assert_not_contains "10 lines inline (no marker)" "[embo-capture]" "$OUT"

# ---- 1.5 / 1.6 marker contract ----
OUT="$(run 'for i in $(seq 1 50); do echo row$i; done')"
assert_contains "marker: prefix"        "[embo-capture] truncated" "$OUT"
assert_contains "marker: lines word"    "lines" "$OUT"
assert_contains "marker: bytes word"    "bytes" "$OUT"
assert_contains "marker: full output"   "Full output:" "$OUT"
assert_contains "marker: exit shown"    "(exit=0)" "$OUT"
assert_contains "marker: preview line"  "row1" "$OUT"
# preview is only the first lines, not the whole output
assert_not_contains "marker: not full inline" "row50" "$OUT"

# marker carries the wrapped command's real exit code
OUT="$(run 'for i in $(seq 1 50); do echo row$i; done; exit 4')"
assert_eq       "marker: rc propagates"  "4" "$(rc)"
assert_contains "marker: exit=4"         "(exit=4)" "$OUT"

# ---- 1.7 / 1.8 per-call file holds FULL output ----
OUT="$(run 'for i in $(seq 1 50); do echo row$i; done')"
# extract the path token from the marker (the indented line after it)
FILE="$(printf '%s' "$OUT" | sed -nE 's/^[[:space:]]*([^[:space:]]+\.log)[[:space:]]*\(exit=.*/\1/p' | head -1)"
assert_contains "file: path under tmp/cap" "tmp/cap/" "$FILE"
if [ -n "$FILE" ] && [ -f "$SCRATCH/$FILE" ]; then
  FULL="$(cat "$SCRATCH/$FILE")"
  assert_contains "file: has first line"  "row1"  "$FULL"
  assert_contains "file: has last line"   "row50" "$FULL"
else
  FAIL=$((FAIL + 1)); printf 'FAIL: file: captured log not found [%s]\n' "$FILE"
fi

# two calls -> two distinct files (unique per call)
F1="$(run 'seq 1 50' | sed -nE 's/^[[:space:]]*([^[:space:]]+\.log)[[:space:]]*\(exit=.*/\1/p' | head -1)"
F2="$(run 'seq 1 50' | sed -nE 's/^[[:space:]]*([^[:space:]]+\.log)[[:space:]]*\(exit=.*/\1/p' | head -1)"
if [ "$F1" != "$F2" ]; then PASS=$((PASS + 1)); else
  FAIL=$((FAIL + 1)); printf 'FAIL: per-call files not unique [%s == %s]\n' "$F1" "$F2"
fi

rm -rf "$SCRATCH" "$RC_FILE"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
