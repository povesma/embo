#!/usr/bin/env bash
# Plain-bash unit tests for embo-worktree-finish (no framework).
# Run: bash plugin/bin/embo-worktree-finish.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/embo-worktree-finish"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *)
      FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' \
        "$desc" "$needle" "$hay"
      ;;
  esac
}

assert_not_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*)
      FAIL=$((FAIL + 1))
      printf 'FAIL: %s\n  unexpected: [%s]\n  in:         [%s]\n' \
        "$desc" "$needle" "$hay"
      ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

assert_exit() {
  local desc="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  want exit: %s  got: %s\n' "$desc" "$want" "$got"
  fi
}

# new_repo <name> -> path : a throwaway git repo under $WORK, one commit
# on main, ready for `git worktree add`.
new_repo() {
  local p="$WORK/$1"
  mkdir -p "$p"
  git -C "$p" init -q -b main
  git -C "$p" config user.email t@t.t
  git -C "$p" config user.name t
  printf 'v1\n' > "$p/a.txt"
  git -C "$p" add a.txt
  git -C "$p" commit -qm "init"
  printf '%s' "$p"
}

# add_worktree <repo> <name> <branch> -> prints worktree path
add_worktree() {
  local r="$1" name="$2" br="$3" wt="$WORK/$2"
  git -C "$r" worktree add -q "$wt" -b "$br" HEAD
  printf '%s' "$wt"
}

# commit_change <dir> <file> <content> <msg>
commit_change() {
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -qm "$4"
}

# run_finish <wt> [args...] -> sets OUT and RC
run_finish() {
  local wt="$1"; shift
  OUT="$(cd "$wt" && bash "$BIN" "$@" 2>&1)"
  RC=$?
}

# --- 4.1 happy path: green tests -> merge -> re-test -> cleanup -----------

test_happy_path() {
  local r; r="$(new_repo happy)"
  local wt; wt="$(add_worktree "$r" happy-wt feat)"
  commit_change "$wt" b.txt "feat" "feat: add b"
  run_finish "$wt" main --test-cmd "true"
  assert_exit "4.1 happy finish exits 0" 0 "$RC"
  assert_contains "4.1 reports merge into main" "merged into main" "$OUT"
  # branch's file is now on main
  assert_contains "4.1 main tree now has b.txt" "b.txt" \
    "$(git -C "$r" ls-tree --name-only main)"
  # worktree removed
  assert_not_contains "4.1 worktree branch gone" "feat" \
    "$(git -C "$r" worktree list)"
}

# --- 4.2 dirty guards ----------------------------------------------------

test_base_dirty_aborts() {
  local r; r="$(new_repo basedirty)"
  local wt; wt="$(add_worktree "$r" bd-wt feat)"
  commit_change "$wt" b.txt "feat" "feat: b"
  printf 'dirty\n' > "$r/a.txt"   # main tree (owns base) now dirty
  run_finish "$wt" main --test-cmd "true"
  assert_exit "4.2 base dirty -> exit 4" 4 "$RC"
  assert_contains "4.2 reports base dirty" "dirty" "$OUT"
}

test_dirty_worktree_not_removed() {
  local r; r="$(new_repo wtdirty)"
  local wt; wt="$(add_worktree "$r" wd-wt feat)"
  commit_change "$wt" b.txt "feat" "feat: b"
  # leave an uncommitted tracked change in the worktree AFTER commit
  printf 'more\n' >> "$wt/b.txt"
  run_finish "$wt" main --test-cmd "true"
  assert_exit "4.2 dirty worktree cleanup refused -> exit 7" 7 "$RC"
  assert_contains "4.2 surfaces uncommitted files" "b.txt" "$OUT"
}

# --- 4.3 base ownership sub-cases ----------------------------------------

test_base_on_other_branch_uses_temp() {
  # main tree on 'main', base is 'dev' checked out nowhere -> temp worktree
  local r; r="$(new_repo baseother)"
  git -C "$r" branch dev            # create dev at main, not checked out
  local wt; wt="$(add_worktree "$r" bo-wt feat)"
  commit_change "$wt" b.txt "feat" "feat: b"
  run_finish "$wt" dev --test-cmd "true"
  assert_exit "4.3 unheld base via temp worktree exits 0" 0 "$RC"
  assert_contains "4.3 dev now has b.txt" "b.txt" \
    "$(git -C "$r" ls-tree --name-only dev)"
  # main tree still on main, untouched
  assert_contains "4.3 main tree still on main" "main" \
    "$(git -C "$r" symbolic-ref --short HEAD)"
}

# --- 4.4 red merge-result preserves the worktree -------------------------

test_red_merge_preserves_worktree() {
  # Tests must PASS in the worktree but FAIL on the merged result. A marker
  # committed only on the base ('poison') is absent in the worktree (step 1
  # passes) and present after merge (step 5 fails) -> exit 6, worktree kept.
  local r; r="$(new_repo redmerge)"
  local wt; wt="$(add_worktree "$r" rm-wt feat)"
  commit_change "$wt" b.txt "feat" "feat: b"
  commit_change "$r" poison.txt "x" "poison base"
  run_finish "$wt" main --test-cmd "test ! -f poison.txt"
  assert_exit "4.4 merged-result failure -> exit 6" 6 "$RC"
  assert_contains "4.4 reports worktree preserved" "worktree preserved" "$OUT"
  assert_contains "4.4 worktree still present" "rm-wt" \
    "$(git -C "$r" worktree list)"
}

# --- 4.6 menu dispatch: keep / pr ----------------------------------------

test_mode_keep_preserves_worktree() {
  local r; r="$(new_repo modekeep)"
  local wt; wt="$(add_worktree "$r" mk-wt feat)"
  commit_change "$wt" b.txt "feat" "feat: b"
  run_finish "$wt" main --mode keep --test-cmd "true"
  assert_exit "4.6 keep exits 0" 0 "$RC"
  assert_contains "4.6 keep reports kept" "worktree kept" "$OUT"
  assert_contains "4.6 keep merged into main" "b.txt" \
    "$(git -C "$r" ls-tree --name-only main)"
  assert_contains "4.6 keep leaves worktree in place" "mk-wt" \
    "$(git -C "$r" worktree list)"
}

test_mode_pr_hands_off() {
  local r; r="$(new_repo modepr)"
  local wt; wt="$(add_worktree "$r" mp-wt feat)"
  commit_change "$wt" b.txt "feat" "feat: b"
  run_finish "$wt" main --mode pr --test-cmd "true"
  assert_exit "4.6 pr exits 0" 0 "$RC"
  assert_contains "4.6 pr hands off to embo-deliver" "embo-deliver pr" "$OUT"
}

run_all() {
  test_happy_path
  test_base_dirty_aborts
  test_dirty_worktree_not_removed
  test_base_on_other_branch_uses_temp
  test_red_merge_preserves_worktree
  test_mode_keep_preserves_worktree
  test_mode_pr_hands_off
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
