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

# --- strip_redundant_tail <command> -> command with reflexive tail removed ---
# Removes a trailing `; echo "exit=$?"` / `; echo exit=$?` and/or a
# trailing `; cat <file>` when <file> equals the redirect target of a
# `>`/`>>` in the command head. Leaves the command unchanged otherwise.
# The exit code is returned natively; the cat-back re-floods context.
strip_redundant_tail() {
  local cmd="$1" target seg head rest changed=1

  # Capture the first redirect target (`> file` or `>> file`). If none,
  # there is no captured file, so a trailing cat is not a redundant
  # read-back — leave the command alone.
  target="$(printf '%s' "$cmd" | sed -nE 's/.*[^0-9]>>?[[:space:]]*([^[:space:];|&]+).*/\1/p')"

  while [ "$changed" = "1" ]; do
    changed=0
    # Last `;`-separated segment and the head before it.
    case "$cmd" in
      *\;*)
        seg="${cmd##*;}"
        head="${cmd%;*}"
        ;;
      *) break ;;
    esac
    # Trim surrounding whitespace from the candidate segment.
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

    # Strip a reflexive exit-code echo.
    case "$seg" in
      'echo "exit=$?"'|"echo 'exit=\$?'"|'echo exit=$?'|'echo "exit=${?}"'|'echo $?'|'echo "$?"')
        cmd="$(printf '%s' "$head" | sed -E 's/[[:space:]]+$//')"
        changed=1
        continue
        ;;
    esac

    # Strip a cat of the captured redirect target.
    if [ -n "$target" ]; then
      case "$seg" in
        "cat $target")
          cmd="$(printf '%s' "$head" | sed -E 's/[[:space:]]+$//')"
          changed=1
          continue
          ;;
      esac
    fi
  done

  printf '%s' "$cmd"
}

# --- normalize_subcommand <subcommand> -> bare cmd+args ---
# Strips trailing I/O redirections, a leading `env` wrapper (with its
# flags), leading env-var assignments, and leading process wrappers.
# Leaves the bare command and its arguments.
normalize_subcommand() {
  local s="$1"
  # Drop redirections and everything after the first redirect operator.
  s="$(strip_redirects "$s")"
  s="$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  # Strip a leading `env` wrapper and its flags (-i, -u NAME, --, ...);
  # assignments after it are handled by the loop below. Bare `env`
  # normalizes to empty -> caller falls through.
  case "$s" in
    env)
      s="" ;;
    env\ *)
      s="$(printf '%s' "$s" | sed -E 's/^env[[:space:]]+//')"
      while true; do
        case "$s" in
          --)      s=""; break ;;
          --\ *)   s="$(printf '%s' "$s" | sed -E 's/^--[[:space:]]+//')"; break ;;
          -u|-u\ *) s="$(printf '%s' "$s" | sed -E 's/^-u([[:space:]]+[^[:space:]]+)?[[:space:]]*//')" ;;
          -*\ *)   s="$(printf '%s' "$s" | sed -E 's/^-[^[:space:]]+[[:space:]]+//')" ;;
          -*)      s=""; break ;;
          *)       break ;;
        esac
      done
      ;;
  esac
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

# --- 028 capture wrapper integration ---

# The command the rewrite invokes. Defaults to the installed wrapper
# path; overridable in tests. The re-entrancy guard and the allow-rule
# both key off the stable `embo-capture.sh` token in this string.
EMBO_CAPTURE_CMD="${EMBO_CAPTURE_CMD:-~/.claude/hooks/embo-capture.sh}"

# Heads whose output is interactive or streaming: wrapping would buffer
# (hang) or hide live output. Left unwrapped. Extend as needed.
CAPTURE_NOWRAP_HEADS="ssh sftp scp telnet vim vi nano emacs less more man \
top htop watch tail-f ftp mysql psql redis-cli sqlite3 python python3 node \
irb pry bash sh zsh fish docker-attach kubectl-exec npm-run-dev yarn-dev \
sudo"

# has_redirect <command> -> "yes" | "no"  (any >, >>, &>, < redirect)
has_redirect() {
  case "$1" in
    *'>'*|*'<'*) echo "yes" ;;
    *) echo "no" ;;
  esac
}

# is_interactive_head <normalized-subcommand> -> "yes" | "no"
is_interactive_head() {
  local head; head="$(printf '%s' "$1" | awk '{print $1}')"
  # `tail -f` is the streaming case; treat any tail with -f specially.
  case "$1" in
    tail\ *-f*|*' -f '*tail*) echo "yes"; return ;;
  esac
  case " $CAPTURE_NOWRAP_HEADS " in
    *" $head "*) echo "yes"; return ;;
  esac
  echo "no"
}

# should_wrap <command> -> "yes" | "no"
# Wrap an allowed command (simple OR compound: && || ; |) for output
# capture UNLESS:
#  - it is already an embo-capture call (re-entrancy guard, FIRST),
#  - it already redirects (model owns its output target),
#  - it contains an unsafe construct,
#  - it is backgrounded (trailing &): async capture is undefined,
#  - any segment's head is interactive/streaming: wrapping buffers
#    output, which would hang that segment.
should_wrap() {
  local cmd="$1"
  case "$cmd" in
    *embo-capture.sh\ *) echo "no"; return ;;      # re-entrancy guard
  esac
  [ "$(has_redirect "$cmd")" = "yes" ] && { echo "no"; return; }
  [ "$(is_unsafe "$cmd")" = "bail" ] && { echo "no"; return; }
  # backgrounding & in ANY position, and dangling trailing operators
  # (checked on the raw string — the split below eats & as a
  # separator). Redirects are excluded above, so the only legitimate
  # & forms left are && and |&; remove those, any survivor & is a
  # backgrounding job.
  local t; t="$(printf '%s' "$cmd" | sed -E 's/[[:space:]]+$//')"
  case "$t" in
    *'&&'|*'||'|*'|') echo "no"; return ;;   # dangling operator
  esac
  case "$(printf '%s' "$t" | sed -E 's/&&|\|&//g')" in
    *'&'*) echo "no"; return ;;              # backgrounding &
  esac
  local seg
  while IFS= read -r seg; do
    [ -z "$seg" ] && continue
    [ "$(is_interactive_head "$(normalize_subcommand "$seg")")" = "yes" ] \
      && { echo "no"; return; }
  done <<< "$(split_subcommands "$cmd")"
  echo "yes"
}

# wrap_command <command> -> <wrapper> --b64 <base64-of-command>
wrap_command() {
  printf '%s --b64 %s' "$EMBO_CAPTURE_CMD" \
    "$(printf '%s' "$1" | base64 | tr -d '\n')"
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

  # Re-entrancy guard FIRST: never touch an already-wrapped command.
  case "$CMD" in
    *embo-capture.sh\ *) exit 0 ;;
  esac

  STRIPPED="$(strip_redundant_tail "$CMD")"
  DECISION="$(decide "$STRIPPED" "$PROJ")"
  case "$DECISION" in
    allow)
      # Order: tail already stripped; now consider wrapping the survivor
      # for output capture. Wrap only an eligible (non-redirect, simple,
      # non-interactive) command. The emitted command is the final one.
      FINAL="$STRIPPED"
      if [ "$(should_wrap "$STRIPPED")" = "yes" ]; then
        FINAL="$(wrap_command "$STRIPPED")"
      fi
      if [ "$FINAL" != "$CMD" ]; then
        jq -n --arg c "$FINAL" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:{command:$c}}}'
      else
        jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow"}}'
      fi
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
