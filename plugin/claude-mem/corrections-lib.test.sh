#!/usr/bin/env bash
# Plain-Bash unit tests for corrections-lib.sh (no framework).
# Run: bash plugin/claude-mem/corrections-lib.test.sh
# Exits non-zero if any assertion fails.
#
# Operates ONLY on synthetic temp files — never the user's real
# ~/.claude or ~/.claude-mem config.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

test_merge_modes_dir() {
  printf '%s\n' '{"model":"sonnet"}' > "$TMP/no_env.json"
  corrections_merge_modes_dir "$TMP/no_env.json"
  assert_eq "merge into missing env adds the key" \
    "$CORRECTIONS_MODES_DIR_VALUE" \
    "$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/no_env.json")"
  assert_eq "merge into missing env keeps top-level keys" "sonnet" \
    "$(jq -r '.model' "$TMP/no_env.json")"

  printf '%s\n' '{"env":{}}' > "$TMP/empty_env.json"
  corrections_merge_modes_dir "$TMP/empty_env.json"
  assert_eq "merge into empty env adds the key" \
    "$CORRECTIONS_MODES_DIR_VALUE" \
    "$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/empty_env.json")"

  printf '%s\n' '{"env":{"OTHER":"keep"}}' > "$TMP/other_env.json"
  corrections_merge_modes_dir "$TMP/other_env.json"
  assert_eq "merge preserves our key" \
    "$CORRECTIONS_MODES_DIR_VALUE" \
    "$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/other_env.json")"
  assert_eq "merge preserves the unrelated env key" "keep" \
    "$(jq -r '.env.OTHER' "$TMP/other_env.json")"
}

# ---- 1.2 corrections_modes_dir_conflict ----

test_modes_dir_conflict() {
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
}

# ---- 1.2 corrections_write_enable_record ----

test_write_enable_record() {
  corrections_write_enable_record "$TMP/rec.json" "code" "true"
  assert_eq "record: prior mode stored" "code" \
    "$(jq -r '.prior_claude_mem_mode' "$TMP/rec.json")"
  assert_eq "record: written flag stored" "true" \
    "$(jq -r '.claude_mem_modes_dir_written' "$TMP/rec.json")"
  assert_eq "record: modes-dir value stored" "$CORRECTIONS_MODES_DIR_VALUE" \
    "$(jq -r '.claude_mem_modes_dir_value' "$TMP/rec.json")"
  assert_eq "record: has enabled_at" "true" \
    "$(jq -r 'has("enabled_at")' "$TMP/rec.json")"

  corrections_write_enable_record "$TMP/rec2.json" "code" "false"
  assert_eq "record: written=false stored" "false" \
    "$(jq -r '.claude_mem_modes_dir_written' "$TMP/rec2.json")"
}

# ---- 1.3 enable idempotency ----

test_enable_idempotency() {
  printf '%s\n' '{"env":{"OTHER":"keep"}}' > "$TMP/idem.json"
  corrections_merge_modes_dir "$TMP/idem.json"
  local once twice
  once="$(cat "$TMP/idem.json")"
  corrections_merge_modes_dir "$TMP/idem.json"
  twice="$(cat "$TMP/idem.json")"
  assert_eq "merge is idempotent (twice == once)" "$once" "$twice"
  assert_eq "conflict reports same after merge" "same" \
    "$(corrections_modes_dir_conflict "$TMP/idem.json")"
  assert_eq "idempotent merge still keeps unrelated key" "keep" \
    "$(jq -r '.env.OTHER' "$TMP/idem.json")"

  printf '%s\n' '{"model":"x"}' > "$TMP/half.json"
  corrections_merge_modes_dir "$TMP/half.json"
  assert_eq "half-applied converges on re-run" "same" \
    "$(corrections_modes_dir_conflict "$TMP/half.json")"
}

# ---- 2.1 corrections_should_remove_modes_dir ----

test_should_remove_modes_dir() {
  corrections_write_enable_record "$TMP/r_match.json" "code" "true"
  jq -n --arg v "$CORRECTIONS_MODES_DIR_VALUE" \
    '{env:{CLAUDE_MEM_MODES_DIR:$v}}' > "$TMP/s_match.json"
  corrections_should_remove_modes_dir "$TMP/r_match.json" "$TMP/s_match.json"
  assert_eq "remove when written=true and value matches" "0" "$?"

  corrections_write_enable_record "$TMP/r_false.json" "code" "false"
  corrections_should_remove_modes_dir "$TMP/r_false.json" "$TMP/s_match.json"
  assert_eq "keep when written=false" "1" "$?"

  printf '%s\n' '{"env":{"CLAUDE_MEM_MODES_DIR":"/changed/path"}}' \
    > "$TMP/s_changed.json"
  corrections_should_remove_modes_dir "$TMP/r_match.json" "$TMP/s_changed.json"
  assert_eq "keep when value changed since enable" "1" "$?"
}

# ---- 2.2 crash-safe re-run ----

test_crash_safe_rerun() {
  printf '%s\n' '{"CLAUDE_MEM_MODE":"code-embo"}' > "$TMP/d_mode.json"
  corrections_restore_mode "$TMP/d_mode.json" "code"
  local once twice
  once="$(cat "$TMP/d_mode.json")"
  corrections_restore_mode "$TMP/d_mode.json" "code"
  twice="$(cat "$TMP/d_mode.json")"
  assert_eq "restore_mode idempotent (crash-safe re-run)" "$once" "$twice"
  assert_eq "restore_mode set prior value" "code" \
    "$(jq -r '.CLAUDE_MEM_MODE' "$TMP/d_mode.json")"

  jq -n --arg v "$CORRECTIONS_MODES_DIR_VALUE" \
    '{env:{CLAUDE_MEM_MODES_DIR:$v,KEEP:"y"}}' > "$TMP/d_env.json"
  corrections_remove_modes_dir "$TMP/d_env.json"
  assert_eq "remove_modes_dir dropped the key" "null" \
    "$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/d_env.json")"
  assert_eq "remove_modes_dir kept unrelated key" "y" \
    "$(jq -r '.env.KEEP' "$TMP/d_env.json")"
  corrections_remove_modes_dir "$TMP/d_env.json"
  assert_eq "remove_modes_dir idempotent" "null" \
    "$(jq -r '.env.CLAUDE_MEM_MODES_DIR' "$TMP/d_env.json")"
}

# ---- 3.1 corrections_curation_read / _write ----

test_curation_read_write() {
  assert_eq "curation read of absent file is empty" "" \
    "$(corrections_curation_read "$TMP/cur_absent.json")"

  corrections_curation_write "$TMP/cur.json" 29191 29205
  assert_eq "curation write+read returns ids" "29191 29205" \
    "$(corrections_curation_read "$TMP/cur.json")"

  corrections_curation_write "$TMP/cur.json" 29205 29999
  assert_eq "curation write dedups and merges" "29191 29205 29999" \
    "$(corrections_curation_read "$TMP/cur.json")"

  printf '%s' 'not json{' > "$TMP/cur_bad.json"
  assert_eq "curation read of garbage is empty" "" \
    "$(corrections_curation_read "$TMP/cur_bad.json")"
}

# ---- 3.2 atomic curation write ----

test_curation_atomic_write() {
  corrections_curation_write "$TMP/cur_atomic.json" 1 2 3
  assert_eq "curation file is valid JSON after write" "true" \
    "$(jq -e 'type == "object"' "$TMP/cur_atomic.json" >/dev/null 2>&1 \
       && echo true || echo false)"
  corrections_curation_write "$TMP/cur_atomic.json" 4
  assert_eq "curation file still valid after rewrite" "1 2 3 4" \
    "$(corrections_curation_read "$TMP/cur_atomic.json")"
}

# ---- corrections_list (requires sqlite3) ----

test_corrections_list() {
  export CORRECTIONS_DB="$TMP/fixture.db"
  sqlite3 "$CORRECTIONS_DB" "CREATE TABLE observations(id INTEGER, project TEXT, type TEXT, title TEXT, subtitle TEXT, narrative TEXT, created_at TEXT);"
  sqlite3 "$CORRECTIONS_DB" "INSERT INTO observations VALUES
    (1,'embo','correction','older corr','s1','n1','2026-01-01T00:00:00Z'),
    (2,'embo','correction','newer corr','s2','n2','2026-02-01T00:00:00Z'),
    (3,'embo','discovery','not a corr','s3','n3','2026-03-01T00:00:00Z'),
    (4,'other','correction','other project','s4','n4','2026-02-15T00:00:00Z');"

  local list
  list="$(corrections_list embo)"
  assert_eq "list returns only embo corrections (2)" "2" \
    "$(printf '%s' "$list" | jq 'length')"
  assert_eq "list excludes non-correction types" "false" \
    "$(printf '%s' "$list" | jq '[.[].title] | contains(["not a corr"])')"
  assert_eq "list excludes other projects" "false" \
    "$(printf '%s' "$list" | jq '[.[].title] | contains(["other project"])')"
  assert_eq "list is newest-first" "newer corr" \
    "$(printf '%s' "$list" | jq -r '.[0].title')"

  local bad_out bad_rc
  bad_out="$(corrections_list "x'; DROP TABLE observations; --" 2>/dev/null)"
  bad_rc=$?
  assert_eq "list rejects a non-identifier project (rc)" "2" "$bad_rc"
  assert_eq "list emits nothing for a bad project" "" "$bad_out"
  assert_eq "list rejection left the table intact" "4" \
    "$(sqlite3 "$CORRECTIONS_DB" 'SELECT count(*) FROM observations;')"

  sqlite3 "$CORRECTIONS_DB" "INSERT INTO observations VALUES
    (5,'my-repo.v2_x','correction','ok name','s5','n5','2026-04-01T00:00:00Z');"
  assert_eq "list accepts hyphen/dot/underscore names" "1" \
    "$(corrections_list 'my-repo.v2_x' | jq 'length')"
}

# ---- 042/1.1 corrections_list_pending ----

test_corrections_list_pending() {
  local p_first p_one p_all p_bad p_empty

  p_first="$(corrections_list_pending embo "$TMP/lp_absent.json")"
  assert_eq "pending: absent curation → all corrections" "2" \
    "$(printf '%s' "$p_first" | jq 'length')"
  assert_eq "pending: absent curation → newest first" "newer corr" \
    "$(printf '%s' "$p_first" | jq -r '.[0].title')"

  corrections_curation_write "$TMP/lp_one.json" 2
  p_one="$(corrections_list_pending embo "$TMP/lp_one.json")"
  assert_eq "pending: one curated → one remains" "1" \
    "$(printf '%s' "$p_one" | jq 'length')"
  assert_eq "pending: the remaining one is the uncurated id" "1" \
    "$(printf '%s' "$p_one" | jq -r '.[0].id')"

  corrections_curation_write "$TMP/lp_all.json" 1 2
  p_all="$(corrections_list_pending embo "$TMP/lp_all.json")"
  assert_eq "pending: all curated → empty array" "0" \
    "$(printf '%s' "$p_all" | jq 'length')"

  printf '%s' 'not json{' > "$TMP/lp_bad.json"
  p_bad="$(corrections_list_pending embo "$TMP/lp_bad.json")"
  assert_eq "pending: unparseable curation → all pending" "2" \
    "$(printf '%s' "$p_bad" | jq 'length')"

  p_empty="$(corrections_list_pending 'no-such-project' "$TMP/lp_absent.json")"
  assert_eq "pending: project with no corrections → empty array" "0" \
    "$(printf '%s' "$p_empty" | jq 'length')"
}

# ---- curation_write fail-safe on non-numeric id ----

test_curation_write_nonnumeric() {
  corrections_curation_write "$TMP/cur_mixed.json" 10 notanumber 20
  assert_eq "curation write skips a non-numeric id, keeps the rest" "10 20" \
    "$(corrections_curation_read "$TMP/cur_mixed.json")"
  assert_eq "curation file valid JSON after mixed-id write" "true" \
    "$(jq -e 'type == "object"' "$TMP/cur_mixed.json" >/dev/null 2>&1 \
       && echo true || echo false)"
}

# ---- 042 corrections_mode ----

test_corrections_mode() {
  export CORRECTIONS_CM_SETTINGS="$TMP/cm_absent.json"
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
}

# ---- 4.1 corrections_load_jsonl ----
# Reads the marker-hook JSONL file; returns a JSON array of entries.
# Invalid lines silently skipped; missing or empty file returns [].

test_corrections_load_jsonl() {
  # Valid JSONL — 3 entries with the fields capture-correction.sh writes.
  {
    printf '{"ts":"2026-08-15T10:00:00Z","session_id":"s1","rule":"do not indent","hash":"aaa111","source":"PostToolUse","source_type":"acknowledgment"}\n'
    printf '{"ts":"2026-08-15T10:01:00Z","session_id":"s1","rule":"use AskUserQuestion","hash":"bbb222","source":"Stop","source_type":"acknowledgment"}\n'
    printf '{"ts":"2026-08-15T10:02:00Z","session_id":"s2","rule":"check docs first","hash":"ccc333","source":"PostToolUse","source_type":"rejection_unacknowledged"}\n'
  } > "$TMP/jl_valid.jsonl"
  assert_eq "load_jsonl: 3 valid entries → length 3" "3" \
    "$(corrections_load_jsonl "$TMP/jl_valid.jsonl" | jq 'length')"
  assert_eq "load_jsonl: entry has rule field" "do not indent" \
    "$(corrections_load_jsonl "$TMP/jl_valid.jsonl" | jq -r '.[0].rule')"
  assert_eq "load_jsonl: entry has hash field" "aaa111" \
    "$(corrections_load_jsonl "$TMP/jl_valid.jsonl" | jq -r '.[0].hash')"

  # Empty file → [].
  : > "$TMP/jl_empty.jsonl"
  assert_eq "load_jsonl: empty file → length 0" "0" \
    "$(corrections_load_jsonl "$TMP/jl_empty.jsonl" | jq 'length')"

  # Invalid lines mixed with valid → valid ones returned, invalid skipped.
  {
    printf '{"ts":"2026-08-15T10:00:00Z","session_id":"s1","rule":"do not indent","hash":"aaa111","source":"PostToolUse","source_type":"acknowledgment"}\n'
    printf 'not valid json{\n'
    printf '{"ts":"2026-08-15T10:02:00Z","session_id":"s2","rule":"check docs first","hash":"ccc333","source":"PostToolUse","source_type":"rejection_unacknowledged"}\n'
  } > "$TMP/jl_mixed.jsonl"
  assert_eq "load_jsonl: 2 valid + 1 invalid → length 2" "2" \
    "$(corrections_load_jsonl "$TMP/jl_mixed.jsonl" | jq 'length')"

  # Missing file → [], no crash.
  assert_eq "load_jsonl: missing file → length 0" "0" \
    "$(corrections_load_jsonl "$TMP/jl_no_such_file.jsonl" | jq 'length')"

  # All-invalid lines → [].
  printf 'bad{json\nalso bad\n' > "$TMP/jl_allbad.jsonl"
  assert_eq "load_jsonl: all-invalid → length 0" "0" \
    "$(corrections_load_jsonl "$TMP/jl_allbad.jsonl" | jq 'length')"
}

# ---- run all tests ----

test_merge_modes_dir
test_modes_dir_conflict
test_write_enable_record
test_enable_idempotency
test_should_remove_modes_dir
test_crash_safe_rerun
test_curation_read_write
test_curation_atomic_write
if command -v sqlite3 >/dev/null 2>&1; then
  test_corrections_list
  test_corrections_list_pending
else
  printf 'SKIP: sqlite3 not available for corrections_list tests\n'
fi
test_curation_write_nonnumeric
test_corrections_mode
test_corrections_load_jsonl

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
