#!/usr/bin/env bash
# context-guard.sh — UserPromptSubmit hook
# Blocks new development work when context window usage >= threshold.
# Fails open on all errors: any unhandled path exits 0.

trap 'exit 0' ERR

THRESHOLD="${CONTEXT_GUARD_THRESHOLD:-80}"

# --- 1. Parse stdin JSON ---
STDIN_TMP=$(mktemp) || exit 0
cat > "$STDIN_TMP"
export STDIN_TMP

PARSED=$(python3 - <<'PY' 2>/dev/null
import json, os
try:
    with open(os.environ['STDIN_TMP']) as f:
        d = json.load(f)
    transcript = d.get('transcript_path', '')
    prompt = d.get('prompt', '')
    print(transcript)
    print(prompt)
except Exception:
    print()
    print()
PY
) || exit 0

rm -f "$STDIN_TMP"

TRANSCRIPT_PATH=$(echo "$PARSED" | sed -n '1p')
USER_PROMPT=$(echo "$PARSED" | tail -n +2)

[ -z "$TRANSCRIPT_PATH" ] && exit 0

# --- 2. File-size skip optimisation ---
FILE_SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null) || exit 0
[ "$FILE_SIZE" -lt 10240 ] && exit 0

# --- 3. Read last assistant line and compute usage % ---
OS=$(uname)
if [ "$OS" = "Darwin" ]; then
    LAST_ASSISTANT=$(tail -r "$TRANSCRIPT_PATH" 2>/dev/null | grep -m1 '"type": *"assistant"') || exit 0
else
    LAST_ASSISTANT=$(tac "$TRANSCRIPT_PATH" 2>/dev/null | grep -m1 '"type": *"assistant"') || exit 0
fi

[ -z "$LAST_ASSISTANT" ] && exit 0

LAST_TMP=$(mktemp) || exit 0
echo "$LAST_ASSISTANT" > "$LAST_TMP"
export LAST_TMP

USED_PCT=$(python3 - <<'PY' 2>/dev/null
import json, os
try:
    with open(os.environ['LAST_TMP']) as f:
        d = json.loads(f.read())
    cw = d.get('message', {}).get('context_window', {})
    if cw and cw.get('used_percentage') is not None:
        print(int(cw['used_percentage']))
    else:
        usage = d['message'].get('usage', {})
        inp = usage.get('input_tokens', 0)
        cc = usage.get('cache_creation_input_tokens', 0)
        cr = usage.get('cache_read_input_tokens', 0)
        total = inp + cc + cr
        ctx_size = (cw or {}).get('context_window_size', 0)
        if ctx_size and ctx_size > 0:
            print(total * 100 // ctx_size)
        else:
            print(-1)
except Exception:
    print(-1)
PY
) || exit 0

rm -f "$LAST_TMP"

[ "${USED_PCT:-0}" -lt 0 ] && exit 0

# --- 4. Threshold check ---
[ "${USED_PCT:-0}" -lt "$THRESHOLD" ] && exit 0

# --- 5. Blocklist classification ---
PROMPT_LOWER=$(echo "$USER_PROMPT" | tr '[:upper:]' '[:lower:]')
BLOCKED=0
for keyword in implement code build create write develop "add feature" \
               "start story" "begin story" "start task" "begin task" \
               refactor "fix bug" debug; do
    case "$PROMPT_LOWER" in
        *"$keyword"*) BLOCKED=1; break ;;
    esac
done

[ "$BLOCKED" -eq 0 ] && exit 0

# --- 7. Soft warn — inject warning into Claude's context via plain text stdout ---
printf '[Context Guard] ⚠️ Context is %d%% full (threshold: %d%%). Consider running /rlm-mem:develop:save (or /coding:develop:save) to wrap up this session before starting new work. You may proceed, but be aware the session may run out of context mid-task.\n' \
    "$USED_PCT" "$THRESHOLD"
