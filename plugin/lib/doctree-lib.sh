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

# --- Resume and run-state (D10, D11) ------------------------------------

# doctree_resume_phase <taskdir> <run-date> <slug>
# Resumability reads the documents first (D10): prints the phase key
# (prd | tech-design | tasks) of the FIRST phase whose document is missing
# on disk, so a resumed run restarts there. Prints nothing (rc 0) when all
# three documents exist — the run is complete. The phase order is fixed.
doctree_resume_phase() {
  local taskdir="$1" date="$2" slug="$3" phase p
  for phase in prd tech_design tasks; do
    p="$(doctree_phase_doc_path "$taskdir" "$date" "$slug" "$phase")"
    if [ ! -f "$p" ]; then
      case "$phase" in
        tech_design) printf 'tech-design' ;;
        *)           printf '%s' "$phase" ;;
      esac
      return 0
    fi
  done
  return 0
}

# doctree_runstate_round <run-state-file>
# The run-state artifact (D11) carries what the documents do not: the
# round number and open findings. Prints the round number from the
# artifact, or 0 when the file or the field is absent. Requires yq.
doctree_runstate_round() {
  local f="$1"
  [ -f "$f" ] || { printf '0'; return 0; }
  command -v yq >/dev/null 2>&1 || { printf '0'; return 2; }
  local r
  r="$(yq -r '.round // 0' "$f" 2>/dev/null)"
  case "$r" in ''|null|*[!0-9]*) r=0 ;; esac
  printf '%s' "$r"
}

# doctree_runstate_open_findings <run-state-file>
# Prints the count of open findings recorded in the run-state artifact, or
# 0 when the file or the field is absent. Requires yq.
doctree_runstate_open_findings() {
  local f="$1"
  [ -f "$f" ] || { printf '0'; return 0; }
  command -v yq >/dev/null 2>&1 || { printf '0'; return 2; }
  local n
  n="$(yq -r '[.findings[]? | select(.status=="open")] | length' "$f" 2>/dev/null)"
  case "$n" in ''|null|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# --- Findings and the six deterministic gates (D13) ---------------------
# These gates need no model judgement: each is a pure check, shared by both
# orchestration paths so a gate is defined once. A gate prints the offending
# items (one per line) and returns 1 when it fails, prints nothing and
# returns 0 when it passes. The gates that compare documents operate on
# ID/citation lists the caller has already extracted, so the gate logic
# stays pure and testable and the (format-specific) extraction lives in the
# caller.

# doctree_finding_is_significant <severity>
# A finding triggers a replay only when significant: severity in
# {high, infeasible}. medium/low are recorded but never replay. Returns 0
# when significant, 1 otherwise.
doctree_finding_is_significant() {
  case "$1" in
    high|infeasible) return 0 ;;
    *)               return 1 ;;
  esac
}

# doctree_gate_missing <required-list> <present-list>
# The shared set-subset check behind gates 1 and 2: every id in the
# newline-separated <required-list> must appear in <present-list>. Prints
# each required id that is absent; returns 1 if any is missing, else 0.
doctree_gate_missing() {
  local required="$1" present="$2" id missing=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    case "
$present
" in
      *"
$id
"*) ;;
      *) printf '%s\n' "$id"; missing=1 ;;
    esac
  done <<EOF
$required
EOF
  return "$missing"
}

# doctree_gate_fr_has_criterion <fr-ids> <frs-with-a-criterion>
# Gate 1: every FR in the PRD maps to at least one acceptance criterion.
doctree_gate_fr_has_criterion() {
  doctree_gate_missing "$1" "$2"
}

# doctree_gate_fr_in_verification_table <fr-ids> <frs-in-table>
# Gate 2: every FR appears in the tech-design's verification table.
doctree_gate_fr_in_verification_table() {
  doctree_gate_missing "$1" "$2"
}

# doctree_gate_citations_resolve <doc> <repo-root>
# Gate 3: every `path:line` citation in <doc> resolves to a real file with
# at least that many lines. Prints each unresolved citation; returns 1 if
# any fails. Citations look like `path/to/file.ext:123`.
doctree_gate_citations_resolve() {
  local doc="$1" root="${2:-.}" cite path line fail=0
  [ -f "$doc" ] || { printf 'doc-not-found:%s\n' "$doc"; return 1; }
  while IFS= read -r cite; do
    [ -z "$cite" ] && continue
    path="${cite%:*}"
    line="${cite##*:}"
    case "$line" in ''|*[!0-9]*) continue ;; esac
    if [ ! -f "$root/$path" ]; then
      printf '%s\n' "$cite"; fail=1; continue
    fi
    local n
    n="$(grep -c '' "$root/$path" 2>/dev/null || echo 0)"
    [ "$line" -gt "$n" ] && { printf '%s\n' "$cite"; fail=1; }
  done <<EOF
$(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' "$doc" 2>/dev/null | sort -u)
EOF
  return "$fail"
}

# doctree_gate_amend_grounded <amend-json> <target-doc>
# Gate 4: an AMEND record must be well-formed (doctree_validate_amend) AND
# its `section` must match a real heading or requirement ID in the target
# document. Prints the reason on failure; returns 1 if it fails, 2 on a
# usage/parse error, 0 if it passes. Requires jq.
doctree_gate_amend_grounded() {
  local rec="$1" target_doc="$2"
  command -v jq >/dev/null 2>&1 || return 2
  if ! doctree_validate_amend "$rec"; then
    printf 'malformed-or-ungrounded\n'; return 1
  fi
  [ -f "$target_doc" ] || { printf 'target-doc-not-found:%s\n' "$target_doc"; return 1; }
  local section
  section="$(printf '%s' "$rec" | jq -r '.section' 2>/dev/null)"
  # Match the section against a markdown heading or a requirement ID (e.g.
  # "FR-3") anywhere in the target document.
  if grep -qF "$section" "$target_doc" 2>/dev/null; then
    return 0
  fi
  printf 'section-not-in-target:%s\n' "$section"
  return 1
}

# doctree_gate_no_open_infeasible <findings-json>
# Gate 5: no open finding of severity 'infeasible' that references a PRD
# requirement (success metric 4). Input is a JSON array of findings, each
# {severity, status, target}. Prints the offending targets; returns 1 if
# any exist. Requires jq.
doctree_gate_no_open_infeasible() {
  local findings="$1"
  command -v jq >/dev/null 2>&1 || return 2
  local bad
  bad="$(printf '%s' "$findings" | jq -r '
    .[] | select(.severity=="infeasible" and .status=="open" and .target=="prd")
    | (.section // "prd")' 2>/dev/null)"
  if [ -n "$bad" ]; then printf '%s\n' "$bad"; return 1; fi
  return 0
}

# doctree_gate_decisions_taken <decisions-count> <had-skip-steps>
# Gate 6: a phase given skip_steps must return decisions_taken > 0.
# <had-skip-steps> is "yes" or "no". Returns 1 when the gate fails.
doctree_gate_decisions_taken() {
  local count="$1" had="$2"
  [ "$had" = "yes" ] || return 0
  case "$count" in
    ''|*[!0-9]*) printf 'non-numeric-count:%s\n' "$count"; return 1 ;;
  esac
  [ "$count" -gt 0 ] && return 0
  printf 'zero-decisions-with-skip-steps\n'
  return 1
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
