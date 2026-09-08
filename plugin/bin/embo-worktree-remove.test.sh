#!/usr/bin/env bash
# Plain-bash unit tests for embo-worktree-remove (no framework).
# Run: bash plugin/bin/embo-worktree-remove.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/embo-worktree-remove"
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

assert_exit() {
  local desc="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  want exit: %s  got: %s\n' "$desc" "$want" "$got"
  fi
}

new_repo() {
  local p="$WORK/$1"
  mkdir -p "$p"
  git -C "$p" init -q -b main
  git -C "$p" config user.email t@t.t
  git -C "$p" config user.name t
  printf 'v1\n' > "$p/a.txt"
  git -C "$p" add a.txt
  git -C "$p" commit -qm init
  printf '%s' "$p"
}

add_worktree() {
  local r="$1" name="$2" br="$3" wt="$WORK/$2"
  git -C "$r" worktree add -q "$wt" -b "$br" HEAD
  printf '%s' "$wt"
}

run_remove() {
  local r="$1"; shift
  OUT="$(cd "$r" && bash "$BIN" "$@" 2>&1)"
  RC=$?
}

# --- clean worktree removed ----------------------------------------------

test_remove_clean() {
  local r; r="$(new_repo clean)"
  local wt; wt="$(add_worktree "$r" clean-wt feat)"
  run_remove "$r" "$wt"
  assert_exit "remove clean worktree exits 0" 0 "$RC"
  assert_contains "reports removed" "removed worktree" "$OUT"
  assert_exit "worktree dir gone" 1 "$([ -d "$wt" ]; echo $?)"
}

# --- dirty worktree refused ----------------------------------------------

test_remove_dirty_refused() {
  local r; r="$(new_repo dirty)"
  local wt; wt="$(add_worktree "$r" dirty-wt feat)"
  printf 'change\n' >> "$wt/a.txt"   # uncommitted tracked change
  run_remove "$r" "$wt"
  assert_exit "dirty worktree refused -> exit 3" 3 "$RC"
  assert_contains "surfaces the file" "a.txt" "$OUT"
  assert_exit "dirty worktree NOT removed" 0 "$([ -d "$wt" ]; echo $?)"
}

# --- --branch deletes a merged branch ------------------------------------

test_remove_with_branch() {
  local r; r="$(new_repo withbranch)"
  local wt; wt="$(add_worktree "$r" wb-wt feat)"
  # feat has no commits beyond HEAD -> merged into main -> -d succeeds
  run_remove "$r" "$wt" --branch
  assert_exit "remove + branch exits 0" 0 "$RC"
  assert_exit "branch feat deleted" 1 \
    "$([ -n "$(git -C "$r" branch --list feat)" ]; echo $?)"
}

# --- --branch keeps an unmerged branch (no --force-branch) ---------------

test_remove_keeps_unmerged_branch() {
  local r; r="$(new_repo unmerged)"
  local wt; wt="$(add_worktree "$r" um-wt feat)"
  printf 'x\n' > "$wt/b.txt"
  git -C "$wt" add b.txt
  git -C "$wt" commit -qm "unmerged work"
  run_remove "$r" "$wt" --branch
  assert_exit "remove exits 0 even if branch kept" 0 "$RC"
  assert_contains "notes the branch was kept" "kept" "$OUT"
  assert_exit "unmerged branch still present" 0 \
    "$([ -n "$(git -C "$r" branch --list feat)" ]; echo $?)"
}

# --- not a registered worktree -------------------------------------------

test_reject_non_worktree() {
  local r; r="$(new_repo nonwt)"
  mkdir -p "$r/random-dir"
  run_remove "$r" "$r/random-dir"
  assert_exit "non-worktree dir -> exit 2" 2 "$RC"
  assert_contains "says not a worktree" "not a registered worktree" "$OUT"
}

run_all() {
  test_remove_clean
  test_remove_dirty_refused
  test_remove_with_branch
  test_remove_keeps_unmerged_branch
  test_reject_non_worktree
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
