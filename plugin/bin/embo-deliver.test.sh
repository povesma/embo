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
git -C "$REPO2" init -q -b b     # start ON plan.branch so reconcile is a no-op
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
git -C "$REPO3" init -q -b b     # start ON plan.branch so reconcile is a no-op
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

# --- BUG-2026-07-22: branch reconcile + protected-base guard -------------
# The executor must treat plan.branch as authoritative for where the commit
# lands, never the ambient checked-out branch. Regression: a commit landed
# on main while the push targeted a stale feature branch.

# (a) protected base as a push target -> refuse, exit 7, no git changes.
#     This is a validation-time check (before any git state), so --dry-run
#     exercises it and asserts nothing runs.
for b in main master; do
  PLAN_PROT="$(write_plan "prot-$b.txt" "branch: $b
mode: push
file: a.py
message:
x")"
  run_dry "$PLAN_PROT"
  assert_exit "reconcile: push to protected '$b' -> exit 7" 7 "$RC"
  assert_contains "reconcile: names the protected branch '$b'" "$b" "$OUT"
  assert_not_contains "reconcile: protected push runs no git add" "add -- " "$OUT"
done

# (b) protected branch as a PR *base* is legitimate -> not refused.
run_dry "$VALID_PR"    # base: main, branch: feature/x
assert_exit "reconcile: main as PR base is allowed, exit 0" 0 "$RC"

# (c) THE BUG: standing on main, plan targets a feature branch that already
#     exists at a stale commit. The commit must land on the feature branch,
#     never on main. Real run against a throwaway repo with a bare remote.
BARE_R="$WORK/bareR.git"
git init -q --bare "$BARE_R"
REPO_R="$WORK/repoR"
mkdir -p "$REPO_R"
git -C "$REPO_R" init -q -b main
git -C "$REPO_R" config user.email t@t.t
git -C "$REPO_R" config user.name t
printf 'x\n' > "$REPO_R/a.py"
git -C "$REPO_R" add a.py
git -C "$REPO_R" commit -qm init
git -C "$REPO_R" branch feat/x           # feature branch exists at init commit
git -C "$REPO_R" remote add origin "$BARE_R"
git -C "$REPO_R" push -qu origin main
MAIN_BEFORE="$(git -C "$REPO_R" rev-parse main)"
# operator is standing on main (the mistake) with a real change to deliver:
git -C "$REPO_R" checkout -q main
printf 'y\n' > "$REPO_R/a.py"
PLAN_R="$(write_plan reconcile.txt 'branch: feat/x
mode: push
file: a.py
message:
fix: bump on the right branch')"
OUT_R="$(cd "$REPO_R" && bash "$BIN" --plan "$PLAN_R" 2>&1)"
RC_R=$?
assert_exit "reconcile: delivery from main -> exit 0" 0 "$RC_R"
MAIN_AFTER="$(git -C "$REPO_R" rev-parse main)"
assert_exit "reconcile: main is UNCHANGED (commit did not land here)" \
  "$MAIN_BEFORE" "$MAIN_AFTER"
HEAD_BRANCH="$(git -C "$REPO_R" symbolic-ref --short HEAD)"
assert_contains "reconcile: HEAD ends on the plan branch" "feat/x" "$HEAD_BRANCH"
FEAT_MSG="$(git -C "$REPO_R" log -1 --format=%s feat/x)"
assert_contains "reconcile: commit landed on feat/x" "fix: bump on the right branch" "$FEAT_MSG"

# (d) branch does not exist + push mode (no base) -> abort, exit 7, no commit.
REPO_N="$WORK/repoN"
mkdir -p "$REPO_N"
git -C "$REPO_N" init -q -b main
git -C "$REPO_N" config user.email t@t.t
git -C "$REPO_N" config user.name t
printf 'x\n' > "$REPO_N/a.py"
git -C "$REPO_N" add a.py
git -C "$REPO_N" commit -qm init
CNT_N_BEFORE="$(git -C "$REPO_N" rev-list --count HEAD)"
printf 'y\n' > "$REPO_N/a.py"
PLAN_N="$(write_plan noexist.txt 'branch: feat/new
mode: push
file: a.py
message:
fix: bump')"
OUT_N="$(cd "$REPO_N" && bash "$BIN" --plan "$PLAN_N" 2>&1)"
RC_N=$?
assert_exit "reconcile: push to absent branch (no base) -> exit 7" 7 "$RC_N"
assert_contains "reconcile: message tells operator to create it or use pr" "does not exist" "$OUT_N"
CNT_N_AFTER="$(git -C "$REPO_N" rev-list --count HEAD)"
assert_exit "reconcile: no commit made when aborting" "$CNT_N_BEFORE" "$CNT_N_AFTER"

# (e) branch does not exist + pr mode with base -> created from BASE, not
#     from ambient HEAD. The fixture deliberately puts HEAD on a branch that
#     is NOT base: main carries an extra commit, and the operator stands on
#     `other` (forked from init). If the code wrongly created the new branch
#     from HEAD instead of `base`, the new branch's parent would be init
#     (other's tip), not main's tip — so the parent assertion is load-bearing.
BARE_C="$WORK/bareC.git"
git init -q --bare "$BARE_C"
REPO_C="$WORK/repoC"
mkdir -p "$REPO_C"
git -C "$REPO_C" init -q -b main
git -C "$REPO_C" config user.email t@t.t
git -C "$REPO_C" config user.name t
printf 'x\n' > "$REPO_C/a.py"
git -C "$REPO_C" add a.py
git -C "$REPO_C" commit -qm init
git -C "$REPO_C" checkout -q -b other      # forked from init
git -C "$REPO_C" checkout -q main
printf 'x2\n' > "$REPO_C/b.py"              # main advances beyond init
git -C "$REPO_C" add b.py
git -C "$REPO_C" commit -qm "main: second commit"
MAIN_TIP="$(git -C "$REPO_C" rev-parse main)"
git -C "$REPO_C" remote add origin "$BARE_C"
git -C "$REPO_C" push -qu origin main
git -C "$REPO_C" checkout -q other          # operator stands on `other`, NOT base
printf 'y\n' > "$REPO_C/a.py"
# pr mode invokes gh, which is not present in the test env; the branch
# creation + commit + push happen BEFORE gh. We assert the branch was
# created from base (its parent is main's tip) and the commit landed on it,
# regardless of the gh step.
PLAN_C="$(write_plan create-pr.txt 'branch: feat/created
mode: pr
base: main
file: a.py
message:
feat: on a freshly created branch')"
OUT_C="$(cd "$REPO_C" && bash "$BIN" --plan "$PLAN_C" 2>&1)" || true
CREATED=0
git -C "$REPO_C" show-ref --verify --quiet refs/heads/feat/created && CREATED=1
assert_exit "reconcile: pr mode created the absent branch from base" 1 "$CREATED"
if [ "$CREATED" -eq 1 ]; then
  C_MSG="$(git -C "$REPO_C" log -1 --format=%s feat/created)"
  assert_contains "reconcile: commit landed on the created branch" "feat: on a freshly created branch" "$C_MSG"
  # the new commit's parent must be main's tip — proving create-from-base,
  # not create-from-HEAD (which would parent it on `other`/init).
  C_PARENT="$(git -C "$REPO_C" rev-parse 'feat/created^')"
  assert_exit "reconcile: created branch is rooted on base (not ambient HEAD)" \
    "$MAIN_TIP" "$C_PARENT"
fi

# (f) reconcile does NOT run under --dry-run (dry-run mutates no git state).
#     A dry-run plan targeting a protected base for PUSH still hits the (a)
#     validation refusal; but a dry-run targeting an absent feature branch
#     must NOT abort at reconcile, because reconcile is skipped in dry mode.
PLAN_DRY="$(write_plan dry-absent.txt 'branch: feat/whatever
mode: push
file: a.py
message:
x')"
run_dry "$PLAN_DRY"
assert_exit "reconcile: dry-run skips reconcile (no exit 7 for absent branch)" 0 "$RC"

# --- T043 1.0: mode: release (dry-run contract) --------------------------
# A release is a pr-merge PLUS a tail: after merge, tag vX.Y.Z on the merge
# commit and publish a non-draft/non-prerelease GitHub Release. The executor
# writes NOTHING to source files — the maintainer edits the version
# manifests + CHANGELOG beforehand and lists them as ordinary `file:`
# entries (verified by the skill, never by the executor). New plan fields:
# `version:` (the vX.Y.Z to tag) and a `release-notes:` block (the Release
# body). Dry-run must PRINT each step in order and run nothing.

REL_PLAN='# release: merge + PUBLIC tag + Release — irreversible
branch: feature/rel
mode: release
base: main
version: 9.9.9
file: plugin/.claude-plugin/plugin.json
file: CHANGELOG.md
release-notes:
embo 9.9.9

Highlights: the thing works.
message:
release: 9.9.9'

REL="$(write_plan release.txt "$REL_PLAN")"
run_dry "$REL"
assert_exit "release: valid dry-run plan exits 0" 0 "$RC"
# the executor stages ONLY the plan's file list (maintainer-prepared) —
# it never edits or names manifests itself.
assert_contains "release: stages the maintainer-edited manifest" "plugin.json" "$OUT"
assert_contains "release: stages the maintainer-edited CHANGELOG" "CHANGELOG.md" "$OUT"
assert_contains "release: commits"                    "git commit" "$OUT"
assert_contains "release: pushes"                     "git push" "$OUT"
assert_contains "release: opens a PR"                 "gh pr create" "$OUT"
assert_contains "release: merges"                     "gh pr merge --squash" "$OUT"
assert_contains "release: tags vX.Y.Z"                "git tag" "$OUT"
assert_contains "release: tag carries the v-prefixed version" "v9.9.9" "$OUT"
assert_contains "release: publishes a GitHub Release"  "gh release create" "$OUT"
# the executor must NOT edit files itself — no jq, no manifest write step.
assert_not_contains "release: executor does not run jq" "jq " "$OUT"

# ordering: merge before tag; tag before release.
line_of() { printf '%s\n' "$OUT" | grep -n -- "$1" | head -1 | cut -d: -f1; }
N_MERGE="$(line_of 'gh pr merge')"
N_TAG="$(line_of 'git tag')"
N_REL="$(line_of 'gh release create')"
assert_exit "release: merge precedes tag"   1 "$([ -n "$N_MERGE" ] && [ -n "$N_TAG" ] && [ "$N_MERGE" -lt "$N_TAG" ] && echo 1 || echo 0)"
assert_exit "release: tag precedes publish" 1 "$([ -n "$N_TAG" ] && [ -n "$N_REL" ] && [ "$N_TAG" -lt "$N_REL" ] && echo 1 || echo 0)"

# release requires version:
REL_NOVER="$(write_plan rel-nover.txt '# release — irreversible
branch: feature/rel
mode: release
base: main
file: CHANGELOG.md
release-notes:
notes
message:
release: x')"
run_dry "$REL_NOVER"
assert_exit "release: missing version: -> exit 2" 2 "$RC"
assert_not_contains "release: no-version plan runs no git add" "add -- " "$OUT"

# release requires base:
REL_NOBASE="$(write_plan rel-nobase.txt '# release — irreversible
branch: feature/rel
mode: release
version: 9.9.9
file: CHANGELOG.md
release-notes:
notes
message:
release: x')"
run_dry "$REL_NOBASE"
assert_exit "release: missing base: -> exit 2" 2 "$RC"

# release requires a release-notes: block (the GitHub Release body)
REL_NONOTES="$(write_plan rel-nonotes.txt '# release — irreversible
branch: feature/rel
mode: release
base: main
version: 9.9.9
file: CHANGELOG.md
message:
release: x')"
run_dry "$REL_NONOTES"
assert_exit "release: missing release-notes: -> exit 2" 2 "$RC"

# --- T043 2.0: release halts on failure, undoes nothing ------------------
# Real run of a release plan where the PR step fails. The commit + push
# must already have happened and NOT be reverted; the run stops with the
# step's documented exit code (5, PR not created).
#
# CRITICAL: the host may have a real `gh` on PATH. A test must make NO real
# network/API call, so we shadow `gh` with a stub that always fails,
# injected at the FRONT of PATH for this run only. This makes the failing
# step deterministic regardless of the host and guarantees no GitHub API is
# touched.
STUBDIR="$WORK/stubbin"
mkdir -p "$STUBDIR"
printf '#!/usr/bin/env bash\necho "stub gh: forced failure" >&2\nexit 1\n' > "$STUBDIR/gh"
chmod +x "$STUBDIR/gh"

BARE_H="$WORK/bareH.git"
git init -q --bare "$BARE_H"
REPO_H="$WORK/repoH"
mkdir -p "$REPO_H"
git -C "$REPO_H" init -q -b relbranch   # start ON the plan branch
git -C "$REPO_H" config user.email t@t.t
git -C "$REPO_H" config user.name t
printf 'v1\n' > "$REPO_H/a.py"
git -C "$REPO_H" add a.py
git -C "$REPO_H" commit -qm init
git -C "$REPO_H" remote add origin "$BARE_H"
git -C "$REPO_H" push -qu origin relbranch
CNT_H_BEFORE="$(git -C "$REPO_H" rev-list --count HEAD)"
printf 'v2\n' > "$REPO_H/a.py"          # a real release change
PLAN_H="$(write_plan rel-halt.txt '# release — irreversible
branch: relbranch
mode: release
base: main
version: 9.9.9
file: a.py
release-notes:
notes body
message:
release: 9.9.9')"
# stub gh at the front of PATH -> gh pr create fails -> exit 5, AFTER the
# commit + push already succeeded.
OUT_H="$(cd "$REPO_H" && PATH="$STUBDIR:$PATH" bash "$BIN" --plan "$PLAN_H" 2>&1)"
RC_H=$?
CNT_H_AFTER="$(git -C "$REPO_H" rev-list --count HEAD)"
# The commit was made (count grew by 1) and is NOT undone by the failure.
assert_exit "release halt: the release commit was made and kept" \
  "$((CNT_H_BEFORE + 1))" "$CNT_H_AFTER"
assert_exit "release halt: stops at the PR step -> exit 5" 5 "$RC_H"
assert_not_contains "release halt: no reset/undo was attempted" "reset" "$OUT_H"
# commit + push happened before the gh call; the status line says so, and
# the tag/publish tail never ran.
assert_contains "release halt: status shows commit+push before the halt" "committed, pushed" "$OUT_H"
assert_not_contains "release halt: tag step did not run" "tagged v9.9.9" "$OUT_H"
# no v-tag was created locally, since the tail is past the failing step.
HAS_TAG=0
git -C "$REPO_H" rev-parse -q --verify refs/tags/v9.9.9 >/dev/null 2>&1 && HAS_TAG=1
assert_exit "release halt: no tag created (tail never reached)" 0 "$HAS_TAG"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
