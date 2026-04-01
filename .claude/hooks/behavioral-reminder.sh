#!/usr/bin/env bash
# behavioral-reminder.sh — UserPromptSubmit hook
# Classifies the incoming user prompt and injects rule tag reminders
# into Claude's context before each response.
# Fails open: any error path exits 0 silently.

trap 'exit 0' ERR

# --- Disable switch ---
[ "${BEHAVIORAL_REMINDER_DISABLED:-0}" = "1" ] && exit 0

# --- Parse stdin ---
PROMPT_RAW=$(jq -r '.prompt // ""' 2>/dev/null) || exit 0
PROMPT_LOWER=$(printf '%s' "$PROMPT_RAW" | tr '[:upper:]' '[:lower:]')

# --- Classification flags ---
CRITICISM=0
IMPL_REQUEST=0
GIT_REQUEST=0

# CRITICISM patterns — triggers WITHSTAND-CRITICISM + CHALLENGE-INSTRUCTION
case "$PROMPT_LOWER" in
    *"you're wrong"*|*"youre wrong"*|*"that's not right"*|\
    *"thats not right"*|*"why did you"*|*"you missed"*|\
    *"i disagree"*|*"incorrect"*|*"you ignored"*|\
    *"you should have"*|*"that's incorrect"*|*"thats incorrect"*)
        CRITICISM=1 ;;
esac

# IMPL_REQUEST patterns — triggers DOCS-FIRST + ONE-SUBTASK
case "$PROMPT_LOWER" in
    *"implement"*|*"write the code"*|*"create the file"*|\
    *"add feature"*|*"start task"*|*"start story"*|\
    *"next subtask"*|*"next task"*)
        IMPL_REQUEST=1 ;;
esac

# GIT_REQUEST patterns — triggers GIT-SKILL
case "$PROMPT_LOWER" in
    *"git commit"*|*"git push"*|*"git add"*|*"git merge"*|\
    *"open a pr"*|*"create a pr"*|*"make a pr"*|*"submit a pr"*|\
    *"open a pull request"*|*"create a pull request"*|\
    *"commit my changes"*|*"commit these changes"*|\
    *"push the branch"*|*"push my branch"*)
        GIT_REQUEST=1 ;;
esac

# --- Build additionalContext ---
BASELINE="[RULES ACTIVE: CHALLENGE-INSTRUCTION · WITHSTAND-CRITICISM · DOCS-FIRST · ONE-SUBTASK · GIT-SKILL]"

REMINDER="$BASELINE"

if [ "$CRITICISM" = "1" ]; then
    REMINDER="$REMINDER
[REMINDER:WITHSTAND-CRITICISM][REMINDER:CHALLENGE-INSTRUCTION] Criticism or challenge detected — assess it before responding. See <!-- RULE:WITHSTAND-CRITICISM --> in dev:start and <!-- RULE:CHALLENGE-INSTRUCTION --> in dev:impl."
fi

if [ "$IMPL_REQUEST" = "1" ]; then
    REMINDER="$REMINDER
[REMINDER:DOCS-FIRST][REMINDER:ONE-SUBTASK] Implementation request detected — check the task list first, then implement one subtask at a time. See <!-- RULE:DOCS-FIRST --> and <!-- RULE:ONE-SUBTASK --> in dev:impl."
fi

if [ "$GIT_REQUEST" = "1" ]; then
    REMINDER="$REMINDER
[REMINDER:GIT-SKILL] Git or PR operation detected — use the /dev:git skill, do not run git/gh commands directly. See <!-- RULE:GIT-SKILL --> in dev:git."
fi

# --- Output JSON ---
jq -n --arg ctx "$REMINDER" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $ctx
    }
}'
