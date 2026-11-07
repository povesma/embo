#!/usr/bin/env bash
# Plain-Bash unit tests for the embo-session-state writer (no framework).
# Run: bash plugin/bin/embo-session-state.test.sh
# Exits non-zero if any assertion fails.
#
# Operates ONLY on a synthetic temp XDG_STATE_HOME / HOME — never the
# user's real ~/.local/state or ~/.claude.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_BIN="$HERE/embo-session-state"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' \
      "$desc" "$exp" "$act"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A clean environment for each invocation: a temp HOME and an explicit
# XDG_STATE_HOME under it, so no test ever touches the real user state.
run_state() {
  HOME="$TMP/home" XDG_STATE_HOME="$TMP/home/.local/state" \
    bash "$STATE_BIN" "$@"
}

# Same, but with XDG_STATE_HOME unset so the $HOME fallback path applies.
run_state_no_xdg() {
  env -u XDG_STATE_HOME HOME="$TMP/home" \
    bash "$STATE_BIN" "$@"
}

# Read a field from the state file of a given session id.
state_field() {
  local sid="$1" field="$2" path
  path="$(run_state path "$sid")"
  jq -r "$field" "$path" 2>/dev/null
}

# ---- 1.1 path resolution ----

test_path_from_xdg_state_home() {
  local got
  got="$(run_state path abc123)"
  assert_eq "path honours XDG_STATE_HOME" \
    "$TMP/home/.local/state/embo/session-state/abc123.json" "$got"
}

test_path_falls_back_to_home() {
  local got
  got="$(run_state_no_xdg path abc123)"
  assert_eq "path falls back to \$HOME/.local/state when XDG unset" \
    "$TMP/home/.local/state/embo/session-state/abc123.json" "$got"
}

test_path_is_git_free() {
  local repo got_a got_b
  repo="$TMP/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  got_a="$(cd "$repo" && run_state path samesid)"
  got_b="$(run_state path samesid)"
  assert_eq "path is identical inside and outside a git repo" \
    "$got_a" "$got_b"
  assert_eq "path inside a repo still resolves under HOME, not the repo" \
    "$TMP/home/.local/state/embo/session-state/samesid.json" "$got_a"
}

test_path_distinct_per_session_id() {
  local a b
  a="$(run_state path sid-one)"
  b="$(run_state path sid-two)"
  assert_eq "distinct session ids resolve to distinct files" "false" \
    "$([ "$a" = "$b" ] && echo true || echo false)"
}

# ---- 1.3 id safety ----

test_id_safety() {
  run_state baseline "" startup >/dev/null 2>&1
  assert_eq "empty id exits non-zero" "false" \
    "$([ "$?" -eq 0 ] && echo true || echo false)"

  run_state baseline '${CLAUDE_SESSION_ID}' startup >/dev/null 2>&1
  assert_eq "literal \${CLAUDE_SESSION_ID} exits non-zero" "false" \
    "$([ "$?" -eq 0 ] && echo true || echo false)"

  run_state baseline 'a/b' startup >/dev/null 2>&1
  assert_eq "id with / exits non-zero" "false" \
    "$([ "$?" -eq 0 ] && echo true || echo false)"

  run_state baseline '..' startup >/dev/null 2>&1
  assert_eq "id of .. exits non-zero" "false" \
    "$([ "$?" -eq 0 ] && echo true || echo false)"

  run_state baseline 'a..b' startup >/dev/null 2>&1
  assert_eq "id containing .. exits non-zero" "false" \
    "$([ "$?" -eq 0 ] && echo true || echo false)"

  run_state baseline 'Clean.id-123_OK' startup >/dev/null 2>&1
  assert_eq "a clean id exits 0" "true" \
    "$([ "$?" -eq 0 ] && echo true || echo false)"
}

test_id_safety_path_escape() {
  # A hostile id must never build a path outside session-state/. path
  # itself must reject the same ids.
  run_state path '../escape' >/dev/null 2>&1
  assert_eq "path rejects a traversal id (non-zero)" "false" \
    "$([ "$?" -eq 0 ] && echo true || echo false)"
}

# ---- 1.5 atomic write + unreadable-as-absent ----

test_atomic_no_tmp_left() {
  run_state baseline atomsid startup >/dev/null 2>&1
  local dir
  dir="$(dirname "$(run_state path atomsid)")"
  local tmpcount
  tmpcount="$(find "$dir" -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "no .tmp file left behind after write" "0" "$tmpcount"
  assert_eq "written file is valid JSON" "true" \
    "$(jq -e 'type == "object"' "$(run_state path atomsid)" >/dev/null 2>&1 \
       && echo true || echo false)"
}

test_unreadable_treated_as_absent() {
  # A corrupt existing file must be treated as absent (start fresh),
  # never partially merged.
  local path
  run_state baseline corruptsid startup >/dev/null 2>&1
  path="$(run_state path corruptsid)"
  printf 'not json{' > "$path"
  run_state start corruptsid deadbeef feat/x '~/repo' >/dev/null 2>&1
  assert_eq "corrupt file is rebuilt as valid JSON" "true" \
    "$(jq -e 'type == "object"' "$path" >/dev/null 2>&1 \
       && echo true || echo false)"
  assert_eq "corrupt file rebuilt with the new phase" "started" \
    "$(jq -r '.phase' "$path")"
}

# ---- 1.7 per-subcommand behaviour ----

test_baseline_new_and_preserve() {
  run_state baseline b1 startup >/dev/null 2>&1
  assert_eq "baseline with no file writes phase new" "new" \
    "$(state_field b1 '.phase')"
  assert_eq "baseline records source" "startup" \
    "$(state_field b1 '.source')"
  assert_eq "baseline sets schema 1" "1" \
    "$(state_field b1 '.schema')"

  # Advance to started, then re-fire baseline (resume/compact).
  run_state start b1 abc feat/y '~/r' >/dev/null 2>&1
  run_state baseline b1 resume >/dev/null 2>&1
  assert_eq "baseline re-fire preserves started phase" "started" \
    "$(state_field b1 '.phase')"
  assert_eq "baseline re-fire updates source" "resume" \
    "$(state_field b1 '.source')"
}

test_start_sets_fields_and_resets() {
  run_state baseline s1 startup >/dev/null 2>&1
  run_state start s1 sha111 feat/z '~/proj' >/dev/null 2>&1
  assert_eq "start sets phase started" "started" \
    "$(state_field s1 '.phase')"
  assert_eq "start sets head_sha" "sha111" \
    "$(state_field s1 '.head_sha')"
  assert_eq "start sets branch" "feat/z" \
    "$(state_field s1 '.branch')"
  assert_eq "start sets repo_root" "~/proj" \
    "$(state_field s1 '.repo_root')"
  assert_eq "start sets started_at (non-null)" "false" \
    "$(state_field s1 '.started_at == null')"

  local first_started
  first_started="$(state_field s1 '.started_at')"
  run_state start s1 sha222 feat/z2 '~/proj2' >/dev/null 2>&1
  assert_eq "second start keeps phase started" "started" \
    "$(state_field s1 '.phase')"
  assert_eq "second start updates head_sha" "sha222" \
    "$(state_field s1 '.head_sha')"
  assert_eq "second start preserves original started_at" "$first_started" \
    "$(state_field s1 '.started_at')"
}

test_wrapup_and_minimal() {
  run_state baseline w1 startup >/dev/null 2>&1
  run_state start w1 shaA feat/a '~/a' >/dev/null 2>&1
  run_state wrapup w1 >/dev/null 2>&1
  assert_eq "wrapup sets phase wrapped_up" "wrapped_up" \
    "$(state_field w1 '.phase')"
  assert_eq "wrapup sets wrapped_up_at (non-null)" "false" \
    "$(state_field w1 '.wrapped_up_at == null')"

  # wrapup without any prior file → minimal, null started_at.
  run_state wrapup w2 >/dev/null 2>&1
  assert_eq "wrapup without start → phase wrapped_up" "wrapped_up" \
    "$(state_field w2 '.phase')"
  assert_eq "wrapup without start → null started_at" "true" \
    "$(state_field w2 '.started_at == null')"
}

test_resume_flip_and_noop() {
  run_state baseline r1 startup >/dev/null 2>&1
  run_state start r1 shaR feat/r '~/r' >/dev/null 2>&1
  run_state wrapup r1 >/dev/null 2>&1
  run_state resume r1 >/dev/null 2>&1
  assert_eq "resume flips wrapped_up to started" "started" \
    "$(state_field r1 '.phase')"

  # resume on a started file is a no-op on phase.
  run_state resume r1 >/dev/null 2>&1
  assert_eq "resume on started leaves phase started" "started" \
    "$(state_field r1 '.phase')"

  # resume with no file → no-op, no file created.
  run_state resume r-nofile >/dev/null 2>&1
  assert_eq "resume with no file creates nothing" "false" \
    "$([ -f "$(run_state path r-nofile)" ] && echo true || echo false)"
}

# ---- 1.7 merge-preserve ext/unknown keys ----

test_merge_preserve() {
  run_state baseline m1 startup >/dev/null 2>&1
  local path
  path="$(run_state path m1)"
  # Inject an ext value and an unrecognised top-level key.
  local tmp
  tmp="$(jq '.ext = {"task":"070"} | .custom_top = "keepme"' "$path")"
  printf '%s\n' "$tmp" > "$path"

  run_state start m1 shaM feat/m '~/m' >/dev/null 2>&1
  assert_eq "start preserves ext" "070" \
    "$(state_field m1 '.ext.task')"
  assert_eq "start preserves unknown top-level key" "keepme" \
    "$(state_field m1 '.custom_top')"

  run_state wrapup m1 >/dev/null 2>&1
  assert_eq "wrapup preserves ext" "070" \
    "$(state_field m1 '.ext.task')"
  assert_eq "wrapup preserves unknown top-level key" "keepme" \
    "$(state_field m1 '.custom_top')"

  run_state resume m1 >/dev/null 2>&1
  assert_eq "resume preserves unknown top-level key" "keepme" \
    "$(state_field m1 '.custom_top')"
}

# ---- 1.11 prune ----

test_prune_mtime_and_guards() {
  # Build >50 files so the prune pass is not skipped, with one stale and
  # one fresh file to check the boundary.
  local dir
  run_state baseline pr-seed startup >/dev/null 2>&1
  dir="$(dirname "$(run_state path pr-seed)")"

  local i
  for i in $(seq 1 60); do
    printf '{"schema":1,"phase":"new"}\n' > "$dir/old-$i.json"
    touch -t 202001010000 "$dir/old-$i.json"
  done
  printf '{"schema":1,"phase":"new"}\n' > "$dir/fresh.json"
  printf 'leftover' > "$dir/scratch.tmp"
  touch -t 202001010000 "$dir/scratch.tmp"

  # A start triggers the prune.
  run_state start pr-now shaP feat/p '~/p' >/dev/null 2>&1

  assert_eq "prune removes a stale-by-mtime file" "false" \
    "$([ -f "$dir/old-1.json" ] && echo true || echo false)"
  assert_eq "prune keeps a fresh file" "true" \
    "$([ -f "$dir/fresh.json" ] && echo true || echo false)"
  assert_eq "prune keeps the just-touched session file" "true" \
    "$([ -f "$(run_state path pr-now)" ] && echo true || echo false)"
  assert_eq "prune ignores *.tmp files" "true" \
    "$([ -f "$dir/scratch.tmp" ] && echo true || echo false)"
}

test_prune_skips_small_dir() {
  # With <50 files, a stale file must survive (prune pass skipped).
  local dir
  run_state baseline sm-seed startup >/dev/null 2>&1
  dir="$(dirname "$(run_state path sm-seed)")"
  printf '{"schema":1,"phase":"new"}\n' > "$dir/lonely-old.json"
  touch -t 202001010000 "$dir/lonely-old.json"

  run_state start sm-now shaS feat/s '~/s' >/dev/null 2>&1
  assert_eq "prune skipped in a small dir → stale file survives" "true" \
    "$([ -f "$dir/lonely-old.json" ] && echo true || echo false)"
}

test_baseline_does_not_prune() {
  # baseline must never prune (avoids a stat storm on every session start).
  local dir
  run_state baseline bp-seed startup >/dev/null 2>&1
  dir="$(dirname "$(run_state path bp-seed)")"
  local i
  for i in $(seq 1 60); do
    printf '{"schema":1,"phase":"new"}\n' > "$dir/bpold-$i.json"
    touch -t 202001010000 "$dir/bpold-$i.json"
  done
  run_state baseline bp-now startup >/dev/null 2>&1
  assert_eq "baseline does not prune stale files" "true" \
    "$([ -f "$dir/bpold-1.json" ] && echo true || echo false)"
}

# ---- run all tests ----

test_path_from_xdg_state_home
test_path_falls_back_to_home
test_path_is_git_free
test_path_distinct_per_session_id
test_id_safety
test_id_safety_path_escape
test_atomic_no_tmp_left
test_unreadable_treated_as_absent
test_baseline_new_and_preserve
test_start_sets_fields_and_resets
test_wrapup_and_minimal
test_resume_flip_and_noop
test_merge_preserve
test_prune_mtime_and_guards
test_prune_skips_small_dir
test_baseline_does_not_prune

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
