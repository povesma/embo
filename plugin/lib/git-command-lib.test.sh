#!/usr/bin/env bash
# Plain-Bash unit tests for git-command-lib.sh (no framework).
# Run: bash plugin/lib/git-command-lib.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/git-command-lib.sh"

# shellcheck source=./git-command-lib.sh
. "$LIB"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$desc" "$exp" "$act"
  fi
}

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

assert_true() {
  local desc="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected true from: %s\n' "$desc" "$*"
  fi
}

assert_false() {
  local desc="$1"; shift
  if ! "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected false from: %s\n' "$desc" "$*"
  fi
}

# ---------------------------------------------------------------------------
# gcl_split
# ---------------------------------------------------------------------------

test_gcl_split_and() {
  local out
  out="$(gcl_split "git add . && git commit -m msg")"
  assert_contains "split &&: first part"  "git add ."        "$out"
  assert_contains "split &&: second part" "git commit -m msg" "$out"
}

test_gcl_split_or() {
  local out
  out="$(gcl_split "git fetch || git pull")"
  assert_contains "split ||: first"  "git fetch" "$out"
  assert_contains "split ||: second" "git pull"  "$out"
}

test_gcl_split_semicolon() {
  local out
  out="$(gcl_split "git status; git log")"
  assert_contains "split ;: first"  "git status" "$out"
  assert_contains "split ;: second" "git log"    "$out"
}

test_gcl_split_pipe() {
  local out
  out="$(gcl_split "git log --oneline | head -5")"
  assert_contains "split |: first"  "git log --oneline" "$out"
  assert_contains "split |: second" "head -5"           "$out"
}

test_gcl_split_pipe_amp() {
  local out
  out="$(gcl_split "cmd1 |& cmd2")"
  assert_contains "split |&: first"  "cmd1" "$out"
  assert_contains "split |&: second" "cmd2" "$out"
}

test_gcl_split_amp() {
  local out
  out="$(gcl_split "git push origin main & echo done")"
  assert_contains "split &: first"  "git push origin main" "$out"
  assert_contains "split &: second" "echo done"            "$out"
}

test_gcl_split_newline() {
  local out
  out="$(gcl_split "$(printf 'git add .\ngit commit -m x')")"
  assert_contains "split newline: first"  "git add ."    "$out"
  assert_contains "split newline: second" "git commit" "$out"
}

test_gcl_split_single() {
  local out
  out="$(gcl_split "git status")"
  assert_eq "split single: no split" "git status" "$out"
}

test_gcl_split_trims_whitespace() {
  local out
  out="$(gcl_split "  git add .  &&  git commit  ")"
  assert_contains "split trims: first"  "git add ." "$out"
  assert_contains "split trims: second" "git commit" "$out"
  assert_not_contains "split trims: no leading space" "  git" "$out"
}

test_gcl_split_empty_segments_dropped() {
  local count
  count="$(gcl_split "git add . && && git commit" | wc -l | tr -d ' ')"
  assert_eq "split drops empty segments" "2" "$count"
}

# ---------------------------------------------------------------------------
# gcl_is_git_mutation
# ---------------------------------------------------------------------------

test_mutation_commit() {
  assert_true  "commit is mutation"           gcl_is_git_mutation "git commit -m msg"
  assert_true  "commit --amend is mutation"   gcl_is_git_mutation "git commit --amend"
}

test_mutation_merge() {
  assert_true  "merge is mutation"            gcl_is_git_mutation "git merge feature"
  assert_true  "merge --no-ff is mutation"    gcl_is_git_mutation "git merge --no-ff feat"
}

test_mutation_rebase() {
  assert_true  "rebase is mutation"           gcl_is_git_mutation "git rebase main"
  assert_true  "rebase -i is mutation"        gcl_is_git_mutation "git rebase -i HEAD~3"
}

test_mutation_cherry_pick() {
  assert_true  "cherry-pick is mutation"      gcl_is_git_mutation "git cherry-pick abc123"
}

test_mutation_am() {
  assert_true  "am is mutation"               gcl_is_git_mutation "git am patch.mbox"
}

test_mutation_revert() {
  assert_true  "revert is mutation"           gcl_is_git_mutation "git revert HEAD"
}

test_mutation_reset_hard() {
  assert_true  "reset --hard is mutation"     gcl_is_git_mutation "git reset --hard HEAD~1"
  assert_true  "reset --soft is mutation"     gcl_is_git_mutation "git reset --soft HEAD~1"
  assert_true  "reset --mixed is mutation"    gcl_is_git_mutation "git reset --mixed HEAD~1"
}

test_mutation_reset_bare_not_mutation() {
  assert_false "bare reset is NOT mutation"   gcl_is_git_mutation "git reset"
  assert_false "reset <file> is NOT mutation" gcl_is_git_mutation "git reset -- file.txt"
}

test_mutation_global_options() {
  assert_true  "git -C dir commit is mutation"     gcl_is_git_mutation "git -C ../repo commit -m x"
  assert_true  "env-prefixed commit is mutation"   gcl_is_git_mutation "GIT_EDITOR=true git commit"
  assert_true  "quoted message with && kept whole" gcl_is_git_mutation "git commit -m 'a && b'"
}

test_mutation_abort_not_mutation() {
  assert_false "merge --abort is recovery"         gcl_is_git_mutation "git merge --abort"
  assert_false "rebase --abort is recovery"        gcl_is_git_mutation "git rebase --abort"
}

test_non_mutations() {
  assert_false "status is not mutation"       gcl_is_git_mutation "git status"
  assert_false "log is not mutation"          gcl_is_git_mutation "git log --oneline"
  assert_false "diff is not mutation"         gcl_is_git_mutation "git diff HEAD"
  assert_false "fetch is not mutation"        gcl_is_git_mutation "git fetch origin"
  assert_false "pull is not mutation"         gcl_is_git_mutation "git pull"
  assert_false "stash is not mutation"        gcl_is_git_mutation "git stash"
  assert_false "add is not mutation"          gcl_is_git_mutation "git add ."
  assert_false "switch is not mutation"       gcl_is_git_mutation "git switch main"
  assert_false "checkout file is not mut"     gcl_is_git_mutation "git checkout -- file.txt"
  assert_false "branch list is not mutation"  gcl_is_git_mutation "git branch --list"
}

# ---------------------------------------------------------------------------
# gcl_walk (branch in effect at each subcommand of a compound)
# ---------------------------------------------------------------------------

# walk_branch_at <command> <current> <subcommand-prefix>
# Branch gcl_walk reports for the first subcommand starting with prefix.
walk_branch_at() {
  gcl_walk "$1" "$2" | awk -F '\t' -v p="$3" 'index($2, p) == 1 { print $1; exit }'
}

test_walk_switch_c() {
  assert_eq "switch -c: commit runs on the new branch" "feat/x" \
    "$(walk_branch_at "git switch -c feat/x && git commit -m x" main "git commit")"
}

test_walk_checkout_b() {
  assert_eq "checkout -b: commit runs on the new branch" "feat/y" \
    "$(walk_branch_at "git checkout -b feat/y && git commit -m y" main "git commit")"
}

test_walk_switch_existing() {
  assert_eq "plain switch: commit runs on the switched-to branch" "feat/x" \
    "$(walk_branch_at "git switch feat/x && git commit -m x" main "git commit")"
}

test_walk_checkout_ambiguous_stays() {
  assert_eq "plain checkout (branch or path): branch unchanged" "main" \
    "$(walk_branch_at "git checkout feat/x && git commit -m x" main "git commit")"
}

test_walk_worktree_add_without_cd_stays() {
  assert_eq "worktree add alone: shell still in the main worktree" "main" \
    "$(walk_branch_at "git worktree add ../wt feat/z && git commit -m z" main "git commit")"
}

test_walk_worktree_add_then_cd() {
  assert_eq "worktree add <path> <branch> then cd: worktree branch" "feat/z" \
    "$(walk_branch_at "git worktree add ../wt feat/z && cd ../wt && git commit -m z" main "git commit")"
  assert_eq "worktree add -b then cd: new branch" "feat/w" \
    "$(walk_branch_at "git worktree add -b feat/w ../wt2 && cd ../wt2/ && git commit -m w" main "git commit")"
}

test_walk_no_create_stays() {
  assert_eq "no branch change: stays on the original" "main" \
    "$(walk_branch_at "git add . && git commit -m x" main "git commit")"
}

test_walk_order_matters() {
  assert_eq "commit BEFORE switch -c still runs on main" "main" \
    "$(walk_branch_at "git commit -m x && git switch -c feat/x" main "git commit")"
}

test_walk_detach() {
  assert_eq "switch --detach: detached (empty branch)" "" \
    "$(walk_branch_at "git switch --detach && git commit -m x" main "git commit")"
}

test_walk_lists_every_subcommand() {
  local count
  count="$(gcl_walk "git add . && git commit -m x && git push" main | wc -l | tr -d ' ')"
  assert_eq "walk prints one line per subcommand" "3" "$count"
}

# ---------------------------------------------------------------------------
# gcl_push_targets
# ---------------------------------------------------------------------------

test_push_targets_explicit() {
  local out
  out="$(gcl_push_targets "git push origin main" "feat/x")"
  assert_eq "explicit push target" "main" "$out"
}

test_push_targets_implicit_current() {
  local out
  out="$(gcl_push_targets "git push origin" "main")"
  assert_eq "implicit push = current branch" "main" "$out"
}

test_push_targets_head() {
  local out
  out="$(gcl_push_targets "git push origin HEAD" "main")"
  assert_eq "HEAD push target = current branch" "main" "$out"
}

test_push_targets_refspec_dst() {
  local out
  out="$(gcl_push_targets "git push origin feat:main" "feat")"
  assert_eq "src:dst push: target is dst" "main" "$out"
}

test_push_targets_all() {
  local out
  out="$(gcl_push_targets "git push --all origin" "feat")"
  assert_eq "push --all yields --all itself" "--all" "$out"
}

test_push_targets_mirror() {
  local out
  out="$(gcl_push_targets "git push --mirror origin" "feat")"
  assert_eq "push --mirror yields --mirror itself" "--mirror" "$out"
}

test_push_targets_delete() {
  local out
  out="$(gcl_push_targets "git push origin --delete main" "feat")"
  assert_eq "push --delete main targets main" "main" "$out"
}

test_push_targets_feature_from_main() {
  local out
  out="$(gcl_push_targets "git push origin feature" "main")"
  assert_eq "push feature while on main: target is feature only" "feature" "$out"
}

test_push_targets_force_plus_refspec() {
  local out
  out="$(gcl_push_targets "git push origin +feat:main" "feat")"
  assert_eq "+src:dst push: target is dst" "main" "$out"
}

test_push_targets_head_colon_main() {
  local out
  out="$(gcl_push_targets "git push origin HEAD:main" "feat")"
  assert_eq "HEAD:dst push: target is dst" "main" "$out"
}

# ---------------------------------------------------------------------------
# gcl_shell_write_paths
# ---------------------------------------------------------------------------

test_shell_write_redirect() {
  local out
  out="$(gcl_shell_write_paths "echo hello > foo.txt")"
  assert_eq "redirect > target" "foo.txt" "$out"
}

test_shell_write_append() {
  local out
  out="$(gcl_shell_write_paths "echo hello >> foo.txt")"
  assert_eq "redirect >> target" "foo.txt" "$out"
}

test_shell_write_tee() {
  local out
  out="$(gcl_shell_write_paths "cmd | tee foo.txt")"
  assert_eq "tee target" "foo.txt" "$out"
}

test_shell_write_sed_i() {
  local out
  out="$(gcl_shell_write_paths "sed -i 's/a/b/' foo.txt")"
  assert_eq "sed -i target" "foo.txt" "$out"
}

test_shell_write_fd_dup_not_target() {
  assert_eq "2>&1 is an fd dup, not a file" "out.log" \
    "$(gcl_shell_write_paths "make build > out.log 2>&1")"
  assert_eq "2>/dev/null is a device, not a file" "" \
    "$(gcl_shell_write_paths "ls missing 2>/dev/null")"
}

test_shell_write_no_space_redirect() {
  assert_eq "redirect with no space" "foo.txt" "$(gcl_shell_write_paths "echo x >foo.txt")"
}

test_shell_write_sed_bsd_suffix() {
  assert_eq "BSD sed -i '' script file" "foo.txt" \
    "$(gcl_shell_write_paths "sed -i '' 's/a b/c/' foo.txt")"
  assert_eq "sed -e script then file" "foo.txt" \
    "$(gcl_shell_write_paths "sed -i -e 's/a/b/' foo.txt")"
  assert_eq "sed without -i writes nothing" "" \
    "$(gcl_shell_write_paths "sed 's/a/b/' foo.txt")"
}

test_shell_write_quoted_gt_not_redirect() {
  assert_eq "quoted > in a commit message is not a redirect" "" \
    "$(gcl_shell_write_paths "git commit -m 'a > b'")"
}

test_shell_write_readonly_empty() {
  local out
  out="$(gcl_shell_write_paths "git log --oneline")"
  assert_eq "read-only: no paths" "" "$out"
}

test_shell_write_cat_readonly() {
  local out
  out="$(gcl_shell_write_paths "cat foo.txt")"
  assert_eq "cat is read-only: no paths" "" "$out"
}

# ---------------------------------------------------------------------------
# unparseable construct handling
# ---------------------------------------------------------------------------

test_unparseable_subshell_with_git_commit() {
  assert_true  "subshell + git commit = candidate"   gcl_is_unparseable_candidate "git commit -m \"\$(date)\""
}

test_unparseable_backtick_with_push() {
  assert_true  "backtick + git push = candidate"     gcl_is_unparseable_candidate "git push origin \`cat branch\`"
}

test_unparseable_heredoc_with_merge() {
  assert_true  "heredoc + git merge = candidate"     gcl_is_unparseable_candidate "$(printf 'git merge <<EOF\nmain\nEOF')"
}

test_unparseable_eval_with_commit() {
  assert_true  "eval + commit token = candidate"     gcl_is_unparseable_candidate "eval git commit -m x"
}

test_unparseable_bash_c_with_push() {
  assert_true  "bash -c + push token = candidate"    gcl_is_unparseable_candidate "bash -c 'git push origin main'"
}

test_unparseable_subshell_no_git_token() {
  assert_false "subshell without git token = NOT candidate" gcl_is_unparseable_candidate "echo \$(date)"
}

test_unparseable_clean_command() {
  assert_false "clean git log = NOT candidate"       gcl_is_unparseable_candidate "git log --oneline"
}

# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------

run_all() {
  test_gcl_split_and
  test_gcl_split_or
  test_gcl_split_semicolon
  test_gcl_split_pipe
  test_gcl_split_pipe_amp
  test_gcl_split_amp
  test_gcl_split_newline
  test_gcl_split_single
  test_gcl_split_trims_whitespace
  test_gcl_split_empty_segments_dropped

  test_mutation_commit
  test_mutation_merge
  test_mutation_rebase
  test_mutation_cherry_pick
  test_mutation_am
  test_mutation_revert
  test_mutation_reset_hard
  test_mutation_reset_bare_not_mutation
  test_mutation_global_options
  test_mutation_abort_not_mutation
  test_non_mutations

  test_walk_switch_c
  test_walk_checkout_b
  test_walk_switch_existing
  test_walk_checkout_ambiguous_stays
  test_walk_worktree_add_without_cd_stays
  test_walk_worktree_add_then_cd
  test_walk_no_create_stays
  test_walk_order_matters
  test_walk_detach
  test_walk_lists_every_subcommand

  test_push_targets_explicit
  test_push_targets_implicit_current
  test_push_targets_head
  test_push_targets_refspec_dst
  test_push_targets_all
  test_push_targets_mirror
  test_push_targets_delete
  test_push_targets_feature_from_main
  test_push_targets_force_plus_refspec
  test_push_targets_head_colon_main

  test_shell_write_redirect
  test_shell_write_append
  test_shell_write_tee
  test_shell_write_sed_i
  test_shell_write_fd_dup_not_target
  test_shell_write_no_space_redirect
  test_shell_write_sed_bsd_suffix
  test_shell_write_quoted_gt_not_redirect
  test_shell_write_readonly_empty
  test_shell_write_cat_readonly

  test_unparseable_subshell_with_git_commit
  test_unparseable_backtick_with_push
  test_unparseable_heredoc_with_merge
  test_unparseable_eval_with_commit
  test_unparseable_bash_c_with_push
  test_unparseable_subshell_no_git_token
  test_unparseable_clean_command
}

run_all

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
