#!/usr/bin/env bash
# Plain-Bash unit tests for main-branch-guard.sh (no framework).
# Run: bash plugin/hooks/main-branch-guard.test.sh
# Exits non-zero if any assertion fails.
#
# The guard is a PreToolUse hook: Claude Code pipes a JSON payload on
# stdin (tool_name, tool_input, cwd) and reads the decision from the
# hook's stdout/exit code. Each case builds a throwaway git repo with
# `mktemp -d`, writes a case-local profile file pointed at by
# EMBO_PROFILE_ACTIVE (so ~/.claude is never touched), builds the
# payload with `jq -n`, and drives the hook against it.
#
# This file is the shared scaffolding (repo helper, payload builder,
# profile fixture, assert and run helpers). The behaviour cases live
# alongside it.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/main-branch-guard.sh"

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

# Build a throwaway repo with one committed tracked file and leave the
# working tree clean. The guard reads the current branch and whether a
# path is tracked; cases dirty or add files as they need.
#   $1 = case name (used for dir)
#   $2 = branch to leave checked out ("main" stays on the default branch;
#        anything else is created from main; "detach" leaves a detached HEAD)
# Prints the repo path on stdout.
build_repo() {
  local case_name="$1" branch_name="${2:-main}"
  local repo="$TMP/$case_name"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  printf 'x\n' > "$repo/tracked.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init

  case "$branch_name" in
    main) : ;;
    detach) git -C "$repo" switch --detach -q HEAD ;;
    *) git -C "$repo" switch -q -c "$branch_name" ;;
  esac

  printf '%s\n' "$repo"
}

# Write a case-local profile file carrying the three guard fields and
# print its path. Point EMBO_PROFILE_ACTIVE at it so the guard reads
# this policy instead of ~/.claude. A field passed empty is omitted so
# the guard falls back to its built-in default.
#   $1 = case name
#   $2 = protected_branch_mode (block|warn|off, or empty to omit)
#   $3 = branch_task_mode (warn|block|off, or empty to omit)
#   $4 = protected_branches flow list body, e.g. "main, master"
#        (empty omits the field)
make_profile() {
  local case_name="$1" pb_mode="${2:-}" bt_mode="${3:-}" branches="${4:-}"
  local file="$TMP/$case_name.profile.yaml"
  {
    printf 'rules:\n'
    printf '  workflow:\n'
    [ -n "$branches" ] && printf '    protected_branches: [%s]\n' "$branches"
    [ -n "$pb_mode" ] && printf '    protected_branch_mode: %s\n' "$pb_mode"
    [ -n "$bt_mode" ] && printf '    branch_task_mode: %s\n' "$bt_mode"
  } > "$file"
  printf '%s\n' "$file"
}

# Build a PreToolUse payload as JSON and print it. Only the fields the
# guard reads are set; tool_input carries whichever key fits the tool.
#   $1 = tool_name (Edit|Write|NotebookEdit|Bash)
#   $2 = cwd (repo path)
#   $3 = the tool_input value: a path for Edit/Write/NotebookEdit, or the
#        command string for Bash
#   $4 = session_id (optional; the FR-5 mismatch check keys its marker and
#        its active-task lookup on it)
payload() {
  local tool="$1" cwd="$2" val="$3" sid="${4:-}"
  case "$tool" in
    NotebookEdit) jq -n --arg t "$tool" --arg c "$cwd" --arg v "$val" --arg s "$sid" \
      '{tool_name:$t, cwd:$c, session_id:$s, tool_input:{notebook_path:$v}}' ;;
    Bash) jq -n --arg t "$tool" --arg c "$cwd" --arg v "$val" --arg s "$sid" \
      '{tool_name:$t, cwd:$c, session_id:$s, tool_input:{command:$v}}' ;;
    *) jq -n --arg t "$tool" --arg c "$cwd" --arg v "$val" --arg s "$sid" \
      '{tool_name:$t, cwd:$c, session_id:$s, tool_input:{file_path:$v}}' ;;
  esac
}

# Run the guard with a payload on stdin and the given profile file.
# Sets OUT (stdout), ERR (stderr) and RC (exit code). stdout carries the
# JSON decision; stderr carries notices and the deny/warn secondary line.
#   $1 = payload JSON
#   $2 = profile file path (may be empty to exercise the default path)
#   $3 = active-task state dir (optional; EMBO_TASK_STATE_DIR for the
#        FR-5 task lookup). Defaults to an isolated empty dir so the FR-5
#        check never reads the real project tmp/.
#   $4 = guard marker dir (optional; EMBO_GUARD_MARKER_DIR for the FR-5
#        per-session marker). Defaults to an isolated dir so markers from
#        one case never leak into another.
# Both default dirs are unique per call, so FR-5 state is isolated unless
# a case deliberately reuses a dir to exercise marker suppression.
run_guard() {
  local pl="$1" profile="${2:-}"
  local task_dir="${3:-$TMP/taskstate.$$.$RANDOM}"
  local marker_dir="${4:-$TMP/marker.$$.$RANDOM}"
  local errfile="$TMP/.stderr.$$"
  OUT="$(printf '%s' "$pl" \
    | EMBO_PROFILE_ACTIVE="$profile" \
      EMBO_TASK_STATE_DIR="$task_dir" \
      EMBO_GUARD_MARKER_DIR="$marker_dir" \
      bash "$HOOK" 2>"$errfile")"
  RC=$?
  ERR="$(cat "$errfile")"
  rm -f "$errfile"
}

# --- scaffolding self-check -----------------------------------------
# Proves the helpers themselves work before any guard exists. The
# behaviour cases (block/warn/off, tracked/untracked, push targets)
# are added alongside this file.
test_scaffolding_helpers() {
  local repo profile pl
  repo="$(build_repo selfcheck_main main)"
  assert_eq "repo built on main" "main" \
    "$(git -C "$repo" symbolic-ref --short -q HEAD)"
  assert_contains "repo has the committed tracked file" \
    "tracked.txt" "$(git -C "$repo" ls-files)"

  repo="$(build_repo selfcheck_feat feat/055-x)"
  assert_eq "repo built on a feature branch" "feat/055-x" \
    "$(git -C "$repo" symbolic-ref --short -q HEAD)"

  profile="$(make_profile selfcheck block warn "main, master")"
  assert_contains "profile carries the block mode" \
    "protected_branch_mode: block" "$(cat "$profile")"
  assert_contains "profile carries the branch list" \
    "protected_branches: [main, master]" "$(cat "$profile")"

  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  assert_eq "Edit payload names the tool" "Edit" \
    "$(printf '%s' "$pl" | jq -r '.tool_name')"
  assert_eq "Edit payload carries file_path" "$repo/tracked.txt" \
    "$(printf '%s' "$pl" | jq -r '.tool_input.file_path')"

  pl="$(payload Bash "$repo" 'git commit -m x')"
  assert_eq "Bash payload carries the command" "git commit -m x" \
    "$(printf '%s' "$pl" | jq -r '.tool_input.command')"

  pl="$(payload NotebookEdit "$repo" "$repo/nb.ipynb")"
  assert_eq "NotebookEdit payload carries notebook_path" "$repo/nb.ipynb" \
    "$(printf '%s' "$pl" | jq -r '.tool_input.notebook_path')"
}

# --- 3.2 Edit/Write/NotebookEdit guard behaviour --------------------

# tracked file on main in `block` -> deny naming branch + the fix
test_edit_tracked_main_block_denies() {
  local repo profile pl
  repo="$(build_repo edit_block main)"
  profile="$(make_profile edit_block block warn "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_eq "3.2: block Edit on main -> exit 0 (JSON deny)" 0 "$RC"
  assert_contains "3.2: deny decision" '"permissionDecision": "deny"' "$OUT"
  assert_contains "3.2: deny names the branch" "main" "$OUT"
  assert_contains "3.2: deny offers the git switch -c fix" "git switch -c" "$OUT"
}

# same on `warn` -> allow (no deny) with a visible warning
test_edit_tracked_main_warn_allows_with_warning() {
  local repo profile pl
  repo="$(build_repo edit_warn main)"
  profile="$(make_profile edit_warn warn warn "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_eq "3.2: warn Edit on main -> exit 0" 0 "$RC"
  assert_not_contains "3.2: warn carries no permissionDecision at all" \
    '"permissionDecision"' "$OUT"
  assert_contains "3.2: warn carries additionalContext" \
    '"additionalContext"' "$OUT"
  assert_contains "3.2: warn surfaces the branch" "main" "$OUT$ERR"
}

# `off` -> allow silently
test_edit_tracked_main_off_silent() {
  local repo profile pl
  repo="$(build_repo edit_off main)"
  profile="$(make_profile edit_off off warn "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_eq "3.2: off -> exit 0" 0 "$RC"
  assert_eq "3.2: off -> no stdout" "" "$OUT"
  assert_not_contains "3.2: off -> no deny" \
    '"permissionDecision"' "$OUT"
}

# new untracked file on main in block -> allow (not yet tracked)
test_edit_untracked_main_block_allows() {
  local repo profile pl
  repo="$(build_repo edit_untracked main)"
  printf 'new\n' > "$repo/fresh.txt"
  profile="$(make_profile edit_untracked block warn "main, master")"
  pl="$(payload Write "$repo" "$repo/fresh.txt")"
  run_guard "$pl" "$profile"
  assert_eq "3.2: untracked Write on main -> exit 0" 0 "$RC"
  assert_not_contains "3.2: untracked -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
}

# out-of-repo path in block -> allow
test_edit_out_of_repo_block_allows() {
  local repo profile pl
  repo="$(build_repo edit_outofrepo main)"
  profile="$(make_profile edit_outofrepo block warn "main, master")"
  pl="$(payload Edit "$repo" "$TMP/outside.txt")"
  run_guard "$pl" "$profile"
  assert_eq "3.2: out-of-repo Edit -> exit 0" 0 "$RC"
  assert_not_contains "3.2: out-of-repo -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
}

# tracked file on an UNPROTECTED branch in block -> allow
test_edit_tracked_feature_block_allows() {
  local repo profile pl
  repo="$(build_repo edit_feature feat/055-x)"
  profile="$(make_profile edit_feature block warn "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_eq "3.2: tracked Edit on feature branch -> exit 0" 0 "$RC"
  assert_not_contains "3.2: unprotected branch -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
}

# NotebookEdit of a tracked notebook on main in block -> deny
test_notebookedit_tracked_main_block_denies() {
  local repo profile pl
  repo="$(build_repo nb_block main)"
  printf '{}\n' > "$repo/book.ipynb"
  git -C "$repo" add -A
  git -C "$repo" commit -qm nb
  profile="$(make_profile nb_block block warn "main, master")"
  pl="$(payload NotebookEdit "$repo" "$repo/book.ipynb")"
  run_guard "$pl" "$profile"
  assert_eq "3.2: block NotebookEdit on main -> exit 0" 0 "$RC"
  assert_contains "3.2: NotebookEdit deny decision" \
    '"permissionDecision": "deny"' "$OUT"
}

# --- 3.6 payload key names pinned by a captured real payload --------
# A real Claude Code PreToolUse payload for Edit/Write uses
# `tool_input.file_path`; NotebookEdit uses `tool_input.notebook_path`.
# This fixture pins those key names so a rename upstream fails loudly.
test_payload_key_names_pinned() {
  local repo pl
  repo="$(build_repo keypin main)"
  pl='{"session_id":"abc","transcript_path":"/x","cwd":"'"$repo"'","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"'"$repo"'/tracked.txt","old_string":"x","new_string":"y"}}'
  assert_eq "3.6: real Edit payload exposes tool_input.file_path" \
    "$repo/tracked.txt" "$(printf '%s' "$pl" | jq -r '.tool_input.file_path')"
  pl='{"cwd":"'"$repo"'","hook_event_name":"PreToolUse","tool_name":"NotebookEdit","tool_input":{"notebook_path":"'"$repo"'/book.ipynb","new_source":"print(1)"}}'
  assert_eq "3.6: real NotebookEdit payload exposes tool_input.notebook_path" \
    "$repo/book.ipynb" "$(printf '%s' "$pl" | jq -r '.tool_input.notebook_path')"
}

# --- 4.1 Bash commit/mutation guard ---------------------------------

# bare git commit on main in block -> deny
test_bash_commit_main_block_denies() {
  local repo profile pl
  repo="$(build_repo bash_commit main)"
  profile="$(make_profile bash_commit block warn "main, master")"
  pl="$(payload Bash "$repo" 'git commit -m wip')"
  run_guard "$pl" "$profile"
  assert_eq "4.1: git commit on main -> exit 0" 0 "$RC"
  assert_contains "4.1: commit deny decision" \
    '"permissionDecision": "deny"' "$OUT"
  assert_contains "4.1: deny names the branch" "main" "$OUT"
  assert_contains "4.1: deny offers the fix" "git switch -c" "$OUT"
}

# merge / rebase / cherry-pick on main in block -> deny
test_bash_merge_main_block_denies() {
  local repo profile pl
  repo="$(build_repo bash_merge main)"
  profile="$(make_profile bash_merge block warn "main, master")"
  pl="$(payload Bash "$repo" 'git merge feature')"
  run_guard "$pl" "$profile"
  assert_contains "4.1: merge on main denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# compound: git add . && git commit on main -> deny
test_bash_compound_commit_main_block_denies() {
  local repo profile pl
  repo="$(build_repo bash_compound main)"
  profile="$(make_profile bash_compound block warn "main, master")"
  pl="$(payload Bash "$repo" 'git add . && git commit -m x')"
  run_guard "$pl" "$profile"
  assert_contains "4.1: compound add+commit on main denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# branch-create precedes the commit -> ALLOW (a false denial here would
# block the deny message's own fix)
test_bash_switch_then_commit_allows() {
  local repo profile pl
  repo="$(build_repo bash_switch main)"
  profile="$(make_profile bash_switch block warn "main, master")"
  pl="$(payload Bash "$repo" 'git switch -c feat/x && git commit -m x')"
  run_guard "$pl" "$profile"
  assert_eq "4.1: switch -c then commit -> exit 0" 0 "$RC"
  assert_not_contains "4.1: switch -c then commit allows" \
    '"permissionDecision": "deny"' "$OUT"
}

# checkout -b precedes the commit -> ALLOW
test_bash_checkout_b_then_commit_allows() {
  local repo profile pl
  repo="$(build_repo bash_checkout main)"
  profile="$(make_profile bash_checkout block warn "main, master")"
  pl="$(payload Bash "$repo" 'git checkout -b feat/x && git commit -m x')"
  run_guard "$pl" "$profile"
  assert_not_contains "4.1: checkout -b then commit allows" \
    '"permissionDecision": "deny"' "$OUT"
}

# read-only command on main -> allow
test_bash_readonly_main_allows() {
  local repo profile pl
  repo="$(build_repo bash_readonly main)"
  profile="$(make_profile bash_readonly block warn "main, master")"
  pl="$(payload Bash "$repo" 'git status && git log --oneline -5')"
  run_guard "$pl" "$profile"
  assert_eq "4.1: read-only on main -> exit 0" 0 "$RC"
  assert_not_contains "4.1: read-only allows" \
    '"permissionDecision": "deny"' "$OUT"
}

# redirect onto a tracked path on main -> deny
test_bash_redirect_tracked_main_block_denies() {
  local repo profile pl
  repo="$(build_repo bash_redirect main)"
  profile="$(make_profile bash_redirect block warn "main, master")"
  pl="$(payload Bash "$repo" 'echo x > tracked.txt')"
  run_guard "$pl" "$profile"
  assert_contains "4.1: redirect onto tracked path on main denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# --- 4.2 push guard -------------------------------------------------

# implicit push while on main -> deny
test_bash_push_implicit_main_denies() {
  local repo profile pl
  repo="$(build_repo push_implicit main)"
  profile="$(make_profile push_implicit block warn "main, master")"
  pl="$(payload Bash "$repo" 'git push')"
  run_guard "$pl" "$profile"
  assert_contains "4.2: implicit push on main denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# push origin HEAD:main from a feature branch -> deny (target is main)
test_bash_push_head_to_main_from_feature_denies() {
  local repo profile pl
  repo="$(build_repo push_head feat/055-x)"
  profile="$(make_profile push_head block warn "main, master")"
  pl="$(payload Bash "$repo" 'git push origin HEAD:main')"
  run_guard "$pl" "$profile"
  assert_contains "4.2: push HEAD:main from feature denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# push --all from a feature branch -> deny (can push protected refs)
test_bash_push_all_denies() {
  local repo profile pl
  repo="$(build_repo push_all feat/055-x)"
  profile="$(make_profile push_all block warn "main, master")"
  pl="$(payload Bash "$repo" 'git push --all origin')"
  run_guard "$pl" "$profile"
  assert_contains "4.2: push --all denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# push --delete main -> deny
test_bash_push_delete_main_denies() {
  local repo profile pl
  repo="$(build_repo push_delete feat/055-x)"
  profile="$(make_profile push_delete block warn "main, master")"
  pl="$(payload Bash "$repo" 'git push origin --delete main')"
  run_guard "$pl" "$profile"
  assert_contains "4.2: push --delete main denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# +src:main force refspec -> deny
test_bash_push_force_refspec_main_denies() {
  local repo profile pl
  repo="$(build_repo push_force feat/055-x)"
  profile="$(make_profile push_force block warn "main, master")"
  pl="$(payload Bash "$repo" 'git push origin +feat/x:main')"
  run_guard "$pl" "$profile"
  assert_contains "4.2: +src:main denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# push origin feature while on main -> ALLOW (target is not protected)
test_bash_push_feature_from_main_allows() {
  local repo profile pl
  repo="$(build_repo push_feature main)"
  profile="$(make_profile push_feature block warn "main, master")"
  pl="$(payload Bash "$repo" 'git push origin feature')"
  run_guard "$pl" "$profile"
  assert_eq "4.2: push feature from main -> exit 0" 0 "$RC"
  assert_not_contains "4.2: push to feature allows" \
    '"permissionDecision": "deny"' "$OUT"
}

# push to main in warn mode -> allow with warning, no deny
test_bash_push_main_warn_allows() {
  local repo profile pl
  repo="$(build_repo push_warn main)"
  profile="$(make_profile push_warn warn warn "main, master")"
  pl="$(payload Bash "$repo" 'git push')"
  run_guard "$pl" "$profile"
  assert_eq "4.2: push on main in warn -> exit 0" 0 "$RC"
  assert_not_contains "4.2: warn carries no permissionDecision" \
    '"permissionDecision"' "$OUT"
  assert_contains "4.2: warn carries additionalContext" \
    '"additionalContext"' "$OUT"
}

# push to main in off mode -> silent allow
test_bash_push_main_off_silent() {
  local repo profile pl
  repo="$(build_repo push_off main)"
  profile="$(make_profile push_off off warn "main, master")"
  pl="$(payload Bash "$repo" 'git push')"
  run_guard "$pl" "$profile"
  assert_eq "4.2: push on main in off -> exit 0" 0 "$RC"
  assert_eq "4.2: off -> no stdout" "" "$OUT"
}

# plain git commit on a feature branch -> ALLOW (the normal case)
test_bash_commit_feature_allows() {
  local repo profile pl
  repo="$(build_repo commit_feature feat/055-x)"
  profile="$(make_profile commit_feature block warn "main, master")"
  pl="$(payload Bash "$repo" 'git commit -m real-work')"
  run_guard "$pl" "$profile"
  assert_eq "4.1: commit on feature branch -> exit 0" 0 "$RC"
  assert_not_contains "4.1: commit on feature allows" \
    '"permissionDecision": "deny"' "$OUT"
}

# --- 4.4 denial text content ----------------------------------------

# denial names branch + reason + fix, carries no internal task refs
test_bash_denial_text_content() {
  local repo profile pl
  repo="$(build_repo denial_text main)"
  profile="$(make_profile denial_text block warn "main, master")"
  pl="$(payload Bash "$repo" 'git commit -m x')"
  run_guard "$pl" "$profile"
  assert_contains "4.4: denial names the branch" "main" "$OUT"
  assert_contains "4.4: denial states the fix" "git switch -c" "$OUT"
  assert_not_contains "4.4: no tasks/ path reference" "tasks/" "$OUT"
  assert_not_contains "4.4: no task-number reference" "055" "$OUT"
}

# --- 5.1 fail-open policy -------------------------------------------

# not in a git repo -> allow silently
test_fail_not_in_repo_silent() {
  local profile pl d="$TMP/nrepo"
  mkdir -p "$d"
  profile="$(make_profile fail_nrepo block warn "main, master")"
  pl="$(payload Edit "$d" "$d/x.txt")"
  run_guard "$pl" "$profile"
  assert_eq "5.1: no repo -> exit 0" 0 "$RC"
  assert_eq "5.1: no repo -> no stdout" "" "$OUT"
}

# detached HEAD -> allow silently
test_fail_detached_head_silent() {
  local repo profile pl
  repo="$(build_repo fail_detach detach)"
  profile="$(make_profile fail_detach block warn "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_eq "5.1: detached HEAD -> exit 0" 0 "$RC"
  assert_eq "5.1: detached HEAD -> no stdout" "" "$OUT"
}

# non-JSON payload -> allow with a stderr notice
test_fail_non_json_notice() {
  local profile
  profile="$(make_profile fail_nonjson block warn "main, master")"
  run_guard 'this is not json' "$profile"
  assert_eq "5.1: non-JSON -> exit 0" 0 "$RC"
  assert_eq "5.1: non-JSON -> no stdout" "" "$OUT"
  assert_contains "5.1: non-JSON -> stderr notice" "main-branch-guard:" "$ERR"
}

# unreadable profile (file does not exist) -> built-in defaults apply,
# so an Edit on main still denies (default mode is block, default
# branches include main)
test_fail_missing_profile_uses_defaults() {
  local repo pl
  repo="$(build_repo fail_noprofile main)"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$TMP/does-not-exist.yaml"
  assert_eq "5.1: missing profile -> exit 0" 0 "$RC"
  assert_contains "5.1: missing profile -> default block denies on main" \
    '"permissionDecision": "deny"' "$OUT"
}

# absent protected_branch_mode field -> defaults to block
test_fail_absent_mode_defaults_block() {
  local repo profile pl
  repo="$(build_repo fail_nomode main)"
  # profile with the branch list but no mode field
  profile="$(make_profile fail_nomode "" warn "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_contains "5.1: absent mode -> default block denies" \
    '"permissionDecision": "deny"' "$OUT"
}

# unknown mode value -> falls back to block with a stderr notice
test_fail_unknown_mode_falls_back() {
  local repo profile pl
  repo="$(build_repo fail_badmode main)"
  profile="$(make_profile fail_badmode bogus warn "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_contains "5.1: unknown mode -> denies (fell back to block)" \
    '"permissionDecision": "deny"' "$OUT"
  assert_contains "5.1: unknown mode -> stderr notice" \
    "unknown protected_branch_mode" "$ERR"
}

# lib not sourceable -> allow with a notice (never deny, never crash).
# Temporarily hide the command library next to the hook, exercising the
# documented "lib not sourced" fail-open path, then restore it.
test_fail_lib_unavailable_allows() {
  local repo profile pl
  repo="$(build_repo fail_nolib main)"
  profile="$(make_profile fail_nolib block warn "main, master")"
  pl="$(payload Bash "$repo" 'git commit -m x')"
  local lib="$HERE/../lib/git-command-lib.sh"
  mv "$lib" "$lib.hidden"
  run_guard "$pl" "$profile"
  mv "$lib.hidden" "$lib"
  assert_eq "5.2: lib unavailable -> exit 0" 0 "$RC"
  assert_not_contains "5.2: lib unavailable -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
  assert_contains "5.2: lib unavailable -> stderr notice" \
    "main-branch-guard:" "$ERR"
}

# --- 5.3 timing smoke check -----------------------------------------
# A non-candidate tool call must return quickly without touching git or
# the profile, and a candidate call must also complete promptly. This is
# a smoke check (completes, exit 0), not a hard timing assertion.
test_timing_non_candidate_quick() {
  local repo profile pl
  repo="$(build_repo timing_nc main)"
  profile="$(make_profile timing_nc block warn "main, master")"
  pl="$(payload Read "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_eq "5.3: non-candidate tool -> exit 0 (early allow)" 0 "$RC"
  assert_eq "5.3: non-candidate -> no stdout" "" "$OUT"
}

test_timing_candidate_completes() {
  local repo profile pl
  repo="$(build_repo timing_cand main)"
  profile="$(make_profile timing_cand block warn "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt")"
  run_guard "$pl" "$profile"
  assert_eq "5.3: candidate call completes -> exit 0" 0 "$RC"
}

# --- 6.1 branch/task mismatch check (FR-5) --------------------------
# The guard reads the active task number for the session (written by
# /embo:impl via embo-task-state) and, on a candidate call, compares it
# against the checked-out branch. A match is silent. A mismatch nudges —
# once per session — with a create/switch suggestion: in `warn` as an
# allow + additionalContext, in `block` as a single deny that then does
# NOT re-fire on the retry (the per-session marker suppresses repeats in
# both modes). No derivable task, or a tie, stays silent; `off` is
# silent. These cases run on a FEATURE branch so the protected-branch
# guard (FR-1/2) never fires and only the FR-5 path is under test.
#
# WRAPPER points at the embo-task-state bin so a case can seed the active
# task the same way /embo:impl would.
TASK_STATE_BIN="$HERE/../bin/embo-task-state"

# Seed the active task number for a session into a fresh task-state dir
# and print the dir, so the case can pass it to run_guard.
#   $1 = case name  $2 = session_id  $3 = task number
seed_active_task() {
  local case_name="$1" sid="$2" task="$3"
  local dir="$TMP/$case_name.taskstate"
  EMBO_TASK_STATE_DIR="$dir" bash "$TASK_STATE_BIN" set "$sid" "$task" >/dev/null 2>&1
  printf '%s\n' "$dir"
}

# matching branch (feat/055-x, active task 055) -> silent, no nudge
test_fr5_matching_branch_silent() {
  local repo profile pl taskdir
  repo="$(build_repo fr5_match feat/055-x)"
  profile="$(make_profile fr5_match block warn "main, master")"
  taskdir="$(seed_active_task fr5_match sid-match 055)"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-match)"
  run_guard "$pl" "$profile" "$taskdir"
  assert_eq "6.1: matching branch -> exit 0" 0 "$RC"
  assert_not_contains "6.1: matching branch -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
  assert_not_contains "6.1: matching branch -> no additionalContext nudge" \
    '"additionalContext"' "$OUT"
}

# mismatch in warn (branch feat/055-x, active task 068) -> allow + a one
# -line nudge carrying a create/switch suggestion, no deny
test_fr5_mismatch_warn_nudges() {
  local repo profile pl taskdir
  repo="$(build_repo fr5_warn feat/055-x)"
  profile="$(make_profile fr5_warn block warn "main, master")"
  taskdir="$(seed_active_task fr5_warn sid-warn 068)"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-warn)"
  run_guard "$pl" "$profile" "$taskdir"
  assert_eq "6.1: mismatch warn -> exit 0" 0 "$RC"
  assert_not_contains "6.1: mismatch warn -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
  assert_contains "6.1: mismatch warn -> additionalContext nudge" \
    '"additionalContext"' "$OUT"
  assert_contains "6.1: mismatch warn -> names the active task" "068" "$OUT$ERR"
  assert_contains "6.1: mismatch warn -> offers a switch suggestion" \
    "switch" "$OUT$ERR"
}

# mismatch in block -> deny ONCE with the suggestion
test_fr5_mismatch_block_denies_once() {
  local repo profile pl taskdir markerdir
  repo="$(build_repo fr5_block feat/055-x)"
  profile="$(make_profile fr5_block block block "main, master")"
  taskdir="$(seed_active_task fr5_block sid-block 068)"
  markerdir="$TMP/fr5_block.marker"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-block)"
  run_guard "$pl" "$profile" "$taskdir" "$markerdir"
  assert_eq "6.1: mismatch block (first) -> exit 0" 0 "$RC"
  assert_contains "6.1: mismatch block (first) -> deny decision" \
    '"permissionDecision": "deny"' "$OUT"
  assert_contains "6.1: mismatch block deny -> names the active task" "068" "$OUT"
  assert_contains "6.1: mismatch block deny -> offers a switch suggestion" \
    "switch" "$OUT"
}

# the block-mode retry is NOT re-denied: the marker from the first denial
# suppresses the second identical call, so the run is not wedged
test_fr5_mismatch_block_retry_not_redenied() {
  local repo profile pl taskdir markerdir
  repo="$(build_repo fr5_retry feat/055-x)"
  profile="$(make_profile fr5_retry block block "main, master")"
  taskdir="$(seed_active_task fr5_retry sid-retry 068)"
  markerdir="$TMP/fr5_retry.marker"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-retry)"
  # first call records the marker and denies
  run_guard "$pl" "$profile" "$taskdir" "$markerdir"
  assert_contains "6.1: retry setup -> first call denied" \
    '"permissionDecision": "deny"' "$OUT"
  # second identical call: marker present -> no re-deny (FR-5 is silent)
  run_guard "$pl" "$profile" "$taskdir" "$markerdir"
  assert_eq "6.1: block retry -> exit 0" 0 "$RC"
  assert_not_contains "6.1: block retry -> FR-5 does not re-deny" \
    '"permissionDecision": "deny"' "$OUT"
}

# the per-session marker suppresses repeats in WARN mode too
test_fr5_mismatch_warn_marker_suppresses_repeat() {
  local repo profile pl taskdir markerdir
  repo="$(build_repo fr5_warnrepeat feat/055-x)"
  profile="$(make_profile fr5_warnrepeat block warn "main, master")"
  taskdir="$(seed_active_task fr5_warnrepeat sid-wr 068)"
  markerdir="$TMP/fr5_warnrepeat.marker"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-wr)"
  run_guard "$pl" "$profile" "$taskdir" "$markerdir"
  assert_contains "6.1: warn-repeat setup -> first call nudges" \
    '"additionalContext"' "$OUT"
  run_guard "$pl" "$profile" "$taskdir" "$markerdir"
  assert_not_contains "6.1: warn repeat -> no second nudge (marker suppresses)" \
    '"additionalContext"' "$OUT"
}

# no active-task state file: fall back to deriving the task from the
# uncommitted changes. An uncommitted edit under tasks/068-... derives
# 068, which mismatches feat/055-x -> deny in block.
test_fr5_fallback_to_path_derivation_denies() {
  local repo profile pl
  repo="$(build_repo fr5_fallback feat/055-x)"
  mkdir -p "$repo/tasks/068-OTHER"
  printf 'x\n' > "$repo/tasks/068-OTHER/notes.md"
  git -C "$repo" add -A
  profile="$(make_profile fr5_fallback block block "main, master")"
  # no seeded task-state dir -> run_guard uses an empty default, forcing
  # the path-derivation fallback
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-fallback)"
  run_guard "$pl" "$profile"
  assert_contains "6.1: no state file -> derives task from paths and denies" \
    '"permissionDecision": "deny"' "$OUT"
  assert_contains "6.1: fallback deny names the derived task" "068" "$OUT"
}

# no derivable task at all (clean tree, no state file) -> silent
test_fr5_no_task_silent() {
  local repo profile pl
  repo="$(build_repo fr5_notask feat/055-x)"
  profile="$(make_profile fr5_notask block block "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-notask)"
  run_guard "$pl" "$profile"
  assert_eq "6.1: no derivable task -> exit 0" 0 "$RC"
  assert_not_contains "6.1: no derivable task -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
  assert_not_contains "6.1: no derivable task -> no nudge" \
    '"additionalContext"' "$OUT"
}

# a tie in path derivation (equal paths under two tasks, no state file)
# -> silent (no single task to blame)
test_fr5_tie_silent() {
  local repo profile pl
  repo="$(build_repo fr5_tie feat/055-x)"
  mkdir -p "$repo/tasks/068-A" "$repo/tasks/069-B"
  printf 'x\n' > "$repo/tasks/068-A/a.md"
  printf 'x\n' > "$repo/tasks/069-B/b.md"
  git -C "$repo" add -A
  profile="$(make_profile fr5_tie block block "main, master")"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-tie)"
  run_guard "$pl" "$profile"
  assert_eq "6.1: tie -> exit 0" 0 "$RC"
  assert_not_contains "6.1: tie -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
}

# off mode -> FR-5 silent even on a clear mismatch
test_fr5_off_silent() {
  local repo profile pl taskdir
  repo="$(build_repo fr5_off feat/055-x)"
  # protected_branch_mode off would also early-exit; set it block so only
  # branch_task_mode=off governs the FR-5 path, and run on a feature
  # branch so FR-1/2 never fires.
  profile="$(make_profile fr5_off block off "main, master")"
  taskdir="$(seed_active_task fr5_off sid-off 068)"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-off)"
  run_guard "$pl" "$profile" "$taskdir"
  assert_eq "6.1: branch_task_mode off -> exit 0" 0 "$RC"
  assert_not_contains "6.1: off -> no deny" \
    '"permissionDecision": "deny"' "$OUT"
  assert_not_contains "6.1: off -> no nudge" \
    '"additionalContext"' "$OUT"
}

# the protected-branch deny (FR-1/2) takes precedence over FR-5: an Edit
# on a PROTECTED branch with a task mismatch is denied by FR-1, and the
# denial is the protected-branch message, not the FR-5 nudge.
test_fr5_protected_branch_takes_precedence() {
  local repo profile pl taskdir
  repo="$(build_repo fr5_precede main)"
  profile="$(make_profile fr5_precede block block "main, master")"
  taskdir="$(seed_active_task fr5_precede sid-prec 068)"
  pl="$(payload Edit "$repo" "$repo/tracked.txt" sid-prec)"
  run_guard "$pl" "$profile" "$taskdir"
  assert_contains "6.1: protected branch still denies" \
    '"permissionDecision": "deny"' "$OUT"
  assert_contains "6.1: precedence -> protected-branch reason, not FR-5" \
    "while branch main is checked out" "$OUT"
}

# --- 7.2 registration check -----------------------------------------
# The guard must be registered as a PreToolUse hook in hooks.json with a
# matcher covering Edit|Write|NotebookEdit|Bash, WITHOUT disturbing the
# existing approve-compound.sh Bash entry.
test_registered_in_hooks_json() {
  local hj="$HERE/hooks.json"
  assert_eq "7.2: hooks.json exists and is valid JSON" "0" \
    "$(jq -e . "$hj" >/dev/null 2>&1; echo $?)"
  assert_eq "7.2: a PreToolUse entry calls main-branch-guard.sh" "true" \
    "$(jq -r '[.hooks.PreToolUse[].hooks[].command | select(test("main-branch-guard.sh"))] | length > 0' "$hj")"
  assert_eq "7.2: the guard matcher covers Edit, Write, NotebookEdit and Bash" "true" \
    "$(jq -r '[.hooks.PreToolUse[] | select(.hooks[].command | test("main-branch-guard.sh")) | .matcher] | any(. == "Edit|Write|NotebookEdit|Bash")' "$hj")"
  assert_eq "7.2: the approve-compound Bash entry is still present" "true" \
    "$(jq -r '[.hooks.PreToolUse[] | select(.hooks[].command | test("approve-compound.sh")) | .matcher] | any(. == "Bash")' "$hj")"
}

# --- runner ---------------------------------------------------------
test_scaffolding_helpers
test_registered_in_hooks_json
test_edit_tracked_main_block_denies
test_edit_tracked_main_warn_allows_with_warning
test_edit_tracked_main_off_silent
test_edit_untracked_main_block_allows
test_edit_out_of_repo_block_allows
test_edit_tracked_feature_block_allows
test_notebookedit_tracked_main_block_denies
test_payload_key_names_pinned
test_bash_commit_main_block_denies
test_bash_merge_main_block_denies
test_bash_compound_commit_main_block_denies
test_bash_switch_then_commit_allows
test_bash_checkout_b_then_commit_allows
test_bash_readonly_main_allows
test_bash_commit_feature_allows
test_bash_redirect_tracked_main_block_denies
test_bash_push_implicit_main_denies
test_bash_push_head_to_main_from_feature_denies
test_bash_push_all_denies
test_bash_push_delete_main_denies
test_bash_push_force_refspec_main_denies
test_bash_push_feature_from_main_allows
test_bash_push_main_warn_allows
test_bash_push_main_off_silent
test_bash_denial_text_content
test_fail_not_in_repo_silent
test_fail_detached_head_silent
test_fail_non_json_notice
test_fail_missing_profile_uses_defaults
test_fail_absent_mode_defaults_block
test_fail_unknown_mode_falls_back
test_fail_lib_unavailable_allows
test_timing_non_candidate_quick
test_timing_candidate_completes
test_fr5_matching_branch_silent
test_fr5_mismatch_warn_nudges
test_fr5_mismatch_block_denies_once
test_fr5_mismatch_block_retry_not_redenied
test_fr5_mismatch_warn_marker_suppresses_repeat
test_fr5_fallback_to_path_derivation_denies
test_fr5_no_task_silent
test_fr5_tie_silent
test_fr5_off_silent
test_fr5_protected_branch_takes_precedence

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
