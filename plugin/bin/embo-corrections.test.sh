#!/usr/bin/env bash
# Plain-Bash tests for the embo-corrections wrapper.
# Run: bash plugin/bin/embo-corrections.test.sh
# Exits non-zero if any assertion fails.
#
# Verifies the wrapper's own behaviour — project derivation from CWD,
# subcommand dispatch, curation-file default, and that it runs with
# CLAUDE_PLUGIN_ROOT unset from an arbitrary CWD. The correction/curation
# LOGIC is tested in claude-mem/corrections-lib.test.sh; this file tests
# only the wrapper wiring. Operates on synthetic temp files only.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$HERE/embo-corrections"

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

if ! command -v sqlite3 >/dev/null 2>&1; then
  printf 'SKIP: sqlite3 not available for embo-corrections wrapper test\n'
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fixture project dir whose basename is the project name.
PROJ="$TMP/embo"
mkdir -p "$PROJ/.claude"

# Fixture claude-mem DB with two embo corrections and one other-project row.
DB="$TMP/fix.db"
sqlite3 "$DB" "CREATE TABLE observations(id INTEGER, project TEXT, type TEXT, title TEXT, subtitle TEXT, narrative TEXT, created_at TEXT);"
sqlite3 "$DB" "INSERT INTO observations VALUES
  (1,'embo','correction','older','s','n','2026-01-01T00:00:00Z'),
  (2,'embo','correction','newer','s','n','2026-02-01T00:00:00Z'),
  (3,'other','correction','elsewhere','s','n','2026-03-01T00:00:00Z');"

export CORRECTIONS_DB="$DB"
unset CLAUDE_PLUGIN_ROOT

# Run the wrapper from inside the fixture project so $PWD basename = embo.
run() { ( cd "$PROJ" && "$WRAPPER" "$@" ); }

# ---- project subcommand ----

test_project_derivation() {
  assert_eq "project derived from CWD basename" "embo" "$(run project)"
}

# ---- list-pending subcommand ----

test_list_pending() {
  local first after

  first="$(run list-pending)"
  assert_eq "list-pending first run count" "2" \
    "$(printf '%s' "$first" | jq 'length')"
  assert_eq "list-pending newest first" "2" \
    "$(printf '%s' "$first" | jq -r '.[0].id')"
  assert_eq "list-pending excludes other project" "false" \
    "$(printf '%s' "$first" | jq '[.[].id] | contains([3])')"

  run write 2 >/dev/null
  assert_eq "write used the default curation path" "true" \
    "$( [ -f "$PROJ/.claude/correction-curation.json" ] && echo true || echo false )"
  assert_eq "write recorded the id" "2" \
    "$(jq -r '.curated_ids | join(" ")' "$PROJ/.claude/correction-curation.json")"

  after="$(run list-pending)"
  assert_eq "list-pending after write count" "1" \
    "$(printf '%s' "$after" | jq 'length')"
  assert_eq "list-pending after write remaining id" "1" \
    "$(printf '%s' "$after" | jq -r '.[0].id')"

  run write "$PROJ/.claude/other-curation.json" 1 >/dev/null
  assert_eq "write honoured an explicit curation path" "1" \
    "$(jq -r '.curated_ids | join(" ")' "$PROJ/.claude/other-curation.json")"
}

# ---- mode subcommand ----

test_mode() {
  printf '%s\n' '{"CLAUDE_MEM_MODE":"code-embo"}' > "$TMP/cm.json"
  export CORRECTIONS_CM_SETTINGS="$TMP/cm.json"
  assert_eq "mode reports code-embo when enabled" "code-embo" "$(run mode)"

  export CORRECTIONS_CM_SETTINGS="$TMP/missing.json"
  assert_eq "mode defaults to code when settings absent" "code" "$(run mode)"
}

# ---- unknown subcommand ----

test_unknown_subcommand() {
  run bogus >/dev/null 2>&1
  assert_eq "unknown subcommand returns rc 2" "2" "$?"
}

# ---- 4.3 merged-list subcommand ----
# Aggregates corrections from both the claude-mem DB and the marker JSONL
# file, deduplicated by content hash. Each entry records which source(s)
# it came from.

test_merged_list() {
  local proj="$TMP/merge-proj"
  mkdir -p "$proj/.claude"

  # Fixture DB: 2 embo corrections (titles unique, so hash on title produces distinct keys).
  local mdb="$TMP/merge.db"
  sqlite3 "$mdb" "CREATE TABLE observations(id INTEGER, project TEXT, type TEXT, title TEXT, subtitle TEXT, narrative TEXT, created_at TEXT);"
  sqlite3 "$mdb" "INSERT INTO observations VALUES
    (10,'merge-proj','correction','cm-only rule','s','n','2026-01-01T00:00:00Z'),
    (11,'merge-proj','correction','shared rule','s','n','2026-02-01T00:00:00Z');"

  # JSONL file: 2 entries — one with the same rule text as the DB entry (hash match)
  # and one unique to JSONL. The shared entry must be deduped; the JSONL-only one added.
  # Hash for "shared rule" is computed by the wrapper (sha256 of the title).
  local shared_hash
  shared_hash="$(printf '%s' 'shared rule' | shasum -a 256 | awk '{print $1}')"
  {
    printf '{"ts":"2026-08-15T10:00:00Z","session_id":"s1","rule":"shared rule","hash":"%s","source":"PostToolUse","source_type":"acknowledgment"}\n' "$shared_hash"
    printf '{"ts":"2026-08-15T10:01:00Z","session_id":"s1","rule":"jsonl-only rule","hash":"fff999","source":"Stop","source_type":"acknowledgment"}\n'
  } > "$proj/.claude/corrections.jsonl"

  local merged
  export CORRECTIONS_DB="$mdb"
  merged="$(cd "$proj" && CORRECTIONS_DB="$mdb" "$WRAPPER" merged-list)"

  assert_eq "merged-list: 3 distinct rules → length 3" "3" \
    "$(printf '%s' "$merged" | jq 'length')"

  # The shared entry must appear exactly once and list both sources.
  local shared_sources
  shared_sources="$(printf '%s' "$merged" | jq -r \
    '[.[] | select(.rule == "shared rule") | .sources[]] | sort | join(",")' 2>/dev/null)"
  assert_eq "merged-list: shared entry has both sources" "claude-mem,jsonl" \
    "$shared_sources"

  # The cm-only entry must appear with source claude-mem only.
  local cm_sources
  cm_sources="$(printf '%s' "$merged" | jq -r \
    '[.[] | select(.rule == "cm-only rule") | .sources[]] | join(",")' 2>/dev/null)"
  assert_eq "merged-list: cm-only entry has source claude-mem" "claude-mem" \
    "$cm_sources"

  # The jsonl-only entry must appear with source jsonl only.
  local jl_sources
  jl_sources="$(printf '%s' "$merged" | jq -r \
    '[.[] | select(.rule == "jsonl-only rule") | .sources[]] | join(",")' 2>/dev/null)"
  assert_eq "merged-list: jsonl-only entry has source jsonl" "jsonl" \
    "$jl_sources"

  # JSONL missing → falls back to claude-mem only.
  local proj2="$TMP/merge-proj2"
  mkdir -p "$proj2/.claude"
  local mdb2="$TMP/merge2.db"
  sqlite3 "$mdb2" "CREATE TABLE observations(id INTEGER, project TEXT, type TEXT, title TEXT, subtitle TEXT, narrative TEXT, created_at TEXT);"
  sqlite3 "$mdb2" "INSERT INTO observations VALUES
    (20,'merge-proj2','correction','cm rule only','s','n','2026-01-01T00:00:00Z');"
  local cm_only_merged
  cm_only_merged="$(cd "$proj2" && CORRECTIONS_DB="$mdb2" "$WRAPPER" merged-list)"
  assert_eq "merged-list: JSONL missing → cm-only, length 1" "1" \
    "$(printf '%s' "$cm_only_merged" | jq 'length')"
  assert_eq "merged-list: JSONL missing → source is claude-mem" "claude-mem" \
    "$(printf '%s' "$cm_only_merged" | jq -r '.[0].sources[0]')"

  # claude-mem empty → falls back to JSONL only.
  local proj3="$TMP/merge-proj3"
  mkdir -p "$proj3/.claude"
  local mdb3="$TMP/merge3.db"
  sqlite3 "$mdb3" "CREATE TABLE observations(id INTEGER, project TEXT, type TEXT, title TEXT, subtitle TEXT, narrative TEXT, created_at TEXT);"
  printf '{"ts":"2026-08-15T10:00:00Z","session_id":"s1","rule":"jsonl rule only","hash":"zzz000","source":"PostToolUse","source_type":"acknowledgment"}\n' \
    > "$proj3/.claude/corrections.jsonl"
  local jl_only_merged
  jl_only_merged="$(cd "$proj3" && CORRECTIONS_DB="$mdb3" "$WRAPPER" merged-list)"
  assert_eq "merged-list: cm empty → jsonl-only, length 1" "1" \
    "$(printf '%s' "$jl_only_merged" | jq 'length')"
  assert_eq "merged-list: cm empty → source is jsonl" "jsonl" \
    "$(printf '%s' "$jl_only_merged" | jq -r '.[0].sources[0]')"
}

# ---- run all tests ----

test_project_derivation
test_list_pending
test_mode
test_unknown_subcommand
test_merged_list

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
