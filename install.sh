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

# commands/rlm-mem
mkdir -p "$TARGET/commands/rlm-mem"
cp -r "$REPO_DIR/.claude/commands/rlm-mem/"* "$TARGET/commands/rlm-mem/"
echo "  commands/rlm-mem: synced"

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

echo ""
echo "Done. Run /rlm-mem:discover:start to begin a session."
