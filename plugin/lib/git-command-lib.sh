#!/usr/bin/env bash
# git-command-lib.sh — recognise git history mutations, push targets and
# shell writes in a Bash command string. Sourced by
# hooks/main-branch-guard.sh.
# Pure functions: results on stdout or as the return status; no logging,
# no exits, no files touched. The command string is only pattern-matched,
# never executed or eval'ed. Best-effort by design: Bash is
# Turing-complete, so wrapped, aliased or scripted forms can evade it.
# Bash 3.2 compatible (macOS /bin/bash): no mapfile, no namerefs.

# gcl_split <command>
# One trimmed subcommand per line. Splits on && || ; | |& & and
# newlines, mirroring hooks/approve-compound.sh; the & inside >&N and &>
# is kept so redirects stay intact.
gcl_split() {
  printf '%s\n' "$1" | awk '
    {
      s = $0
      gsub(/>&/, "\001", s)
      gsub(/&>/, "\002", s)
      gsub(/\|&|&&|\|\||[;|&]/, "\n", s)
      gsub("\001", ">\\&", s)
      gsub("\002", "\\&>", s)
      n = split(s, parts, "\n")
      for (i = 1; i <= n; i++) {
        p = parts[i]
        sub(/^[ \t]+/, "", p)
        sub(/[ \t]+$/, "", p)
        if (p != "") print p
      }
    }'
}

# _gcl_words <subcommand>
# Shell-style words, one per line, quotes removed. Unquoted redirect
# operators are emitted as their own words: > >> &> &>> >& <. A numeric
# fd prefix (the 2 in 2>) is dropped.
_gcl_words() {
  printf '%s\n' "$1" | awk -v SQ="'" '
    function flush() { if (inword) print word; word = ""; inword = 0 }
    {
      if (NR > 1) { if (q == "") flush(); else word = word "\n" }
      line = $0; n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (q == SQ) { if (c == SQ) q = ""; else word = word c; continue }
        if (q == "\"") {
          if (c == "\\" && i < n) {
            nc = substr(line, i + 1, 1)
            if (nc == "\"" || nc == "\\" || nc == "$" || nc == "`") { word = word nc; i++; continue }
          }
          if (c == "\"") q = ""; else word = word c
          continue
        }
        if (c == "\\" && i < n) { word = word substr(line, i + 1, 1); i++; inword = 1; continue }
        if (c == SQ || c == "\"") { q = c; inword = 1; continue }
        if (c == " " || c == "\t") { flush(); continue }
        if (c == "<") {
          flush()
          while (substr(line, i + 1, 1) == "<") i++
          print "<"
          continue
        }
        if (c == ">" || (c == "&" && substr(line, i + 1, 1) == ">")) {
          if (inword && word ~ /^[0-9]+$/) { word = ""; inword = 0 }
          flush()
          op = ""
          if (c == "&") { op = "&"; i++ }
          op = op ">"
          if (substr(line, i + 1, 1) == ">") { op = op ">"; i++ }
          if (substr(line, i + 1, 1) == "|") i++
          if (op == ">" && substr(line, i + 1, 1) == "&") { op = ">&"; i++ }
          print op
          continue
        }
        word = word c; inword = 1
      }
    }
    END { flush() }'
}

# _gcl_load <subcommand> — fills the CALLER's `local -a W` with the words
# (bash dynamic scoping).
_gcl_load() {
  W=()
  local x
  while IFS= read -r x; do W+=("$x"); done < <(_gcl_words "$1")
}

# _gcl_is_op <word> — true for a redirect operator word.
_gcl_is_op() {
  case "$1" in '>'|'>>'|'&>'|'&>>'|'>&'|'<') return 0 ;; esac
  return 1
}

# _gcl_cmd_start — sets the caller's CI to the index of the command word
# in W, skipping VAR=value assignments and transparent wrappers.
_gcl_cmd_start() {
  local i=0 n=${#W[@]}
  while [ "$i" -lt "$n" ]; do
    case "${W[$i]}" in
      [A-Za-z_]*=*|sudo|command|exec|env|nohup|time) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  CI=$i
  [ "$i" -lt "$n" ]
}

# _gcl_git_locate — when W is a git command, sets the caller's GI to the
# index of the git subcommand (after global options) and returns 0.
_gcl_git_locate() {
  local CI n=${#W[@]} i
  _gcl_cmd_start || return 1
  case "${W[$CI]}" in git|*/git) ;; *) return 1 ;; esac
  i=$((CI + 1))
  while [ "$i" -lt "$n" ]; do
    case "${W[$i]}" in
      -C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1
  GI=$i
}

# gcl_is_git_mutation <subcommand>
# True for commit, merge, rebase, cherry-pick, am, revert (except their
# --abort/--quit recovery forms) and for git reset with an explicit mode
# flag. Bare `git reset` (unstage) is not a mutation.
gcl_is_git_mutation() {
  local -a W
  local GI i
  _gcl_load "$1"
  _gcl_git_locate || return 1
  case "${W[$GI]}" in
    commit|merge|rebase|cherry-pick|am|revert)
      for ((i = GI + 1; i < ${#W[@]}; i++)); do
        case "${W[$i]}" in --abort|--quit) return 1 ;; esac
      done
      return 0 ;;
    reset)
      for ((i = GI + 1; i < ${#W[@]}; i++)); do
        case "${W[$i]}" in
          --hard|--soft|--mixed|--merge|--keep) return 0 ;;
          --) break ;;
        esac
      done
      return 1 ;;
  esac
  return 1
}

# gcl_walk <command> <current-branch>
# One line per subcommand: "<branch><TAB><subcommand>", where <branch>
# is the branch checked out when that subcommand runs (empty = detached).
# Assumes && chaining. Branch changers: switch <b> / -c <b>, switch
# --detach, checkout -b/-B/--orphan <b>, checkout --detach; a plain
# `checkout <x>` is ambiguous (branch or path) and leaves the branch
# unchanged. `git worktree add` changes nothing by itself; a later
# `cd <that path>` moves onto the worktree's branch.
gcl_walk() {
  local cur="$2" sub i a n wt_map="" path b commitish
  local -a W
  local GI CI
  while IFS= read -r sub; do
    printf '%s\t%s\n' "$cur" "$sub"
    _gcl_load "$sub"
    n=${#W[@]}
    if _gcl_git_locate; then
      case "${W[$GI]}" in
        switch)
          for ((i = GI + 1; i < n; i++)); do
            a="${W[$i]}"
            case "$a" in
              -c|-C|--create|--force-create|--orphan)
                [ $((i + 1)) -lt "$n" ] && cur="${W[$((i + 1))]}"
                break ;;
              -d|--detach) cur=""; break ;;
              -) break ;;
              -*) ;;
              *) cur="$a"; break ;;
            esac
          done ;;
        checkout)
          for ((i = GI + 1; i < n; i++)); do
            case "${W[$i]}" in
              -b|-B|--orphan)
                [ $((i + 1)) -lt "$n" ] && cur="${W[$((i + 1))]}"
                break ;;
              --detach) cur=""; break ;;
              --) break ;;
            esac
          done ;;
        worktree)
          if [ "${W[$((GI + 1))]:-}" = add ]; then
            path="" b="" commitish=""
            for ((i = GI + 2; i < n; i++)); do
              a="${W[$i]}"
              case "$a" in
                -b|-B) b="${W[$((i + 1))]:-}"; i=$((i + 1)) ;;
                --reason) i=$((i + 1)) ;;
                -d|--detach) b="-" ;;
                -*) ;;
                *) if [ -z "$path" ]; then path="$a"; elif [ -z "$commitish" ]; then commitish="$a"; fi ;;
              esac
            done
            if [ -n "$path" ]; then
              [ -z "$b" ] && b="$commitish"
              [ -z "$b" ] && b="${path%/}" && b="${b##*/}"
              [ "$b" = "-" ] && b=""
              wt_map="$wt_map${path%/}	$b
"
            fi
          fi ;;
      esac
    elif _gcl_cmd_start && [ "${W[$CI]}" = cd ] && [ $((CI + 1)) -lt "$n" ]; then
      path="${W[$((CI + 1))]%/}"
      while IFS='	' read -r a b; do
        [ -n "$a" ] && [ "$a" = "$path" ] && cur="$b"
      done <<EOF
$wt_map
EOF
    fi
  done < <(gcl_split "$1")
}

# gcl_push_targets <subcommand> <current-branch>
# For a `git push`, the destination branches, one per line. --all and
# --mirror print themselves as sentinels. No refspec = current branch.
# Prints nothing for a non-push subcommand.
gcl_push_targets() {
  local -a W
  local GI i a remote_seen=0 del=0 any=0 cur="$2" r dst
  local -a refs=()
  _gcl_load "$1"
  _gcl_git_locate || return 0
  [ "${W[$GI]}" = push ] || return 0
  for ((i = GI + 1; i < ${#W[@]}; i++)); do
    a="${W[$i]}"
    case "$a" in
      --all|--branches) printf '%s\n' --all; any=1 ;;
      --mirror) printf '%s\n' --mirror; any=1 ;;
      --tags) any=1 ;;
      -d|--delete) del=1 ;;
      -o|--push-option|--repo|--receive-pack|--exec) i=$((i + 1)) ;;
      -*) ;;
      *) if [ "$remote_seen" = 0 ]; then remote_seen=1; else refs+=("$a"); fi ;;
    esac
  done
  if [ "${#refs[@]}" -eq 0 ]; then
    [ "$any" = 1 ] || [ "$del" = 1 ] || [ -z "$cur" ] || printf '%s\n' "$cur"
    return 0
  fi
  for ((i = 0; i < ${#refs[@]}; i++)); do
    r="${refs[$i]#+}"
    case "$r" in
      *:*) dst="${r#*:}"; [ -z "$dst" ] && dst="${r%%:*}" ;;
      *) dst="$r" ;;
    esac
    [ "$dst" = HEAD ] && dst="$cur"
    dst="${dst#refs/heads/}"
    [ -n "$dst" ] && printf '%s\n' "$dst"
  done
  return 0
}

# _gcl_emit_target <path> — print a write target unless it is a device.
_gcl_emit_target() {
  case "$1" in ''|/dev/*) return 0 ;; esac
  printf '%s\n' "$1"
}

# _gcl_segment_writes <subcommand> — write targets of one subcommand.
_gcl_segment_writes() {
  local -a W
  local CI n i a cmd inplace=0 script_given=0 script_taken=0
  _gcl_load "$1"
  n=${#W[@]}
  for ((i = 0; i < n; i++)); do
    case "${W[$i]}" in
      '>'|'>>'|'&>'|'&>>')
        [ $((i + 1)) -lt "$n" ] && _gcl_emit_target "${W[$((i + 1))]}"
        i=$((i + 1)) ;;
      '>&')
        if [ $((i + 1)) -lt "$n" ]; then
          case "${W[$((i + 1))]}" in
            -|*[!0-9]*) [ "${W[$((i + 1))]}" = - ] || _gcl_emit_target "${W[$((i + 1))]}" ;;
          esac
        fi
        i=$((i + 1)) ;;
    esac
  done
  _gcl_cmd_start || return 0
  cmd="${W[$CI]##*/}"
  case "$cmd" in
    tee)
      for ((i = CI + 1; i < n; i++)); do
        a="${W[$i]}"
        if _gcl_is_op "$a"; then i=$((i + 1)); continue; fi
        case "$a" in -*) ;; *) _gcl_emit_target "$a" ;; esac
      done ;;
    sed|gsed)
      for ((i = CI + 1; i < n; i++)); do
        case "${W[$i]}" in
          --in-place*|-i*) inplace=1 ;;
          -e|-f|--expression|--file|-e*|-f*|--expression=*|--file=*) script_given=1 ;;
          --*) ;;
          -[A-Za-z]*i*) inplace=1 ;;
        esac
      done
      [ "$inplace" = 1 ] || return 0
      for ((i = CI + 1; i < n; i++)); do
        a="${W[$i]}"
        if _gcl_is_op "$a"; then i=$((i + 1)); continue; fi
        case "$a" in
          -i)
            case "${W[$((i + 1))]-x}" in
              ''|.*) i=$((i + 1)) ;;
            esac ;;
          -e|-f|--expression|--file) i=$((i + 1)) ;;
          -*) ;;
          *)
            if [ "$script_given" = 0 ] && [ "$script_taken" = 0 ]; then
              script_taken=1
            else
              _gcl_emit_target "$a"
            fi ;;
        esac
      done ;;
  esac
}

# gcl_shell_write_paths <command>
# Files the command writes through > >> &> redirects, tee, or sed -i,
# one per line. Read-only commands print nothing.
gcl_shell_write_paths() {
  local seg
  while IFS= read -r seg; do
    _gcl_segment_writes "$seg"
  done < <(gcl_split "$1")
}

# gcl_is_unparseable_candidate <command>
# True when the command contains a construct this library cannot
# analyse ($( ), backticks, heredoc, process substitution, eval,
# sh/bash -c) AND a literal git mutation token — or, for the
# eval / sh -c wrappers that hide a whole command in a string, a literal
# write token. Such a command is treated as a mutation.
gcl_is_unparseable_candidate() {
  local c="$1" opaque=0 wrapper=0
  case "$c" in *'$('*|*'`'*|*'<<'*|*'<('*) opaque=1 ;; esac
  if printf '%s\n' "$c" | grep -Eq '(^|[[:space:];&|(/])(eval|(ba|z|da|k)?sh[[:space:]]+-[a-z]*c)([[:space:]]|$)'; then
    opaque=1
    wrapper=1
  fi
  [ "$opaque" = 1 ] || return 1
  if printf '%s\n' "$c" | grep -Eq '(^|[^[:alnum:]_-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+(commit|push|merge|rebase|cherry-pick|am|revert)([^[:alnum:]_-]|$)'; then
    return 0
  fi
  [ "$wrapper" = 1 ] || return 1
  printf '%s\n' "$c" | grep -Eq '>|(^|[[:space:]])tee[[:space:]]|sed[[:space:]].*-i'
}
