#!/usr/bin/env bash
# install.sh — sync this repo's .claude/ files to ~/.claude/
# Run after cloning or after making changes in .claude/ to update your installation.

set -euo pipefail

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
            read -r -p "  Add statusLine to $SETTINGS? [y/N] " yn
            case "$yn" in
                [Yy]*)
                    jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}' \
                        "$SETTINGS" > /tmp/_rlm_settings.tmp \
                        && mv /tmp/_rlm_settings.tmp "$SETTINGS"
                    echo "  settings.json: statusLine added"
                    echo "  Restart Claude Code for the change to take effect."
                    ;;
                *)
                    echo "  settings.json: skipped — see README §Statusline for manual step"
                    ;;
            esac
        fi
    fi
fi

# clean up old files
if [ -d "$TARGET/commands/rlm-mem" ]; then
    echo ""
    read -r -p "  Old /rlm-mem:* commands found. Remove? [Y/n] " yn
    case "$yn" in
        [Nn]*) echo "  skipped — remove manually: rm -rf $TARGET/commands/rlm-mem" ;;
        *) rm -rf "$TARGET/commands/rlm-mem"; echo "  removed $TARGET/commands/rlm-mem" ;;
    esac
fi
if [ -f "$TARGET/hooks/docs-first-guard.sh" ]; then
    read -r -p "  Deprecated docs-first-guard hook found. Remove? [Y/n] " yn
    case "$yn" in
        [Nn]*) echo "  skipped — remove manually: rm $TARGET/hooks/docs-first-guard.sh" ;;
        *) rm "$TARGET/hooks/docs-first-guard.sh"; echo "  removed docs-first-guard.sh" ;;
    esac
fi

echo ""
echo "Done. Run /dev:start to begin a session."
