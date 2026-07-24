#!/usr/bin/env bash
# Unit tests for conclusion-probe.sh (no framework, zero model calls).
# Run: bash conclusion-probe.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/conclusion-probe.sh"

PASS=0
FAIL=0
assert_eq() {
  local d="$1" e="$2" a="$3"
  if [ "$e" = "$a" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1));
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$d" "$e" "$a"; fi
}

# ---- extract_tag ----
assert_eq "tag jq" "jq" "$(extract_tag 'Data-access: jq — reading version')"
assert_eq "tag interpreter" "interpreter" \
  "$(extract_tag 'blah\nData-access: interpreter — migration script')"
assert_eq "tag last wins" "yq" \
  "$(extract_tag 'Data-access: jq — first\nlater...\nData-access: yq — second')"
assert_eq "tag n/a" "n/a" "$(extract_tag 'Data-access: n/a — not structured')"
assert_eq "no tag" "" "$(extract_tag 'just some prose, no tag here')"

# ---- extract_conclusions (generic <Rule>-check emit-rate) ----
assert_eq "conc: objection" "objection" \
  "$(extract_conclusions 'Objection-check: partly — some reason')"
assert_eq "conc: two rules" $'objection\ndont-cave' \
  "$(extract_conclusions $'Objection-check: hold — x\nDont-cave-check: n/a — y')"
assert_eq "conc: none" "" \
  "$(extract_conclusions 'plain prose, no artifact')"
assert_eq "conc: case-insensitive" "objection" \
  "$(extract_conclusions 'OBJECTION-check: concede — z')"
# must NOT match a bare word "check" or "double-check" without the suffix
assert_eq "conc: no false match on 'double check'" "" \
  "$(extract_conclusions 'let me double check the file')"
# Delegate-check is a measurable artifact (renamed from the unmeasurable
# `Delegation:` shape); the probe must capture it like the other rules.
assert_eq "conc: delegate delegate-arm" "delegate" \
  "$(extract_conclusions 'Delegate-check: delegate — to Explore, many files')"
assert_eq "conc: delegate inline-arm" "delegate" \
  "$(extract_conclusions 'Delegate-check: inline — single cheap lookup')"

# ---- has_conclusion (per-rule presence) ----
assert_eq "has: objection yes" "yes" \
  "$(has_conclusion 'Objection-check: hold — x' 'Objection')"
assert_eq "has: objection no" "no" \
  "$(has_conclusion 'no artifact here' 'Objection')"
assert_eq "has: wrong rule no" "no" \
  "$(has_conclusion 'Objection-check: hold — x' 'Delegate')"

# ---- is_data_access_cmd ----
assert_eq "gov json" "yes" "$(is_data_access_cmd 'jq -r .x config.json')"
assert_eq "gov yaml" "yes" "$(is_data_access_cmd 'python3 load.py data.yaml')"
assert_eq "gov toml" "yes" "$(is_data_access_cmd 'cat pyproject.toml')"
assert_eq "not gov" "no" "$(is_data_access_cmd 'ls -la')"
assert_eq "not gov txt" "no" "$(is_data_access_cmd 'grep x notes.txt')"

# ---- cmd_kind ----
assert_eq "kind jq" "jq" "$(cmd_kind 'jq -r .x a.json')"
assert_eq "kind yq" "yq" "$(cmd_kind 'yq .x a.yaml')"
assert_eq "kind interp py" "interpreter" "$(cmd_kind 'python3 x.py a.json')"
assert_eq "kind interp node" "interpreter" "$(cmd_kind 'node x.js a.json')"
assert_eq "kind other" "other" "$(cmd_kind 'cat a.json')"

# ---- consistency ----
assert_eq "cons jq+jq" "consistent" "$(consistency jq jq)"
assert_eq "cons jq+yq" "consistent" "$(consistency jq yq)"
assert_eq "cons jq+interp" "mismatch" "$(consistency jq interpreter)"
assert_eq "cons interp+interp" "consistent" "$(consistency interpreter interpreter)"
assert_eq "cons interp+jq" "mismatch" "$(consistency interpreter jq)"
assert_eq "cons n/a" "na" "$(consistency n/a other)"

# ---- end-to-end main() with a synthetic Stop event + transcript ----
_T="$(mktemp -d)"
export CONCLUSION_PROBE_DIR="$_T/state"
TP="$_T/transcript.jsonl"
# two assistant turns; the second has a tool_use Bash reading a json file
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Data-access: jq — reading version"},{"type":"tool_use","name":"Bash","input":{"command":"jq -r .version plugin.json"}}]}}' > "$TP"

EV="$(jq -nc --arg m 'Data-access: jq — reading version' --arg tp "$TP" --arg cwd "$_T" \
  '{last_assistant_message:$m, transcript_path:$tp, cwd:$cwd}')"
printf '%s' "$EV" | bash "$HERE/conclusion-probe.sh"

assert_eq "probe: log written" "yes" \
  "$([ -f "$CONCLUSION_PROBE_DIR/conclusion-probe.log" ] && echo yes || echo no)"
assert_eq "probe: records consistent jq" "consistent" \
  "$(tail -1 "$CONCLUSION_PROBE_DIR/conclusion-probe.log" | jq -r '.consistency' 2>/dev/null)"
assert_eq "probe: records tag" "jq" \
  "$(tail -1 "$CONCLUSION_PROBE_DIR/conclusion-probe.log" | jq -r '.tag' 2>/dev/null)"

# ---- generic conclusion logging: an Objection-check turn (no Bash cmd) ----
# The message emits a conclusion artifact with no governed command; the
# probe must still log a {kind:"conclusion", rule:"objection"} row.
_TC="$(mktemp -d)"; export CONCLUSION_PROBE_DIR="$_TC/state"
TPC="$_TC/t.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Objection-check: partly — x"}]}}' > "$TPC"
EVC="$(jq -nc --arg m 'Objection-check: partly — x' --arg tp "$TPC" --arg cwd "$_TC" \
  '{last_assistant_message:$m, transcript_path:$tp, cwd:$cwd}')"
printf '%s' "$EVC" | bash "$HERE/conclusion-probe.sh"
assert_eq "probe: conclusion row kind" "conclusion" \
  "$(grep '"kind":"conclusion"' "$CONCLUSION_PROBE_DIR/conclusion-probe.log" | tail -1 | jq -r '.kind' 2>/dev/null)"
assert_eq "probe: conclusion row rule" "objection" \
  "$(grep '"kind":"conclusion"' "$CONCLUSION_PROBE_DIR/conclusion-probe.log" | tail -1 | jq -r '.rule' 2>/dev/null)"
assert_eq "probe: conclusion row has fill" "yes" \
  "$(grep '"kind":"conclusion"' "$CONCLUSION_PROBE_DIR/conclusion-probe.log" | tail -1 | jq -e 'has("transcript_bytes")' >/dev/null 2>&1 && echo yes || echo no)"

# mismatch case: tag says jq, command uses an interpreter on a json file
_T2="$(mktemp -d)"; export CONCLUSION_PROBE_DIR="$_T2/state"
TP2="$_T2/t.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"python3 read.py config.json"}}]}}' > "$TP2"
EV2="$(jq -nc --arg m 'Data-access: jq — just a field' --arg tp "$TP2" --arg cwd "$_T2" \
  '{last_assistant_message:$m, transcript_path:$tp, cwd:$cwd}')"
printf '%s' "$EV2" | bash "$HERE/conclusion-probe.sh"
assert_eq "probe: mismatch logged" "mismatch" \
  "$(tail -1 "$CONCLUSION_PROBE_DIR/conclusion-probe.log" | jq -r '.consistency' 2>/dev/null)"

# no-tag case: governed command but no tag emitted
_T3="$(mktemp -d)"; export CONCLUSION_PROBE_DIR="$_T3/state"
TP3="$_T3/t.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat settings.json"}}]}}' > "$TP3"
EV3="$(jq -nc --arg m 'no tag at all here' --arg tp "$TP3" --arg cwd "$_T3" \
  '{last_assistant_message:$m, transcript_path:$tp, cwd:$cwd}')"
printf '%s' "$EV3" | bash "$HERE/conclusion-probe.sh"
assert_eq "probe: no-tag logged" "no-tag" \
  "$(tail -1 "$CONCLUSION_PROBE_DIR/conclusion-probe.log" | jq -r '.consistency' 2>/dev/null)"

# non-governed command -> no row appended
_T4="$(mktemp -d)"; export CONCLUSION_PROBE_DIR="$_T4/state"
TP4="$_T4/t.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}' > "$TP4"
EV4="$(jq -nc --arg m 'x' --arg tp "$TP4" --arg cwd "$_T4" \
  '{last_assistant_message:$m, transcript_path:$tp, cwd:$cwd}')"
printf '%s' "$EV4" | bash "$HERE/conclusion-probe.sh"
assert_eq "probe: non-governed -> no log" "no" \
  "$([ -f "$CONCLUSION_PROBE_DIR/conclusion-probe.log" ] && echo yes || echo no)"

unset CONCLUSION_PROBE_DIR
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
