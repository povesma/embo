#!/usr/bin/env bash
# Plain-bash unit tests for embo-worktree-start (no framework).
# Run: bash plugin/bin/embo-worktree-start.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/embo-worktree-start"
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

run_start() {
  local dir="$1"; shift
  OUT="$(cd "$dir" && bash "$BIN" "$@" 2>&1)"
  RC=$?
}

# --- 7.1 create with derived name ----------------------------------------

test_create_derived_name() {
  local r; r="$(new_repo create)"
  run_start "$r" feat/shiny
  assert_exit "7.1 start exits 0" 0 "$RC"
  # feat/shiny -> feat-shiny under .worktrees/
  assert_contains "7.1 derives name (slash -> dash)" \
    ".worktrees/feat-shiny" "$OUT"
  assert_contains "7.1 worktree registered" "feat-shiny" \
    "$(git -C "$r" worktree list)"
  assert_contains "7.1 branch created" "feat/shiny" \
    "$(git -C "$r" branch --list 'feat/shiny')"
}

test_refuses_nesting() {
  local r; r="$(new_repo nest)"
  run_start "$r" feat/a
  local wt="$r/.worktrees/feat-a"
  # from INSIDE the worktree, starting another must refuse
  run_start "$wt" feat/b
  assert_exit "7.1 nesting refused -> exit 2" 2 "$RC"
  assert_contains "7.1 nesting message" "already inside a linked worktree" "$OUT"
}

test_path_conflict() {
  local r; r="$(new_repo conflict)"
  run_start "$r" feat/dup
  run_start "$r" feat/dup   # same derived path
  assert_exit "7.1 duplicate path -> exit 2" 2 "$RC"
  assert_contains "7.1 duplicate message" "already exists" "$OUT"
}

# --- 7.2 list ------------------------------------------------------------

test_list_shows_worktrees() {
  local r; r="$(new_repo listing)"
  run_start "$r" feat/one
  run_start "$r" --list
  assert_exit "7.2 list exits 0" 0 "$RC"
  assert_contains "7.2 list shows the main tree" "$r" "$OUT"
  assert_contains "7.2 list shows the created worktree" "feat-one" "$OUT"
}

run_all() {
  test_create_derived_name
  test_refuses_nesting
  test_path_conflict
  test_list_shows_worktrees
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
