#!/usr/bin/env bash
# branch-task-check.sh — SessionStart hook.
#
# Surface a one-line warning when the current git branch does not
# appear to reference the task being worked on — derived from the
# uncommitted working-tree changes, the same evidence embo-deliver
# derives from, so the two checks cannot disagree. This catches the
# free-form editing failure mode: the agent is deep in a task, edits
# files directly (no /embo:impl entry point, no embo-deliver plan),
# and never notices HEAD is on the wrong branch.
#
# The other two layers (/embo:impl's bullet, embo-deliver's check)
# never fire during free-form editing; this one does.
#
# Fails open on any uncertainty (clean tree, no task paths, a tie,
# detached HEAD, no git): silent, exit 0, never blocks a session.

set -u

# Fail-open early exit helper.
bail() { exit 0; }

# Shared match rule. A partial install must not break the session.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || bail
# shellcheck source=../lib/branch-task-lib.sh
. "$HERE/../lib/branch-task-lib.sh" 2>/dev/null || bail

# --- resolve the git repo root the hook is running in ---------------
# Claude Code invokes the hook from the session's working directory;
# git rev-parse resolves relative to CWD.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || bail
[ -n "$REPO_ROOT" ] || bail
cd "$REPO_ROOT" || bail

# --- read the current branch ---------------------------------------
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null)" || bail
[ -n "$BRANCH" ] || bail   # detached HEAD — silent

# --- derive the task from the uncommitted working-tree changes ------
# The files being edited right now, the same evidence embo-deliver
# reads from plan.files.
CURRENT_TASK="$(
  git status --porcelain 2>/dev/null \
  | branch_task_paths_from_porcelain \
  | branch_task_derive_from_paths
)"
[ -n "$CURRENT_TASK" ] || bail   # no single task in the changes — silent

branch_task_matches "$BRANCH" "$CURRENT_TASK" && exit 0   # match — silent

# --- mismatch — one line to stderr, then exit 0 --------------------
# Suggest existing local branches only. `git branch --list` globs on
# substrings, so candidates go through the whole-token rule too.
MATCHING=""
while IFS= read -r cand; do
  [ -n "$cand" ] || continue
  [ "$cand" = "$BRANCH" ] && continue
  if branch_task_matches "$cand" "$CURRENT_TASK"; then
    MATCHING="$MATCHING$cand "
  fi
done <<EOF
$(git branch --list "*${CURRENT_TASK}*" --format='%(refname:short)' 2>/dev/null)
EOF

printf 'branch-task-check: current branch %s does not appear to match task %s (from your uncommitted changes).\n' \
  "$BRANCH" "$CURRENT_TASK" >&2
if [ -n "$MATCHING" ]; then
  printf 'branch-task-check: matching local branch(es) found: %s\n' \
    "$MATCHING" >&2
  printf 'branch-task-check: consider `git switch <branch>` before editing task %s files.\n' \
    "$CURRENT_TASK" >&2
else
  printf 'branch-task-check: no local branch references task %s; consider `git switch -c` before editing task files.\n' \
    "$CURRENT_TASK" >&2
fi

exit 0
