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

# ---- 2.7: embo-profile get reads doctree.* from every shipped profile ----
# Runs the real wrapper against each shipped profile via EMBO_PROFILE_ACTIVE,
# so no ~/.claude is touched. Skipped with a notice if yq is unavailable.

PROFILES_DIR="$HERE/../profiles"
WRAPPER="$HERE/../bin/embo-profile"

pget() {
  # pget <profile.yaml> <dotted-field>
  EMBO_PROFILE_ACTIVE="$PROFILES_DIR/$1" "$WRAPPER" get "$2"
}

test_profiles_doctree_fields() {
  if ! command -v yq >/dev/null 2>&1; then
    printf 'SKIP: 2.7 profile-field checks (yq not found)\n'
    return 0
  fi
  # Expected per the tech-design defaults table.
  # profile|prd|tech_design|tasks|escalation|round_cap|max_agents
  local rows="
default.yaml|opus|opus|sonnet|collect|2|20
quality.yaml|opus|opus|sonnet|collect|2|20
fast.yaml|sonnet|sonnet|haiku|collect|1|12
minimal.yaml|sonnet|sonnet|haiku|collect|1|12
research.yaml|opus|opus|sonnet|halt|2|24
"
  local line p prd td tk esc rc ma
  while IFS='|' read -r p prd td tk esc rc ma; do
    [ -z "$p" ] && continue
    assert_eq "$p doctree.models.prd" "$prd" "$(pget "$p" doctree.models.prd)"
    assert_eq "$p doctree.models.tech_design" "$td" "$(pget "$p" doctree.models.tech_design)"
    assert_eq "$p doctree.models.tasks" "$tk" "$(pget "$p" doctree.models.tasks)"
    assert_eq "$p doctree.escalation" "$esc" "$(pget "$p" doctree.escalation)"
    assert_eq "$p doctree.round_cap" "$rc" "$(pget "$p" doctree.round_cap)"
    assert_eq "$p doctree.budget.max_agents" "$ma" "$(pget "$p" doctree.budget.max_agents)"
    assert_eq "$p doctree.reviewer_model_family" "sonnet" \
      "$(pget "$p" doctree.reviewer_model_family)"
  done <<< "$rows"
  # Absent field → empty string.
  assert_eq "default.yaml absent field → empty" "" \
    "$(pget default.yaml doctree.models.nope)"
}

# ---- 7.3/7.4: doctree_effective_model (override wins over profile) ----

test_effective_model_override_wins() {
  stub_profile_returns "opus"   # profile would say opus for every phase
  assert_eq "effective_model: override wins over profile" "fable" \
    "$(doctree_effective_model fable prd)"
  assert_eq "effective_model: no override → profile value" "opus" \
    "$(doctree_effective_model "" prd)"
}

test_effective_model_falls_back_to_default() {
  stub_profile_returns ""        # profile absent → built-in defaults
  assert_eq "effective_model: no override, absent field → prd default" "opus" \
    "$(doctree_effective_model "" prd)"
  assert_eq "effective_model: no override, absent field → tasks default" "sonnet" \
    "$(doctree_effective_model "" tasks)"
  assert_eq "effective_model: override still wins when field absent" "haiku" \
    "$(doctree_effective_model haiku tasks)"
}

# ---- 2.8: escalation modes (collect / halt) ----
# doctree_should_halt <mode> <blocked-count> → rc 0 halt, 1 continue,
# 2 unknown mode.

test_escalation_collect_never_halts() {
  doctree_should_halt collect 0; assert_eq "collect, 0 blocked → continue" "1" "$?"
  doctree_should_halt collect 1; assert_eq "collect, 1 blocked → continue" "1" "$?"
  doctree_should_halt collect 9; assert_eq "collect, many blocked → continue" "1" "$?"
}

test_escalation_halt_stops_on_first() {
  doctree_should_halt halt 0; assert_eq "halt, 0 blocked → continue" "1" "$?"
  doctree_should_halt halt 1; assert_eq "halt, 1 blocked → halt" "0" "$?"
  doctree_should_halt halt 3; assert_eq "halt, 3 blocked → halt" "0" "$?"
}

test_escalation_unknown_mode() {
  doctree_should_halt bogus 1 2>/dev/null; assert_eq "unknown mode → rc 2" "2" "$?"
}

# ---- 2.10: parity fixtures are well-formed ----
# The fixture file is shared by doctree_validate_amend (shell) and the
# inlined JS validator (workflow script), so they cannot drift. The
# validators themselves arrive in later stories; this guards the fixtures
# now: valid JSON, every case has id/verdict/record, verdicts are in set.

FIXTURES="$HERE/doctree-amend-fixtures.json"

test_parity_fixtures_wellformed() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: 2.10 fixture checks (jq not found)\n'
    return 0
  fi
  assert_eq "fixtures: file is valid JSON" "ok" \
    "$(jq -e . "$FIXTURES" >/dev/null 2>&1 && echo ok || echo bad)"
  assert_eq "fixtures: has at least one valid and one rejected case" "ok" \
    "$(jq -e '([.cases[]|select(.verdict=="valid")]|length>0) and ([.cases[]|select(.verdict=="rejected")]|length>0)' "$FIXTURES" >/dev/null 2>&1 && echo ok || echo bad)"
  assert_eq "fixtures: every case has id, verdict, record" "0" \
    "$(jq '[.cases[]|select((has("id") and has("verdict") and has("record"))|not)]|length' "$FIXTURES")"
  assert_eq "fixtures: every verdict is valid|rejected" "0" \
    "$(jq '[.cases[]|select(.verdict|IN("valid","rejected")|not)]|length' "$FIXTURES")"
  assert_eq "fixtures: required_fields list is present" "ok" \
    "$(jq -e '.required_fields|length>0' "$FIXTURES" >/dev/null 2>&1 && echo ok || echo bad)"
}

# ---- 8.1: doctree_validate_amend against the parity fixtures ----
# Every fixture case is run through the shell validator; its verdict must
# match the fixture's expected verdict. The same fixtures drive the JS
# validator (Story 5.5), so the two cannot diverge.

test_validate_amend_fixtures() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: 8.1 validate_amend fixtures (jq not found)\n'
    return 0
  fi
  local n i id expected rec rc got
  n="$(jq '.cases | length' "$FIXTURES")"
  i=0
  while [ "$i" -lt "$n" ]; do
    id="$(jq -r ".cases[$i].id" "$FIXTURES")"
    expected="$(jq -r ".cases[$i].verdict" "$FIXTURES")"
    rec="$(jq -c ".cases[$i].record" "$FIXTURES")"
    if doctree_validate_amend "$rec"; then got="valid"; else got="rejected"; fi
    assert_eq "validate_amend[$id]" "$expected" "$got"
    i=$((i + 1))
  done
}

# ---- 8.1: doctree_validate_amend edge cases ----

test_validate_amend_edges() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: 8.1 validate_amend edges (jq not found)\n'
    return 0
  fi
  doctree_validate_amend "" 2>/dev/null
  assert_eq "validate_amend: empty arg → rc 2" "2" "$?"
  doctree_validate_amend "not json{" 2>/dev/null
  assert_eq "validate_amend: unparseable → rc 2" "2" "$?"
}

# ---- 3.5: the phase agent carries the FR-3 canary, matching the hook ----
# The canary phrase the agent is told to echo must be a phrase the
# SubagentStart hook actually injects, or the canary proves nothing.

AGENT="$HERE/../agents/doctree-phase.md"
HOOK="$HERE/../hooks/subagent-rules.sh"

test_agent_canary_matches_hook() {
  assert_eq "agent: references the canary phrase" "yes" \
    "$(grep -q 'BINDING SUBAGENT RULES' "$AGENT" && echo yes || echo no)"
  assert_eq "hook: injects the canary phrase" "yes" \
    "$(grep -q 'BINDING SUBAGENT RULES' "$HOOK" && echo yes || echo no)"
  assert_eq "agent: has a canary field in the digest" "yes" \
    "$(grep -q 'canary:' "$AGENT" && echo yes || echo no)"
}

# ---- 3.6: the phase agent body has no task numbers or tasks/ paths ----

test_agent_no_task_refs() {
  # A real task-path reference is tasks/ followed by a digit. The input
  # contract's literal placeholder tasks/<nnn>-<SLUG>/ is allowed.
  assert_eq "agent: no tasks/<digit> paths" "0" \
    "$(grep -Ec 'tasks/[0-9]' "$AGENT" || true)"
  assert_eq "agent: no bare task-number references" "0" \
    "$(grep -Ec 'task(s)? +[0-9]{3}|Story [0-9]' "$AGENT" || true)"
}

# ---- 7.9: the entry command body has no task numbers or tasks/ paths ----

DOCTREE_CMD="$HERE/../commands/doctree.md"

test_command_no_task_refs() {
  assert_eq "command: no tasks/<digit> paths" "0" \
    "$(grep -Ec 'tasks/[0-9]' "$DOCTREE_CMD" || true)"
  assert_eq "command: no bare task-number references" "0" \
    "$(grep -Ec 'task(s)? +[0-9]{3}|Story [0-9]' "$DOCTREE_CMD" || true)"
}

# ---- run all tests ----

test_resolve_model_profile_value
test_resolve_model_builtin_default
test_resolve_model_mixed
test_resolve_model_unknown_phase
test_effective_model_override_wins
test_effective_model_falls_back_to_default
test_phase_doc_path_all
test_phase_doc_path_trailing_slash
test_phase_doc_path_unknown_phase
test_escalation_collect_never_halts
test_escalation_halt_stops_on_first
test_escalation_unknown_mode
test_validate_amend_fixtures
test_validate_amend_edges
test_agent_canary_matches_hook
test_agent_no_task_refs
test_command_no_task_refs
test_profiles_doctree_fields
test_parity_fixtures_wellformed

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
