#!/usr/bin/env bash
# corrections-lib.sh — sourceable helpers for embo correction capture
# (/embo:enable-corrections, /embo:disable-corrections, /embo:improve).
#
# Why this exists (task 041): the enable/disable/curation logic has real
# branching (settings-merge, a conflict guard, an idempotent enable, a
# crash-safe disable, curation bookkeeping). Embedding it as prose inside
# command markdown would make it untestable. This library holds that
# logic as sourceable functions so it is unit-tested the same way as
# fix-hooks.sh — a test file sources it and asserts against synthetic
# temp files.
#
# All file paths are parameters or overridable env vars, so tests target
# temp files and never the user's real ~/.claude or ~/.claude-mem config.
#
# Requires: jq. No other external dependency.

set -uo pipefail

# The value enable-corrections writes for CLAUDE_MEM_MODES_DIR. A literal
# tilde is intentional: it is what a human reads in settings.json and what
# the conflict guard compares against; expansion happens in the worker.
CORRECTIONS_MODES_DIR_VALUE="${CORRECTIONS_MODES_DIR_VALUE:-$HOME/.claude-mem/modes}"

# corrections_merge_modes_dir <cc-settings-file>
#   Merge CLAUDE_MEM_MODES_DIR into the settings file's top-level .env
#   block, creating .env if absent, preserving every existing key. Atomic
#   (temp file + mv).
corrections_merge_modes_dir() {
  local file="$1" tmp
  tmp="$(mktemp)"
  jq --arg v "$CORRECTIONS_MODES_DIR_VALUE" \
    '.env = ((.env // {}) + {CLAUDE_MEM_MODES_DIR: $v})' \
    "$file" > "$tmp" && mv "$tmp" "$file"
}

# corrections_modes_dir_conflict <cc-settings-file>
#   Echo one of: "absent" (no key / no file), "same" (already our value),
#   "conflict" (set to a different value). Drives the enable-record's
#   claude_mem_modes_dir_written flag and the enable-time conflict guard.
corrections_modes_dir_conflict() {
  local file="$1" cur
  [ -f "$file" ] || { echo "absent"; return; }
  cur="$(jq -r '.env.CLAUDE_MEM_MODES_DIR // empty' "$file" 2>/dev/null)"
  if [ -z "$cur" ]; then
    echo "absent"
  elif [ "$cur" = "$CORRECTIONS_MODES_DIR_VALUE" ]; then
    echo "same"
  else
    echo "conflict"
  fi
}

# corrections_write_enable_record <record-file> <prior-mode> <written-bool>
#   Write the enable-record JSON atomically. Fields per tech-design Data
#   Models. The claude-mem version is read from CORRECTIONS_CM_VERSION
#   (the enable command sets it to the detected version; defaults to
#   "unknown" so tests need not depend on a live install).
corrections_write_enable_record() {
  local file="$1" prior="$2" written="$3" tmp
  tmp="$(mktemp)"
  jq -n \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg prior "$prior" \
    --argjson written "$written" \
    --arg val "$CORRECTIONS_MODES_DIR_VALUE" \
    --arg ver "${CORRECTIONS_CM_VERSION:-unknown}" \
    '{
      enabled_at: $at,
      prior_claude_mem_mode: $prior,
      claude_mem_modes_dir_written: $written,
      claude_mem_modes_dir_value: $val,
      claude_mem_version_at_enable: $ver
    }' > "$tmp" && mv "$tmp" "$file"
}

# corrections_should_remove_modes_dir <record-file> <cc-settings-file>
#   Return 0 (remove) ONLY when the record has
#   claude_mem_modes_dir_written=true AND the settings file's current
#   value equals the recorded claude_mem_modes_dir_value; else return 1.
corrections_should_remove_modes_dir() {
  local record="$1" settings="$2" written recorded current
  [ -f "$record" ] || return 1
  written="$(jq -r '.claude_mem_modes_dir_written' "$record" 2>/dev/null)"
  [ "$written" = "true" ] || return 1
  recorded="$(jq -r '.claude_mem_modes_dir_value' "$record" 2>/dev/null)"
  current="$(jq -r '.env.CLAUDE_MEM_MODES_DIR // empty' "$settings" 2>/dev/null)"
  [ "$current" = "$recorded" ]
}

# corrections_restore_mode <cm-settings-file> <prior-mode>
#   Set CLAUDE_MEM_MODE back to <prior-mode> atomically. Idempotent:
#   running it twice yields the same result. Used by disable Step 2.
corrections_restore_mode() {
  local file="$1" prior="$2" tmp
  tmp="$(mktemp)"
  jq --arg m "$prior" '.CLAUDE_MEM_MODE = $m' "$file" > "$tmp" \
    && mv "$tmp" "$file"
}

# corrections_remove_modes_dir <cc-settings-file>
#   Delete the CLAUDE_MEM_MODES_DIR key from .env atomically. Idempotent:
#   removing an absent key is a no-op success. Used by disable Step 3
#   only when corrections_should_remove_modes_dir returns 0.
corrections_remove_modes_dir() {
  local file="$1" tmp
  tmp="$(mktemp)"
  jq 'if .env then .env |= del(.CLAUDE_MEM_MODES_DIR) else . end' \
    "$file" > "$tmp" && mv "$tmp" "$file"
}

# corrections_curation_read <curation-file>
#   Echo the space-separated curated_ids. An absent or unparseable file
#   echoes nothing (treated as "no state yet"), never errors.
corrections_curation_read() {
  local file="$1"
  [ -f "$file" ] || return 0
  jq -r '(.curated_ids // []) | join(" ")' "$file" 2>/dev/null || true
}

# corrections_curation_write <curation-file> <id>...
#   Merge the given IDs into curated_ids (numeric, sorted, deduped) and
#   write atomically (temp file + mv), so a crash mid-write cannot
#   truncate the file. last_run_at is refreshed each write.
corrections_curation_write() {
  local file="$1"; shift
  local tmp existing ids_json
  tmp="$(mktemp)"
  if [ -f "$file" ] && jq -e . "$file" >/dev/null 2>&1; then
    existing="$(jq -c '.curated_ids // []' "$file")"
  else
    existing='[]'
  fi
  # Coerce each arg to a number, silently dropping any non-numeric one, so
  # a stray bad id can never abort the write and lose the reviewed set.
  ids_json="$(printf '%s\n' "$@" | jq -R '(try tonumber catch empty)' | jq -s '.')"
  jq -n --argjson old "$existing" --argjson new "$ids_json" \
     --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '{
        curated_ids: (($old + $new) | unique),
        last_run_at: $at
      }' > "$tmp" && mv "$tmp" "$file"
}

# The claude-mem relational DB. Overridable so tests target a fixture DB.
CORRECTIONS_DB="${CORRECTIONS_DB:-$HOME/.claude-mem/claude-mem.db}"

# corrections_list <project>
#   Print every correction observation for <project> as a JSON array
#   (id, title, subtitle, narrative, created_at), newest first. Reads the
#   relational source of truth directly — NOT the MCP search tool, whose
#   type= filter is broken for custom types (#3279). Keeping this in the
#   lib lets /embo:improve call it as one bare command, so the approval
#   dialog shows `corrections_list embo`, not a raw SQL pipeline.
corrections_list() {
  local project="$1"
  # Guard against SQL injection / query-breakage: the project name is a
  # directory basename, but a name with an apostrophe (or worse) would
  # break — or subvert — the interpolated query. Accept only the plain
  # identifier characters a project name legitimately uses; reject
  # anything else with rc 2 and no output.
  case "$project" in
    *[!A-Za-z0-9._-]* | "") return 2 ;;
  esac
  sqlite3 -json "$CORRECTIONS_DB" \
    "SELECT id, title, subtitle, narrative, created_at
     FROM observations
     WHERE type='correction' AND project='$project'
     ORDER BY created_at DESC"
}
