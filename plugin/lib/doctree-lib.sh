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
