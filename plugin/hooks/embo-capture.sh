#!/usr/bin/env bash
# embo-capture.sh — Bash output capture wrapper.
# Invoked by the PreToolUse rewrite as: embo-capture --b64 <base64-cmd>
# Runs the decoded command, tees FULL output to a per-call scratch file,
# preserves the real exit code, and prints either the output inline (when
# small) or a recognizable marker pointing at the file (when large).
# See: tasks/028-REDIRECT-ZEROPROMPT-contradiction/
#
# Inline iff captured output is <= MAX_LINES AND <= MAX_BYTES.
# Marker contract (stable — the model recognizes the prefix):
#   <first PREVIEW_LINES lines>
#   [embo-capture] truncated — <N> lines, <M> bytes. Full output:
#     <path>  (exit=<code>)
#
# Filter mode (030): embo-capture --filter-b64 <b64-filter> --b64 <b64-cmd>
# Runs the upstream alone (stdout to the log, stderr separate), then the
# filter chain over the captured stdout. The filtered view goes inline
# (same thresholds); the marker always follows and carries BOTH codes:
#   [embo-capture] filtered view — full output:
#     <path>  (<N> lines, <M> bytes, upstream exit=<EU>, filter exit=<EF>)
# Wrapper exit = filter's exit (native pipe semantics, pipefail off).

set -uo pipefail

MAX_LINES="${EMBO_CAPTURE_MAX_LINES:-10}"
MAX_BYTES="${EMBO_CAPTURE_MAX_BYTES:-300}"
PREVIEW_LINES="${EMBO_CAPTURE_PREVIEW_LINES:-5}"
SCRATCH_DIR="${EMBO_CAPTURE_DIR:-tmp/cap}"

FILTER=""
if [ "${1:-}" = "--filter-b64" ] && [ -n "${2:-}" ]; then
  FILTER="$(printf '%s' "$2" | base64 --decode 2>/dev/null)" || {
    echo "embo-capture: invalid base64 payload" >&2
    exit 64
  }
  shift 2
fi

if [ "${1:-}" != "--b64" ] || [ -z "${2:-}" ]; then
  echo "embo-capture: usage: embo-capture [--filter-b64 <base64-filter>] --b64 <base64-command>" >&2
  exit 64
fi

CMD="$(printf '%s' "$2" | base64 --decode 2>/dev/null)" || {
  echo "embo-capture: invalid base64 payload" >&2
  exit 64
}

mkdir -p "$SCRATCH_DIR" 2>/dev/null || true

# Per-call file: pid + nanoseconds (fallback to RANDOM) for uniqueness.
stamp="$(date +%s%N 2>/dev/null)"
case "$stamp" in *N|"") stamp="$(date +%s)${RANDOM}" ;; esac
LOG="$SCRATCH_DIR/cap-$$-$stamp.log"

if [ -n "$FILTER" ]; then
  # Filter mode: upstream stdout to the log, stderr kept out of the
  # filter path (a real pipe only routes stdout through the filter).
  ERRLOG="$LOG.err"
  VIEW="$LOG.view"
  bash -c "$CMD" >"$LOG" 2>"$ERRLOG"
  EU=$?
  bash -c "$FILTER" <"$LOG" >"$VIEW" 2>>"$ERRLOG"
  EF=$?

  lines=$(wc -l <"$LOG" | tr -d ' ')
  bytes=$(wc -c <"$LOG" | tr -d ' ')
  vlines=$(wc -l <"$VIEW" | tr -d ' ')
  vbytes=$(wc -c <"$VIEW" | tr -d ' ')

  if [ "$vlines" -le "$MAX_LINES" ] && [ "$vbytes" -le "$MAX_BYTES" ]; then
    cat "$VIEW"
  else
    head -n "$PREVIEW_LINES" "$VIEW"
  fi

  if [ -s "$ERRLOG" ]; then
    head -n "$PREVIEW_LINES" "$ERRLOG" >&2
    elines=$(wc -l <"$ERRLOG" | tr -d ' ')
    [ "$elines" -gt "$PREVIEW_LINES" ] && printf \
      '[embo-capture] stderr truncated — %s lines. Full: %s\n' \
      "$elines" "$ERRLOG" >&2
  fi

  printf '[embo-capture] filtered view — full output:\n'
  printf '  %s  (%s lines, %s bytes, upstream exit=%s, filter exit=%s)\n' \
    "$LOG" "$lines" "$bytes" "$EU" "$EF"
  exit "$EF"
fi

# Run the decoded command through a shell, full output to the log.
bash -c "$CMD" >"$LOG" 2>&1
EC=$?

lines=$(wc -l <"$LOG" | tr -d ' ')
bytes=$(wc -c <"$LOG" | tr -d ' ')

if [ "$lines" -le "$MAX_LINES" ] && [ "$bytes" -le "$MAX_BYTES" ]; then
  cat "$LOG"
else
  head -n "$PREVIEW_LINES" "$LOG"
  printf '[embo-capture] truncated — %s lines, %s bytes. Full output:\n' \
    "$lines" "$bytes"
  printf '  %s  (exit=%s)\n' "$LOG" "$EC"
fi

exit "$EC"
