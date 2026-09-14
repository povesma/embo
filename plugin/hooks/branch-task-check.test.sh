#!/usr/bin/env bash
# Plain-Bash unit tests for branch-task-check.sh (no framework).
# Run: bash plugin/hooks/branch-task-check.test.sh
# Exits non-zero if any assertion fails.
#
# The hook runs in the user's CWD (Claude Code invokes SessionStart
# hooks from the session working directory). We drive it against
# throwaway git repos built fresh for each case, with controlled
# UNCOMMITTED changes under tasks/NNN-*/ and a controlled current
# branch. All assertions check stderr content and exit code — the hook
# is fail-open by contract, so exit is always 0 even on mismatch.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/branch-task-check.sh"

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *)
      FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$desc" "$needle" "$hay"
      ;;
  esac
}

assert_not_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*)
      FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  unexpected: [%s]\n  in:         [%s]\n' "$desc" "$needle" "$hay"
      ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$desc" "$exp" "$act"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a throwaway repo with a committed baseline, then leave
# UNCOMMITTED edits under the given task folders — that is the signal
# the hook reads.
#   $1 = case name (used for dir)
#   $2 = branch to be on
#   $3 = space-separated "NNN:count" specs — count dirty files under
#        tasks/NNN-x/
#   $4 = extra existing local branches (space-separated, may be empty)
build_repo() {
  local case_name="$1" branch_name="$2" dirty_spec="$3" extra_branches="${4:-}"
  local repo="$TMP/$case_name"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  printf 'x\n' > "$repo/README.md"

  # committed baseline for every task folder in the spec
  local spec num
  for spec in $dirty_spec; do
    num="${spec%%:*}"
    mkdir -p "$repo/tasks/${num}-x"
    printf 'base\n' > "$repo/tasks/${num}-x/design.md"
  done
  git -C "$repo" add -A
  git -C "$repo" commit -qm init

  if [ "$branch_name" != "main" ]; then
    git -C "$repo" switch -q -c "$branch_name"
  fi
  for b in $extra_branches; do
    git -C "$repo" branch "$b" 2>/dev/null || true
  done

  # now dirty the working tree: `count` modified files under each task
  local count i
  for spec in $dirty_spec; do
    num="${spec%%:*}"
    count="${spec##*:}"
    i=0
    while [ "$i" -lt "$count" ]; do
      printf 'dirty %s\n' "$i" > "$repo/tasks/${num}-x/file$i.md"
      i=$((i + 1))
    done
  done

  printf '%s\n' "$repo"
}

run_hook() {  # run_hook <cwd> -> sets OUT and RC (stderr captured to
              # OUT; stdout discarded — the hook writes only to stderr).
  OUT="$(cd "$1" && bash "$HOOK" 2>&1 >/dev/null)"
  RC=$?
}

# --- 1. mismatch on `main` -> warning + suggests existing branch
test_mismatch_main_with_existing_branch() {
  local repo
  repo="$(build_repo mismatch_main main "066:2" "feat/066-x")"
  run_hook "$repo"
  assert_eq "1: mismatch main -> exit 0 (fail-open by design)" 0 "$RC"
  assert_contains "1: warns about mismatch" \
    "does not appear to match" "$OUT"
  assert_contains "1: names the current branch (main)" \
    "current branch main" "$OUT"
  assert_contains "1: names the task (066)" "task 066" "$OUT"
  assert_contains "1: mentions the existing matching branch" \
    "feat/066-x" "$OUT"
}

# --- 2. mismatch on an unrelated feature branch, no matching branch
#       exists -> suggests git switch -c
test_mismatch_feature_no_matching_branch() {
  local repo
  repo="$(build_repo mismatch_feat feat/062-worktree "066:2" "")"
  run_hook "$repo"
  assert_eq "2: mismatch feat/062 -> exit 0" 0 "$RC"
  assert_contains "2: warns about mismatch" \
    "does not appear to match" "$OUT"
  assert_contains "2: names task 066" "task 066" "$OUT"
  assert_contains "2: suggests git switch -c" "git switch -c" "$OUT"
}

# --- 3. match on `feat/066-x` -> silent
test_match_middle() {
  local repo
  repo="$(build_repo match_mid feat/066-x "066:2" "")"
  run_hook "$repo"
  assert_eq "3: match feat/066-x -> exit 0" 0 "$RC"
  assert_not_contains "3: match -> no warning" \
    "does not appear to match" "$OUT"
}

# --- 4. match at start (066-thing) -> silent
test_match_start() {
  local repo
  repo="$(build_repo match_start 066-thing "066:2" "")"
  run_hook "$repo"
  assert_eq "4: match 066-thing -> exit 0" 0 "$RC"
  assert_not_contains "4: match -> no warning" \
    "does not appear to match" "$OUT"
}

# --- 5. match at end (hotfix/066) -> silent
test_match_end() {
  local repo
  repo="$(build_repo match_end hotfix/066 "066:2" "")"
  run_hook "$repo"
  assert_eq "5: match hotfix/066 -> exit 0" 0 "$RC"
  assert_not_contains "5: match -> no warning" \
    "does not appear to match" "$OUT"
}

# --- 6. whole-token: `066` does NOT match `feat/1066-x` -> warning
test_wholetoken_rejects_1066() {
  local repo
  repo="$(build_repo wholetoken feat/1066-x "066:2" "")"
  run_hook "$repo"
  assert_eq "6: whole-token 1066 -> exit 0" 0 "$RC"
  assert_contains "6: 1066 not a whole-token match -> warning" \
    "does not appear to match" "$OUT"
}

# --- 7. fail-open: clean working tree -> silent
#       (the committed task folder must NOT trigger anything)
test_failopen_clean_tree() {
  local repo="$TMP/clean_tree"
  mkdir -p "$repo/tasks/066-x"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  printf 'x\n' > "$repo/tasks/066-x/design.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  git -C "$repo" switch -q -c feat/999-other
  run_hook "$repo"
  assert_eq "7: clean tree -> exit 0" 0 "$RC"
  assert_not_contains "7: clean tree -> no output" \
    "does not appear to match" "$OUT"
}

# --- 8. fail-open: not in a git repo -> silent
test_failopen_not_in_repo() {
  local d="$TMP/not_a_repo"
  mkdir -p "$d"
  run_hook "$d"
  assert_eq "8: not a git repo -> exit 0" 0 "$RC"
  assert_not_contains "8: not a git repo -> no output" \
    "does not appear to match" "$OUT"
}

# --- 9. fail-open: detached HEAD -> silent
test_failopen_detached_head() {
  local repo
  repo="$(build_repo detached main "066:2" "")"
  git -C "$repo" switch --detach -q HEAD
  run_hook "$repo"
  assert_eq "9: detached HEAD -> exit 0" 0 "$RC"
  assert_not_contains "9: detached HEAD -> no output" \
    "does not appear to match" "$OUT"
}

# --- 10. fail-open: dirty files, but none under tasks/ -> silent
test_failopen_no_task_paths() {
  local repo="$TMP/no_task_paths"
  mkdir -p "$repo/src"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  printf 'x\n' > "$repo/src/a.py"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  git -C "$repo" switch -q -c feat/999-other
  printf 'changed\n' > "$repo/src/a.py"
  run_hook "$repo"
  assert_eq "10: no task paths dirty -> exit 0" 0 "$RC"
  assert_not_contains "10: no task paths dirty -> no output" \
    "does not appear to match" "$OUT"
}

# --- 11. fail-open on a TIE: equal file counts across two tasks ------
#        The evidence does not identify one task, so the hook must not
#        guess (this is where "highest number wins" used to misfire).
test_failopen_tie() {
  local repo
  repo="$(build_repo tie_case feat/999-other "055:2 066:2" "")"
  run_hook "$repo"
  assert_eq "11: tie -> exit 0" 0 "$RC"
  assert_not_contains "11: tie -> no output (cannot identify one task)" \
    "does not appear to match" "$OUT"
}

# --- 12. picks the task with the MOST changed files -----------------
test_picks_most_changed() {
  local repo
  repo="$(build_repo most_changed feat/055-something "055:1 066:3" "")"
  run_hook "$repo"
  assert_eq "12: picks most-changed -> exit 0" 0 "$RC"
  assert_contains "12: picks 066 (3 files) over 055 (1 file)" \
    "task 066" "$OUT"
  assert_contains "12: warns, feat/055-something lacks 066" \
    "does not appear to match" "$OUT"
}

# --- 13. REVERSE of 12: the LOWER task number is the active one -----
#        Proves the hook follows the evidence, not the number. The old
#        mtime+highest-number heuristic failed exactly this case.
test_picks_lower_number_when_it_leads() {
  local repo
  repo="$(build_repo lower_wins feat/042-fix "042:3 066:1" "")"
  run_hook "$repo"
  assert_eq "13: lower-number active -> exit 0" 0 "$RC"
  assert_not_contains "13: on feat/042-fix with 042 leading -> silent" \
    "does not appear to match" "$OUT"
}

# --- 14. same fixture as 13, mismatched branch -> names 042, not 066
test_lower_number_named_on_mismatch() {
  local repo
  repo="$(build_repo lower_named feat/999-other "042:3 066:1" "")"
  run_hook "$repo"
  assert_eq "14: lower-number active, mismatch -> exit 0" 0 "$RC"
  assert_contains "14: names task 042 (the most-changed one)" \
    "task 042" "$OUT"
  assert_not_contains "14: does NOT name 066 (higher but less changed)" \
    "task 066" "$OUT"
}

# --- 15. branch suggestion obeys the whole-token rule ----------------
#        `git branch --list '*066*'` also matches feat/1066-x, which is
#        NOT a whole-token match and must not be suggested.
test_suggestion_rejects_substring_branch() {
  local repo
  repo="$(build_repo suggest_filter main "066:2" "feat/1066-x")"
  run_hook "$repo"
  assert_eq "15: substring-only branch -> exit 0" 0 "$RC"
  assert_contains "15: still warns about the mismatch" \
    "does not appear to match" "$OUT"
  assert_not_contains "15: does NOT suggest feat/1066-x" \
    "feat/1066-x" "$OUT"
  assert_contains "15: falls back to git switch -c" \
    "git switch -c" "$OUT"
}

# --- 16. renamed file is attributed to its destination path ---------
test_rename_attributed_to_destination() {
  local repo="$TMP/rename_case"
  mkdir -p "$repo/tasks/066-x"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  printf 'a\n' > "$repo/tasks/066-x/old.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  git -C "$repo" switch -q -c feat/999-other
  git -C "$repo" mv tasks/066-x/old.md tasks/066-x/new.md
  run_hook "$repo"
  assert_eq "16: rename -> exit 0" 0 "$RC"
  assert_contains "16: rename counted, names task 066" \
    "task 066" "$OUT"
}

# --- runner ---------------------------------------------------------
test_mismatch_main_with_existing_branch
test_mismatch_feature_no_matching_branch
test_match_middle
test_match_start
test_match_end
test_wholetoken_rejects_1066
test_failopen_clean_tree
test_failopen_not_in_repo
test_failopen_detached_head
test_failopen_no_task_paths
test_failopen_tie
test_picks_most_changed
test_picks_lower_number_when_it_leads
test_lower_number_named_on_mismatch
test_suggestion_rejects_substring_branch
test_rename_attributed_to_destination

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
