#!/usr/bin/env bash
# Integration tests for install.sh and uninstall.sh (no framework).
# Run: bash install.test.sh
# Exits non-zero if any assertion fails.
#
# Unlike the hooks' unit tests (which source a script and call its
# functions), these run install.sh / uninstall.sh as WHOLE PROGRAMS
# against a throwaway HOME, then assert on the resulting files and
# settings.json. They operate ONLY in a mktemp sandbox — never the
# user's real ~/.claude. Each scenario uses --force --yes so the
# scripts run non-interactively and auto-accept their own prompts.
#
# Covered:
#   1. uninstall.sh on a PRE-PLUGIN install (/dev:*, old paths) leaves a
#      clean state and preserves non-embo entries.
#   2. install.sh --standalone produces the current /embo:* layout with
#      the three real hooks registered via tilde paths.
#   3. round-trip: uninstall.sh on a standalone install cleans it back.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$REPO/install.sh"
UNINSTALL="$REPO/uninstall.sh"

PASS=0
FAIL=0

assert() {
  # assert <description> <condition-exit-code>  (0 = pass)
  local desc="$1" rc="$2"
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$desc"
  fi
}

exists()    { [ -e "$1" ]; }      # path present
absent()    { [ ! -e "$1" ]; }    # path gone
jq_true()   { jq -e "$1" "$2" >/dev/null 2>&1; }   # filter is truthy

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not found"; exit 0; }
[ -f "$INSTALL" ] && [ -f "$UNINSTALL" ] || { echo "FAIL: scripts not found"; exit 1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# ===========================================================================
# Scenario 1 — uninstall.sh on a PRE-PLUGIN install
# ===========================================================================
# Build the footprint the OLD installer left: /dev:* commands, the 3
# agents, embo hook files (+ a deprecated one + a NON-embo hook), the old
# rlm_repl.py, statusline, profiles, active-profile.yaml, and a
# settings.json with the old registrations, the old permission rule, a
# non-embo hook registration, and generic permissions.

H1="$SANDBOX/pre/.claude"
mkdir -p "$H1/commands/dev" "$H1/agents" "$H1/hooks" "$H1/rlm_scripts" "$H1/profiles"
touch "$H1/commands/dev/git.md" "$H1/commands/dev/start.md"
touch "$H1/agents/rlm-subcall.md" "$H1/agents/examine-advisor.md" "$H1/agents/approach-validator.md"
touch "$H1/hooks/context-guard.sh" "$H1/hooks/behavioral-reminder.sh" \
      "$H1/hooks/approve-compound.sh" "$H1/hooks/embo-capture.sh" \
      "$H1/hooks/docs-first-guard.sh" "$H1/hooks/some-other-tool.sh"
touch "$H1/rlm_scripts/rlm_repl.py" "$H1/statusline.sh"
touch "$H1/profiles/quality.yaml" "$H1/active-profile.yaml"
cat > "$H1/settings.json" <<'JSON'
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" },
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/context-guard.sh" } ] },
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/behavioral-reminder.sh" } ] },
      { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/some-other-tool.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/approve-compound.sh" } ] }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)",
      "Bash(~/.claude/hooks/embo-capture.sh *)",
      "Bash(find:*)",
      "Read(~/somefile)"
    ]
  }
}
JSON

HOME="$SANDBOX/pre" bash "$UNINSTALL" --force --yes >/dev/null 2>&1
assert "1: uninstall pre-plugin exits 0" "$?"

# embo files gone
assert "1: /dev commands removed"     "$(absent "$H1/commands/dev"; echo $?)"
assert "1: rlm_repl.py removed"        "$(absent "$H1/rlm_scripts/rlm_repl.py"; echo $?)"
assert "1: statusline removed"         "$(absent "$H1/statusline.sh"; echo $?)"
assert "1: docs-first-guard removed"   "$(absent "$H1/hooks/docs-first-guard.sh"; echo $?)"
assert "1: embo hook context-guard removed" "$(absent "$H1/hooks/context-guard.sh"; echo $?)"
assert "1: agent rlm-subcall removed"  "$(absent "$H1/agents/rlm-subcall.md"; echo $?)"
# kept
assert "1: non-embo hook file kept"    "$(exists "$H1/hooks/some-other-tool.sh"; echo $?)"
assert "1: profiles kept"              "$(exists "$H1/profiles/quality.yaml"; echo $?)"
assert "1: active-profile kept"        "$(exists "$H1/active-profile.yaml"; echo $?)"
assert "1: backup created"             "$(exists "$H1/settings.json.embo-backup"; echo $?)"
# settings.json: embo entries gone, non-embo kept
S1="$H1/settings.json"
assert "1: statusLine removed" "$(jq_true 'has("statusLine") | not' "$S1"; echo $?)"
assert "1: context-guard registration gone" \
  "$(jq_true '[.. | .command? // empty] | any(test("context-guard")) | not' "$S1"; echo $?)"
assert "1: approve-compound registration gone" \
  "$(jq_true '[.. | .command? // empty] | any(test("approve-compound")) | not' "$S1"; echo $?)"
assert "1: non-embo hook registration kept" \
  "$(jq_true '[.. | .command? // empty] | any(test("some-other-tool"))' "$S1"; echo $?)"
assert "1: old rlm_repl.py permission gone" \
  "$(jq_true '[.permissions.allow[]] | any(test("rlm_repl.py")) | not' "$S1"; echo $?)"
assert "1: embo-capture permission gone" \
  "$(jq_true '[.permissions.allow[]] | any(test("embo-capture")) | not' "$S1"; echo $?)"
assert "1: generic find permission kept" \
  "$(jq_true '[.permissions.allow[]] | any(. == "Bash(find:*)")' "$S1"; echo $?)"
assert "1: non-embo Read permission kept" \
  "$(jq_true '[.permissions.allow[]] | any(. == "Read(~/somefile)")' "$S1"; echo $?)"

# ===========================================================================
# Scenario 2 — install.sh --standalone produces the /embo:* layout
# ===========================================================================
H2="$SANDBOX/std/.claude"
mkdir -p "$SANDBOX/std"
HOME="$SANDBOX/std" bash "$INSTALL" --standalone --force --yes >/dev/null 2>&1
assert "2: standalone install exits 0" "$?"

assert "2: rlm_repl wrapper present"   "$(exists "$H2/bin/rlm_repl"; echo $?)"
assert "2: rlm_repl.py sibling present" "$(exists "$H2/rlm_scripts/rlm_repl.py"; echo $?)"
assert "2: commands in embo/ namespace" "$(exists "$H2/commands/embo/start.md"; echo $?)"
assert "2: research subdir present"    "$(exists "$H2/commands/embo/research"; echo $?)"
assert "2: 3 agents present"           "$(exists "$H2/agents/rlm-subcall.md"; echo $?)"
assert "2: statusline present"         "$(exists "$H2/statusline.sh"; echo $?)"
S2="$H2/settings.json"
assert "2: context-guard registered (tilde)" \
  "$(jq_true '[.. | .command? // empty] | any(test("bash ~/.claude/hooks/context-guard.sh"))' "$S2"; echo $?)"
assert "2: behavioral-reminder registered" \
  "$(jq_true '[.. | .command? // empty] | any(test("behavioral-reminder"))' "$S2"; echo $?)"
assert "2: approve-compound registered" \
  "$(jq_true '[.. | .command? // empty] | any(test("approve-compound"))' "$S2"; echo $?)"
# embo-capture and fix-hooks are NOT event hooks — must not be registered
assert "2: embo-capture NOT registered as a hook" \
  "$(jq_true '[.hooks[]?[]?.hooks[]?.command // empty] | any(test("embo-capture")) | not' "$S2"; echo $?)"
assert "2: no CLAUDE_PLUGIN_ROOT in registrations" \
  "$(jq_true '[.. | .command? // empty] | any(test("CLAUDE_PLUGIN_ROOT")) | not' "$S2"; echo $?)"
assert "2: rlm_repl permission added" \
  "$(jq_true '[.permissions.allow[]] | any(. == "Bash(rlm_repl *)")' "$S2"; echo $?)"

# ===========================================================================
# Scenario 3 — round-trip: uninstall the standalone install
# ===========================================================================
HOME="$SANDBOX/std" bash "$UNINSTALL" --force --yes >/dev/null 2>&1
assert "3: round-trip uninstall exits 0" "$?"
assert "3: embo commands removed"      "$(absent "$H2/commands/embo"; echo $?)"
assert "3: rlm_repl wrapper removed"   "$(absent "$H2/bin/rlm_repl"; echo $?)"
assert "3: statusline removed"         "$(absent "$H2/statusline.sh"; echo $?)"
assert "3: profiles kept"              "$(exists "$H2/profiles/quality.yaml"; echo $?)"
assert "3: no embo hook registrations remain" \
  "$(jq_true '[.. | .command? // empty] | any(test("context-guard|behavioral-reminder|approve-compound")) | not' "$S2"; echo $?)"
assert "3: rlm_repl permission removed" \
  "$(jq_true '[.permissions.allow[]?] | any(. == "Bash(rlm_repl *)") | not' "$S2"; echo $?)"

# ===========================================================================
echo ""
echo "install/uninstall integration tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
