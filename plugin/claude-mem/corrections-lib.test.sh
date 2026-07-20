#!/usr/bin/env bash
# Plain-Bash unit tests for corrections-lib.sh (no framework).
# Run: bash plugin/claude-mem/corrections-lib.test.sh
# Exits non-zero if any assertion fails.
#
# Operates ONLY on synthetic temp files — never the user's real
# ~/.claude or ~/.claude-mem config.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pin the modes-dir value to a fixed fixture string (not a real path) so
# assertions are deterministic regardless of the tester's $HOME. Must be
# set before sourcing the lib, which otherwise defaults it to
# $HOME/.claude-mem/modes.
export CORRECTIONS_MODES_DIR_VALUE="FIXTURE/.claude-mem/modes"
# shellcheck source=/dev/null
source "$HERE/corrections-lib.sh"

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

# ---- 1.1 corrections_merge_modes_dir ----
# Merges CLAUDE_MEM_MODES_DIR into .env, creating .env if absent,
# preserving every existing key.

# Case A: no .env block at all.
printf '%s\n' '{"model":"sonnet"}' > "$TMP/no_env.json"
corrections_merge_modes_dir "$TMP/no_env.json"
A_VAL="$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/no_env.json")"
assert_eq "merge into missing env adds the key" \
  "$CORRECTIONS_MODES_DIR_VALUE" "$A_VAL"
A_KEEP="$(jq -r '.model' "$TMP/no_env.json")"
assert_eq "merge into missing env keeps top-level keys" "sonnet" "$A_KEEP"

# Case B: empty .env block.
printf '%s\n' '{"env":{}}' > "$TMP/empty_env.json"
corrections_merge_modes_dir "$TMP/empty_env.json"
B_VAL="$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/empty_env.json")"
assert_eq "merge into empty env adds the key" \
  "$CORRECTIONS_MODES_DIR_VALUE" "$B_VAL"

# Case C: .env has an unrelated key — must be preserved.
printf '%s\n' '{"env":{"OTHER":"keep"}}' > "$TMP/other_env.json"
corrections_merge_modes_dir "$TMP/other_env.json"
C_VAL="$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/other_env.json")"
assert_eq "merge preserves our key" "$CORRECTIONS_MODES_DIR_VALUE" "$C_VAL"
C_KEEP="$(jq -r '.env.OTHER' "$TMP/other_env.json")"
assert_eq "merge preserves the unrelated env key" "keep" "$C_KEEP"

# ---- 1.2 corrections_modes_dir_conflict ----
# Echoes absent | same | conflict for CLAUDE_MEM_MODES_DIR in .env.

printf '%s\n' '{"model":"x"}' > "$TMP/c_absent.json"
assert_eq "conflict: absent when no key" "absent" \
  "$(corrections_modes_dir_conflict "$TMP/c_absent.json")"

jq -n --arg v "$CORRECTIONS_MODES_DIR_VALUE" \
  '{env:{CLAUDE_MEM_MODES_DIR:$v}}' > "$TMP/c_same.json"
assert_eq "conflict: same when our value" "same" \
  "$(corrections_modes_dir_conflict "$TMP/c_same.json")"

printf '%s\n' '{"env":{"CLAUDE_MEM_MODES_DIR":"/other/path"}}' \
  > "$TMP/c_diff.json"
assert_eq "conflict: conflict when different value" "conflict" \
  "$(corrections_modes_dir_conflict "$TMP/c_diff.json")"

# ---- 1.2 corrections_write_enable_record ----
# Writes the enable-record JSON with all tech-design fields.

corrections_write_enable_record "$TMP/rec.json" "code" "true"
assert_eq "record: prior mode stored" "code" \
  "$(jq -r '.prior_claude_mem_mode' "$TMP/rec.json")"
assert_eq "record: written flag stored" "true" \
  "$(jq -r '.claude_mem_modes_dir_written' "$TMP/rec.json")"
assert_eq "record: modes-dir value stored" "$CORRECTIONS_MODES_DIR_VALUE" \
  "$(jq -r '.claude_mem_modes_dir_value' "$TMP/rec.json")"
HAS_TS="$(jq -r 'has("enabled_at")' "$TMP/rec.json")"
assert_eq "record: has enabled_at" "true" "$HAS_TS"

# written=false path: the value field is still recorded (disable reads it
# only when written=true, but storing it is harmless and simpler).
corrections_write_enable_record "$TMP/rec2.json" "code" "false"
assert_eq "record: written=false stored" "false" \
  "$(jq -r '.claude_mem_modes_dir_written' "$TMP/rec2.json")"

# ---- 1.3 enable idempotency ----
# Re-running the merge converges: running it twice yields the same file
# as running it once, and the conflict check then reports "same".

printf '%s\n' '{"env":{"OTHER":"keep"}}' > "$TMP/idem.json"
corrections_merge_modes_dir "$TMP/idem.json"
ONCE="$(cat "$TMP/idem.json")"
corrections_merge_modes_dir "$TMP/idem.json"
TWICE="$(cat "$TMP/idem.json")"
assert_eq "merge is idempotent (twice == once)" "$ONCE" "$TWICE"
assert_eq "conflict reports same after merge" "same" \
  "$(corrections_modes_dir_conflict "$TMP/idem.json")"
assert_eq "idempotent merge still keeps unrelated key" "keep" \
  "$(jq -r '.env.OTHER' "$TMP/idem.json")"

# Half-applied state (mode file conceptually written, env var not) is
# just the absent-key case for the settings file: merge converges.
printf '%s\n' '{"model":"x"}' > "$TMP/half.json"
corrections_merge_modes_dir "$TMP/half.json"
assert_eq "half-applied converges on re-run" "same" \
  "$(corrections_modes_dir_conflict "$TMP/half.json")"

# ---- 2.1 corrections_should_remove_modes_dir ----
# Returns 0 (remove) ONLY when written=true AND current settings value
# equals the recorded value; 1 otherwise.

# written=true, values match → remove (rc 0).
corrections_write_enable_record "$TMP/r_match.json" "code" "true"
jq -n --arg v "$CORRECTIONS_MODES_DIR_VALUE" \
  '{env:{CLAUDE_MEM_MODES_DIR:$v}}' > "$TMP/s_match.json"
corrections_should_remove_modes_dir "$TMP/r_match.json" "$TMP/s_match.json"
assert_eq "remove when written=true and value matches" "0" "$?"

# written=false → do not remove (rc 1), even if value matches.
corrections_write_enable_record "$TMP/r_false.json" "code" "false"
corrections_should_remove_modes_dir "$TMP/r_false.json" "$TMP/s_match.json"
assert_eq "keep when written=false" "1" "$?"

# written=true but current value changed → do not remove (rc 1).
printf '%s\n' '{"env":{"CLAUDE_MEM_MODES_DIR":"/changed/path"}}' \
  > "$TMP/s_changed.json"
corrections_should_remove_modes_dir "$TMP/r_match.json" "$TMP/s_changed.json"
assert_eq "keep when value changed since enable" "1" "$?"

# ---- 2.2 crash-safe re-run (restore + remove are idempotent) ----
# Disable deletes the enable-record only after restore steps succeed, so
# a crash before deletion means a re-run repeats restore harmlessly.

printf '%s\n' '{"CLAUDE_MEM_MODE":"code-embo"}' > "$TMP/d_mode.json"
corrections_restore_mode "$TMP/d_mode.json" "code"
R_ONCE="$(cat "$TMP/d_mode.json")"
corrections_restore_mode "$TMP/d_mode.json" "code"
R_TWICE="$(cat "$TMP/d_mode.json")"
assert_eq "restore_mode idempotent (crash-safe re-run)" "$R_ONCE" "$R_TWICE"
assert_eq "restore_mode set prior value" "code" \
  "$(jq -r '.CLAUDE_MEM_MODE' "$TMP/d_mode.json")"

jq -n --arg v "$CORRECTIONS_MODES_DIR_VALUE" \
  '{env:{CLAUDE_MEM_MODES_DIR:$v,KEEP:"y"}}' > "$TMP/d_env.json"
corrections_remove_modes_dir "$TMP/d_env.json"
assert_eq "remove_modes_dir dropped the key" "null" \
  "$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/d_env.json")"
assert_eq "remove_modes_dir kept unrelated key" "y" \
  "$(jq -r '.env.KEEP' "$TMP/d_env.json")"
# Re-run on the already-removed file: no error, still absent.
corrections_remove_modes_dir "$TMP/d_env.json"
assert_eq "remove_modes_dir idempotent" "null" \
  "$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/d_env.json")"

# ---- 3.1 corrections_curation_read / _write ----
# read echoes space-separated curated_ids; write merges + dedups; an
# absent or unparseable file reads as empty (no state yet), never errors.

# Absent file → empty read, no error.
assert_eq "curation read of absent file is empty" "" \
  "$(corrections_curation_read "$TMP/cur_absent.json")"

# Write then read back.
corrections_curation_write "$TMP/cur.json" 29191 29205
assert_eq "curation write+read returns ids" "29191 29205" \
  "$(corrections_curation_read "$TMP/cur.json")"

# Second write merges and dedups (29205 repeated, 29999 new).
corrections_curation_write "$TMP/cur.json" 29205 29999
assert_eq "curation write dedups and merges" "29191 29205 29999" \
  "$(corrections_curation_read "$TMP/cur.json")"

# Unparseable file → read as empty, never crash.
printf '%s' 'not json{' > "$TMP/cur_bad.json"
assert_eq "curation read of garbage is empty" "" \
  "$(corrections_curation_read "$TMP/cur_bad.json")"

# ---- 3.2 atomic curation write ----
# A write goes through a temp file + rename, so a prior good file is
# never left truncated. We assert the file is always valid JSON after a
# write (a partial write would fail jq parse).
corrections_curation_write "$TMP/cur_atomic.json" 1 2 3
assert_eq "curation file is valid JSON after write" "true" \
  "$(jq -e 'type == "object"' "$TMP/cur_atomic.json" >/dev/null 2>&1 \
     && echo true || echo false)"
# Writing over an existing good file keeps it parseable.
corrections_curation_write "$TMP/cur_atomic.json" 4
assert_eq "curation file still valid after rewrite" "1 2 3 4" \
  "$(corrections_curation_read "$TMP/cur_atomic.json")"

# ---- corrections_list (against a fixture DB) ----
# Reads type='correction' rows for a project, newest first, as JSON.
# Only runs if sqlite3 is available.
if command -v sqlite3 >/dev/null 2>&1; then
  export CORRECTIONS_DB="$TMP/fixture.db"
  sqlite3 "$CORRECTIONS_DB" "CREATE TABLE observations(id INTEGER, project TEXT, type TEXT, title TEXT, subtitle TEXT, narrative TEXT, created_at TEXT);"
  sqlite3 "$CORRECTIONS_DB" "INSERT INTO observations VALUES
    (1,'embo','correction','older corr','s1','n1','2026-01-01T00:00:00Z'),
    (2,'embo','correction','newer corr','s2','n2','2026-02-01T00:00:00Z'),
    (3,'embo','discovery','not a corr','s3','n3','2026-03-01T00:00:00Z'),
    (4,'other','correction','other project','s4','n4','2026-02-15T00:00:00Z');"

  LIST="$(corrections_list embo)"
  assert_eq "list returns only embo corrections (2)" "2" \
    "$(printf '%s' "$LIST" | jq 'length')"
  assert_eq "list excludes non-correction types" "false" \
    "$(printf '%s' "$LIST" | jq '[.[].title] | contains(["not a corr"])')"
  assert_eq "list excludes other projects" "false" \
    "$(printf '%s' "$LIST" | jq '[.[].title] | contains(["other project"])')"
  assert_eq "list is newest-first" "newer corr" \
    "$(printf '%s' "$LIST" | jq -r '.[0].title')"

  # A project name that is not a plain identifier (here an apostrophe, the
  # SQL-injection vector AND a query-breaker) must be rejected before it
  # reaches SQL: non-zero return, no output, no crash.
  BAD_OUT="$(corrections_list "x'; DROP TABLE observations; --" 2>/dev/null)"
  BAD_RC=$?
  assert_eq "list rejects a non-identifier project (rc)" "2" "$BAD_RC"
  assert_eq "list emits nothing for a bad project" "" "$BAD_OUT"
  # The injection did not run: the table still has all 4 rows.
  assert_eq "list rejection left the table intact" "4" \
    "$(sqlite3 "$CORRECTIONS_DB" 'SELECT count(*) FROM observations;')"
  # A legitimate name with a hyphen/dot/underscore still works.
  sqlite3 "$CORRECTIONS_DB" "INSERT INTO observations VALUES
    (5,'my-repo.v2_x','correction','ok name','s5','n5','2026-04-01T00:00:00Z');"
  assert_eq "list accepts hyphen/dot/underscore names" "1" \
    "$(corrections_list 'my-repo.v2_x' | jq 'length')"

  # ---- 042/1.1 corrections_list_pending ----
  # Reads corrections for a project (via corrections_list) and subtracts
  # the IDs already recorded in the curation file, emitting only the
  # not-yet-reviewed rows as a JSON array, newest first. The model never
  # does the subtraction. Fixture DB has embo corrections id 1 (older)
  # and id 2 (newer).

  # First-run: curation file absent → every correction is pending.
  P_FIRST="$(corrections_list_pending embo "$TMP/lp_absent.json")"
  assert_eq "pending: absent curation → all corrections" "2" \
    "$(printf '%s' "$P_FIRST" | jq 'length')"
  assert_eq "pending: absent curation → newest first" "newer corr" \
    "$(printf '%s' "$P_FIRST" | jq -r '.[0].title')"

  # After a curation write of id 2 → only id 1 remains pending.
  corrections_curation_write "$TMP/lp_one.json" 2
  P_ONE="$(corrections_list_pending embo "$TMP/lp_one.json")"
  assert_eq "pending: one curated → one remains" "1" \
    "$(printf '%s' "$P_ONE" | jq 'length')"
  assert_eq "pending: the remaining one is the uncurated id" "1" \
    "$(printf '%s' "$P_ONE" | jq -r '.[0].id')"

  # All corrections curated → empty array (valid JSON, length 0).
  corrections_curation_write "$TMP/lp_all.json" 1 2
  P_ALL="$(corrections_list_pending embo "$TMP/lp_all.json")"
  assert_eq "pending: all curated → empty array" "0" \
    "$(printf '%s' "$P_ALL" | jq 'length')"

  # Unparseable curation file → treated as no state yet → all pending,
  # never a crash (mirrors corrections_curation_read's fail-safe).
  printf '%s' 'not json{' > "$TMP/lp_bad.json"
  P_BAD="$(corrections_list_pending embo "$TMP/lp_bad.json")"
  assert_eq "pending: unparseable curation → all pending" "2" \
    "$(printf '%s' "$P_BAD" | jq 'length')"

  # A project with no corrections → empty array, not an error.
  P_EMPTY="$(corrections_list_pending 'no-such-project' "$TMP/lp_absent.json")"
  assert_eq "pending: project with no corrections → empty array" "0" \
    "$(printf '%s' "$P_EMPTY" | jq 'length')"
else
  printf 'SKIP: sqlite3 not available for corrections_list test\n'
fi

# ---- curation_write is fail-safe on a non-numeric id ----
# A stray non-numeric argument must not abort the write and lose the
# session's curation; it is skipped, valid ids are still recorded.
corrections_curation_write "$TMP/cur_mixed.json" 10 notanumber 20
assert_eq "curation write skips a non-numeric id, keeps the rest" "10 20" \
  "$(corrections_curation_read "$TMP/cur_mixed.json")"
assert_eq "curation file valid JSON after mixed-id write" "true" \
  "$(jq -e 'type == "object"' "$TMP/cur_mixed.json" >/dev/null 2>&1 \
     && echo true || echo false)"

# ---- 042 corrections_mode ----
# Echoes CLAUDE_MEM_MODE from the (overridable) claude-mem settings file,
# defaulting to "code" when the file or key is absent; never errors.

export CORRECTIONS_CM_SETTINGS="$TMP/cm_absent.json"   # does not exist
assert_eq "mode: absent settings → code" "code" "$(corrections_mode)"

printf '%s\n' '{"CLAUDE_MEM_MODE":"code-embo"}' > "$TMP/cm_on.json"
export CORRECTIONS_CM_SETTINGS="$TMP/cm_on.json"
assert_eq "mode: reads code-embo when enabled" "code-embo" "$(corrections_mode)"

printf '%s\n' '{"model":"x"}' > "$TMP/cm_nokey.json"
export CORRECTIONS_CM_SETTINGS="$TMP/cm_nokey.json"
assert_eq "mode: missing key → code" "code" "$(corrections_mode)"

printf '%s' 'not json{' > "$TMP/cm_bad.json"
export CORRECTIONS_CM_SETTINGS="$TMP/cm_bad.json"
assert_eq "mode: garbage settings → code (no crash)" "code" "$(corrections_mode)"

# ---- summary ----
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
