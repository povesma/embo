#!/usr/bin/env bash
# Integration fixture: both registered PreToolUse hooks on one payload.
# Run: bash plugin/hooks/main-branch-guard.integration.test.sh
# Exits non-zero if any assertion fails.
#
# Claude Code runs every matching PreToolUse hook against the SAME
# original payload; one hook's `updatedInput` rewrite does not change the
# command another hook sees. So on a protected-branch push the guard must
# deny regardless of what approve-compound would do, and on a compound
# command approve-compound would rewrite, the guard still judges the
# ORIGINAL command. This fixture drives approve-compound.sh and
# main-branch-guard.sh on the same payloads and asserts the combined
# outcome a deny from EITHER hook makes the call a deny.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/main-branch-guard.sh"
APPROVE="$HERE/approve-compound.sh"

PASS=0
FAIL=0
assert_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1))
       printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$desc" "$needle" "$hay" ;;
  esac
}
assert_not_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) FAIL=$((FAIL + 1))
       printf 'FAIL: %s\n  unexpected: [%s]\n  in:         [%s]\n' "$desc" "$needle" "$hay" ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A throwaway repo on main with one committed tracked file.
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t
printf 'x\n' > "$REPO/tracked.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init

# Case-local profile with the guard in block mode.
PROFILE="$TMP/profile.yaml"
printf 'rules:\n  workflow:\n    protected_branches: [main, master]\n    protected_branch_mode: block\n    branch_task_mode: off\n' > "$PROFILE"

# approve-compound reads allow/deny from <cwd>/.claude/settings.json and
# $HOME/.claude/settings.json. Put the allow rules in the repo's own
# settings and point HOME at an empty dir so the real home never leaks.
mkdir -p "$REPO/.claude"
printf '{"permissions":{"allow":["Bash(git status)","Bash(git log *)","Bash(echo *)"],"deny":[]}}' \
  > "$REPO/.claude/settings.json"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude"

bash_payload() {
  jq -n --arg c "$REPO" --arg v "$1" \
    '{tool_name:"Bash", cwd:$c, session_id:"intg", tool_input:{command:$v}}'
}

run_guard() {
  printf '%s' "$1" | EMBO_PROFILE_ACTIVE="$PROFILE" \
    EMBO_TASK_STATE_DIR="$TMP/ts" EMBO_GUARD_MARKER_DIR="$TMP/mk" \
    bash "$GUARD" 2>/dev/null
}
run_approve() {
  printf '%s' "$1" | HOME="$FAKE_HOME" bash "$APPROVE" 2>/dev/null
}

# --- case 1: git push origin main -> the guard denies ---------------
pl="$(bash_payload 'git push origin main')"
g_out="$(run_guard "$pl")"
assert_contains "push origin main: guard denies" \
  '"permissionDecision": "deny"' "$g_out"
# approve-compound must not turn it into an allow that masks the deny:
# either it denies too, or it falls through (no allow decision). A deny
# from the guard is the binding outcome either way.
a_out="$(run_approve "$pl")"
assert_not_contains "push origin main: approve-compound does not emit allow" \
  '"permissionDecision": "allow"' "$a_out"

# --- case 2: approve-compound ALLOWS (and may rewrite via updatedInput)
# a command the guard must DENY. `echo x > tracked.txt` with `echo *`
# allowed: approve-compound emits an allow decision, but the guard sees
# the ORIGINAL command, recognises a redirect onto a tracked file while
# main is checked out, and denies. Claude Code treats any deny as binding
# over an allow, so the call is refused.
pl="$(bash_payload 'echo x > tracked.txt')"
a_out="$(run_approve "$pl")"
assert_contains "redirect on main: approve-compound allows it" \
  '"permissionDecision": "allow"' "$a_out"
g_out="$(run_guard "$pl")"
assert_contains "redirect on main: guard denies the original despite the allow" \
  '"permissionDecision": "deny"' "$g_out"

# also a compound whose original form mutates on main -> guard denies the
# ORIGINAL (not any rewritten subset). approve-compound will NOT allow it
# (commit is not in the allow list), so the deny stands alone.
pl="$(bash_payload 'git status && git commit -m x')"
g_out="$(run_guard "$pl")"
assert_contains "compound commit on main: guard denies the original" \
  '"permissionDecision": "deny"' "$g_out"

# --- case 3: a fully-allowed compound approve-compound DOES rewrite --
# (`git status && git log --oneline -5`) is read-only: the guard allows
# it silently, and approve-compound may rewrite/allow it. The guard must
# NOT deny a read-only compound even on main.
pl="$(bash_payload 'git status && git log --oneline -5')"
g_out="$(run_guard "$pl")"
assert_not_contains "read-only compound on main: guard does not deny" \
  '"permissionDecision": "deny"' "$g_out"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
