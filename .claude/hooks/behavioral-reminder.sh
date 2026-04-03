#!/usr/bin/env bash
# behavioral-reminder.sh — UserPromptSubmit hook
# Classifies the incoming user prompt via awk weighted keyword scoring (AWSK)
# and injects rule tag reminders into Claude's context before each response.
# Fails open: any error path exits 0 silently.
# See: tasks/015-behavioral-reminder-hook/awsk-research.md

trap 'exit 0' ERR

# --- Disable switch ---
[ "${BEHAVIORAL_REMINDER_DISABLED:-0}" = "1" ] && exit 0

# --- Parse stdin ---
PROMPT_RAW=$(jq -r '.prompt // ""' 2>/dev/null) || exit 0

# --- AWSK classification (awk weighted keyword scoring, ~7ms) ---
# Each category has weighted keywords and a threshold.
# Negative patterns subtract score to reduce false positives.
# Word boundaries are simulated by padding input with spaces.
read -r CRITICISM IMPL_REQUEST GIT_REQUEST <<< "$(
  printf ' %s ' "$PROMPT_RAW" | tr '[:upper:]' '[:lower:]' | awk '
  {
    line = $0

    # --- CRITICISM (threshold: 2) ---
    c = 0
    if (index(line, "you'\''re wrong"))   c += 3
    if (index(line, "youre wrong"))        c += 3
    if (index(line, "that'\''s not right")) c += 3
    if (index(line, "thats not right"))    c += 3
    if (index(line, "that'\''s incorrect")) c += 3
    if (index(line, "thats incorrect"))    c += 3
    if (index(line, "you missed"))         c += 3
    if (index(line, "you ignored"))        c += 3
    if (index(line, "you should have"))    c += 3
    if (index(line, "i disagree"))         c += 2
    if (index(line, " incorrect"))         c += 2
    if (index(line, "why did you"))        c += 2
    if (index(line, " wrong "))            c += 1
    if (index(line, "not what i"))         c += 2
    if (index(line, "that'\''s wrong"))    c += 3
    if (index(line, "thats wrong"))        c += 3
    if (index(line, "no, "))               c += 1
    if (index(line, "nope"))               c += 1
    if (index(line, "bad approach"))       c += 2
    if (index(line, "not correct"))        c += 2

    # --- IMPL_REQUEST (threshold: 2) ---
    i = 0
    if (index(line, " implement"))         i += 3
    if (index(line, "write the code"))     i += 3
    if (index(line, "create the file"))    i += 3
    if (index(line, "add feature"))        i += 3
    if (index(line, "start task"))         i += 3
    if (index(line, "start story"))        i += 3
    if (index(line, "next subtask"))       i += 3
    if (index(line, "next task"))          i += 3
    if (index(line, "build the"))          i += 2
    if (index(line, "code this"))          i += 2
    if (index(line, "write code"))         i += 2
    if (index(line, "add the "))           i += 1
    if (index(line, "create a "))          i += 1
    if (index(line, " feature"))           i += 1
    # negative: "do not implement" / "don'\''t implement"
    if (index(line, "do not implement"))   i -= 4
    if (index(line, "don'\''t implement")) i -= 4

    # --- GIT_REQUEST (threshold: 2) ---
    g = 0
    if (index(line, "git commit"))         g += 3
    if (index(line, "git push"))           g += 3
    if (index(line, "git add"))            g += 3
    if (index(line, "git merge"))          g += 3
    if (index(line, " commit"))            g += 2
    if (index(line, " push"))              g += 1
    if (index(line, "pull request"))       g += 3
    if (index(line, " pr "))               g += 2
    if (index(line, "open a pr"))          g += 3
    if (index(line, "create a pr"))        g += 3
    if (index(line, "make a pr"))          g += 3
    if (index(line, "submit a pr"))        g += 3
    if (index(line, "merge request"))      g += 3
    if (index(line, " branch"))            g += 1
    if (index(line, " staged"))            g += 2
    if (index(line, " stash"))             g += 2
    # negative: "committed to" = dedication, not git
    if (index(line, "committed to"))       g -= 3
    if (index(line, "push back"))          g -= 2
    if (index(line, "push for"))           g -= 2

    # --- Apply thresholds ---
    printf "%d %d %d", (c >= 2 ? 1 : 0), (i >= 2 ? 1 : 0), (g >= 2 ? 1 : 0)
  }'
)"

# --- Build additionalContext ---
BASELINE="[RULES ACTIVE: CHALLENGE-INSTRUCTION · WITHSTAND-CRITICISM · DOCS-FIRST · ONE-SUBTASK · DEV-GIT]"

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
[REMINDER:DEV-GIT] Git or PR operation detected — use the /dev:git skill, do not run git/gh commands directly. See <!-- RULE:DEV-GIT --> in dev:git."
fi

# --- Output JSON ---
jq -n --arg ctx "$REMINDER" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: $ctx
    }
}'
