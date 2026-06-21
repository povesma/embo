#!/usr/bin/env bash
# uninstall.sh — remove a MANUAL embo install from ~/.claude/, any era.
#
# Covers both manual-install layouts:
#   - current  (install.sh --standalone): commands/embo/ (/embo:*),
#     agents, hooks, bin/rlm_repl + rlm_scripts/rlm_repl.py, statusline,
#     and the Bash(rlm_repl *) permission rule.
#   - pre-plugin era (old install.sh): commands/dev/ (/dev:*) and the old
#     Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*) permission rule.
# It removes the shared pieces (agents, hooks, statusline, hook
# registrations) and the era-specific pieces of whichever is present.
# Backs up settings.json before editing.
#
# This does NOT touch:
#   - the embo PLUGIN — remove that with /plugin uninstall embo@embo
#     (Claude Code's own tool); this script is for manual installs only
#   - claude-mem, bun, uv, node, jq, python (system dependencies)
#   - ~/.claude/active-profile.yaml or ~/.claude/profiles/ (user-managed)
#   - per-project .claude/rlm_state/ (local index state)
#
# Every deletion is confirmed individually. With --force the default is
# 'no' (nothing removed); --force --yes accepts all.

set -euo pipefail

FORCE=0
YES=0
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=1 ;;
        --yes|-y) YES=1 ;;
        -h|--help)
            echo "Usage: uninstall.sh [--force] [--yes]"
            echo "  Removes a standalone embo install from ~/.claude/."
            echo "  --force       non-interactive; default answer 'no'"
            echo "  --yes         with --force, accept all removals"
            exit 0 ;;
        *) echo "Usage: uninstall.sh [--force] [--yes]"; exit 1 ;;
    esac
done

confirm() {
    if [ "$FORCE" = "1" ]; then
        if [ "$YES" = "1" ]; then return 0; fi
        return 1
    fi
    local yn=""
    read -r -p "$1" yn || true
    case "${yn:-${2:-n}}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

TARGET="$HOME/.claude"
SETTINGS="$TARGET/settings.json"

echo "Removing standalone embo install from $TARGET/"
echo ""

# --- Files -----------------------------------------------------------------

# remove_path <path> <label>  — confirm, then rm -rf the path if present.
remove_path() {
    local path="$1" label="$2"
    [ -e "$path" ] || { echo "  $label: not present — skipping"; return; }
    if confirm "  Remove $label ($path)? [Y/n] " y; then
        rm -rf "$path"
        echo "  $label: removed"
    else
        echo "  $label: kept"
    fi
}

remove_path "$TARGET/commands/embo"          "embo commands (/embo:*)"
remove_path "$TARGET/commands/dev"           "pre-plugin commands (/dev:*)"
remove_path "$TARGET/agents/rlm-subcall.md"  "agent rlm-subcall"
remove_path "$TARGET/agents/examine-advisor.md"   "agent examine-advisor"
remove_path "$TARGET/agents/approach-validator.md" "agent approach-validator"
remove_path "$TARGET/bin/rlm_repl"           "rlm_repl wrapper"
remove_path "$TARGET/rlm_scripts/rlm_repl.py" "RLM script"
remove_path "$TARGET/hooks/context-guard.sh"      "hook context-guard"
remove_path "$TARGET/hooks/behavioral-reminder.sh" "hook behavioral-reminder"
remove_path "$TARGET/hooks/approve-compound.sh"   "hook approve-compound"
remove_path "$TARGET/hooks/embo-capture.sh"  "hook embo-capture (helper)"
remove_path "$TARGET/hooks/fix-hooks.sh"     "hook fix-hooks (doctor)"
remove_path "$TARGET/hooks/docs-first-guard.sh"   "hook docs-first-guard (pre-plugin, deprecated)"
remove_path "$TARGET/statusline.sh"          "statusline"

echo ""

# --- settings.json ---------------------------------------------------------
# Strip embo hook registrations and embo permission rules. Backup first.

if [ ! -f "$SETTINGS" ]; then
    echo "  settings.json: not present — nothing to clean"
elif ! command -v jq >/dev/null 2>&1; then
    echo "  settings.json: jq not found — remove embo entries by hand:"
    echo "    - hooks referencing ~/.claude/hooks/{context-guard,behavioral-reminder,approve-compound}.sh"
    echo "    - statusLine pointing at ~/.claude/statusline.sh"
    echo "    - permissions.allow entries: Bash(rlm_repl *),"
    echo "      Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*),"
    echo "      Bash(~/.claude/hooks/embo-capture.sh *)"
else
    if confirm "  Clean embo entries from $SETTINGS? [Y/n] " y; then
        cp "$SETTINGS" "$SETTINGS.embo-backup"
        echo "  settings.json: backed up to $SETTINGS.embo-backup"
        # Remove hook entries whose command references an embo hook script;
        # drop now-empty hook groups; drop the embo statusLine; drop embo
        # permission rules. Each filter is null-safe with // {} / // [].
        jq '
          def embo_cmd: (.command? // "")
            | test("context-guard\\.sh|behavioral-reminder\\.sh|approve-compound\\.sh");
          (.hooks // {}) as $h
          | .hooks = (
              $h | to_entries
              | map(.value = (.value
                  | map(.hooks = ((.hooks // []) | map(select(embo_cmd | not))))
                  | map(select((.hooks // []) | length > 0))))
              | map(select((.value | length) > 0))
              | from_entries)
          | (if (.statusLine.command? // "") | test("~/\\.claude/statusline\\.sh|statusline\\.sh")
               then del(.statusLine) else . end)
          | (if .permissions.allow then
               .permissions.allow |= map(select(
                 . != "Bash(rlm_repl *)"
                 and . != "Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)"
                 and . != "Bash(~/.claude/hooks/embo-capture.sh *)"))
             else . end)
        ' "$SETTINGS" > /tmp/_embo_uninstall.tmp \
            && mv /tmp/_embo_uninstall.tmp "$SETTINGS"
        echo "  settings.json: embo hooks, statusLine, and permission rules removed"
    else
        echo "  settings.json: left unchanged"
    fi
fi

echo ""
echo "Done. Restart Claude Code. Kept: profiles, active-profile.yaml,"
echo "claude-mem, and system dependencies (bun/uv/node/jq/python)."
echo "If you also installed the embo plugin: /plugin uninstall embo@embo."
