#!/usr/bin/env bash
# fix-hooks.sh — detect and remove duplicate embo hook registrations.
#
# Why this exists (task 032, FR-5b): embo's hooks can be registered in
# more than one place on a machine — an old manual install in
# ~/.claude/settings.json AND a plugin registration — by DIFFERENT
# command paths. Claude Code dedupes hooks only when command strings are
# byte-identical, so different paths both fire. The behavior of two
# PreToolUse hooks returning different rewrites is undocumented, so the
# duplicate must be removed, not tolerated.
#
# Usage:
#   bash fix-hooks.sh          # detect + report; exit 1 if duplicates
#   bash fix-hooks.sh --fix    # additionally offer to remove stale ones
#
# Exit codes: 0 = clean (no duplicates), 1 = duplicates found
# (report-only), 2 = duplicates removed (with --fix + consent).
#
# Operates on user/project settings files only; never touches managed or
# plugin registrations. Backs up each file before editing.

# Embo hook scripts that get registered as event handlers. embo-capture.sh
# is intentionally absent: it is a subprocess helper, never registered.
EMBO_HOOK_TOKENS="approve-compound.sh behavioral-reminder.sh context-guard.sh"

# Settings files that can carry user-editable hook registrations.
# Overridable for testing via the SETTINGS_FILES env var.
default_settings_files() {
  printf '%s\n' "$HOME/.claude/settings.json" "$PWD/.claude/settings.json"
}

# fix_hooks_detect <settings-file> -> one line per embo registration:
#   "<token>\t<command-string>". No output if file missing or none found.
# Uses `any(.hooks[]; .command? | strings | contains($t))` so a hook entry
# carrying only an `if` field (no command) does not error the filter.
fix_hooks_detect() {
  local file="$1" tok
  [ -f "$file" ] || return 0
  for tok in $EMBO_HOOK_TOKENS; do
    jq -r --arg t "$tok" '
      (.hooks // {}) | to_entries[] | .value[]?
      | .hooks[]? | .command? | strings
      | select(contains($t))
      | "\($t)\t\(.)"
    ' "$file" 2>/dev/null
  done
}

# fix_hooks_count_dups <detect-output> -> number of distinct tokens that
# appear more than once (i.e. handlers registered 2+ times).
fix_hooks_count_dups() {
  printf '%s\n' "$1" \
    | grep -c '.' >/dev/null 2>&1 || { echo 0; return; }
  printf '%s\n' "$1" \
    | awk -F'\t' 'NF{c[$1]++} END{n=0; for (k in c) if (c[k]>1) n++; print n}'
}

# fix_hooks_remove_stale <settings-file> -> remove the tilde-path
# (~/.claude) registration for any duplicated handler, keeping the other.
# Backup-before-edit via temp file + atomic mv. Returns 0 if it edited.
fix_hooks_remove_stale() {
  local file="$1" tmp
  tmp="$(mktemp)"
  # Drop array elements whose any inner hook command contains an embo
  # token AND a tilde ~/.claude path — the stale manual-install entry.
  jq '
    (.hooks // {}) as $h
    | .hooks = (
        $h | to_entries
        | map(.value = (
            .value
            | map(select(
                ([.hooks[]? | .command? | strings
                  | select(test("\\.claude/hooks/(approve-compound|behavioral-reminder|context-guard)\\.sh")
                           and (startswith("bash ~/") or contains(" ~/.claude/")))
                 ] | length) == 0
              ))
          ))
        | from_entries
      )
  ' "$file" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  cp "$file" "$file.bak"
  mv "$tmp" "$file"
}

# fix_hooks_advise_stale_files <claude-home> -> if an old cp-install left
# embo command/agent files under <claude-home>, print the exact removal
# command for the user to run. Advisory only — NEVER removes files
# (deleting directories of user files is riskier than a consented jq
# edit; the safety rules forbid casual rm). Returns 1 if nothing stale.
fix_hooks_advise_stale_files() {
  local home="$1" found="no"
  if [ -d "$home/commands/dev" ]; then
    found="yes"
    echo "fix-hooks: stale manual-install commands at $home/commands/dev"
    echo "  the plugin now provides these as /embo:* — remove the old"
    echo "  copies with:  rm -rf $home/commands/dev"
  fi
  [ "$found" = "yes" ] || return 1
}

# fix_hooks_main [--fix] -> orchestrate detect/report/remove across files.
fix_hooks_main() {
  command -v jq >/dev/null 2>&1 || {
    echo "fix-hooks: jq is required but not found" >&2
    return 3
  }

  local do_fix="no"
  [ "${1:-}" = "--fix" ] && do_fix="yes"

  local files
  if [ -n "${SETTINGS_FILES:-}" ]; then
    files="$SETTINGS_FILES"
  else
    files="$(default_settings_files)"
  fi

  local found_dups="no" edited="no" file out dups
  for file in $files; do
    [ -f "$file" ] || continue
    out="$(fix_hooks_detect "$file")"
    [ -n "$out" ] || continue
    dups="$(fix_hooks_count_dups "$out")"
    if [ "$dups" -gt 0 ]; then
      found_dups="yes"
      echo "fix-hooks: $dups duplicated embo handler(s) in $file:" >&2
      printf '%s\n' "$out" >&2
      if [ "$do_fix" = "yes" ]; then
        printf 'Remove the stale ~/.claude registration(s) in %s? [y/N] ' \
          "$file" >&2
        local reply
        IFS= read -r reply
        case "$reply" in
          y|Y)
            if fix_hooks_remove_stale "$file"; then
              edited="yes"
              echo "fix-hooks: removed stale entry, backup at $file.bak" >&2
            fi
            ;;
          *) echo "fix-hooks: left $file unchanged" >&2 ;;
        esac
      fi
    fi
  done

  # Advisory: flag stale manual-install command files (not registrations).
  # Skipped when SETTINGS_FILES is overridden (test mode) to keep tests
  # hermetic against the real ~/.claude.
  [ -z "${SETTINGS_FILES:-}" ] && fix_hooks_advise_stale_files "$HOME/.claude" >&2

  [ "$edited" = "yes" ] && return 2
  [ "$found_dups" = "yes" ] && return 1
  return 0
}

# Run main only when executed directly, not when sourced by tests.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  fix_hooks_main "$@"
  exit $?
fi
