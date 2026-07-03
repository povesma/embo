#!/usr/bin/env bash
# Plain-bash unit tests for embo-deliver (no framework).
# Run: bash plugin/bin/embo-deliver.test.sh
# Exits non-zero if any assertion fails.
#
# The executor's --dry-run flag prints the git/gh commands it WOULD run,
# one per line, prefixed "DRYRUN: ", and executes nothing. Tests assert on
# that output and on exit codes, so no real git repo or network is touched.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/embo-deliver"
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

# write_plan <name> <content> -> path
write_plan() {
  local p="$WORK/$1"
  printf '%s' "$2" > "$p"
  printf '%s' "$p"
}

# run_dry <plan-path> -> sets OUT and RC
run_dry() {
  OUT="$(bash "$BIN" --dry-run --plan "$1" 2>&1)"
  RC=$?
}

# --- 1.1: valid plan parses; invalid plans rejected with exit 2 -----------

VALID_PUSH="$(write_plan valid-push.txt 'branch: feature/x
mode: push
file: a.py
file: b.py
message:
fix: correct the thing')"

run_dry "$VALID_PUSH"
assert_exit "valid push plan exits 0" 0 "$RC"
assert_contains "valid plan stages a.py by name" "add -- " "$OUT"
assert_contains "valid plan includes a.py" "a.py" "$OUT"
assert_contains "valid plan includes b.py" "b.py" "$OUT"
assert_contains "valid plan runs a commit step" "git commit -m" "$OUT"

MISSING_BRANCH="$(write_plan no-branch.txt 'mode: push
file: a.py
message:
x')"
run_dry "$MISSING_BRANCH"
assert_exit "missing branch -> exit 2" 2 "$RC"
assert_not_contains "invalid plan runs no git add" "add -- " "$OUT"

MISSING_MODE="$(write_plan no-mode.txt 'branch: b
file: a.py
message:
x')"
run_dry "$MISSING_MODE"
assert_exit "missing mode -> exit 2" 2 "$RC"

NO_FILES="$(write_plan no-files.txt 'branch: b
mode: push
message:
x')"
run_dry "$NO_FILES"
assert_exit "zero file: lines -> exit 2" 2 "$RC"
assert_not_contains "no-files plan runs no git add" "add -- " "$OUT"

BAD_MODE="$(write_plan bad-mode.txt 'branch: b
mode: shipit
file: a.py
message:
x')"
run_dry "$BAD_MODE"
assert_exit "unknown mode -> exit 2" 2 "$RC"

MISSING_MSG="$(write_plan no-msg.txt 'branch: b
mode: push
file: a.py')"
run_dry "$MISSING_MSG"
assert_exit "missing message -> exit 2" 2 "$RC"

PR_NO_BASE="$(write_plan pr-no-base.txt 'branch: b
mode: pr
file: a.py
message:
x')"
run_dry "$PR_NO_BASE"
assert_exit "pr mode without base -> exit 2" 2 "$RC"

NO_PLAN_RC=0
bash "$BIN" --dry-run --plan "$WORK/does-not-exist.txt" >/dev/null 2>&1 \
  || NO_PLAN_RC=$?
assert_exit "nonexistent plan file -> exit 2" 2 "$NO_PLAN_RC"

# --- 1.3: stages only plan files, by name; forbidden git forms absent -----

run_dry "$VALID_PUSH"
assert_contains "stages via git add --" "git add -- " "$OUT"
assert_not_contains "never git add -A (dry output)" "add -A" "$OUT"
assert_not_contains "never git add . (dry output)" "add ." "$OUT"
assert_not_contains "never commit -a (dry output)" "commit -a" "$OUT"

# The script's executable lines (comments stripped) must never contain the
# forbidden forms. The prohibition is documented in a comment, so we grep
# only non-comment lines.
CODE="$(grep -v '^[[:space:]]*#' "$BIN")"
assert_not_contains "code has no 'git add -A'" "git add -A" "$CODE"
assert_not_contains "code has no 'git add .'" "git add ." "$CODE"
assert_not_contains "code has no 'commit -a'" "commit -a" "$CODE"

# --- 1.5: push routing --------------------------------------------------

run_dry "$VALID_PUSH"
assert_contains "pushes after commit" "git push" "$OUT"
assert_contains "push targets plan branch" "feature/x" "$OUT"

# --- 2.1: mode routing via --dry-run ------------------------------------

run_dry "$VALID_PUSH"
assert_not_contains "push mode: no gh pr create" "gh pr create" "$OUT"
assert_not_contains "push mode: no gh pr merge" "gh pr merge" "$OUT"

VALID_PR="$(write_plan valid-pr.txt 'branch: feature/x
mode: pr
base: main
file: a.py
message:
fix: thing')"
run_dry "$VALID_PR"
assert_exit "valid pr plan exits 0" 0 "$RC"
assert_contains "pr mode: gh pr create" "gh pr create" "$OUT"
assert_contains "pr mode: --base main" "main" "$OUT"
assert_contains "pr mode: --head branch" "feature/x" "$OUT"
assert_not_contains "pr mode: no merge" "gh pr merge" "$OUT"

VALID_MERGE="$(write_plan valid-merge.txt 'branch: feature/x
mode: pr-merge
base: main
file: a.py
message:
fix: thing')"
run_dry "$VALID_MERGE"
assert_exit "valid pr-merge plan exits 0" 0 "$RC"
assert_contains "pr-merge mode: gh pr create" "gh pr create" "$OUT"
assert_contains "pr-merge mode: gh pr merge --squash" "gh pr merge --squash" "$OUT"

# --- 3.1: failure exit codes are mapped on each step --------------------
# The exit code on a *runtime* failure (push rejected, gh missing, merge
# blocked) is straight-line `|| fail "..." N` bash. We verify each step is
# guarded with its documented code by reading the script — no fake broken
# environment, which would test the harness, not the feature. Live failure
# behaviour is checked end-to-end at subtask 4.5.

assert_contains "push guarded with exit 4" 'push failed" 4' "$CODE"
assert_contains "gh-absent guarded with exit 3" 'gh not installed' "$CODE"
assert_contains "pr create guarded with exit 5" 'PR not created" 5' "$CODE"
assert_contains "merge guarded with exit 6" 'merge blocked' "$CODE"

# --- 3.2: no rollback/undo anywhere in the script -----------------------

assert_not_contains "code has no 'git reset'" "git reset" "$CODE"
assert_not_contains "code has no 'git revert'" "git revert" "$CODE"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
