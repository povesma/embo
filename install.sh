#!/usr/bin/env bash
# install.sh — embo dependency installer (default) and manual standalone
# installer (--standalone).
#
# RECOMMENDED INSTALL IS THE PLUGIN, not this script. Inside Claude Code:
#   /plugin marketplace add povesma/embo
#   /plugin install embo@embo
#   /plugin install claude-mem      (from thedotmack/claude-mem)
# The plugin still needs the system dependencies below, so run this script
# in its default mode to get them, then install the plugins.
#
# Modes:
#   bash install.sh               Install/verify dependencies only
#                                 (Python, Node, jq, bun, uv). Use this
#                                 with the plugin install.
#   bash install.sh --standalone  Dependencies, THEN copy embo into
#                                 ~/.claude/ as a manual (no-plugin)
#                                 install. For developers who clone and
#                                 tweak embo. Do NOT combine standalone
#                                 with the plugin — they register the same
#                                 hooks and commands and would collide.
#                                 Remove a standalone install with
#                                 uninstall.sh.
#
# Flags: --standalone, --force/-f (non-interactive, default 'no'),
#        --yes/-y (with --force: auto-accept all prompts).

set -euo pipefail

STANDALONE=0
FORCE=0
YES=0
for arg in "$@"; do
    case "$arg" in
        --standalone) STANDALONE=1 ;;
        --force|-f) FORCE=1 ;;
        --yes|-y) YES=1 ;;
        -h|--help)
            echo "Usage: install.sh [--standalone] [--force] [--yes]"
            echo "  (no flag)     install/verify dependencies only"
            echo "  --standalone  also copy embo into ~/.claude/ (manual install)"
            echo "  --force       non-interactive; skip prompts (default: no)"
            echo "  --yes         with --force, auto-accept all prompts"
            exit 0 ;;
        *) echo "Usage: install.sh [--standalone] [--force] [--yes]"; exit 1 ;;
    esac
done

SKIPPED=0

# confirm "prompt" [default]
# $2 = interactive default when user presses Enter: "y" or "n" (default: "n")
# --force alone: skips prompt, returns 1 (no). --force --yes: returns 0 (yes).
confirm() {
    if [ "$FORCE" = "1" ]; then
        if [ "$YES" = "1" ]; then return 0; fi
        SKIPPED=$((SKIPPED + 1))
        return 1
    fi
    local yn=""
    read -r -p "$1" yn || true
    case "${yn:-${2:-n}}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO_DIR/plugin"
TARGET="$HOME/.claude"

# Pick the platform package manager for the optional jq install.
PKG_INSTALL=""
if command -v brew >/dev/null 2>&1; then
    PKG_INSTALL="brew install"
elif command -v apt-get >/dev/null 2>&1; then
    PKG_INSTALL="sudo apt-get install -y"
elif command -v dnf >/dev/null 2>&1; then
    PKG_INSTALL="sudo dnf install -y"
fi

DEPS_MISSING=0   # set when a required runtime is absent and not installable here

# ---------------------------------------------------------------------------
# Dependency mode (always runs)
# ---------------------------------------------------------------------------

echo "embo dependencies"
echo ""

# Python 3.8-3.12 — required by RLM. Report only; installing a language
# runtime system-wide is intrusive and can conflict with pyenv/asdf.
if command -v python3 >/dev/null 2>&1; then
    PYV="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "?")"
    echo "  python3: found ($PYV)  [RLM needs 3.8-3.12; 3.13+ breaks ChromaDB]"
else
    echo "  python3: MISSING — required by RLM."
    echo "    macOS:  brew install python@3.12"
    echo "    Linux:  sudo apt-get install python3"
    DEPS_MISSING=1
fi

# Node.js 20+ — required by claude-mem. Report only (same reasoning).
if command -v node >/dev/null 2>&1; then
    NODEV="$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
    if [ -n "$NODEV" ] && [ "$NODEV" -ge 20 ] 2>/dev/null; then
        echo "  node: found (v$(node -v | sed 's/^v//'))  [claude-mem needs 20+]"
    else
        echo "  node: found but < 20 — claude-mem needs Node 20+. Upgrade Node."
        DEPS_MISSING=1
    fi
else
    echo "  node: MISSING — required by claude-mem."
    echo "    macOS:  brew install node"
    echo "    Linux:  see https://nodejs.org (or nvm); needs v20+"
    DEPS_MISSING=1
fi

# jq — required by hooks/statusline. Small tool; offer to install.
if command -v jq >/dev/null 2>&1; then
    echo "  jq: found"
else
    if [ -n "$PKG_INSTALL" ] && confirm "  jq missing. Install with '$PKG_INSTALL jq'? [Y/n] " y; then
        $PKG_INSTALL jq && echo "  jq: installed"
    else
        echo "  jq: MISSING — needed by hooks/statusline. Install: $PKG_INSTALL jq"
        DEPS_MISSING=1
    fi
fi

# uv — Python package manager claude-mem uses. claude-mem is supposed to
# auto-install it; in practice that does not always fire, so offer it here.
if command -v uv >/dev/null 2>&1; then
    echo "  uv: found"
else
    if confirm "  uv missing. Install via astral.sh installer? [Y/n] " y; then
        curl -LsSf https://astral.sh/uv/install.sh | sh \
            && echo "  uv: installed to ~/.local/bin (add it to PATH — see end)"
    else
        echo "  uv: skipped — install later: curl -LsSf https://astral.sh/uv/install.sh | sh"
    fi
fi

# bun — JS runtime claude-mem uses. claude-mem is documented to auto-install
# bun, but it frequently does not, so install it here.
if command -v bun >/dev/null 2>&1; then
    echo "  bun: found"
else
    if confirm "  bun missing. Install via bun.com installer? [Y/n] " y; then
        curl -fsSL https://bun.com/install | bash \
            && echo "  bun: installed to ~/.bun/bin (add it to PATH — see end)"
    else
        echo "  bun: skipped — install later: curl -fsSL https://bun.com/install | bash"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Standalone mode (only with --standalone): copy embo into ~/.claude/
# ---------------------------------------------------------------------------

if [ "$STANDALONE" = "1" ]; then
    if [ ! -d "$SRC" ]; then
        echo "ERROR: $SRC not found. Run --standalone from the embo repo root." >&2
        exit 1
    fi

    echo "Standalone install: syncing from $SRC/ to $TARGET/"

    # 1. RLM script + the bin/ wrapper that runs it as a plain `rlm_repl`.
    #    The wrapper resolves rlm_repl.py as ../rlm_scripts/rlm_repl.py
    #    relative to itself, so bin/ and rlm_scripts/ must be siblings.
    mkdir -p "$TARGET/rlm_scripts" "$TARGET/bin"
    cp "$SRC/rlm_scripts/rlm_repl.py" "$TARGET/rlm_scripts/"
    cp "$SRC/bin/rlm_repl" "$TARGET/bin/"
    chmod +x "$TARGET/rlm_scripts/rlm_repl.py" "$TARGET/bin/rlm_repl"
    echo "  rlm: rlm_repl.py + bin/rlm_repl wrapper"

    # 2. Agents
    mkdir -p "$TARGET/agents"
    cp "$SRC/agents/"*.md "$TARGET/agents/"
    echo "  agents: $(ls "$SRC/agents/"*.md | wc -l | tr -d ' ') files"

    # 3. Commands — into an embo/ namespace dir so they invoke as /embo:*
    #    (the research/ subdir gives /embo:research:examine etc.)
    mkdir -p "$TARGET/commands/embo"
    cp -r "$SRC/commands/"* "$TARGET/commands/embo/"
    echo "  commands: synced to commands/embo/ (/embo:*)"

    # 4. Profiles
    mkdir -p "$TARGET/profiles"
    cp "$SRC/profiles/"*.yaml "$TARGET/profiles/"
    echo "  profiles: $(ls "$SRC/profiles/"*.yaml | wc -l | tr -d ' ') files"

    # 5. Hooks (exclude *.test.sh — developer test files, not shipped)
    mkdir -p "$TARGET/hooks"
    for h in "$SRC/hooks/"*.sh; do
        case "$h" in *.test.sh) continue ;; esac
        cp "$h" "$TARGET/hooks/"
    done
    chmod +x "$TARGET/hooks/"*.sh
    echo "  hooks: $(ls "$SRC/hooks/"*.sh | grep -cv '\.test\.sh$' | tr -d ' ') files"

    # 6. Status line (optional)
    if [ -f "$SRC/statusline.sh" ]; then
        cp "$SRC/statusline.sh" "$TARGET/statusline.sh"
        chmod +x "$TARGET/statusline.sh"
        echo "  statusline: copied to $TARGET/statusline.sh"

        SETTINGS="$TARGET/settings.json"
        if ! command -v jq >/dev/null 2>&1; then
            echo "  statusline settings.json: jq not found — add manually:"
            echo '    { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }'
        else
            if [ ! -f "$SETTINGS" ]; then echo '{}' > "$SETTINGS"; fi
            if jq -e '.statusLine' "$SETTINGS" > /dev/null 2>&1; then
                echo "  settings.json: statusLine already configured — skipping"
            elif confirm "  Add statusLine to $SETTINGS? [Y/n] " y; then
                jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}' \
                    "$SETTINGS" > /tmp/_embo_settings.tmp \
                    && mv /tmp/_embo_settings.tmp "$SETTINGS"
                echo "  settings.json: statusLine added"
            else
                echo "  settings.json: statusLine skipped — see README §Statusline"
            fi
        fi
    fi

    # 7. Hooks — register in settings.json with literal ~/.claude/ paths.
    #    (A manual install has no ${CLAUDE_PLUGIN_ROOT}; the plugin's
    #    hooks.json uses that variable, but it is empty outside the plugin
    #    runtime, so a manual install must register tilde paths.)
    SETTINGS="$TARGET/settings.json"

    # register_hook <token> <event> <jq-append-expression>
    # Skips if a registration containing <token> already exists for <event>.
    register_hook() {
        local token="$1" event="$2" expr="$3"
        if ! command -v jq >/dev/null 2>&1; then
            echo "  $token: jq not found — register manually under hooks.$event"
            return
        fi
        if [ ! -f "$SETTINGS" ]; then echo '{}' > "$SETTINGS"; fi
        if jq -e --arg e "$event" --arg t "$token" \
            '[.hooks[$e][]?.hooks[]?.command] | any(. != null and contains($t))' \
            "$SETTINGS" > /dev/null 2>&1; then
            echo "  settings.json: $token already registered — skipping"
        else
            jq "$expr" "$SETTINGS" > /tmp/_embo_settings.tmp \
                && mv /tmp/_embo_settings.tmp "$SETTINGS"
            echo "  settings.json: $token hook registered"
        fi
    }

    if [ -f "$TARGET/hooks/context-guard.sh" ]; then
        register_hook context-guard UserPromptSubmit \
            '.hooks.UserPromptSubmit += [{"hooks": [{"type": "command",
             "command": "bash ~/.claude/hooks/context-guard.sh"}]}]'
    fi
    if [ -f "$TARGET/hooks/behavioral-reminder.sh" ]; then
        register_hook behavioral-reminder UserPromptSubmit \
            '.hooks.UserPromptSubmit += [{"hooks": [{"type": "command",
             "command": "bash ~/.claude/hooks/behavioral-reminder.sh"}]}]'
    fi
    if [ -f "$TARGET/hooks/approve-compound.sh" ]; then
        register_hook approve-compound PreToolUse \
            '.hooks.PreToolUse += [{"matcher": "Bash", "hooks": [{"type": "command",
             "command": "bash ~/.claude/hooks/approve-compound.sh"}]}]'
    fi

    # 8. Permissions — allow the read-only commands the workflow relies on.
    RLM_PERMS=(
        'Bash(rlm_repl *)'
        'Bash(find:*)'
        'Bash(git log:*)'
        'Bash(git diff:*)'
        'Bash(git status:*)'
        'Bash(grep:*)'
        'Bash(head:*)'
        'Bash(basename:*)'
        'Bash(git rev-parse:*)'
        'Bash(~/.claude/hooks/embo-capture.sh *)'
        # Note: profile-load permissions live in start.md frontmatter
        # (`allowed-tools:` Bash(cat ~/.claude/active-profile.yaml *)
        # and Read(~/.claude/active-profile.yaml)). No global rules needed.
    )
    if ! command -v jq >/dev/null 2>&1; then
        echo "  permissions: jq not found — add under permissions.allow:"
        for p in "${RLM_PERMS[@]}"; do echo "      \"$p\""; done
    else
        if [ ! -f "$SETTINGS" ]; then echo '{}' > "$SETTINGS"; fi
        ADDED=0
        for p in "${RLM_PERMS[@]}"; do
            if ! jq -e --arg p "$p" '[.permissions.allow[]?] | any(. == $p)' "$SETTINGS" > /dev/null 2>&1; then
                jq --arg p "$p" '.permissions.allow += [$p]' "$SETTINGS" > /tmp/_embo_settings.tmp \
                    && mv /tmp/_embo_settings.tmp "$SETTINGS"
                ADDED=$((ADDED + 1))
            fi
        done
        if [ "$ADDED" -gt 0 ]; then
            echo "  permissions: $ADDED read-only rules added"
        else
            echo "  permissions: all rules already present — skipping"
        fi
    fi
    echo ""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

if [ "$SKIPPED" -gt 0 ]; then
    echo "  $SKIPPED prompt(s) skipped with default 'no' (--force without --yes)."
    echo "  Accept all: bash install.sh ${STANDALONE:+--standalone }--force --yes"
    echo ""
fi

echo "PATH: ensure these are on PATH (add to ~/.zshrc or ~/.bashrc):"
echo "    export PATH=\"\$HOME/.local/bin:\$PATH\"   # uv"
echo "    export PATH=\"\$HOME/.bun/bin:\$PATH\"     # bun"
if [ "$STANDALONE" = "1" ]; then
    echo "    export PATH=\"\$HOME/.claude/bin:\$PATH\" # rlm_repl (standalone only)"
fi
echo ""

if [ "$STANDALONE" = "1" ]; then
    echo "Standalone install done. Restart Claude Code, then /embo:init for a"
    echo "new project or /embo:start for a session. Verify with /embo:health."
else
    echo "Dependencies done. Now install the plugins inside Claude Code:"
    echo "    /plugin marketplace add povesma/embo && /plugin install embo@embo"
    echo "    /plugin install claude-mem   (from thedotmack/claude-mem)"
    echo "Then verify with /embo:health."
fi

if [ "$DEPS_MISSING" = "1" ]; then
    echo ""
    echo "WARNING: one or more required dependencies are missing (see above)."
    exit 1
fi
