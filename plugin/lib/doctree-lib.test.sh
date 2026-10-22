#!/usr/bin/env bash
# Fixture tests for doctree-lib.sh.
# Run: bash plugin/lib/doctree-lib.test.sh
# Exits non-zero if any assertion fails.
#
# doctree_resolve_model reads a profile field via `embo-profile get`; the
# tests stub that command through DOCTREE_PROFILE_GET so no real profile
# is touched. doctree_phase_doc_path is pure string construction and needs
# no stub.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/doctree-lib.sh"

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

# Stub for `embo-profile get <key>`. The library calls the resolver hook
# DOCTREE_PROFILE_GET with the dotted key; the test sets it per case to
# return a value or an empty string (absent field / absent profile).
stub_profile_returns() {
  # $1 = value to return for any key ("" means absent). The value is
  # baked into the function body at definition time (eval), so it does
  # not depend on a variable that is out of scope at call time.
  eval "DOCTREE_PROFILE_GET() { printf '%s' '$1'; }"
}
stub_profile_map() {
  # Return per-key values from a case statement; keys not listed → "".
  DOCTREE_PROFILE_GET() {
    case "$1" in
      doctree.models.prd)         printf 'opus' ;;
      doctree.models.tech_design) printf 'haiku' ;;
      doctree.models.tasks)       printf '' ;;
      *)                          printf '' ;;
    esac
  }
}

# ---- doctree_resolve_model: profile value when set ----

test_resolve_model_profile_value() {
  stub_profile_returns "fable"
  assert_eq "resolve_model: prd → profile value" "fable" \
    "$(doctree_resolve_model prd)"
  assert_eq "resolve_model: tech_design → profile value" "fable" \
    "$(doctree_resolve_model tech_design)"
  assert_eq "resolve_model: tasks → profile value" "fable" \
    "$(doctree_resolve_model tasks)"
}

# ---- doctree_resolve_model: built-in default when field absent ----

test_resolve_model_builtin_default() {
  stub_profile_returns ""
  assert_eq "resolve_model: prd absent → opus" "opus" \
    "$(doctree_resolve_model prd)"
  assert_eq "resolve_model: tech_design absent → opus" "opus" \
    "$(doctree_resolve_model tech_design)"
  assert_eq "resolve_model: tasks absent → sonnet" "sonnet" \
    "$(doctree_resolve_model tasks)"
}

# ---- doctree_resolve_model: mixed — some set, some fall back ----

test_resolve_model_mixed() {
  stub_profile_map
  assert_eq "resolve_model: prd set → opus" "opus" \
    "$(doctree_resolve_model prd)"
  assert_eq "resolve_model: tech_design set → haiku" "haiku" \
    "$(doctree_resolve_model tech_design)"
  assert_eq "resolve_model: tasks empty → sonnet default" "sonnet" \
    "$(doctree_resolve_model tasks)"
}

# ---- doctree_resolve_model: unknown phase → empty, rc 1 ----

test_resolve_model_unknown_phase() {
  stub_profile_returns ""
  local out
  out="$(doctree_resolve_model bogus)"
  assert_eq "resolve_model: unknown phase → empty" "" "$out"
  doctree_resolve_model bogus >/dev/null 2>&1
  assert_eq "resolve_model: unknown phase → rc 1" "1" "$?"
}

# ---- doctree_phase_doc_path: all three phases ----

test_phase_doc_path_all() {
  local td="tasks/068-TEAMMATE-DOCTREE-pipeline"
  local date="2026-10-21"
  local slug="068-teammate-doctree-pipeline"
  assert_eq "doc_path: prd" \
    "$td/2026-10-21-068-teammate-doctree-pipeline-prd.md" \
    "$(doctree_phase_doc_path "$td" "$date" "$slug" prd)"
  assert_eq "doc_path: tech_design → -tech-design.md" \
    "$td/2026-10-21-068-teammate-doctree-pipeline-tech-design.md" \
    "$(doctree_phase_doc_path "$td" "$date" "$slug" tech_design)"
  assert_eq "doc_path: tasks" \
    "$td/2026-10-21-068-teammate-doctree-pipeline-tasks.md" \
    "$(doctree_phase_doc_path "$td" "$date" "$slug" tasks)"
}

# ---- doctree_phase_doc_path: trailing slash on taskdir is normalized ----

test_phase_doc_path_trailing_slash() {
  assert_eq "doc_path: trailing slash on taskdir normalized" \
    "tasks/x/2026-01-02-foo-prd.md" \
    "$(doctree_phase_doc_path "tasks/x/" "2026-01-02" "foo" prd)"
}

# ---- doctree_phase_doc_path: unknown phase → empty, rc 1 ----

test_phase_doc_path_unknown_phase() {
  local out
  out="$(doctree_phase_doc_path "tasks/x" "2026-01-02" "foo" bogus)"
  assert_eq "doc_path: unknown phase → empty" "" "$out"
  doctree_phase_doc_path "tasks/x" "2026-01-02" "foo" bogus >/dev/null 2>&1
  assert_eq "doc_path: unknown phase → rc 1" "1" "$?"
}

# ---- run all tests ----

test_resolve_model_profile_value
test_resolve_model_builtin_default
test_resolve_model_mixed
test_resolve_model_unknown_phase
test_phase_doc_path_all
test_phase_doc_path_trailing_slash
test_phase_doc_path_unknown_phase

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
