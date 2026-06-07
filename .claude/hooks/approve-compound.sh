#!/usr/bin/env bash
# approve-compound.sh — PreToolUse hook (matcher: Bash).
# Auto-approves a Bash command when every normalized subcommand already
# matches the user's merged permissions.allow and none matches deny.
# Otherwise stays silent (fall through to the normal prompt).
# Stateless. Bash + jq only. Fails open.
# See: tasks/027-COMPOUND-CMD-APPROVAL-HOOK/

# --- is_unsafe <command> -> "bail" | "ok" ---
# "bail" when the command contains a construct the Bash+jq normalizer
# cannot safely analyze (command/process substitution, heredoc).
is_unsafe() {
  local cmd="$1"
  case "$cmd" in
    *'$('*|*'`'*|*'<('*|*'<<'*) echo "bail" ;;
    *) echo "ok" ;;
  esac
}

# --- split_subcommands <command> -> one trimmed subcommand per line ---
# Splits on && || ; | |& & and newlines.
split_subcommands() {
  local cmd="$1"
  printf '%s' "$cmd" \
    | sed -E 's/\|&/\n/g; s/&&/\n/g; s/\|\|/\n/g; s/[;|&]/\n/g' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -v '^$'
}

# --- strip_redirects <command> -> command with I/O redirections removed ---
# Removes redirect operators and their targets so a later split on shell
# separators does not break on the `&` inside `2>&1`. Operates on the
# whole command before splitting.
strip_redirects() {
  printf '%s' "$1" | sed -E \
    -e 's/[[:space:]]*[0-9]*>&[0-9]+//g' \
    -e 's/[[:space:]]*&>[[:space:]]*[^[:space:]|&;]+//g' \
    -e 's/[[:space:]]*[0-9]*>>?[[:space:]]*[^[:space:]|&;]+//g' \
    -e 's/[[:space:]]*<[[:space:]]*[^[:space:]|&;]+//g'
}

# --- normalize_subcommand <subcommand> -> bare cmd+args ---
# Strips trailing I/O redirections, leading env-var assignments, and
# leading process wrappers. Leaves the bare command and its arguments.
normalize_subcommand() {
  local s="$1"
  # Drop redirections and everything after the first redirect operator.
  s="$(strip_redirects "$s")"
  s="$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  # Strip leading env-var assignments (WORD=val ...).
  while printf '%s' "$s" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*='; do
    s="$(printf '%s' "$s" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+//')"
  done
  # Strip a single leading process wrapper (and its args for timeout).
  case "$s" in
    timeout\ *) s="$(printf '%s' "$s" | sed -E 's/^timeout[[:space:]]+[^[:space:]]+[[:space:]]+//')" ;;
    time\ *)    s="${s#time }" ;;
    nice\ *)    s="$(printf '%s' "$s" | sed -E 's/^nice([[:space:]]+-[^[:space:]]+)*[[:space:]]+//')" ;;
    nohup\ *)   s="${s#nohup }" ;;
    stdbuf\ *)  s="$(printf '%s' "$s" | sed -E 's/^stdbuf([[:space:]]+-[^[:space:]]+)*[[:space:]]+//')" ;;
  esac
  printf '%s' "$s" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# --- matches_rule <subcommand> <rule> -> "yes" | "no" ---
# Supports rule forms: Bash(cmd), Bash(cmd *), Bash(cmd:*).
matches_rule() {
  local sub="$1" rule="$2" inner
  case "$rule" in
    'Bash('*')') inner="${rule#Bash(}"; inner="${inner%)}" ;;
    *) echo "no"; return ;;
  esac
  case "$inner" in
    *':*')
      local pfx="${inner%:*}"
      case "$sub" in
        "$pfx"|"$pfx "*) echo "yes"; return ;;
      esac
      ;;
    *' *')
      local pfx="${inner% *}"
      case "$sub" in
        "$pfx"|"$pfx "*) echo "yes"; return ;;
      esac
      ;;
    *)
      [ "$sub" = "$inner" ] && { echo "yes"; return; }
      ;;
  esac
  echo "no"
}

# --- load_rules <allow|deny> <project_dir> -> rules, one per line ---
# Merges the kind across the 4 settings layers (HOME + project, each
# settings.json and settings.local.json). Missing files are skipped.
load_rules() {
  local kind="$1" proj="$2" f
  local files=(
    "$HOME/.claude/settings.json"
    "$HOME/.claude/settings.local.json"
    "$proj/.claude/settings.json"
    "$proj/.claude/settings.local.json"
  )
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    jq -r --arg k "$kind" '.permissions[$k] // [] | .[]' "$f" 2>/dev/null || true
  done
}

# --- decide <command> <project_dir> -> allow | deny | fallthrough ---
decide() {
  local cmd="$1" proj="$2"
  [ -z "$cmd" ] && { echo "fallthrough"; return; }
  [ "$(is_unsafe "$cmd")" = "bail" ] && { echo "fallthrough"; return; }

  local allow deny subs sub norm matched stripped
  allow="$(load_rules allow "$proj")"
  deny="$(load_rules deny "$proj")"
  stripped="$(strip_redirects "$cmd")"
  subs="$(split_subcommands "$stripped")"

  while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    norm="$(normalize_subcommand "$sub")"
    [ -z "$norm" ] && { echo "fallthrough"; return; }
    # Deny wins.
    while IFS= read -r rule; do
      [ -z "$rule" ] && continue
      [ "$(matches_rule "$norm" "$rule")" = "yes" ] && { echo "deny"; return; }
    done <<< "$deny"
    # Must match an allow rule.
    matched="no"
    while IFS= read -r rule; do
      [ -z "$rule" ] && continue
      [ "$(matches_rule "$norm" "$rule")" = "yes" ] && { matched="yes"; break; }
    done <<< "$allow"
    [ "$matched" = "yes" ] || { echo "fallthrough"; return; }
  done <<< "$subs"

  echo "allow"
}

# --- Main (only when executed directly, not when sourced by tests) ---
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -uo pipefail
  trap 'exit 0' ERR

  INPUT="$(cat)"
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
  [ "$TOOL" = "Bash" ] || exit 0
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
  [ -n "$CMD" ] || exit 0
  PROJ="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
  [ -n "$PROJ" ] || PROJ="$PWD"

  DECISION="$(decide "$CMD" "$PROJ")"
  case "$DECISION" in
    allow)
      jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"}}'
      ;;
    deny)
      jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"a subcommand matches a deny rule"}}'
      ;;
    *)
      : # fall through: no output, normal prompt
      ;;
  esac
  exit 0
fi
