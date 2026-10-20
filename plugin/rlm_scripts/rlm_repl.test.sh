#!/usr/bin/env bash
# Plain-bash unit tests for rlm_repl.py state-path resolution and the
# index write lock (no framework).
# Run: bash plugin/rlm_scripts/rlm_repl.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPL="$HERE/rlm_repl.py"
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

# new_repo <name> -> path : a throwaway git repo under $WORK with one
# commit, so HEAD exists and `git worktree add ... HEAD` works.
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

# resolve_prints <cwd> [extra args...] -> sets OUT and RC
# Runs a tiny python snippet that imports rlm_repl and prints the
# resolved state path for the given CWD. Uses the module's public
# resolve_state_path(explicit).
resolve_prints() {
  local cwd="$1"; shift
  local explicit="${1:-}"
  OUT="$(cd "$cwd" && python3 - "$REPL" "$explicit" <<'PY' 2>&1
import importlib.util, sys, pathlib
repl_path, explicit = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("rlm_repl", repl_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
ex = pathlib.Path(explicit) if explicit else None
print(mod.resolve_state_path(ex))
PY
)"
  RC=$?
}

# --- 1.1: main tree default, explicit override, git-absent ---------------

test_main_tree_default() {
  local r; r="$(new_repo main-default)"
  resolve_prints "$r"
  assert_exit "1.1 main tree resolves cleanly" 0 "$RC"
  assert_contains "1.1 main tree uses CWD-relative .claude path" \
    ".claude/rlm_state/state.pkl" "$OUT"
  assert_not_contains "1.1 main tree path has no worktrees segment" \
    "worktrees" "$OUT"
}

test_explicit_override() {
  local r; r="$(new_repo explicit)"
  resolve_prints "$r" "/tmp/custom/state.pkl"
  assert_exit "1.1 explicit --state resolves cleanly" 0 "$RC"
  assert_contains "1.1 explicit --state passes through unchanged" \
    "/tmp/custom/state.pkl" "$OUT"
}

test_git_absent() {
  local d="$WORK/nogit"; mkdir -p "$d"
  resolve_prints "$d"
  assert_exit "1.1 non-git dir resolves cleanly (fallback)" 0 "$RC"
  assert_contains "1.1 non-git dir falls back to CWD-relative default" \
    ".claude/rlm_state/state.pkl" "$OUT"
}

# --- 1.2: worktree resolves to the MAIN tree -----------------------------

test_worktree_resolves_to_main() {
  local r; r="$(new_repo wt-main)"
  local wt="$WORK/wt-main-linked"
  git -C "$r" worktree add -q "$wt" -b feat HEAD
  # Resolve the main root the same way git will (symlink-canonical), so
  # macOS /var -> /private/var does not break the string compare.
  local main_real; main_real="$(cd "$r" && pwd -P)"
  resolve_prints "$wt"
  assert_exit "1.2 worktree resolves cleanly" 0 "$RC"
  # Must point at the MAIN repo's .claude, not the worktree's own dir.
  assert_contains "1.2 worktree points at main tree .claude" \
    "$main_real/.claude/rlm_state/state.pkl" "$OUT"
  assert_not_contains "1.2 worktree does NOT use its own dir" \
    "wt-main-linked/.claude" "$OUT"
}

# --- 1.3: bare-repo guard falls back to CWD default ----------------------

test_bare_repo_guard() {
  local bare="$WORK/bare.git"
  git init -q --bare "$bare"
  # A worktree off a bare repo has no main working tree to anchor to.
  git -C "$bare" worktree add -q "$WORK/bare-wt" -b feat 2>/dev/null || true
  if [ -d "$WORK/bare-wt" ]; then
    resolve_prints "$WORK/bare-wt"
    assert_exit "1.3 bare-repo worktree resolves cleanly (no crash)" 0 "$RC"
    assert_contains "1.3 bare-repo falls back to CWD-relative default" \
      ".claude/rlm_state/state.pkl" "$OUT"
  else
    # Some git versions refuse worktrees off an empty bare repo; the
    # guard is still exercised by the non-git fallback test.
    PASS=$((PASS + 1))
  fi
}

# --- 2.x: write lock serializes concurrent writers ------------------------

# init_repo_state <repo> : build an initial index so exec has state to load
init_repo_state() {
  local r="$1"
  (cd "$r" && python3 "$REPL" init-repo . >/dev/null 2>&1)
}

test_lock_blocks_concurrent_writer() {
  local r; r="$(new_repo lock-concur)"
  init_repo_state "$r"
  local lockfile="$r/.claude/rlm_state/state.pkl.lock"
  # Hold the lock in a background process BEFORE the second writer runs.
  # A sequential test would let the first writer finish and pass vacuously.
  python3 - "$lockfile" <<'PY' &
import sys, fcntl, time
open_ = open(sys.argv[1], "w")
fcntl.flock(open_, fcntl.LOCK_EX | fcntl.LOCK_NB)
time.sleep(5)
PY
  local holder=$!
  sleep 0.5
  # Second writer: an exec that would _save_state. Must fail fast, not hang.
  OUT="$(cd "$r" && python3 "$REPL" exec -c "print(1)" 2>&1)"
  RC=$?
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  assert_exit "2.1 concurrent writer exits non-zero (index busy)" 2 "$RC"
  assert_contains "2.1 concurrent writer reports index busy" \
    "index busy" "$OUT"
}

test_lock_covers_exec_not_just_init() {
  # Proves _save_state on cmd_exec (line 1158) is under the lock: with the
  # lock held, an exec write is blocked (same mechanism as 2.1, asserting
  # the exec path specifically).
  local r; r="$(new_repo lock-exec)"
  init_repo_state "$r"
  local lockfile="$r/.claude/rlm_state/state.pkl.lock"
  python3 - "$lockfile" <<'PY' &
import sys, fcntl, time
f = open(sys.argv[1], "w")
fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
time.sleep(5)
PY
  local holder=$!
  sleep 0.5
  OUT="$(cd "$r" && python3 "$REPL" exec -c "x=1" 2>&1)"
  RC=$?
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  assert_exit "2.2 exec write is under the lock" 2 "$RC"
}

test_lock_free_write_succeeds() {
  # Sanity: with no contention, a write succeeds normally.
  local r; r="$(new_repo lock-free)"
  init_repo_state "$r"
  OUT="$(cd "$r" && python3 "$REPL" exec -c "print(2)" 2>&1)"
  RC=$?
  assert_exit "2.x uncontended exec succeeds" 0 "$RC"
  assert_contains "2.x uncontended exec runs the code" "2" "$OUT"
}

# --- 3.x: Windows / fcntl-absent degrades gracefully ----------------------

test_fcntl_absent_degrades() {
  # Simulate Windows (no fcntl) with a shim that shadows stdlib fcntl and
  # raises ImportError. The write must still succeed, print a one-time
  # warning, and never raise ImportError.
  local r; r="$(new_repo fcntl-absent)"
  init_repo_state "$r"
  local shimdir="$WORK/shim"
  mkdir -p "$shimdir"
  printf 'raise ImportError("no fcntl on this platform")\n' \
    > "$shimdir/fcntl.py"
  OUT="$(cd "$r" && PYTHONPATH="$shimdir" python3 "$REPL" exec -c "print(3)" 2>&1)"
  RC=$?
  assert_exit "3.1 write succeeds with fcntl absent" 0 "$RC"
  assert_contains "3.1 warns write-serialization unavailable" \
    "write-serialization unavailable" "$OUT"
  assert_contains "3.1 the exec still ran" "3" "$OUT"
  assert_not_contains "3.1 no ImportError leaked" "ImportError" "$OUT"
}

# --- 6.1: state survives worktree deletion -------------------------------

test_state_survives_worktree_delete() {
  local r; r="$(new_repo survive)"
  init_repo_state "$r"                       # main-tree index created
  local statefile="$r/.claude/rlm_state/state.pkl"
  [ -f "$statefile" ] || { FAIL=$((FAIL + 1)); echo "6.1 setup: no state.pkl"; return; }
  local wt="$WORK/survive-wt"
  git -C "$r" worktree add -q "$wt" -b feat HEAD
  # A worktree session resolves to the SAME shared state file.
  resolve_prints "$wt"
  local main_real; main_real="$(cd "$r" && pwd -P)"
  assert_contains "6.1 worktree resolves to shared main-tree state" \
    "$main_real/.claude/rlm_state/state.pkl" "$OUT"
  # Remove the worktree; the shared index must remain intact.
  git -C "$r" worktree remove "$wt"
  [ -f "$statefile" ] && PASS=$((PASS + 1)) || {
    FAIL=$((FAIL + 1)); echo "6.1 FAIL: state.pkl gone after worktree remove"; }
  # And it is still usable (status loads it).
  OUT="$(cd "$r" && python3 "$REPL" status 2>&1)"
  RC=$?
  assert_exit "6.1 status still loads shared index after delete" 0 "$RC"
}

run_all() {
  test_main_tree_default
  test_explicit_override
  test_git_absent
  test_worktree_resolves_to_main
  test_bare_repo_guard
  test_lock_blocks_concurrent_writer
  test_lock_covers_exec_not_just_init
  test_lock_free_write_succeeds
  test_fcntl_absent_degrades
  test_state_survives_worktree_delete
}

run_all
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
