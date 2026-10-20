#!/usr/bin/env bash
# branch-task-lib.sh — shared branch<->task correspondence rule.
# Sourced by bin/embo-deliver and hooks/branch-task-check.sh.
# Pure functions: no output, no side effects, no exits.

# branch_task_matches <branch> <task-number>
# True when the task number appears in the branch as a whole token,
# bounded by non-digits. "066" matches feat/066-x, 066-thing,
# hotfix/066; not feat/1066-x, 066x, x066.
branch_task_matches() {
  case "$1" in
    *[!0-9]"$2"[!0-9]* | \
    "$2"[!0-9]*        | \
    *[!0-9]"$2"        | \
    "$2")
      return 0 ;;
  esac
  return 1
}

# branch_task_derive_from_paths
# stdin: file paths, one per line. stdout: the 3-digit task number
# owning the most paths; nothing on a tie or no match.
branch_task_derive_from_paths() {
  awk '
    /^tasks\/[0-9][0-9][0-9]-/ { count[substr($0, 7, 3)]++ }
    END {
      max = 0; winner = ""; ties = 0
      for (n in count) {
        if (count[n] > max)       { max = count[n]; winner = n; ties = 1 }
        else if (count[n] == max) { ties++ }
      }
      if (ties == 1 && winner != "") print winner
    }'
}

# branch_task_paths_from_porcelain
# stdin: `git status --porcelain`. stdout: changed paths, one per line.
# Renames ("old -> new") count toward the destination.
branch_task_paths_from_porcelain() {
  awk '
    {
      path = substr($0, 4)
      if (match(path, / -> /)) path = substr(path, RSTART + 4)
      gsub(/^"|"$/, "", path)
      print path
    }'
}
