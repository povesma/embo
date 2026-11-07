#!/usr/bin/env bash
# Claude Code statusLine script — embo edition
# embo:auto-refresh — remove this line if you customize this file, to stop embo overwriting it on plugin update
# Displays: cwd (tilde-abbreviated) | git branch | model | USED/TOTAL $cost | ctx % | embo stage | mem | time
# Requires: jq (brew install jq / apt install jq)
# Install:  cp .claude/statusline.sh ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh
# settings.json: { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }

set -euo pipefail

# Library mode: when sourced with STATUSLINE_LIB_ONLY=1 (the unit tests),
# load the segment functions and colours but run no render body — so no
# stdin read, no jq gate, no output.
if [ "${STATUSLINE_LIB_ONLY:-}" != "1" ]; then
    input=$(cat)

    if ! command -v jq >/dev/null 2>&1; then
        echo "[statusline: jq not found — install with: brew install jq / apt install jq]"
        exit 0
    fi

    # --- Current working directory (tilde-abbreviated) ---
    cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
    cwd_display="${cwd/#$HOME/\~}"
fi

# --- Short-form number formatting: 1000000→1M, 200000→200K, 999→999, null→? ---
short_num() {
    local n=$1
    if [ -z "$n" ] || [ "$n" = "null" ]; then echo "?"; return; fi
    if   [ "$n" -ge 1000000 ]; then echo "$((n / 1000000))M"
    elif [ "$n" -ge 1000 ];    then echo "$((n / 1000))K"
    else echo "$n"; fi
}

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

# --- Session-stage segment (reads the per-session state file) ---
# Path comes from $HOME + the status line's stdin session_id (no git, no
# network — the state file is user-global and git-free). One jq read of
# .phase maps to a three-state label. Every failure degrades to embo:?.
# $1 is the session id.
embo_state_segment() {
    local sid="$1" base dir path phase

    # Id safety: non-empty, charset ^[A-Za-z0-9._-]+$, no `..`. A bad id
    # degrades silently so it can never build a path outside session-state/.
    if [ -z "$sid" ] || [ "${sid#*..}" != "$sid" ] \
       || [ -n "$(printf '%s' "$sid" | tr -d 'A-Za-z0-9._-')" ]; then
        printf "%b%s%b" "$RESET" "embo:?" "$RESET"
        return 0
    fi

    base="${XDG_STATE_HOME:-$HOME/.local/state}"
    dir="$base/embo/session-state"
    path="$dir/$sid.json"

    phase=""
    if [ -f "$path" ]; then
        phase=$(jq -r '.phase // ""' "$path" 2>/dev/null || true)
    fi

    case "$phase" in
        started)    printf "%b%s%b" "$GREEN" "embo:▶" "$RESET" ;;
        wrapped_up) printf "%b%s%b" "$CYAN"  "embo:✓" "$RESET" ;;
        *)          printf "%b%s%b" "$RESET" "embo:?" "$RESET" ;;
    esac
}

# --- Save the raw Claude Code stdin JSON to a per-session file ---
# Contract with the ATC consumer (do NOT change the path or the `.cc.json`
# name without telling ATC): the raw stdin blob is written, unchanged, to
# $HOME/.local/state/embo/session-state/<session_id>.cc.json so a consumer
# that sees only the screen can read structured session data by id. Raw
# (no reshaping) so embo maintains no schema. Atomic (temp + rename), 0600.
# Every failure is swallowed — this must NEVER affect the status line.
# $1 = raw stdin blob, $2 = session id.
save_cc_stdin() {
    local blob="$1" sid="$2" base dir path tmp
    [ -n "$blob" ] || return 0
    [ -n "$sid" ] || return 0
    # Same id safety as the reader: charset, no `..`.
    case "$sid" in *..*) return 0 ;; esac
    [ -z "$(printf '%s' "$sid" | tr -d 'A-Za-z0-9._-')" ] || return 0

    base="${XDG_STATE_HOME:-$HOME/.local/state}"
    dir="$base/embo/session-state"
    path="$dir/$sid.cc.json"

    mkdir -p "$dir" 2>/dev/null || return 0
    tmp="$(mktemp "$dir/.cc.XXXXXX" 2>/dev/null)" || return 0
    chmod 0600 "$tmp" 2>/dev/null || true
    if printf '%s' "$blob" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$path" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
    else
        rm -f "$tmp" 2>/dev/null || true
    fi
    return 0
}

# Everything below is the render body: it reads $input and is skipped in
# library mode (STATUSLINE_LIB_ONLY=1).
if [ "${STATUSLINE_LIB_ONLY:-}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

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

used_short=$(short_num "$used")
ctx_short=$(short_num "$ctx_size")

# --- Session id (from stdin) for the stage segment ---
session_id=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null || true)

# Save the raw stdin JSON for the ATC consumer (failures swallowed).
save_cc_stdin "$input" "$session_id"

# --- Assemble two rows ---
# Row 1 (identity): cwd + git branch — the two long items, each of which
# can fill a terminal width on its own, get their own row.
# Row 2 (metrics): model | tokens | ctx% | embo stage | mem | time.
# A plain split keeps the long items off the metrics row, so nothing is
# pushed off-screen; no COLUMNS width math is needed.
separator=" | "

# join_parts <part>... — join non-empty args with the separator.
join_parts() {
    local out="" p
    for p in "$@"; do
        [ -z "$p" ] && continue
        if [ -z "$out" ]; then out="$p"; else out="$out$separator$p"; fi
    done
    printf '%s' "$out"
}

row1="$(join_parts \
    "$(printf "${CYAN}%s${RESET}" "$cwd_display")" \
    "$([ -n "$git_branch" ] && printf "${GREEN}%s${RESET}" "$git_branch")")"

# Row 2 leads with the embo stage segment so <model> is flanked by a pipe
# on BOTH sides (`| model |`). An external consumer that matches model
# with a both-sides-pipe regex (e.g. ATC) then keeps working; model is no
# longer the first, left-pipe-less token.
row2="$(join_parts \
    "$(embo_state_segment "$session_id")" \
    "$(printf "${MAGENTA}%s${RESET}" "$model")" \
    "$(printf "${YELLOW}%s/%s \$%s${RESET}" "$used_short" "$ctx_short" "$(printf '%.3f' "$cost")")" \
    "$(printf "${BRIGHT_WHITE}ctx %s%%${RESET}" "$used_pct")" \
    "$(cmem_segment)" \
    "$(printf "${WHITE}%s${RESET}" "$current_time")")"

printf "%b\n%b\n" "$row1" "$row2"
