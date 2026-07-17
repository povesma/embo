#!/usr/bin/env bash
# Claude Code statusLine script — embo edition
# Displays: cwd (tilde-abbreviated) | git branch | model | USED/TOTAL $cost | ctx % | mem | time
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
RED='\033[31m'
BRIGHT_WHITE='\033[97m'
WHITE='\033[37m'

# --- Claude-mem freshness segment ---
CMEM_GREEN_MAX=10
CMEM_YELLOW_MAX=30
cmem_segment() {
    if ! command -v curl >/dev/null 2>&1; then
        printf "%b%s%b" "$RED" "mem:NOCURL" "$RESET"
        return
    fi

    # claude-mem's worker port is not fixed. It is CLAUDE_MEM_WORKER_PORT when
    # set, else 37700 + (uid % 100) (37777 fallback when uid is unavailable,
    # e.g. Windows). The env var is set in the worker's own process but is not
    # reliably inherited by the statusline, and installs pin it to different
    # values, so we probe candidate ports and use the first that answers with
    # valid JSON rather than trusting a single computed value.
    local uid formula_port candidates
    uid=$(id -u 2>/dev/null || echo "")
    if [ -n "$uid" ]; then formula_port=$(( 37700 + uid % 100 )); else formula_port=37777; fi
    # Order: explicit env override, the per-user formula, then the legacy default.
    candidates="${CLAUDE_MEM_WORKER_PORT:-} $formula_port 37777"

    local resp="" p
    for p in $candidates; do
        [ -z "$p" ] && continue
        resp=$(curl -s --max-time 2 \
            "http://127.0.0.1:${p}/api/observations?limit=1" 2>/dev/null || true)
        if [ -n "$resp" ] && echo "$resp" | jq -e . >/dev/null 2>&1; then
            break
        fi
        resp=""
    done

    if [ -z "$resp" ]; then
        printf "%b%s%b" "$RED" "mem:DOWN" "$RESET"
        return
    fi

    local epoch_ms
    epoch_ms=$(echo "$resp" | jq -r '.items[0].created_at_epoch // empty' 2>/dev/null || true)
    if [ -z "$epoch_ms" ] || [ "$epoch_ms" = "null" ]; then
        printf "%b%s%b" "$YELLOW" "mem:idle" "$RESET"
        return
    fi

    local now_ms elapsed_min
    now_ms=$(( $(date +%s 2>/dev/null || echo 0) * 1000 ))
    elapsed_min=$(( (now_ms - epoch_ms) / 60000 ))
    if [ "$elapsed_min" -lt 0 ]; then elapsed_min=0; fi

    local cmem_color
    if   [ "$elapsed_min" -le "$CMEM_GREEN_MAX" ];  then cmem_color="$GREEN"
    elif [ "$elapsed_min" -le "$CMEM_YELLOW_MAX" ]; then cmem_color="$YELLOW"
    else cmem_color="$RED"
    fi

    printf "%b%s%b" "$cmem_color" "mem:${elapsed_min}m" "$RESET"
}

# --- Assemble segments ---
parts=()
parts+=("$(printf "${CYAN}%s${RESET}" "$cwd_display")")

if [ -n "$git_branch" ]; then
    parts+=("$(printf "${GREEN}%s${RESET}" "$git_branch")")
fi

parts+=("$(printf "${MAGENTA}%s${RESET}" "$model")")
parts+=("$(printf "${YELLOW}%s/%s \$%s${RESET}" "$used_short" "$ctx_short" "$(printf '%.3f' "$cost")")")
parts+=("$(printf "${BRIGHT_WHITE}ctx %s%%${RESET}" "$used_pct")")
parts+=("$(cmem_segment)")
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
