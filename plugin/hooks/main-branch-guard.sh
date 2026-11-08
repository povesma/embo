#!/usr/bin/env bash
# main-branch-guard.sh — PreToolUse hook.
#
# Refuse edits and history mutations while a protected branch (main /
# master by default) is checked out, and refuse pushes that target a
# protected branch from anywhere, so the agent must branch first and
# nothing is committed to or published from a protected branch.
#
# Reads the PreToolUse JSON payload on stdin (tool_name, tool_input,
# cwd), decides allow / warn / deny per the active profile, and emits
# the decision as hookSpecificOutput JSON on stdout.
#
# Fails OPEN on any uncertainty or internal error (no repo, detached
# HEAD, missing jq, unreadable profile): the call is allowed, with a
# one-line stderr notice when a dependency is missing. A broken guard
# must never wedge the session — the one thing worse than no guard.

set -u

# Fail-safe net: any unexpected non-zero exit (an unbound variable under
# `set -u`, the lib failing to source, a command dying) is converted to
# an allow with a notice. A broken guard must never wedge the session;
# exit 2 — the deny-by-stderr form — is NEVER emitted on an internal
# error, only ever on a deliberate deny path (which uses exit 0 + JSON
# here anyway). The intentional allow/deny paths all `exit 0`, so this
# trap fires only on a genuine malfunction.
trap '
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf "main-branch-guard: internal error (exit %s); allowing\n" "$rc" >&2
    exit 0
  fi
' EXIT

# Allow (no decision) and exit. A silent exit 0 is "no opinion" — the
# call continues through the normal permission flow; it is NOT an
# explicit approval.
allow() { exit 0; }

# Allow but print a dependency/fail-open notice to stderr first.
allow_notice() { printf 'main-branch-guard: %s\n' "$1" >&2; exit 0; }

# Emit the decision for the active mode, then exit. $1 = reason text.
# block -> deny JSON; warn -> additionalContext JSON + stderr; off is
# handled earlier (never reaches here).
decide() {
  local reason="$1"
  if [ "$PB_MODE" = "warn" ]; then
    jq -n --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$r}}'
    printf '%s\n' "$reason" >&2
    exit 0
  fi
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r}}'
  exit 0
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || allow

command -v jq >/dev/null 2>&1 || allow_notice "jq not found; allowing"

# --- read the payload ----------------------------------------------
PAYLOAD="$(cat)"
[ -n "$PAYLOAD" ] || allow
printf '%s' "$PAYLOAD" | jq -e . >/dev/null 2>&1 || allow_notice "non-JSON payload; allowing"

TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // ""')"
CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // ""')"
SID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // ""')"

# --- candidate check: cheap early exit for non-mutating calls -------
case "$TOOL" in
  Edit|Write|NotebookEdit)
    TARGET="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')"
    [ -n "$TARGET" ] || allow
    REPO_CTX="$CWD"
    [ -d "$REPO_CTX" ] || REPO_CTX="$(dirname "$TARGET")"
    ;;
  Bash)
    COMMAND="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // ""')"
    [ -n "$COMMAND" ] || allow
    REPO_CTX="$CWD"
    ;;
  *)
    allow
    ;;
esac

# --- resolve the branch --------------------------------------------
BRANCH="$(git -C "$REPO_CTX" symbolic-ref --short -q HEAD 2>/dev/null)" || allow
[ -n "$BRANCH" ] || allow   # detached HEAD — no protected branch to guard

# --- load policy ----------------------------------------------------
PB_MODE="$(embo-profile get rules.workflow.protected_branch_mode 2>/dev/null)"
BRANCHES_RAW="$(embo-profile get rules.workflow.protected_branches 2>/dev/null)"

case "$PB_MODE" in
  block|warn|off) : ;;
  "") PB_MODE="block" ;;
  *) printf 'main-branch-guard: unknown protected_branch_mode %s; using block\n' "$PB_MODE" >&2
     PB_MODE="block" ;;
esac

BT_MODE="$(embo-profile get rules.workflow.branch_task_mode 2>/dev/null)"
case "$BT_MODE" in
  warn|block|off) : ;;
  "") BT_MODE="warn" ;;
  *) printf 'main-branch-guard: unknown branch_task_mode %s; using warn\n' "$BT_MODE" >&2
     BT_MODE="warn" ;;
esac

# yq renders a list one element per line; strip brackets/commas so a
# flow list ([main, master]) and a block list both parse.
PROTECTED="$(printf '%s\n' "$BRANCHES_RAW" | tr -d '[],' | tr ' ' '\n' | grep -v '^$')"
[ -n "$PROTECTED" ] || PROTECTED="$(printf 'main\nmaster\n')"

is_protected() {  # is_protected <branch>
  local want="$1" b
  [ -n "$want" ] || return 1
  while IFS= read -r b; do
    [ "$b" = "$want" ] && return 0
  done <<EOF
$PROTECTED
EOF
  return 1
}

FIX='Create a feature branch first: git switch -c feat/<name>, then re-run.'

# --- FR-5: branch/task mismatch nudge ------------------------------
# A softer check than the protected-branch guard: when /embo:impl has
# recorded an active task number for this session and the checked-out
# branch does not reference it, nudge once per session. warn -> allow +
# additionalContext; block -> deny once. A per-session marker (keyed by
# session_id) suppresses repeats in BOTH modes so a run is never wedged.
# Skipped on a protected branch (FR-1/2 owns that), on an empty/invalid
# session id, and whenever no single task is derivable. Fails open.

# Validate a session id with the same charset embo-task-state enforces.
valid_sid() {
  case "$1" in
    "" | *..* | *[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Emit the FR-5 decision for BT_MODE, then exit. $1 = reason text.
decide_bt() {
  local reason="$1"
  if [ "$BT_MODE" = "block" ]; then
    jq -n --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r}}'
    exit 0
  fi
  # warn: allow with additionalContext, and echo to stderr as well.
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$r}}'
  printf '%s\n' "$reason" >&2
  exit 0
}

# fr5_check: run the mismatch nudge. Returns (does not exit) on every
# silent-allow path so the caller continues to its own allow.
fr5_check() {
  # off / protected branch / invalid session id -> no FR-5.
  [ "$BT_MODE" = "off" ] && return 0
  is_protected "$BRANCH" && return 0
  valid_sid "$SID" || return 0

  # Both state dirs anchor on the git toplevel so the guard reads the
  # same file /embo:impl wrote, and the marker lives in the project tmp/.
  local top task_dir marker_dir
  top="$(git -C "$REPO_CTX" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$top" ] || return 0
  task_dir="${EMBO_TASK_STATE_DIR:-$top/tmp/embo-task-state}"
  marker_dir="${EMBO_GUARD_MARKER_DIR:-$top/tmp/embo-guard}"

  # Primary source: the active-task state file written by /embo:impl.
  local task
  task="$(EMBO_TASK_STATE_DIR="$task_dir" "$HERE/../bin/embo-task-state" get "$SID" 2>/dev/null)"

  # Fallback: derive the task from the uncommitted/staged changes.
  if [ -z "$task" ]; then
    . "$HERE/../lib/branch-task-lib.sh" 2>/dev/null || return 0
    task="$(git -C "$REPO_CTX" status --porcelain 2>/dev/null \
      | branch_task_paths_from_porcelain \
      | branch_task_derive_from_paths)"
  fi

  # No single task derivable (clean tree, tie, or absent) -> silent.
  [ -n "$task" ] || return 0

  # A match is the normal, silent case.
  . "$HERE/../lib/branch-task-lib.sh" 2>/dev/null || return 0
  branch_task_matches "$BRANCH" "$task" && return 0

  # Mismatch. The per-session marker suppresses the repeat in both modes.
  local marker="$marker_dir/$SID"
  [ -f "$marker" ] && return 0
  mkdir -p "$marker_dir" 2>/dev/null && : > "$marker" 2>/dev/null \
    || { printf 'main-branch-guard: cannot record FR-5 marker; allowing\n' >&2; return 0; }

  decide_bt "main-branch-guard: active task $task does not match branch $BRANCH. Create or switch to its branch: git switch -c feat/$task-<name> (or git switch <existing>)."
}

# --- Edit/Write/NotebookEdit ---------------------------------------
if [ "$TOOL" != Bash ]; then
  # FR-5 runs first: it self-skips on a protected branch (where FR-1/2
  # takes precedence), in off mode, and when no task is derivable. On a
  # feature-branch mismatch it emits and exits.
  fr5_check
  [ "$PB_MODE" = "off" ] && allow   # FR-1/2 disabled; FR-5 already ran
  is_protected "$BRANCH" || allow   # on a feature branch — allow
  # Only tracked files are guarded.
  git -C "$REPO_CTX" ls-files --error-unmatch -- "$TARGET" >/dev/null 2>&1 || allow
  decide "main-branch-guard: refusing to edit a tracked file while branch $BRANCH is checked out. $FIX"
fi

# --- Bash: commits, mutations, writes, and push targets ------------
# shellcheck source=../lib/git-command-lib.sh
. "$HERE/../lib/git-command-lib.sh" 2>/dev/null || allow_notice "git-command-lib unavailable; allowing"

# FR-5 on Bash: only a mutating/writing command spends the one-shot
# nudge (a read-only `ls`/`git status` must not), and the remedy command
# (`git switch -c` / `git checkout -b`) is exempt so block mode never
# denies the very fix it suggests. fr5_check itself self-skips on a
# protected branch, off mode, and when no task is derivable.
if [ "$BT_MODE" != "off" ]; then
  bash_is_fr5_candidate=0
  while IFS='	' read -r _bt sub; do
    [ -n "$sub" ] || continue
    case "$sub" in
      'git switch -c'* | 'git checkout -b'*) continue ;;  # the remedy
    esac
    if gcl_is_git_mutation "$sub"; then bash_is_fr5_candidate=1; break; fi
    if [ -n "$(gcl_shell_write_paths "$sub")" ]; then bash_is_fr5_candidate=1; break; fi
  done <<EOF
$(gcl_walk "$COMMAND" "$BRANCH")
EOF
  [ "$bash_is_fr5_candidate" -eq 1 ] && fr5_check
fi

# FR-1/FR-2 (protected-branch mutations and push targets) are disabled
# when protected_branch_mode is off; FR-5 above has already run.
[ "$PB_MODE" = "off" ] && allow

# Push targets are checked regardless of the checked-out branch: a push
# to a protected ref is refused from anywhere.
while IFS= read -r seg; do
  while IFS= read -r tgt; do
    case "$tgt" in
      --all|--mirror)
        decide "main-branch-guard: refusing git push $tgt — it can publish a protected branch. $FIX" ;;
    esac
    if is_protected "$tgt"; then
      decide "main-branch-guard: refusing to push to protected branch $tgt. $FIX"
    fi
  done <<EOF
$(gcl_push_targets "$seg" "$BRANCH")
EOF
done <<EOF
$(gcl_split "$COMMAND")
EOF

# History mutations and writes to tracked paths, judged on the branch in
# effect at EACH subcommand (so `git switch -c b && git commit` is judged
# on b, not the protected branch).
while IFS='	' read -r at_branch sub; do
  [ -n "$sub" ] || continue
  is_protected "$at_branch" || continue
  if gcl_is_git_mutation "$sub"; then
    decide "main-branch-guard: refusing a git history change while branch $at_branch is checked out. $FIX"
  fi
  while IFS= read -r wpath; do
    [ -n "$wpath" ] || continue
    git -C "$REPO_CTX" ls-files --error-unmatch -- "$wpath" >/dev/null 2>&1 \
      && decide "main-branch-guard: refusing to write tracked file $wpath while branch $at_branch is checked out. $FIX"
  done <<EOF
$(gcl_shell_write_paths "$sub")
EOF
done <<EOF
$(gcl_walk "$COMMAND" "$BRANCH")
EOF

# Unparseable constructs carrying a mutation/write token, on a protected
# branch -> treat as a mutation.
if is_protected "$BRANCH" && gcl_is_unparseable_candidate "$COMMAND"; then
  decide "main-branch-guard: refusing an unparseable command that may change history while branch $BRANCH is checked out. $FIX"
fi

allow
