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

# A fixture project directory whose basename is the project name.
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
# The whole point: the wrapper must not need this to be set.
unset CLAUDE_PLUGIN_ROOT

# Run the wrapper from inside the fixture project so $PWD basename = embo.
run() { ( cd "$PROJ" && "$WRAPPER" "$@" ); }

# project: derived from CWD basename.
assert_eq "project derived from CWD basename" "embo" "$(run project)"

# list-pending first run: both embo corrections, newest first, other
# project excluded.
FIRST="$(run list-pending)"
assert_eq "list-pending first run count" "2" \
  "$(printf '%s' "$FIRST" | jq 'length')"
assert_eq "list-pending newest first" "2" \
  "$(printf '%s' "$FIRST" | jq -r '.[0].id')"
assert_eq "list-pending excludes other project" "false" \
  "$(printf '%s' "$FIRST" | jq '[.[].id] | contains([3])')"

# write with default curation file: lands at ./.claude/correction-curation.json.
run write 2 >/dev/null
assert_eq "write used the default curation path" "true" \
  "$( [ -f "$PROJ/.claude/correction-curation.json" ] && echo true || echo false )"
assert_eq "write recorded the id" "2" \
  "$(jq -r '.curated_ids | join(" ")' "$PROJ/.claude/correction-curation.json")"

# list-pending after write: id 2 excluded, only id 1 remains.
AFTER="$(run list-pending)"
assert_eq "list-pending after write count" "1" \
  "$(printf '%s' "$AFTER" | jq 'length')"
assert_eq "list-pending after write remaining id" "1" \
  "$(printf '%s' "$AFTER" | jq -r '.[0].id')"

# write with an explicit curation-file arg (non-numeric first arg).
run write "$PROJ/.claude/other-curation.json" 1 >/dev/null
assert_eq "write honoured an explicit curation path" "1" \
  "$(jq -r '.curated_ids | join(" ")' "$PROJ/.claude/other-curation.json")"

# mode: reads claude-mem's (overridable) settings file.
printf '%s\n' '{"CLAUDE_MEM_MODE":"code-embo"}' > "$TMP/cm.json"
export CORRECTIONS_CM_SETTINGS="$TMP/cm.json"
assert_eq "mode reports code-embo when enabled" "code-embo" "$(run mode)"
export CORRECTIONS_CM_SETTINGS="$TMP/missing.json"
assert_eq "mode defaults to code when settings absent" "code" "$(run mode)"

# unknown subcommand → usage on stderr, rc 2.
run bogus >/dev/null 2>&1
assert_eq "unknown subcommand returns rc 2" "2" "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
