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

assert_contains "push guarded with exit 4" 'push_fail_msg" 4' "$CODE"
assert_contains "gh-absent guarded with exit 3" 'gh not installed' "$CODE"
assert_contains "pr create guarded with exit 5" 'PR not created" 5' "$CODE"
assert_contains "merge guarded with exit 6" 'merge blocked' "$CODE"

# --- 3.2: no rollback/undo anywhere in the script -----------------------

assert_not_contains "code has no 'git reset'" "git reset" "$CODE"
assert_not_contains "code has no 'git revert'" "git revert" "$CODE"

# --- 7.2: paths resolve against repo root regardless of caller CWD ------
# Build a throwaway repo with a file in a subdir; invoke the executor FROM
# the subdir with a repo-root-relative path. It must stage that path
# against the repo root (no subdir/subdir doubling), proving the cd to
# `git rev-parse --show-toplevel` works. We use --dry-run so nothing is
# pushed; the git add itself is real (dry-run only stubs push/gh, not add).

REPO="$WORK/repo72"
mkdir -p "$REPO/frontend/src"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t
printf 'x\n' > "$REPO/frontend/src/a.ts"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init

PLAN_CWD="$(write_plan cwd.txt 'branch: b
mode: push
file: frontend/src/a.ts
message:
chore: touch')"
printf 'y\n' > "$REPO/frontend/src/a.ts"   # a real change to stage
OUT_CWD="$(cd "$REPO/frontend" && bash "$BIN" --dry-run --plan "$PLAN_CWD" 2>&1)"
RC_CWD=$?
assert_exit "P2: dry-run from subdir exits 0" 0 "$RC_CWD"
assert_contains "P2: stages repo-root path" "frontend/src/a.ts" "$OUT_CWD"
assert_not_contains "P2: no doubled subdir prefix" "frontend/frontend" "$OUT_CWD"

# not-a-git-repo -> exit 2
NOREPO="$WORK/notrepo"
mkdir -p "$NOREPO"
PLAN_NR="$(write_plan nr.txt 'branch: b
mode: push
file: a.py
message:
x')"
RC_NR=0
(cd "$NOREPO" && bash "$BIN" --dry-run --plan "$PLAN_NR") >/dev/null 2>&1 || RC_NR=$?
assert_exit "P2: outside a git repo -> exit 2" 2 "$RC_NR"

# --- 7.3: already-committed files -> skip commit, warn loudly (P4) -------
# Real (non-dry) run against a throwaway repo with NO remote. The files are
# already committed and the working tree is clean for them, so the executor
# must skip the commit, print the WARNING, and NOT create a second commit.
# Push then fails (no remote) at exit 4 — expected; we assert on the commit
# count and the warning, which happen before the push.

REPO2="$WORK/repo73"
mkdir -p "$REPO2"
git -C "$REPO2" init -q
git -C "$REPO2" config user.email t@t.t
git -C "$REPO2" config user.name t
printf 'v1\n' > "$REPO2/a.py"
git -C "$REPO2" add -A
git -C "$REPO2" commit -qm "feat: a"
COUNT_BEFORE="$(git -C "$REPO2" rev-list --count HEAD)"

PLAN_AC="$(write_plan already.txt 'branch: b
mode: push
file: a.py
message:
feat: a (again)')"
OUT_AC="$(cd "$REPO2" && bash "$BIN" --plan "$PLAN_AC" 2>&1)"
RC_AC=$?
COUNT_AFTER="$(git -C "$REPO2" rev-list --count HEAD)"
assert_contains "P4: warns loudly when nothing to stage" "nothing to stage" "$OUT_AC"
assert_exit "P4: commit count unchanged (no empty commit)" "$COUNT_BEFORE" "$COUNT_AFTER"
assert_exit "P4: push fails with no remote -> exit 4" 4 "$RC_AC"
assert_contains "P4: failure msg reflects no new commit" "nothing committed, push failed" "$OUT_AC"

# (b) a genuinely-staged change commits and does NOT warn
REPO3="$WORK/repo73b"
mkdir -p "$REPO3"
git -C "$REPO3" init -q
git -C "$REPO3" config user.email t@t.t
git -C "$REPO3" config user.name t
printf 'v1\n' > "$REPO3/a.py"
git -C "$REPO3" add -A
git -C "$REPO3" commit -qm "feat: a"
printf 'v2\n' > "$REPO3/a.py"    # real change
CNT3_BEFORE="$(git -C "$REPO3" rev-list --count HEAD)"
PLAN_ST="$(write_plan staged.txt 'branch: b
mode: push
file: a.py
message:
feat: bump')"
OUT_ST="$(cd "$REPO3" && bash "$BIN" --plan "$PLAN_ST" 2>&1)"
CNT3_AFTER="$(git -C "$REPO3" rev-list --count HEAD)"
assert_not_contains "P4: real change does NOT warn" "nothing to stage" "$OUT_ST"
assert_exit "P4: real change creates one commit" "$((CNT3_BEFORE + 1))" "$CNT3_AFTER"

# --- 7.5: PR title is the message SUBJECT, not the whole message (P5) ----
# BUG-2026-07-07: the full multi-line message was passed as --title, which
# overflows GitHub's 256-char title cap for any commit with a body. The
# title must be the first line only; the full message goes to --body; the
# conflicting --fill flag must be gone. Dry-run prints %q-quoted args, so
# a space in the subject renders as '\ '.

PR_MULTI="$(write_plan pr-multi.txt 'branch: feature/x
mode: pr
base: main
file: a.py
message:
feat: short subject
Long body line one.
Long body line two.')"
run_dry "$PR_MULTI"
assert_exit "P5: multi-line pr plan exits 0" 0 "$RC"
assert_contains "P5: title is subject only, body follows" \
  "--title feat:\\ short\\ subject --body" "$OUT"
assert_not_contains "P5: no --fill flag" "--fill" "$OUT"

# (b) single-line message: title equals the message
run_dry "$VALID_PR"
assert_contains "P5: single-line title equals message" \
  "--title fix:\\ thing --body" "$OUT"

# --- 8.2: leading # comment lines are ignored by the parser --------------
# pr-merge plans are REQUIRED to carry a leading "# ... irreversible"
# comment (shown to the user in the Write approval dialog), so comment
# tolerance is load-bearing, not incidental.

PR_COMMENT="$(write_plan pr-comment.txt '# pr-merge: PR will be MERGED into main — irreversible
branch: feature/x
mode: pr-merge
base: main
file: a.py
message:
fix: thing')"
run_dry "$PR_COMMENT"
assert_exit "comment line: plan still parses, exit 0" 0 "$RC"
assert_contains "comment line: merge step present" "gh pr merge --squash" "$OUT"

# --- 7.6: upstream pointing at a DIFFERENT branch -> push -u origin <b> ---
# P6 (found 2026-07-09): `git worktree add -b <b> ... origin/main` leaves
# the branch tracking origin/main; a plain `git push` then fails on the
# name mismatch. The executor must only plain-push when the upstream IS
# origin/<branch>, and otherwise push explicitly with -u. Local bare repo
# as the remote — a real push, no network.

BARE76="$WORK/bare76.git"
git init -q --bare "$BARE76"
REPO76="$WORK/repo76"
mkdir -p "$REPO76"
git -C "$REPO76" init -q -b main
git -C "$REPO76" config user.email t@t.t
git -C "$REPO76" config user.name t
printf 'x\n' > "$REPO76/a.py"
git -C "$REPO76" add a.py
git -C "$REPO76" commit -qm init
git -C "$REPO76" remote add origin "$BARE76"
git -C "$REPO76" push -qu origin main
git -C "$REPO76" checkout -q -b b
git -C "$REPO76" branch -q -u origin/main b   # the mismatch under test
printf 'y\n' > "$REPO76/a.py"
PLAN76="$(write_plan up76.txt 'branch: b
mode: push
file: a.py
message:
fix: bump')"
OUT76="$(cd "$REPO76" && bash "$BIN" --plan "$PLAN76" 2>&1)"
RC76=$?
assert_exit "P6: mismatched upstream -> delivery succeeds, exit 0" 0 "$RC76"
B_ON_REMOTE=0
git -C "$BARE76" rev-parse --verify -q refs/heads/b >/dev/null && B_ON_REMOTE=1
assert_exit "P6: branch b arrived on the remote" 1 "$B_ON_REMOTE"
UP76="$(git -C "$REPO76" rev-parse --abbrev-ref 'b@{u}' 2>/dev/null)"
assert_contains "P6: upstream re-pointed to origin/b" "origin/b" "$UP76"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
