#!/usr/bin/env bash
# session-prompt-state.sh — UserPromptSubmit hook that keeps the session
# phase honest when work resumes after a wrapup.
#
# Without this, a session that ran /embo:wrapup shows `✓` forever, even as
# the user keeps working. On the first real prompt after a wrapup the
# writer's `resume` form flips `wrapped_up` → `started`; on any other
# prompt it only touches `updated_at`. No state file → no-op (the
# SessionStart baseline should already have created one).
#
# Input: JSON on stdin with session_id (and the prompt, unused here).
# Output: none to stdout (a UserPromptSubmit hook must not inject here).
# Never fails the harness: any error exits 0.

set -u

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)" || exit 0
[ -n "$SESSION_ID" ] || exit 0

src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
hook_dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
STATE_BIN="$hook_dir/../bin/embo-session-state"

[ -x "$STATE_BIN" ] || exit 0

# The writer rejects an unsafe id with a non-zero exit; swallow it.
bash "$STATE_BIN" resume "$SESSION_ID" >/dev/null 2>&1 || exit 0

exit 0
