#!/usr/bin/env bash
# Plain-Bash unit tests for approve-compound.sh (no framework).
# Run: bash .claude/hooks/approve-compound.test.sh
# Exits non-zero if any assertion fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/approve-compound.sh"

PASS=0
FAIL=0

# capture-wrapper helpers (028): the embo-capture form the hook emits.
# Pin the wrapper command so tests are independent of the install path;
# the hook reads EMBO_CAPTURE_CMD (default = installed path).
export EMBO_CAPTURE_CMD="embo-capture.sh"
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
wrap_cmd() { printf '%s --b64 %s' "$EMBO_CAPTURE_CMD" "$(b64 "$1")"; }

assert_eq() {
  # assert_eq <description> <expected> <actual>
  local desc="$1" exp="$2" act="$3"
  if [ "$exp" = "$act" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' \
      "$desc" "$exp" "$act"
  fi
}

# ---- 1.1 unsafe-construct detection ----
# is_unsafe <command>  -> prints "bail" if it contains a construct the
# Bash+jq normalizer cannot analyze, else "ok".

assert_eq "cmd subst \$()"      "bail" "$(is_unsafe 'echo $(whoami)')"
assert_eq "backtick subst"      "bail" "$(is_unsafe 'echo `whoami`')"
assert_eq "process subst <()"   "bail" "$(is_unsafe 'diff <(ls) <(ls)')"
assert_eq "heredoc <<"          "bail" "$(is_unsafe 'cat <<EOF')"
assert_eq "plain redirect ok"   "ok"   "$(is_unsafe 'ls > tmp/x.log 2>&1')"
assert_eq "plain pipe ok"       "ok"   "$(is_unsafe 'ls | grep x')"
assert_eq "plain chain ok"      "ok"   "$(is_unsafe 'ls && pwd')"

# ---- 1.3 split on separators ----
# split_subcommands <command>  -> one subcommand per line, trimmed.

assert_eq "split &&" $'ls\npwd'        "$(split_subcommands 'ls && pwd')"
assert_eq "split |"  $'ls\ngrep x'     "$(split_subcommands 'ls | grep x')"
assert_eq "split ;"  $'ls\necho done'  "$(split_subcommands 'ls ; echo done')"
assert_eq "split ||" $'a\nb'           "$(split_subcommands 'a || b')"
assert_eq "split mixed" $'a\nb\nc'     "$(split_subcommands 'a && b | c')"
assert_eq "split |&" $'a\nb'           "$(split_subcommands 'a |& b')"
assert_eq "split single" 'ls -la'      "$(split_subcommands 'ls -la')"

# ---- 1.5 normalize one subcommand ----
# normalize_subcommand <subcommand>  -> bare cmd+args, redirects/env/
# wrappers stripped.

assert_eq "strip > target"   "ls"        "$(normalize_subcommand 'ls > tmp/x.log')"
assert_eq "strip 2>&1"       "ls"        "$(normalize_subcommand 'ls 2>&1')"
assert_eq "strip &> target"  "ls"        "$(normalize_subcommand 'ls &> out')"
assert_eq "strip >> target"  "ls"        "$(normalize_subcommand 'ls >> out')"
assert_eq "strip < target"   "cat"       "$(normalize_subcommand 'cat < in')"
assert_eq "strip env prefix" "git push"  "$(normalize_subcommand 'FOO=bar git push')"
assert_eq "strip 2 env"      "npm test"  "$(normalize_subcommand 'A=1 B=2 npm test')"
assert_eq "strip timeout"    "npm test"  "$(normalize_subcommand 'timeout 30 npm test')"
assert_eq "strip nice"       "make"      "$(normalize_subcommand 'nice make')"
assert_eq "keep args"        "git log --oneline" \
  "$(normalize_subcommand 'git log --oneline > tmp/x')"

# ---- 2.3 rule-form matching ----
# matches_rule <subcommand> <rule>  -> "yes" | "no"
# rule forms: Bash(cmd), Bash(cmd *), Bash(cmd:*)

assert_eq "exact match"        "yes" "$(matches_rule 'git status' 'Bash(git status)')"
assert_eq "exact no-args only" "no"  "$(matches_rule 'git status -s' 'Bash(git status)')"
assert_eq "prefix space *"     "yes" "$(matches_rule 'git status -s' 'Bash(git status *)')"
assert_eq "prefix space base"  "yes" "$(matches_rule 'git status' 'Bash(git status *)')"
assert_eq "prefix colon *"     "yes" "$(matches_rule 'aws ecr list' 'Bash(aws ecr:*)')"
assert_eq "prefix no match"    "no"  "$(matches_rule 'lsof' 'Bash(ls *)')"
assert_eq "ignore non-Bash"    "no"  "$(matches_rule 'ls' 'Read(./x)')"
assert_eq "prefix * bare"      "yes" "$(matches_rule 'git' 'Bash(git *)')"

# ---- 2.1 merged-layer loading ----
# load_rules <kind> <project_dir>  -> rules of that kind (allow|deny),
# one per line, merged across the 4 settings layers. Uses HOME and the
# given project dir. We point HOME at a temp tree for the test.

_TMPH="$(mktemp -d)"
mkdir -p "$_TMPH/.claude" "$_TMPH/proj/.claude"
printf '{"permissions":{"allow":["Bash(global *)"],"deny":["Bash(rm *)"]}}' \
  > "$_TMPH/.claude/settings.json"
printf '{"permissions":{"allow":["Bash(proj *)"]}}' \
  > "$_TMPH/proj/.claude/settings.json"

assert_eq "merged allow has global" "yes" \
  "$(HOME="$_TMPH" load_rules allow "$_TMPH/proj" | grep -qxF 'Bash(global *)' && echo yes || echo no)"
assert_eq "merged allow has proj" "yes" \
  "$(HOME="$_TMPH" load_rules allow "$_TMPH/proj" | grep -qxF 'Bash(proj *)' && echo yes || echo no)"
assert_eq "merged deny has rm" "yes" \
  "$(HOME="$_TMPH" load_rules deny "$_TMPH/proj" | grep -qxF 'Bash(rm *)' && echo yes || echo no)"
assert_eq "missing layer skipped" "yes" \
  "$(HOME="$_TMPH" load_rules allow "$_TMPH/nonexist" >/dev/null 2>&1 && echo yes || echo no)"
rm -rf "$_TMPH"

# ---- 3.3 decision logic ----
# decide <command> <project_dir>  -> "allow" | "deny" | "fallthrough"
# Set up a temp HOME with known allow/deny.
_TMPH="$(mktemp -d)"
mkdir -p "$_TMPH/.claude"
printf '{"permissions":{"allow":["Bash(ls *)","Bash(pwd)","Bash(git status *)"],"deny":["Bash(rm *)"]}}' \
  > "$_TMPH/.claude/settings.json"

dec() { HOME="$_TMPH" decide "$1" "$_TMPH/noproj"; }

assert_eq "allow redirect"   "allow"       "$(dec 'ls -la > tmp/x.log 2>&1')"
assert_eq "allow compound"   "allow"       "$(dec 'ls && pwd')"
assert_eq "deny wins"        "deny"        "$(dec 'ls && rm -rf x')"
assert_eq "unknown -> fall"  "fallthrough" "$(dec 'curl http://x')"
assert_eq "unsafe -> fall"   "fallthrough" "$(dec 'echo $(whoami)')"
assert_eq "one unknown fall" "fallthrough" "$(dec 'ls && unknowncmd')"
rm -rf "$_TMPH"

# ---- 3.1 / 3.5 main I/O wrapper (invoke the script via stdin) ----
HOOK="$HERE/approve-compound.sh"
run_hook() { printf '%s' "$1" | bash "$HOOK"; }

assert_eq "non-Bash -> no stdout" "" \
  "$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"x"}}')"
assert_eq "empty command -> no stdout" "" \
  "$(run_hook '{"tool_name":"Bash","tool_input":{"command":""}}')"
assert_eq "malformed stdin -> no stdout" "" \
  "$(run_hook 'not json at all')"
assert_eq "unknown cmd -> no stdout (fallthrough)" "" \
  "$(HOME="$(mktemp -d)" run_hook '{"tool_name":"Bash","tool_input":{"command":"weirdcmd123"},"cwd":"/nope"}')"

# allow path emits permissionDecision allow
_TMPH2="$(mktemp -d)"; mkdir -p "$_TMPH2/.claude"
printf '{"permissions":{"allow":["Bash(ls *)"]}}' > "$_TMPH2/.claude/settings.json"
_OUT="$(HOME="$_TMPH2" run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la > tmp/x 2>&1"},"cwd":"/nope"}')"
assert_eq "allow emits allow" "allow" \
  "$(printf '%s' "$_OUT" | jq -r '.hookSpecificOutput.permissionDecision')"
rm -rf "$_TMPH2"

# ---- 3.2 strip redundant capture tail ----
# strip_redundant_tail <command> -> command with a trailing
#   `; echo "exit=$?"` and/or `; cat <same-file>` removed, where
#   <same-file> equals the redirect target of a `>`/`>>` in the head.
# Leaves the command unchanged when the shape does not match.

assert_eq "strip echo exit only" \
  'ls > tmp/x.log 2>&1' \
  "$(strip_redundant_tail 'ls > tmp/x.log 2>&1; echo "exit=$?"')"

assert_eq "strip echo bare exit" \
  'ls > tmp/x.log 2>&1' \
  "$(strip_redundant_tail 'ls > tmp/x.log 2>&1; echo exit=$?')"

assert_eq "strip cat same file" \
  'ls > tmp/x.log 2>&1' \
  "$(strip_redundant_tail 'ls > tmp/x.log 2>&1; cat tmp/x.log')"

assert_eq "strip echo then cat same" \
  'ls > tmp/x.log 2>&1' \
  "$(strip_redundant_tail 'ls > tmp/x.log 2>&1; echo "exit=$?"; cat tmp/x.log')"

assert_eq "strip with >> redirect" \
  'ls >> tmp/x.log' \
  "$(strip_redundant_tail 'ls >> tmp/x.log; cat tmp/x.log')"

assert_eq "strip stdout-only redirect" \
  'kubectl get cm > tmp/v.yaml' \
  "$(strip_redundant_tail 'kubectl get cm > tmp/v.yaml; cat tmp/v.yaml')"

# left alone: cat of a DIFFERENT file
assert_eq "keep cat other file" \
  'ls > tmp/x.log 2>&1; cat tmp/other.log' \
  "$(strip_redundant_tail 'ls > tmp/x.log 2>&1; cat tmp/other.log')"

# left alone: no redirect in head (cat is not a redundant read-back)
assert_eq "keep cat no redirect" \
  'cat tmp/x.log' \
  "$(strip_redundant_tail 'cat tmp/x.log')"

# left alone: plain command, no tail
assert_eq "keep plain command" \
  'ls -la' \
  "$(strip_redundant_tail 'ls -la')"

# left alone: echo that is not the exit-code reflex
assert_eq "keep real echo" \
  'ls > tmp/x.log 2>&1; echo done' \
  "$(strip_redundant_tail 'ls > tmp/x.log 2>&1; echo done')"

# ---- 3.3 / 3.4 rewrite emits updatedInput when head is allowed ----
# When the stripped head is allow-listed, the hook emits
# permissionDecision allow + updatedInput.command = stripped command.
_TMPH3="$(mktemp -d)"; mkdir -p "$_TMPH3/.claude"
printf '{"permissions":{"allow":["Bash(ls *)"]}}' > "$_TMPH3/.claude/settings.json"

_OUT3="$(HOME="$_TMPH3" run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la > tmp/x.log 2>&1; echo \"exit=$?\"; cat tmp/x.log"},"cwd":"/nope"}')"
assert_eq "tail rewrite emits allow" "allow" \
  "$(printf '%s' "$_OUT3" | jq -r '.hookSpecificOutput.permissionDecision')"
# After 028: tail is stripped, but the survivor already contains a
# redirect, so it is NOT wrapped — updatedInput is the stripped command.
assert_eq "tail rewrite strips tail" "ls -la > tmp/x.log 2>&1" \
  "$(printf '%s' "$_OUT3" | jq -r '.hookSpecificOutput.updatedInput.command')"
rm -rf "$_TMPH3"

# ---- 3.5 safety: head not allowed -> no rewrite, fall through ----
_TMPH4="$(mktemp -d)"; mkdir -p "$_TMPH4/.claude"
printf '{"permissions":{"allow":["Bash(ls *)"]}}' > "$_TMPH4/.claude/settings.json"
# kubectl is NOT allowed: must fall through (no stdout), NOT rewrite-allow
assert_eq "unallowed head -> no stdout" "" \
  "$(HOME="$_TMPH4" run_hook '{"tool_name":"Bash","tool_input":{"command":"kubectl get cm > tmp/v.yaml; cat tmp/v.yaml"},"cwd":"/nope"}')"
rm -rf "$_TMPH4"

# ---- 3.5 safety: deny still wins even with a strippable tail ----
_TMPH5="$(mktemp -d)"; mkdir -p "$_TMPH5/.claude"
printf '{"permissions":{"allow":["Bash(ls *)"],"deny":["Bash(rm *)"]}}' > "$_TMPH5/.claude/settings.json"
_OUT5="$(HOME="$_TMPH5" run_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf x > tmp/x.log 2>&1; cat tmp/x.log"},"cwd":"/nope"}')"
assert_eq "deny wins over tail strip" "deny" \
  "$(printf '%s' "$_OUT5" | jq -r '.hookSpecificOutput.permissionDecision')"
rm -rf "$_TMPH5"

# ---- 2.1/2.2 allow-listed plain command is wrapped ----
_TC1="$(mktemp -d)"; mkdir -p "$_TC1/.claude"
printf '{"permissions":{"allow":["Bash(ls *)","Bash(embo-capture *)"]}}' \
  > "$_TC1/.claude/settings.json"
_O="$(HOME="$_TC1" run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/nope"}')"
assert_eq "wrap: plain allowed -> allow" "allow" \
  "$(printf '%s' "$_O" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "wrap: plain allowed -> embo-capture cmd" "$(wrap_cmd 'ls -la')" \
  "$(printf '%s' "$_O" | jq -r '.hookSpecificOutput.updatedInput.command')"
rm -rf "$_TC1"

# ---- 2.3/2.4 ordering: strip tail FIRST, then consider wrapping ----
# Here the survivor still has a redirect, so the already-redirected
# opt-out applies: stripped but NOT wrapped. (Wrapping-after-strip is
# exercised by a no-redirect case below.)
_TC2="$(mktemp -d)"; mkdir -p "$_TC2/.claude"
printf '{"permissions":{"allow":["Bash(ls *)","Bash(embo-capture *)"]}}' \
  > "$_TC2/.claude/settings.json"
_O="$(HOME="$_TC2" run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la > tmp/x.log 2>&1; echo \"exit=$?\"; cat tmp/x.log"},"cwd":"/nope"}')"
assert_eq "order: strip, survivor redirected -> not wrapped" \
  "ls -la > tmp/x.log 2>&1" \
  "$(printf '%s' "$_O" | jq -r '.hookSpecificOutput.updatedInput.command')"
rm -rf "$_TC2"

# strip a NON-redirect tail, survivor has no redirect -> wrapped
_TC2b="$(mktemp -d)"; mkdir -p "$_TC2b/.claude"
printf '{"permissions":{"allow":["Bash(ls *)","Bash(embo-capture *)"]}}' \
  > "$_TC2b/.claude/settings.json"
_O="$(HOME="$_TC2b" run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la; echo \"exit=$?\""},"cwd":"/nope"}')"
assert_eq "order: strip then wrap survivor" "$(wrap_cmd 'ls -la')" \
  "$(printf '%s' "$_O" | jq -r '.hookSpecificOutput.updatedInput.command')"
rm -rf "$_TC2b"

# ---- 2.5/2.6 unallowed head is NOT wrapped-and-allowed ----
_TC3="$(mktemp -d)"; mkdir -p "$_TC3/.claude"
printf '{"permissions":{"allow":["Bash(ls *)","Bash(embo-capture *)"]}}' \
  > "$_TC3/.claude/settings.json"
assert_eq "wrap: unallowed head -> no stdout" "" \
  "$(HOME="$_TC3" run_hook '{"tool_name":"Bash","tool_input":{"command":"kubectl get cm"},"cwd":"/nope"}')"
rm -rf "$_TC3"

# ---- 3.0 re-entrancy guard: already-wrapped command left alone ----
_TC4="$(mktemp -d)"; mkdir -p "$_TC4/.claude"
printf '{"permissions":{"allow":["Bash(ls *)","Bash(embo-capture *)"]}}' \
  > "$_TC4/.claude/settings.json"
# an embo-capture command must NOT be re-wrapped (no stdout = fall through)
assert_eq "guard: already wrapped -> no stdout" "" \
  "$(HOME="$_TC4" run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$(wrap_cmd 'ls -la')\"},\"cwd\":\"/nope\"}")"
rm -rf "$_TC4"

# ---- 3.1/3.2 already-redirected command is NOT wrapped ----
# (the model deliberately redirected; leave its redirect intact = no wrap)
_TC5="$(mktemp -d)"; mkdir -p "$_TC5/.claude"
printf '{"permissions":{"allow":["Bash(ls *)","Bash(embo-capture *)"]}}' \
  > "$_TC5/.claude/settings.json"
_O="$(HOME="$_TC5" run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la > tmp/keep.log 2>&1"},"cwd":"/nope"}')"
# allow (head is listed) but NOT wrapped: command unchanged -> no updatedInput
assert_eq "redirected: not wrapped (no updatedInput)" "null" \
  "$(printf '%s' "$_O" | jq -r '.hookSpecificOutput.updatedInput.command // "null"')"
rm -rf "$_TC5"

# ---- 3.3/3.4 interactive head is NOT wrapped ----
_TC6="$(mktemp -d)"; mkdir -p "$_TC6/.claude"
printf '{"permissions":{"allow":["Bash(ssh *)","Bash(embo-capture *)"]}}' \
  > "$_TC6/.claude/settings.json"
_O="$(HOME="$_TC6" run_hook '{"tool_name":"Bash","tool_input":{"command":"ssh host"},"cwd":"/nope"}')"
assert_eq "interactive: not wrapped (no updatedInput)" "null" \
  "$(printf '%s' "$_O" | jq -r '.hookSpecificOutput.updatedInput.command // "null"')"
rm -rf "$_TC6"

# ---- 3.5/3.6 deny still wins; unsafe still falls through ----
_TC7="$(mktemp -d)"; mkdir -p "$_TC7/.claude"
printf '{"permissions":{"allow":["Bash(ls *)","Bash(embo-capture *)"],"deny":["Bash(rm *)"]}}' \
  > "$_TC7/.claude/settings.json"
_O="$(HOME="$_TC7" run_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"},"cwd":"/nope"}')"
assert_eq "deny wins over wrap" "deny" \
  "$(printf '%s' "$_O" | jq -r '.hookSpecificOutput.permissionDecision')"
rm -rf "$_TC7"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
