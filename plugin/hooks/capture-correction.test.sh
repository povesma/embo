#!/usr/bin/env bash
# Plain-Bash unit tests for capture-correction.sh (no framework).
# Run: bash plugin/hooks/capture-correction.test.sh
# Exits non-zero if any assertion fails.
#
# Operates ONLY on synthetic temp files — never a real Claude Code
# transcript or project directory.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/capture-correction.sh"

PASS=0
FAIL=0
CURRENT_TEST=""

assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s / %s\n  expected: [%s]\n  actual:   [%s]\n' \
      "$CURRENT_TEST" "$desc" "$exp" "$act"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Helpers --------------------------------------------------------

# Fresh, isolated project directory (with .claude/) for each test.
# Uses mktemp so each call is independent of any counter — a counter
# would not survive the command substitution subshell most callers
# use.
make_project() {
  local d
  d="$(mktemp -d "$TMP/proj.XXXXXX")"
  mkdir -p "$d/.claude"
  printf '%s' "$d"
}

# Write a synthetic transcript JSONL file from "role:text" pairs,
# matching the shape Claude Code writes:
#   {"message":{"role":"assistant","content":[{"type":"text","text":"..."}]}}
#
# Special role tokens:
#   - "reject_note:<text>"      -> tool_result rejection with a user
#                                  note (the shape 9.1 identified)
#   - "reject_bare:"            -> tool_result rejection with only
#                                  the standard boilerplate, no note
write_transcript() {
  local out="$1"; shift
  : > "$out"
  local pair role text
  for pair in "$@"; do
    role="${pair%%:*}"
    text="${pair#*:}"
    case "$role" in
      reject_note)
        jq -c -n --arg t "$text" \
          '{message: {role: "user", content: [{type: "tool_result", is_error: true,
            content: ("The user doesn'\''t want to proceed with this tool use. The tool use was rejected. To tell you how to proceed, the user said:\n" + $t)}]}}' \
          >> "$out"
        ;;
      reject_bare)
        jq -c -n \
          '{message: {role: "user", content: [{type: "tool_result", is_error: true,
            content: "The user doesn'\''t want to proceed with this tool use. The tool use was rejected."}]}}' \
          >> "$out"
        ;;
      *)
        jq -c -n --arg r "$role" --arg t "$text" \
          '{message: {role: $r, content: [{type: "text", text: $t}]}}' \
          >> "$out"
        ;;
    esac
  done
}

# Assemble the hook stdin payload for a transcript + session + event.
hook_input() {
  local tpath="$1" sid="$2" event="$3"
  jq -c -n --arg t "$tpath" --arg s "$sid" --arg e "$event" \
    '{transcript_path: $t, session_id: $s, hook_event_name: $e}'
}

# Full setup + run: build transcript, invoke hook, echo exit code.
capture() {
  local proj="$1" sid="$2" event="$3"; shift 3
  write_transcript "$proj/transcript.jsonl" "$@"
  local input
  input="$(hook_input "$proj/transcript.jsonl" "$sid" "$event")"
  (cd "$proj" && printf '%s' "$input" | bash "$SCRIPT")
}

# Run the hook again against the current transcript at
# $proj/transcript.jsonl (used by tests that mutate it between runs
# to check idempotency / incremental capture).
recapture() {
  local proj="$1" sid="$2" event="$3"
  local input
  input="$(hook_input "$proj/transcript.jsonl" "$sid" "$event")"
  (cd "$proj" && printf '%s' "$input" | bash "$SCRIPT")
}

# Count records in a project's corrections file (0 if file absent).
records_in() {
  local f="$1/.claude/corrections.jsonl"
  [ -f "$f" ] || { printf '0'; return; }
  wc -l < "$f" | tr -d ' '
}

# jq a field out of the Nth (1-based) record.
record_field() {
  local proj="$1" n="$2" field="$3"
  sed -n "${n}p" "$proj/.claude/corrections.jsonl" | jq -r ".$field"
}

# ---- Tests (each is a function; runner list is at the bottom) -------

test_empty_transcript_no_records() {
  local P; P="$(make_project)"
  capture "$P" "s" "Stop" >/dev/null
  assert_eq "no records" 0 "$(records_in "$P")"
}

test_no_markers_no_records() {
  local P; P="$(make_project)"
  capture "$P" "s" "PostToolUse" \
    "user:normal user message" \
    "assistant:normal reply without any marker" \
    "assistant:another reply, still no markers" >/dev/null
  assert_eq "no records" 0 "$(records_in "$P")"
}

test_one_marker_records_full_metadata() {
  local P; P="$(make_project)"
  capture "$P" "sess-one" "Stop" \
    "user:steer me" \
    "assistant:[correction] check the docs before guessing" >/dev/null
  assert_eq "record count" 1 "$(records_in "$P")"
  assert_eq "rule text" \
    "check the docs before guessing" \
    "$(record_field "$P" 1 rule)"
  assert_eq "session_id" "sess-one" "$(record_field "$P" 1 session_id)"
  assert_eq "source" "Stop" "$(record_field "$P" 1 source)"
  assert_eq "source_type" "acknowledgment" \
    "$(record_field "$P" 1 source_type)"
  local hash_hex
  hash_hex="$(record_field "$P" 1 hash)"
  assert_eq "hash is 64 hex chars" 64 "${#hash_hex}"
}

test_n_markers_records_in_order() {
  local P; P="$(make_project)"
  capture "$P" "s" "PostToolUse" \
    "assistant:[correction] rule one" \
    "assistant:normal reply between" \
    "assistant:[correction] rule two" \
    "assistant:[correction] rule three" >/dev/null
  assert_eq "three records" 3 "$(records_in "$P")"
  assert_eq "order 1" "rule one" "$(record_field "$P" 1 rule)"
  assert_eq "order 2" "rule two" "$(record_field "$P" 2 rule)"
  assert_eq "order 3" "rule three" "$(record_field "$P" 3 rule)"
}

test_duplicates_deduped_by_hash() {
  local P; P="$(make_project)"
  capture "$P" "s" "Stop" \
    "assistant:[correction] the same rule" \
    "assistant:[correction] a different rule" \
    "assistant:[correction] the same rule" >/dev/null
  assert_eq "unique records" 2 "$(records_in "$P")"
}

test_idempotency_across_invocations() {
  local P; P="$(make_project)"
  capture "$P" "s" "PostToolUse" \
    "assistant:[correction] idempotency rule" >/dev/null
  local before after
  before="$(records_in "$P")"
  recapture "$P" "s" "PostToolUse" >/dev/null
  after="$(records_in "$P")"
  assert_eq "first invocation records 1" 1 "$before"
  assert_eq "second invocation records 0 new" "$before" "$after"
}

test_incremental_capture() {
  local P; P="$(make_project)"
  capture "$P" "s" "PostToolUse" \
    "assistant:[correction] first rule" >/dev/null
  jq -c -n --arg t "[correction] second rule" \
    '{message: {role: "assistant", content: [{type: "text", text: $t}]}}' \
    >> "$P/transcript.jsonl"
  recapture "$P" "s" "PostToolUse" >/dev/null
  assert_eq "two records" 2 "$(records_in "$P")"
  assert_eq "first kept" "first rule" "$(record_field "$P" 1 rule)"
  assert_eq "second appended" "second rule" "$(record_field "$P" 2 rule)"
}

test_user_role_marker_ignored() {
  local P; P="$(make_project)"
  capture "$P" "s" "Stop" \
    "user:[correction] i typed this in a user message" \
    "assistant:[correction] this one is real" >/dev/null
  assert_eq "record count" 1 "$(records_in "$P")"
  assert_eq "only assistant recorded" \
    "this one is real" "$(record_field "$P" 1 rule)"
}

test_missing_transcript_noop() {
  local P; P="$(make_project)"
  local input
  input="$(hook_input "$P/nonexistent.jsonl" "s" "Stop")"
  (cd "$P" && printf '%s' "$input" | bash "$SCRIPT") >/dev/null
  local ec=$?
  assert_eq "hook exits 0" 0 "$ec"
  assert_eq "no records" 0 "$(records_in "$P")"
}

test_invalid_jsonl_lines_skipped() {
  local P; P="$(make_project)"
  write_transcript "$P/transcript.jsonl" \
    "assistant:[correction] before invalid"
  printf 'not a json line\n' >> "$P/transcript.jsonl"
  printf '{"message":{"role":"assistant","content":\n' \
    >> "$P/transcript.jsonl"
  jq -c -n --arg t "[correction] after invalid" \
    '{message: {role: "assistant", content: [{type: "text", text: $t}]}}' \
    >> "$P/transcript.jsonl"
  recapture "$P" "s" "PostToolUse" >/dev/null
  assert_eq "valid entries survive corruption" \
    2 "$(records_in "$P")"
}

test_empty_stdin_noop() {
  local P; P="$(make_project)"
  (cd "$P" && printf '' | bash "$SCRIPT") >/dev/null
  local ec=$?
  assert_eq "hook exits 0" 0 "$ec"
}

test_multi_line_message_marker_found() {
  local P; P="$(make_project)"
  write_transcript "$P/transcript.jsonl" \
    "assistant:first line prose
[correction] rule from a multi-line message
trailing prose"
  recapture "$P" "s" "Stop" >/dev/null
  assert_eq "marker found inside multi-line message" \
    1 "$(records_in "$P")"
  assert_eq "rule extracted correctly" \
    "rule from a multi-line message" \
    "$(record_field "$P" 1 rule)"
}

test_marker_not_at_column_zero_is_ignored() {
  local P; P="$(make_project)"
  # Three false-positive patterns from real prose that used to fire:
  # (a) marker inside a sentence, (b) marker after a bullet, (c)
  # marker inside a fenced code block indent.
  write_transcript "$P/transcript.jsonl" \
    "assistant:some prose about the [correction] marker, mid-line" \
    "assistant:- [correction] i am a bullet, not an acknowledgment" \
    "assistant:  [correction] i am indented, not at column 0" \
    "assistant:[correction] this one is real"
  recapture "$P" "s" "PostToolUse" >/dev/null
  assert_eq "only the column-0 marker is recorded" \
    1 "$(records_in "$P")"
  assert_eq "the recorded rule is the real one" \
    "this one is real" "$(record_field "$P" 1 rule)"
}

# -------- Story 9.0: rejection-note fallback capture ---------------

test_bare_rejection_no_note_is_ignored() {
  # A tool-reject with no user message ("just clicked reject") has
  # nothing to capture and must not create a record.
  local P; P="$(make_project)"
  capture "$P" "s" "Stop" \
    "assistant:some reply then a tool call" \
    "reject_bare:" >/dev/null
  assert_eq "no record" 0 "$(records_in "$P")"
}

test_rejection_with_note_and_acknowledgment_is_deduped() {
  # A rejection followed by a proper [correction] acknowledgment in
  # the assistant's next message. Only the acknowledgment is
  # recorded (path B); the raw rejection text is NOT captured
  # because the model already condensed it.
  local P; P="$(make_project)"
  capture "$P" "s" "Stop" \
    "assistant:i tried something" \
    "reject_note:less showing off. it's just ticking off - oneliner is enough" \
    "assistant:[correction] use one-line commits for trivial ticks
now i'll do it right" >/dev/null
  assert_eq "one record" 1 "$(records_in "$P")"
  assert_eq "recorded as acknowledgment (not raw rejection)" \
    "acknowledgment" "$(record_field "$P" 1 source_type)"
  assert_eq "rule text is the general rule, not the raw rejection" \
    "use one-line commits for trivial ticks" \
    "$(record_field "$P" 1 rule)"
}

test_rejection_with_note_no_acknowledgment_captured_as_fallback() {
  # A rejection with a note, but the assistant reply does NOT emit
  # a [correction] marker. Fallback path A must fire: the raw
  # rejection text is captured with source_type =
  # rejection_unacknowledged.
  local P; P="$(make_project)"
  capture "$P" "s" "Stop" \
    "assistant:i tried something" \
    "reject_note:don't do that" \
    "assistant:i see, i will try something else" >/dev/null
  assert_eq "one record" 1 "$(records_in "$P")"
  assert_eq "source_type marks the fallback path" \
    "rejection_unacknowledged" "$(record_field "$P" 1 source_type)"
  assert_eq "rule stores the raw user rejection text" \
    "don't do that" "$(record_field "$P" 1 rule)"
}

test_multiline_rejection_note_stored_verbatim() {
  # Rejection notes can be multi-line. The full text goes into the
  # `rule` field (no truncation) so /embo:improve can condense at
  # aggregation time.
  local P; P="$(make_project)"
  capture "$P" "s" "PostToolUse" \
    "assistant:i tried something" \
    "reject_note:first paragraph of feedback.

second paragraph after a blank line.
third line follows." \
    "assistant:understood, changing approach" >/dev/null
  assert_eq "one record" 1 "$(records_in "$P")"
  local rule
  rule="$(record_field "$P" 1 rule)"
  # The rule should contain all three parts and both newlines.
  case "$rule" in
    *"first paragraph"*"second paragraph"*"third line"*) PASS=$((PASS+1)) ;;
    *)
      FAIL=$((FAIL+1))
      printf 'FAIL: %s / multiline rejection stored verbatim\n  got: [%s]\n' \
        "$CURRENT_TEST" "$rule"
      ;;
  esac
}

test_rejection_lookahead_ignores_marker_after_next_user_turn() {
  # An acknowledgment counts only if it appears before the NEXT
  # genuine user prompt. A [correction] marker that lands only
  # after a user prompt (in reply to something else) does not
  # rescue the earlier rejection from fallback capture.
  local P; P="$(make_project)"
  capture "$P" "s" "Stop" \
    "assistant:i tried something" \
    "reject_note:that was wrong" \
    "assistant:i see" \
    "user:new prompt about a different topic" \
    "assistant:[correction] unrelated rule for the new topic" >/dev/null
  assert_eq "two records" 2 "$(records_in "$P")"
  # Records may be in either order in the file; assert by content.
  local content
  content="$(jq -c '{source_type, rule}' "$P/.claude/corrections.jsonl")"
  case "$content" in
    *'"source_type":"rejection_unacknowledged","rule":"that was wrong"'*)
      PASS=$((PASS+1)) ;;
    *)
      FAIL=$((FAIL+1))
      printf 'FAIL: %s / rejection captured as fallback\n  got: %s\n' \
        "$CURRENT_TEST" "$content"
      ;;
  esac
  case "$content" in
    *'"source_type":"acknowledgment","rule":"unrelated rule for the new topic"'*)
      PASS=$((PASS+1)) ;;
    *)
      FAIL=$((FAIL+1))
      printf 'FAIL: %s / later marker captured as acknowledgment for new topic\n  got: %s\n' \
        "$CURRENT_TEST" "$content"
      ;;
  esac
}

test_multiple_rejections_one_acknowledged_one_not() {
  # Two rejections in the same session. The first is acknowledged
  # in the next assistant message; the second is not. Result: one
  # acknowledgment record + one rejection_unacknowledged record.
  local P; P="$(make_project)"
  capture "$P" "s" "Stop" \
    "assistant:attempt one" \
    "reject_note:no, do it differently" \
    "assistant:[correction] do it differently rule" \
    "assistant:attempt two" \
    "reject_note:still not right" \
    "assistant:trying again without acknowledgment" >/dev/null
  assert_eq "two records" 2 "$(records_in "$P")"
  local content
  content="$(jq -c '{source_type, rule}' "$P/.claude/corrections.jsonl")"
  case "$content" in
    *'"source_type":"acknowledgment","rule":"do it differently rule"'*)
      PASS=$((PASS+1)) ;;
    *)
      FAIL=$((FAIL+1))
      printf 'FAIL: %s / first rejection acknowledged\n  got: %s\n' \
        "$CURRENT_TEST" "$content"
      ;;
  esac
  case "$content" in
    *'"source_type":"rejection_unacknowledged","rule":"still not right"'*)
      PASS=$((PASS+1)) ;;
    *)
      FAIL=$((FAIL+1))
      printf 'FAIL: %s / second rejection captured as fallback\n  got: %s\n' \
        "$CURRENT_TEST" "$content"
      ;;
  esac
}

# ---- Runner ---------------------------------------------------------

TESTS=(
  test_empty_transcript_no_records
  test_no_markers_no_records
  test_one_marker_records_full_metadata
  test_n_markers_records_in_order
  test_duplicates_deduped_by_hash
  test_idempotency_across_invocations
  test_incremental_capture
  test_user_role_marker_ignored
  test_missing_transcript_noop
  test_invalid_jsonl_lines_skipped
  test_empty_stdin_noop
  test_multi_line_message_marker_found
  test_marker_not_at_column_zero_is_ignored
  test_bare_rejection_no_note_is_ignored
  test_rejection_with_note_and_acknowledgment_is_deduped
  test_rejection_with_note_no_acknowledgment_captured_as_fallback
  test_multiline_rejection_note_stored_verbatim
  test_rejection_lookahead_ignores_marker_after_next_user_turn
  test_multiple_rejections_one_acknowledged_one_not
)

for t in "${TESTS[@]}"; do
  CURRENT_TEST="$t"
  "$t"
done

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
