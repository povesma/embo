#!/usr/bin/env bash
# Claude Code statusLine script — RLM-Mem edition
# Displays: cwd (tilde-abbreviated) | git branch | model | USED/TOTAL $cost | time
# Requires: jq (brew install jq / apt install jq)
# Install:  cp .claude/statusline.sh ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh
# settings.json: { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }

set -euo pipefail

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
    echo "[statusline: jq not found — install with: brew install jq / apt install jq]"
    exit 0
fi

# --- Current working directory (tilde-abbreviated) ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
cwd_display="${cwd/#$HOME/\~}"

# --- Git branch ---
git_branch=""
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# --- Model name ---
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')

# --- Token usage: current context (not cumulative session totals) ---
# current_usage may be null before the first API call; all fields default to 0
used=$(echo "$input" | jq -r '
    (.context_window.current_usage.input_tokens // 0) +
    (.context_window.current_usage.cache_creation_input_tokens // 0) +
    (.context_window.current_usage.cache_read_input_tokens // 0)
')

# context_window_size is the real max for the current model (200K, 1M, etc.)
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // "null"')

# --- Context usage percentage ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# --- Cost (from Claude Code's cumulative counter — accurate, no manual math) ---
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# --- Time ---
current_time=$(date +%H:%M:%S)

# --- Short-form number formatting: 1000000→1M, 200000→200K, 999→999, null→? ---
short_num() {
    local n=$1
    if [ -z "$n" ] || [ "$n" = "null" ]; then echo "?"; return; fi
    if   [ "$n" -ge 1000000 ]; then echo "$((n / 1000000))M"
    elif [ "$n" -ge 1000 ];    then echo "$((n / 1000))K"
    else echo "$n"; fi
}

used_short=$(short_num "$used")
ctx_short=$(short_num "$ctx_size")

# --- ANSI colors ---
RESET='\033[0m'
CYAN='\033[36m'
GREEN='\033[32m'
MAGENTA='\033[35m'
YELLOW='\033[33m'
BRIGHT_WHITE='\033[97m'
WHITE='\033[37m'

# --- Assemble segments ---
parts=()
parts+=("$(printf "${CYAN}%s${RESET}" "$cwd_display")")

if [ -n "$git_branch" ]; then
    parts+=("$(printf "${GREEN}%s${RESET}" "$git_branch")")
fi

parts+=("$(printf "${MAGENTA}%s${RESET}" "$model")")
parts+=("$(printf "${YELLOW}%s/%s \$%s${RESET}" "$used_short" "$ctx_short" "$(printf '%.3f' "$cost")")")
parts+=("$(printf "${BRIGHT_WHITE}ctx %s%%${RESET}" "$used_pct")")
parts+=("$(printf "${WHITE}%s${RESET}" "$current_time")")

# --- Join with separator and print ---
separator=" | "
result=""
for part in "${parts[@]}"; do
    if [ -z "$result" ]; then
        result="$part"
    else
        result="$result$separator$part"
    fi
done

printf "%b\n" "$result"
