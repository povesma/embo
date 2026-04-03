#!/usr/bin/env bash
# install.sh — sync this repo's .claude/ files to ~/.claude/
# Run after cloning or after making changes in .claude/ to update your installation.

set -euo pipefail

FORCE=0
YES=0
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=1 ;;
        --yes|-y) YES=1 ;;
        *) echo "Usage: install.sh [--force] [--yes]"; exit 1 ;;
    esac
done

SKIPPED=0

# confirm "prompt" [default]
# $2 = interactive default when user presses Enter: "y" or "n" (default: "n")
# Interactive: shows prompt, reads input, uses $2 on empty Enter.
# --force alone: skips prompt, returns 1 (no) — safe non-interactive default.
# --force --yes: skips prompt, returns 0 (yes) — auto-accept all.
confirm() {
    if [ "$FORCE" = "1" ]; then
        if [ "$YES" = "1" ]; then return 0; fi
        SKIPPED=$((SKIPPED + 1))
        return 1
    fi
    local yn=""
    read -r -p "$1" yn || true
    # Empty input -> fall back to $2 (per-prompt default); if $2 absent -> "n"
    case "${yn:-${2:-n}}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude"

echo "Syncing from $REPO_DIR/.claude/ to $TARGET/"

# agents
mkdir -p "$TARGET/agents"
cp "$REPO_DIR/.claude/agents/"*.md "$TARGET/agents/"
echo "  agents: $(ls "$REPO_DIR/.claude/agents/"*.md | wc -l | tr -d ' ') files"

# commands/dev
mkdir -p "$TARGET/commands/dev"
cp -r "$REPO_DIR/.claude/commands/dev/"* "$TARGET/commands/dev/"
echo "  commands/dev: synced"

# profiles
mkdir -p "$TARGET/profiles"
cp "$REPO_DIR/.claude/profiles/"*.yaml "$TARGET/profiles/"
echo "  profiles: $(ls "$REPO_DIR/.claude/profiles/"*.yaml | wc -l | tr -d ' ') files"

# hooks
if ls "$REPO_DIR/.claude/hooks/"*.sh 2>/dev/null | grep -q .; then
    mkdir -p "$TARGET/hooks"
    cp "$REPO_DIR/.claude/hooks/"*.sh "$TARGET/hooks/"
    chmod +x "$TARGET/hooks/"*.sh
    echo "  hooks: $(ls "$REPO_DIR/.claude/hooks/"*.sh | wc -l | tr -d ' ') files"
fi

# rlm_scripts
mkdir -p "$TARGET/rlm_scripts"
cp "$REPO_DIR/.claude/rlm_scripts/"*.py "$TARGET/rlm_scripts/"
echo "  rlm_scripts: $(ls "$REPO_DIR/.claude/rlm_scripts/"*.py | wc -l | tr -d ' ') files"

# statusline
if [ -f "$REPO_DIR/.claude/statusline.sh" ]; then
    cp "$REPO_DIR/.claude/statusline.sh" "$TARGET/statusline.sh"
    chmod +x "$TARGET/statusline.sh"
    echo "  statusline: copied to $TARGET/statusline.sh"

    SETTINGS="$TARGET/settings.json"
    if ! command -v jq >/dev/null 2>&1; then
        echo ""
        echo "  statusline settings.json: jq not found — manual step required"
        echo "    Install jq:  brew install jq   (macOS)"
        echo "                 apt install jq    (Linux)"
        echo "    Then add to $SETTINGS:"
        echo '    { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }'
    else
        if [ ! -f "$SETTINGS" ]; then
            echo '{}' > "$SETTINGS"
        fi
        if jq -e '.statusLine' "$SETTINGS" > /dev/null 2>&1; then
            echo "  settings.json: statusLine already configured — skipping"
            echo "    (run /statusline-setup to switch scripts)"
        else
            echo ""
            if confirm "  Add statusLine to $SETTINGS? [Y/n] " y; then
                jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}' \
                    "$SETTINGS" > /tmp/_rlm_settings.tmp \
                    && mv /tmp/_rlm_settings.tmp "$SETTINGS"
                echo "  settings.json: statusLine added"
                echo "  Restart Claude Code for the change to take effect."
            else
                echo "  settings.json: skipped — see README §Statusline for manual step"
            fi
        fi
    fi
fi

# behavioral-reminder hook — register in settings.json
if [ -f "$TARGET/hooks/behavioral-reminder.sh" ]; then
    SETTINGS="$TARGET/settings.json"
    if ! command -v jq >/dev/null 2>&1; then
        echo ""
        echo "  behavioral-reminder: jq not found — manual step required"
        echo "    Add to $SETTINGS under hooks.UserPromptSubmit:"
        echo '    {"hooks":[{"type":"command","command":"bash ~/.claude/hooks/behavioral-reminder.sh"}]}'
    else
        if [ ! -f "$SETTINGS" ]; then
            echo '{}' > "$SETTINGS"
        fi
        if jq -e '[.hooks.UserPromptSubmit[]?.hooks[]?.command] | any(. != null and contains("behavioral-reminder"))' \
            "$SETTINGS" > /dev/null 2>&1; then
            echo "  settings.json: behavioral-reminder already registered — skipping"
        else
            jq '.hooks.UserPromptSubmit += [{"hooks": [{"type": "command",
                "command": "bash ~/.claude/hooks/behavioral-reminder.sh"}]}]' \
                "$SETTINGS" > /tmp/_rlm_settings.tmp \
                && mv /tmp/_rlm_settings.tmp "$SETTINGS"
            echo "  settings.json: behavioral-reminder hook registered"
        fi
    fi
fi

# clean up old files
if [ -d "$TARGET/commands/rlm-mem" ]; then
    echo ""
    if confirm "  Old /rlm-mem:* commands found. Remove? [Y/n] " y; then
        rm -rf "$TARGET/commands/rlm-mem"; echo "  removed $TARGET/commands/rlm-mem"
    else
        echo "  skipped — remove manually: rm -rf $TARGET/commands/rlm-mem"
    fi
fi
if [ -f "$TARGET/hooks/docs-first-guard.sh" ]; then
    if confirm "  Deprecated docs-first-guard hook found. Remove? [Y/n] " y; then
        rm "$TARGET/hooks/docs-first-guard.sh"; echo "  removed docs-first-guard.sh"
    else
        echo "  skipped — remove manually: rm $TARGET/hooks/docs-first-guard.sh"
    fi
fi

if [ "$SKIPPED" -gt 0 ]; then
    echo ""
    echo "  $SKIPPED prompt(s) skipped with default answer 'no' (--force without --yes)."
    echo "  To accept all: bash install.sh --force --yes"
    echo "  To choose interactively: bash install.sh  (in a real terminal)"
fi

echo ""
echo "Done. Run /dev:start to begin a session, or /dev:init for a new project."
