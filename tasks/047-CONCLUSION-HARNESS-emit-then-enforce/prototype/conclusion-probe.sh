#!/usr/bin/env bash
# conclusion-probe.sh — 047 Stop hook (MEASURE-ONLY).
#
# Measures the emit-a-conclusion mechanism without enforcing anything.
# At turn end (Stop), reads the assistant's final message + the turn's
# transcript, and logs NDJSON:
#   1. GENERIC (Story 1): every `<Rule>-check:` conclusion artifact that
#      fired this turn + the context fill — the emit-rate signal for any
#      rule (Objection-check and future rules), not just Data-access.
#   2. DATA-ACCESS (original): per governed Bash command, whether a
#      Data-access tag appeared and whether the command was consistent
#      with it — the consistency signal for the one action-triggered rule.
# It NEVER blocks — the hook exits 0 silently. Purpose: gather the
# measurement that gates umbrella rollout (the decision gate, task 5.0a)
# and the un-primed/long-context evidence (Stories 2, 6).
#
# Sourceable helpers are unit-tested with synthetic JSON (no model calls).
# Bash + jq only. Fails open (exit 0) on any error.

STATE_DIR_DEFAULT=".claude/embo_state"
PROBE_LOG="conclusion-probe.log"
TAG_RE='^[[:space:]]*Data-access:[[:space:]]*(jq|yq|interpreter|n/a)\b'

# --- probe_state_dir <cwd> -> log dir ---
probe_state_dir() {
  printf '%s' "${CONCLUSION_PROBE_DIR:-${1:-$PWD}/$STATE_DIR_DEFAULT}"
}

# --- extract_conclusions <assistant-message-text> -> one tag per line ---
# GENERIC emit-rate probe: find every `<Word>-check:` conclusion artifact
# the message emitted (Objection-check, Data-access uses a different
# suffix; this matches the `-check:` family). Prints the artifact NAME
# (lowercased, without `-check`) once per occurrence, so the caller can
# count which rules' artifacts fired this turn. Empty if none.
# This is the primary Story-1 metric: did ANY conclusion fire, and which.
extract_conclusions() {
  { printf '%s' "$1" \
    | grep -Eio '[A-Za-z][A-Za-z-]*-check:' \
    || true; } \
    | sed -E 's/-check:.*//' \
    | tr '[:upper:]' '[:lower:]'
}

# --- has_conclusion <message> <rule-name> -> yes|no ---
# Did the message emit `<rule-name>-check:` (case-insensitive)?
has_conclusion() {
  local msg="$1" rule="$2"
  printf '%s' "$msg" | grep -Eiq "(^|[^A-Za-z])${rule}-check:" \
    && echo "yes" || echo "no"
}

# --- extract_tag <assistant-message-text> -> jq|yq|interpreter|n/a| (empty) ---
# The LAST Data-access tag in the message (the one nearest the action).
extract_tag() {
  { printf '%s' "$1" \
    | grep -Eio 'Data-access:[[:space:]]*(jq|yq|interpreter|n/a)' \
    || true; } \
    | tail -1 \
    | sed -E 's/.*Data-access:[[:space:]]*//' \
    | tr '[:upper:]' '[:lower:]'
}

# --- is_data_access_cmd <normalized-command> -> yes|no ---
# Does this Bash command read/parse a structured-data file? Deterministic
# surface heuristic — used ONLY to decide whether the rule GOVERNS this
# command (i.e. whether a tag was expected), NOT to judge intent.
is_data_access_cmd() {
  local cmd="$1"
  printf '%s' "$cmd" | grep -Eq '\.(json|ya?ml|toml)\b' || { echo "no"; return; }
  echo "yes"
}

# --- cmd_kind <command> -> jq|yq|interpreter|other ---
# Which tool the command actually uses to touch the data.
cmd_kind() {
  local head; head="$(printf '%s' "$1" | awk '{print $1}')"
  case "$head" in
    jq) echo "jq" ;;
    yq) echo "yq" ;;
    python|python3|node|ruby|perl) echo "interpreter" ;;
    *) echo "other" ;;
  esac
}

# --- consistency <tag> <cmd_kind> -> consistent|mismatch|na ---
# tag jq  -> command should be jq OR yq (both are the sanctioned path)
# tag yq  -> yq (or jq)
# tag interpreter -> an interpreter
# tag n/a -> not governed; na
consistency() {
  local tag="$1" kind="$2"
  case "$tag" in
    jq|yq)
      case "$kind" in jq|yq) echo "consistent" ;; *) echo "mismatch" ;; esac ;;
    interpreter)
      case "$kind" in interpreter) echo "consistent" ;; *) echo "mismatch" ;; esac ;;
    n/a) echo "na" ;;
    *) echo "na" ;;
  esac
}

# --- probe_record <dir> <fields-json> ---
probe_record() {
  local dir="$1" rec="$2"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$rec" >> "$dir/$PROBE_LOG" 2>/dev/null || true
}

# --- transcript_bash_cmds <transcript_path> -> one command per line ---
# Best-effort: pull tool_use blocks for the Bash tool from the JSONL
# transcript. Format is not officially documented, so we try the common
# shapes and fail open (empty) if none match.
transcript_bash_cmds() {
  local tp="$1"
  [ -f "$tp" ] || return 0
  jq -r '
    (.message.content // .content // empty)
    | if type=="array" then .[] else . end
    | select(type=="object")
    | select((.type=="tool_use") and ((.name // "")=="Bash"))
    | (.input.command // empty)
  ' "$tp" 2>/dev/null || true
}

# --- Main (Stop hook) — only when executed directly ---
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -uo pipefail
  trap 'exit 0' ERR

  INPUT="$(cat)"
  MSG="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
  TP="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  [ -n "$CWD" ] || CWD="$PWD"
  DIR="$(probe_state_dir "$CWD")"

  TAG="$(extract_tag "$MSG")"
  FILL="$( [ -f "$TP" ] && wc -c < "$TP" 2>/dev/null | tr -d ' ' || echo 0 )"
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '')"

  # 1. GENERIC emit-rate: log every conclusion artifact that fired this
  #    turn, with the context fill (the primary Story-1 signal).
  CONCLUSIONS="$(extract_conclusions "$MSG")"
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    REC="$(jq -nc --arg ts "$TS" --arg rule "$rule" --argjson fill "${FILL:-0}" \
      '{ts:$ts, kind:"conclusion", rule:$rule, transcript_bytes:$fill}')"
    probe_record "$DIR" "$REC"
  done <<EOF
$CONCLUSIONS
EOF

  # 2. DATA-ACCESS consistency: for each governed Bash command this turn,
  #    log a metric row.
  GOVERNED=0
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    [ "$(is_data_access_cmd "$cmd")" = "yes" ] || continue
    GOVERNED=$((GOVERNED + 1))
    KIND="$(cmd_kind "$cmd")"
    CONS="$( [ -n "$TAG" ] && consistency "$TAG" "$KIND" || echo "no-tag" )"
    REC="$(jq -nc --arg ts "$TS" --arg tag "${TAG:-}" --arg kind "$KIND" \
      --arg cons "$CONS" --argjson fill "${FILL:-0}" \
      '{ts:$ts, rule:"DATA-ACCESS", tag:$tag, cmd_kind:$kind, consistency:$cons, transcript_bytes:$fill}')"
    probe_record "$DIR" "$REC"
  done <<EOF
$(transcript_bash_cmds "$TP")
EOF

  exit 0
fi
