#!/usr/bin/env bash
# capture-correction.sh - hook script that records "[correction]"
# markers emitted by the model to a project-local
# .claude/corrections.jsonl file.
#
# Wired via plugin/hooks/hooks.json to both PostToolUse (primary,
# catches mid-turn markers before any interrupt) and Stop (final
# sweep at end-of-turn). Idempotent: markers whose content hash
# already appears in the JSONL file are not re-recorded.
#
# Input: JSON on stdin with fields:
#   - transcript_path: path to the session transcript (JSONL)
#   - session_id:      current session id
#   - hook_event_name: which event fired this run
#
# Behavior:
#   1. Extract the three fields from stdin.
#   2. Read the transcript, filter to role=assistant messages.
#   3. For each text block in an assistant message, find every line
#      containing "[correction] <rule>" and extract the rule.
#   4. sha256 the trimmed rule text.
#   5. Append a JSONL record for each hash NOT already in the file.
#
# Never fails the harness. Any error (missing transcript, bad JSON,
# missing tools) exits 0 after logging to stderr.

set -u

log_err() { printf '[capture-correction] %s\n' "$*" >&2; }

# Portable sha256: prefer shasum (macOS default), then sha256sum.
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    log_err "no sha256 tool available (shasum / sha256sum)"
    printf ''
  fi
}

# Read stdin; empty is a valid no-op.
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  exit 0
fi

# Parse fields; unparseable input is a no-op.
if ! TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)"; then
  log_err "unparseable stdin JSON"
  exit 0
fi
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)"
EVENT_NAME="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)"

# Missing transcript is a no-op.
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

OUT_DIR=".claude"
OUT_FILE="$OUT_DIR/corrections.jsonl"
mkdir -p "$OUT_DIR" 2>/dev/null || {
  log_err "cannot create $OUT_DIR in $(pwd)"
  exit 0
}
touch "$OUT_FILE" 2>/dev/null || {
  log_err "cannot create $OUT_FILE"
  exit 0
}

# Load already-recorded hashes into a file-based set (bash 3.2 on
# macOS has no associative arrays; the JSONL file is small in
# practice so this is fine).
SEEN_FILE="$(mktemp 2>/dev/null || printf '%s' "/tmp/capture-correction-seen.$$")"
: > "$SEEN_FILE"
trap 'rm -f "$SEEN_FILE"' EXIT

while IFS= read -r line; do
  [ -z "$line" ] && continue
  h="$(printf '%s' "$line" | jq -r '.hash // ""' 2>/dev/null)"
  [ -n "$h" ] && printf '%s\n' "$h" >> "$SEEN_FILE"
done < "$OUT_FILE"

already_seen() { grep -Fxq "$1" "$SEEN_FILE"; }
mark_seen()    { printf '%s\n' "$1" >> "$SEEN_FILE"; }

# Emit each assistant-message line that STARTS with "[correction] "
# as one line on stdout. The start-of-line anchor is load-bearing:
# it prevents docs prose, examples, and quoted mentions of the
# marker (like this comment) from being captured as corrections.
# Only a line whose first character is `[` counts.
#
# Reads the transcript line by line (unparseable lines silently
# skipped), extracts assistant text blocks, and greps for anchored
# markers within each block. Multi-line messages are handled
# because jq -r emits embedded newlines and grep sees each line.
emit_marker_lines() {
  local tline text
  while IFS= read -r tline; do
    [ -z "$tline" ] && continue
    text="$(printf '%s' "$tline" | jq -r '
      select(.message.role == "assistant") |
      .message.content // [] |
      map(select(.type == "text") | .text) |
      .[]
    ' 2>/dev/null)" || continue
    [ -z "$text" ] && continue
    printf '%s\n' "$text" | grep -E '^\[correction\] ' || true
  done < "$TRANSCRIPT_PATH"
}

now_iso() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

# Append one record to OUT_FILE with the given rule text and
# source_type, hashing + deduping via the SEEN_FILE set.
append_record() {
  local rule="$1" source_type="$2"
  [ -z "$rule" ] && return
  local hash_hex
  hash_hex="$(sha256_of "$rule")"
  [ -z "$hash_hex" ] && return
  already_seen "$hash_hex" && return
  mark_seen "$hash_hex"
  jq -c -n \
    --arg ts "$(now_iso)" \
    --arg sid "$SESSION_ID" \
    --arg rule "$rule" \
    --arg hash "$hash_hex" \
    --arg src "$EVENT_NAME" \
    --arg st "$source_type" \
    '{ts: $ts, session_id: $sid, rule: $rule, hash: $hash, source: $src, source_type: $st}' \
    >> "$OUT_FILE"
}

# --- Pass 1: acknowledgment markers ---------------------------------
#
# For each marker line: extract the rule, hash it, append if new.
emit_marker_lines | while IFS= read -r bline; do
  case "$bline" in
    "[correction] "*)
      # Rule = everything after the leading "[correction] ".
      rule="${bline#'[correction] '}"
      # Strip leading/trailing whitespace.
      rule="$(printf '%s' "$rule" | awk '{$1=$1; print}')"
      append_record "$rule" "acknowledgment"
      ;;
  esac
done

# --- Pass 2: unacknowledged rejection-note fallback -----------------
#
# For each tool_result rejection that carries a user note ("To tell
# you how to proceed, the user said:\n<msg>"), look at the assistant
# messages that follow it — up to but not including the next genuine
# user prompt (role=user with content type != tool_result). If any
# of those assistant messages contains a "^[correction] " line, the
# model already condensed the steer via path B; skip. Otherwise
# capture the raw user note as a `rejection_unacknowledged` record.
#
# The lookahead is done at end-of-pass by walking the transcript
# with a small awk program that groups messages by their position
# and knows about the three shapes involved. jq is used to
# extract the structured content; awk drives the walk.
#
# Implementation: for each rejection-note entry, we spool the whole
# transcript into memory as an array of {kind, text} records, then
# scan forward from the rejection's index until either (a) we find
# a "[correction] " line at the start of an assistant text block —
# suppress capture — or (b) we hit a genuine user prompt or EOF —
# capture.
# Temp file used by pass 2 to hold the transcript classification.
# Declared at file scope so its cleanup trap doesn't fight with the
# SEEN_FILE trap and so `set -u` doesn't see an unbound var at exit.
CLASSIFY_FILE="$(mktemp 2>/dev/null || printf '%s' "/tmp/capture-correction-classify.$$")"
: > "$CLASSIFY_FILE"
trap 'rm -f "$SEEN_FILE" "$CLASSIFY_FILE"' EXIT

walk_transcript_for_rejections() {
  # Build a temp file listing every transcript entry classified as
  # one of:
  #   ACK                 -- an assistant message that contains a
  #                          start-of-line [correction] marker.
  #                          Acts as the acknowledgment sentinel
  #                          for a preceding REJECT_NOTE.
  #   ASSIST_NOACK        -- an assistant text message with no
  #                          marker (skipped over during lookahead)
  #   USER_PROMPT         -- a genuine user typed prompt (role=user,
  #                          content type=text). Marks a boundary.
  #   USER_TOOLRES_OK     -- a tool_result that is NOT a rejection
  #                          (an ordinary tool output). NOT a
  #                          boundary; the next assistant message
  #                          is still a reply to whatever came
  #                          before.
  #   REJECT_BARE         -- a tool_result rejection with no user
  #                          note. NOT a boundary; skipped over.
  #   REJECT_NOTE\t<txt>  -- a tool_result rejection WITH a user
  #                          note. Interesting entry; <txt> is the
  #                          user's note (newlines encoded as \n).
  : > "$CLASSIFY_FILE"

  local tline
  while IFS= read -r tline; do
    [ -z "$tline" ] && continue
    # Classify via one jq call per line.
    printf '%s' "$tline" | jq -r --arg marker "[correction] " '
      def txt_from_content:
        (.content // [])
        | map(select(.type == "text") | .text)
        | join("\n");

      def toolres_from_content:
        (.content // [])
        | map(select(.type == "tool_result"))
        | .[0] // null;

      if .message.role == "assistant" then
        (.message | txt_from_content) as $t |
        # An acknowledgment counts if the text either BEGINS with
        # the marker or has an embedded line that begins with it.
        if ($t | test("(^|\\n)\\[correction\\] "))
        then "ACK"
        else "ASSIST_NOACK"
        end
      elif .message.role == "user" then
        (.message | toolres_from_content) as $tr |
        if $tr == null then
          # Regular typed user prompt (content type=text) -> boundary.
          "USER_PROMPT"
        else
          # A tool_result. Rejection or ordinary?
          if ($tr.is_error // false) then
            # Rejection. Note present?
            ($tr.content // "") as $c |
            if ($c | test("To tell you how to proceed, the user said:\\n")) then
              # REJECT_NOTE\t<json-encoded note text> so newlines
              # inside the note do not break line-oriented reading.
              ($c | sub("^.*To tell you how to proceed, the user said:\\n"; ""))
              | "REJECT_NOTE\t" + (. | @json)
            else
              "REJECT_BARE"
            end
          else
            "USER_TOOLRES_OK"
          end
        end
      else
        empty
      end
    ' 2>/dev/null || true
  done < "$TRANSCRIPT_PATH" > "$CLASSIFY_FILE"

  # Now walk CLASSIFY_FILE. For each REJECT_NOTE, look ahead for an
  # ACK before a USER_PROMPT or EOF. If none, capture the note.
  # The note text was emitted as a JSON string (via jq @json) so
  # embedded newlines do not break line-oriented reading; we decode
  # it back with jq before hashing/recording.
  local -a kinds notes
  local idx=0
  while IFS= read -r cline; do
    kinds[$idx]="${cline%%$'\t'*}"
    if [ "${kinds[$idx]}" = "REJECT_NOTE" ]; then
      # cline after the tab is a JSON-quoted string; decode it.
      notes[$idx]="$(printf '%s' "${cline#*$'\t'}" | jq -r . 2>/dev/null)"
    else
      notes[$idx]=""
    fi
    idx=$((idx + 1))
  done < "$CLASSIFY_FILE"

  local total=$idx i j found_ack
  for (( i=0; i<total; i++ )); do
    if [ "${kinds[$i]}" = "REJECT_NOTE" ]; then
      found_ack=0
      for (( j=i+1; j<total; j++ )); do
        case "${kinds[$j]}" in
          ACK) found_ack=1; break ;;
          USER_PROMPT) break ;;
          *) ;;  # ASSIST_NOACK, USER_TOOLRES_OK, REJECT_BARE — skip
        esac
      done
      if [ "$found_ack" -eq 0 ]; then
        # Capture the raw user note as a fallback.
        append_record "${notes[$i]}" "rejection_unacknowledged"
      fi
    fi
  done
}

walk_transcript_for_rejections

exit 0
