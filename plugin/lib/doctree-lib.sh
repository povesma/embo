#!/usr/bin/env bash
# doctree-lib.sh — shared pure functions for the doc-tree pipeline.
# Sourced by the entry command (commands/doctree.md) and the sequential
# fallback. The workflow script cannot source this; it carries an inlined
# copy of the validator kept in step by shared fixtures.
# Pure functions: no output beyond the requested value, no side effects,
# no exits.

# doctree_profile_get <dotted-key>
# One seam over `embo-profile get`, so tests can stub the profile without
# a real ~/.claude. Define DOCTREE_PROFILE_GET to override; otherwise the
# real wrapper is used.
doctree_profile_get() {
  if declare -F DOCTREE_PROFILE_GET >/dev/null 2>&1; then
    DOCTREE_PROFILE_GET "$1"
  else
    embo-profile get "$1"
  fi
}

# doctree_resolve_model <phase>
# Phase is one of prd | tech_design | tasks. Prints the profile's
# doctree.models.<phase> value when set, else the built-in default.
# Unknown phase: prints nothing, returns 1.
doctree_resolve_model() {
  local phase="$1" default value
  case "$phase" in
    prd)         default="opus" ;;
    tech_design) default="opus" ;;
    tasks)       default="sonnet" ;;
    *)           return 1 ;;
  esac
  value="$(doctree_profile_get "doctree.models.$phase")"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$default"
  fi
}

# doctree_validate_amend <json-record>
# The mechanical malformed-record check for an AMEND record (D7). Reads a
# single record as a JSON object on the first argument and applies only
# the checks that need no live resolution:
#   - every required field present AND non-empty
#     (target section finding evidence proposed origin severity status
#      prior_state)
#   - target   ∈ {prd, tech-design, tasks}
#   - severity ∈ {high, medium, low, infeasible}
#   - status   ∈ {open, resolved}
# It does NOT resolve evidence (file:line existence, URL reachability) or
# match section against a live heading — those are live checks. Returns 0
# when the record is well-formed, 1 when it is rejected, 2 on a usage or
# parse error. Requires jq. The inlined JS validator in the workflow
# script mirrors these rules; the shared fixtures keep them in step.
doctree_validate_amend() {
  local rec="${1:-}"
  [ -z "$rec" ] && return 2
  command -v jq >/dev/null 2>&1 || return 2
  # Reject a non-object or unparseable input as a usage/parse error (rc 2),
  # distinct from a well-formed-but-invalid record (rc 1).
  printf '%s' "$rec" | jq -e 'type == "object"' >/dev/null 2>&1 || return 2
  if printf '%s' "$rec" | jq -e '
    . as $r
    | def present($k): ($r|has($k)) and ($r[$k] != null) and (($r[$k]|tostring|length) > 0);
      (["target","section","finding","evidence","proposed","origin","severity","status","prior_state"]
         | all(present(.)))
      and ($r.target   | IN("prd","tech-design","tasks"))
      and ($r.severity | IN("high","medium","low","infeasible"))
      and ($r.status   | IN("open","resolved"))
  ' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# doctree_effective_model <override> <phase>
# The resolution order for a phase's model: a non-empty <override> (from a
# --model-<phase> argument) wins; otherwise fall back to the profile value
# or built-in default via doctree_resolve_model. Prints the chosen model;
# returns doctree_resolve_model's code (1 on an unknown phase) when no
# override is given, 0 when the override is used.
doctree_effective_model() {
  local override="$1" phase="$2"
  if [ -n "$override" ]; then
    printf '%s' "$override"
    return 0
  fi
  doctree_resolve_model "$phase"
}

# doctree_should_halt <mode> <blocked-count>
# The escalation decision. `halt` stops the run as soon as one item is
# blocked; `collect` records blocked items and never halts mid-run (they
# are presented together in the closing report). Returns 0 to halt now,
# 1 to continue, 2 for an unknown mode (fail loudly on a typo'd profile).
doctree_should_halt() {
  local mode="$1" blocked="$2"
  case "$mode" in
    halt)    [ "$blocked" -ge 1 ] && return 0 || return 1 ;;
    collect) return 1 ;;
    *)       return 2 ;;
  esac
}

# doctree_phase_doc_path <taskdir> <run-date> <slug> <phase>
# The single definition of a phase's write target, so the command and the
# fallback agree. Returns <taskdir>/<run-date>-<slug>-<suffix>.md.
# Phase is one of prd | tech_design | tasks (tech_design maps to the
# -tech-design.md suffix). Unknown phase: prints nothing, returns 1.
doctree_phase_doc_path() {
  local taskdir="$1" date="$2" slug="$3" phase="$4" suffix
  case "$phase" in
    prd)         suffix="prd" ;;
    tech_design) suffix="tech-design" ;;
    tasks)       suffix="tasks" ;;
    *)           return 1 ;;
  esac
  taskdir="${taskdir%/}"
  printf '%s/%s-%s-%s.md' "$taskdir" "$date" "$slug" "$suffix"
}
