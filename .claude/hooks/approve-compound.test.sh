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

# ---- 032 capture-wrapper default path resolution ----
# default_capture_cmd -> the wrapper command when EMBO_CAPTURE_CMD is
# unset. Prefers a plugin install (${CLAUDE_PLUGIN_ROOT}/hooks/...) and
# falls back to the manual install (~/.claude/hooks/...). Both forms must
# still contain the stable `embo-capture.sh` token the guard keys off.

# Plugin install: CLAUDE_PLUGIN_ROOT set, EMBO_CAPTURE_CMD unset.
PLUGIN_DEFAULT="$(CLAUDE_PLUGIN_ROOT=/x/plugin; unset EMBO_CAPTURE_CMD; default_capture_cmd)"
assert_eq "default uses plugin root" "/x/plugin/hooks/embo-capture.sh" "$PLUGIN_DEFAULT"

# Manual install: neither var set -> fall back under $HOME/.claude.
MANUAL_DEFAULT="$(unset CLAUDE_PLUGIN_ROOT; unset EMBO_CAPTURE_CMD; default_capture_cmd)"
assert_eq "default falls back to home" "$HOME/.claude/hooks/embo-capture.sh" "$MANUAL_DEFAULT"

# Both forms carry the stable token (guard/allow-rule depend on it).
assert_eq "plugin default has token" "yes" \
  "$(printf '%s' "$PLUGIN_DEFAULT" | grep -q 'embo-capture.sh' && echo yes || echo no)"
assert_eq "manual default has token" "yes" \
  "$(printf '%s' "$MANUAL_DEFAULT" | grep -q 'embo-capture.sh' && echo yes || echo no)"

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

# ---- 029/1.1 compound wrap eligibility ----
# should_wrap <command> -> "yes" | "no"
# Compounds of non-interactive segments are wrapped; backgrounding
# (trailing &) and any interactive segment disqualify.

assert_eq "wrap: && chain"          "yes" "$(should_wrap 'ls && pwd')"
assert_eq "wrap: ; chain"           "yes" "$(should_wrap 'ls ; pwd')"
assert_eq "wrap: || chain"          "yes" "$(should_wrap 'true || pwd')"
assert_eq "wrap: pipeline"          "yes" "$(should_wrap 'ls | grep x')"
assert_eq "wrap: mixed chain+pipe"  "yes" "$(should_wrap 'ls && pwd | grep x')"
assert_eq "nowrap: trailing & (bg)" "no"  "$(should_wrap 'sleep 5 &')"
assert_eq "nowrap: compound bg"     "no"  "$(should_wrap 'ls && sleep 5 &')"
assert_eq "nowrap: | less tail"     "no"  "$(should_wrap 'make | less')"
assert_eq "nowrap: | python3 tail"  "no"  "$(should_wrap 'ls | python3')"
assert_eq "nowrap: interactive 1st" "no"  "$(should_wrap 'ssh host && ls')"
assert_eq "nowrap: interactive mid" "no"  "$(should_wrap 'ls && vim x && pwd')"

# ---- 029/1.2 opt-outs hold for compounds ----
# Redirect, unsafe construct, and re-entrancy must disqualify a
# compound from wrapping exactly as they do a simple command.

assert_eq "nowrap: compound redirect"    "no" \
  "$(should_wrap 'ls && pwd > tmp/x.log')"
assert_eq "nowrap: compound 2>&1"        "no" \
  "$(should_wrap 'ls 2>&1 | grep x')"
assert_eq "nowrap: compound cmd subst"   "no" \
  "$(should_wrap 'echo $(whoami) && ls')"
assert_eq "nowrap: compound backtick"    "no" \
  "$(should_wrap 'ls && echo `id`')"
assert_eq "nowrap: compound heredoc"     "no" \
  "$(should_wrap 'cat <<EOF && ls')"
assert_eq "nowrap: compound re-entrant"  "no" \
  "$(should_wrap "$(wrap_cmd 'ls && pwd')")"

# ---- 029/2.1 strip leading `env` wrapper ----
# `env [flags] [NAME=VALUE ...] cmd args` must normalize to `cmd args`
# so the real head matches its allow-rule. Bare `env` -> empty
# (fallthrough). Live case 2026-06-10: env-prefixed npx prompted.

assert_eq "env: assignments"      "npx test" \
  "$(normalize_subcommand 'env A=1 B=2 npx test')"
assert_eq "env: single var"       "git push" \
  "$(normalize_subcommand 'env FOO=bar git push')"
assert_eq "env: -i flag"          "ls" \
  "$(normalize_subcommand 'env -i ls')"
assert_eq "env: -u NAME"          "ls -la" \
  "$(normalize_subcommand 'env -u PATH ls -la')"
assert_eq "env: -- separator"     "ls" \
  "$(normalize_subcommand 'env -- ls')"
assert_eq "env: flags then vars"  "npm test" \
  "$(normalize_subcommand 'env -i A=1 npm test')"
assert_eq "env: bare -> empty"    "" \
  "$(normalize_subcommand 'env')"
assert_eq "env: keeps cmd args"   "npx --prefix tests playwright test" \
  "$(normalize_subcommand 'env P_A=/tmp/x P_B=dev npx --prefix tests playwright test')"

# ---- 029/9.2 backgrounding & anywhere; dangling operators (G3+G4) ----
# A backgrounding & in any position disqualifies wrapping (capture of
# a detached job is undefined). Dangling trailing operators would make
# bash -c fail on syntax; leave them unwrapped.

assert_eq "nowrap: & then comment"   "no"  "$(should_wrap 'sleep 5 & # start')"
assert_eq "nowrap: & mid (a & b)"    "no"  "$(should_wrap 'sleep 5 & echo done')"
assert_eq "nowrap: dangling &&"      "no"  "$(should_wrap 'ls &&')"
assert_eq "nowrap: dangling ||"      "no"  "$(should_wrap 'pwd ||')"
assert_eq "nowrap: dangling |"       "no"  "$(should_wrap 'ls |')"
assert_eq "wrap: trailing ; ok"      "yes" "$(should_wrap 'ls ;')"
assert_eq "wrap: |& still wraps"     "yes" "$(should_wrap 'ls |& grep x')"

# ---- 029/9.3 sudo never wrapped (G5) ----
# sudo may prompt for a password (no TTY under bash -c -> hang) and
# its child may be interactive. Wrap-side opt-out only: sudo is NOT
# stripped in normalize_subcommand — an allow-rule for `cmd` must not
# authorize `sudo cmd`.

assert_eq "nowrap: sudo simple"      "no" "$(should_wrap 'sudo ls')"
assert_eq "nowrap: sudo interactive" "no" "$(should_wrap 'sudo ssh host')"
assert_eq "nowrap: sudo in compound" "no" "$(should_wrap 'ls && sudo make install')"
assert_eq "norm: sudo NOT stripped"  "sudo ls" "$(normalize_subcommand 'sudo ls')"

# ---- 029/9.1 glued env flags (G2) ----
# `env -uNAME cmd` (value glued to flag) must still expose the real
# command head so deny rules fire on it.

assert_eq "env: glued -uNAME"     "rm -rf /" \
  "$(normalize_subcommand 'env -uPATH rm -rf /')"
assert_eq "env: glued -uNAME ls"  "ls -la" \
  "$(normalize_subcommand 'env -uPATH ls -la')"
assert_eq "env: glued -u only"    "" \
  "$(normalize_subcommand 'env -uPATH')"

# ---- 029/9.4 fail-safe pins: quoted separators (G1), env -- (G6) ----
# The sed split is quote-unaware. These pins document that the
# resulting mis-split NEVER produces a wrong "allow": the truncated
# segment fails to match (-> fallthrough) or matches deny (-> deny).

_TMPH9="$(mktemp -d)"; mkdir -p "$_TMPH9/.claude"
printf '{"permissions":{"allow":["Bash(git log *)","Bash(ls *)"],"deny":["Bash(rm *)"]}}' \
  > "$_TMPH9/.claude/settings.json"
dec9() { HOME="$_TMPH9" decide "$1" "$_TMPH9/noproj"; }

assert_eq "quoted &&: never allow"  "fallthrough" \
  "$(dec9 'git log --format="a && ls"')"
assert_eq "quoted ; rm: deny wins"  "deny" \
  "$(dec9 'git log --format="a; rm -rf /"')"
assert_eq "env -- segment: fall"    "fallthrough" \
  "$(dec9 'ls && env --')"
rm -rf "$_TMPH9"

# ---- 030/1.1 filter-tail detection ----
# split_filter_tail <command> -> on detection prints TWO lines:
#   line 1: upstream command (trimmed)
#   line 2: filter chain, segments re-joined with " | " (trimmed)
# No decomposition -> prints nothing.
# Scope guard: pure pipelines only (no top-level && ; ||).

# positives: single filter tail
assert_eq "ft: cmd | head"   $'kubectl get pods\nhead -20' \
  "$(split_filter_tail 'kubectl get pods | head -20')"
assert_eq "ft: multi-filter tail" $'kubectl get pods -o yaml\ngrep image | head -5' \
  "$(split_filter_tail 'kubectl get pods -o yaml | grep image | head -5')"

# positives: every FILTER_HEADS member in tail position
assert_eq "ft: head"   $'git log\nhead -3'      "$(split_filter_tail 'git log | head -3')"
assert_eq "ft: tail"   $'git log\ntail -3'      "$(split_filter_tail 'git log | tail -3')"
assert_eq "ft: grep"   $'git log\ngrep fix'     "$(split_filter_tail 'git log | grep fix')"
assert_eq "ft: sed"    $'git log\nsed -n 1,5p'  "$(split_filter_tail 'git log | sed -n 1,5p')"
assert_eq "ft: awk"    $'ps aux\nawk "{print}"' "$(split_filter_tail 'ps aux | awk "{print}"')"
assert_eq "ft: cut"    $'ps aux\ncut -d: -f1'   "$(split_filter_tail 'ps aux | cut -d: -f1')"
assert_eq "ft: wc"     $'git log\nwc -l'        "$(split_filter_tail 'git log | wc -l')"
assert_eq "ft: sort"   $'du -s a b\nsort -n'    "$(split_filter_tail 'du -s a b | sort -n')"
assert_eq "ft: uniq"   $'git log\nuniq -c'      "$(split_filter_tail 'git log | uniq -c')"
assert_eq "ft: jq"     $'aws s3api list\njq .Buckets' \
  "$(split_filter_tail 'aws s3api list | jq .Buckets')"
assert_eq "ft: tr"     $'git log\ntr -d x'      "$(split_filter_tail 'git log | tr -d x')"
assert_eq "ft: column" $'df -h\ncolumn -t'      "$(split_filter_tail 'df -h | column -t')"

# negatives: shape outside scope -> empty output
assert_eq "ft: no pipe"          "" "$(split_filter_tail 'ls -la')"
assert_eq "ft: && compound"      "" "$(split_filter_tail 'cd x && git log | head -3')"
assert_eq "ft: ; compound"       "" "$(split_filter_tail 'ls; git log | head -3')"
assert_eq "ft: || compound"      "" "$(split_filter_tail 'a | head || b')"
assert_eq "ft: pipe after tail"  "" "$(split_filter_tail 'a | grep x && b')"
assert_eq "ft: non-filter tail"  "" "$(split_filter_tail 'a | grep x | xargs rm')"
assert_eq "ft: xargs executor"   "" "$(split_filter_tail 'cat list | xargs kubectl delete')"
# all-filter pipeline: maximal trailing run leaves empty upstream -> none
assert_eq "ft: all-filter"       "" "$(split_filter_tail 'grep x file | head -3')"

# ---- 030/1.2 opt-outs and upstream exclusions ----
# Per-head opt-outs: the segment is NOT a filter -> no decomposition.
assert_eq "ft: tail -f consumer"  "" "$(split_filter_tail 'kubectl logs p | tail -f')"
assert_eq "ft: tail -F consumer"  "" "$(split_filter_tail 'kubectl logs p | tail -F')"
assert_eq "ft: grep -q"           "" "$(split_filter_tail 'git log | grep -q fix')"
assert_eq "ft: grep --quiet"      "" "$(split_filter_tail 'git log | grep --quiet fix')"
assert_eq "ft: sed -i"            "" "$(split_filter_tail 'ls | sed -i p x')"

# Whole-command opt-outs (existing fail-safes hold at detection level).
assert_eq "ft: filter redirect"   "" "$(split_filter_tail 'git log | head -3 > out')"
assert_eq "ft: upstream redirect" "" "$(split_filter_tail 'git log 2>&1 | head -3')"
assert_eq "ft: unsafe subst"      "" "$(split_filter_tail 'echo $(id) | head -1')"
assert_eq "ft: backticks"         "" "$(split_filter_tail 'echo `id` | head -1')"
assert_eq "ft: pipe-amp |&"       "" "$(split_filter_tail 'make |& grep err')"
assert_eq "ft: backgrounding &"   "" "$(split_filter_tail 'slow | head -3 &')"

# Upstream exclusions: streaming producers and interactive/sudo heads.
assert_eq "ft: upstream yes"      "" "$(split_filter_tail 'yes | head -5')"
assert_eq "ft: upstream watch"    "" "$(split_filter_tail 'watch date | head -5')"
assert_eq "ft: upstream tail -f"  "" "$(split_filter_tail 'tail -f log | grep err')"
assert_eq "ft: journalctl -f"     "" "$(split_filter_tail 'journalctl -f -u s | grep err')"
assert_eq "ft: upstream ssh"      "" "$(split_filter_tail 'ssh host ls | head -3')"
assert_eq "ft: upstream sudo"     "" "$(split_filter_tail 'sudo dmesg | tail -5')"

# Boundary pins: bounded forms of streaming-capable heads stay eligible.
assert_eq "ft: journalctl -n ok"  $'journalctl -n 50 -u s\ngrep err' \
  "$(split_filter_tail 'journalctl -n 50 -u s | grep err')"

# Quote ambiguity: quoted | must never mis-split (fail-safe: none).
assert_eq "ft: quoted pipe"       "" \
  "$(split_filter_tail 'git log --grep="a | b" | head -3')"

# ---- 030/3.1 final_command: rewrite selection ----
# final_command <command> -> the command main should emit:
#   filter pipeline  -> EMBO_CAPTURE_CMD --filter-b64 <b64f> --b64 <b64u>
#   wrap-eligible    -> EMBO_CAPTURE_CMD --b64 <b64cmd>   (existing)
#   ineligible       -> unchanged
wrapf_cmd() { # <upstream> <filter-chain>
  printf '%s --filter-b64 %s --b64 %s' \
    "$EMBO_CAPTURE_CMD" "$(b64 "$2")" "$(b64 "$1")"
}

assert_eq "fc: filter pipeline" \
  "$(wrapf_cmd 'git log' 'head -3')" \
  "$(final_command 'git log | head -3')"
assert_eq "fc: multi-filter chain" \
  "$(wrapf_cmd 'kubectl get pods' 'grep x | head -5')" \
  "$(final_command 'kubectl get pods | grep x | head -5')"
assert_eq "fc: compound whole-wrap" \
  "$(wrap_cmd 'ls && pwd')" "$(final_command 'ls && pwd')"
assert_eq "fc: simple whole-wrap" \
  "$(wrap_cmd 'ls -la')" "$(final_command 'ls -la')"
assert_eq "fc: grep -q whole-wrap" \
  "$(wrap_cmd 'git log | grep -q fix')" \
  "$(final_command 'git log | grep -q fix')"
assert_eq "fc: backgrounded unchanged" \
  'sleep 5 &' "$(final_command 'sleep 5 &')"
assert_eq "fc: interactive tail unchanged" \
  'make | less' "$(final_command 'make | less')"
assert_eq "fc: re-entrancy unchanged" \
  "$(wrap_cmd 'ls')" "$(final_command "$(wrap_cmd 'ls')")"

# decide() still gates per-segment: filter segments need allow rules too
_TMPHF="$(mktemp -d)"; mkdir -p "$_TMPHF/.claude"
printf '{"permissions":{"allow":["Bash(git log *)","Bash(head *)"],"deny":[]}}' \
  > "$_TMPHF/.claude/settings.json"
decf() { HOME="$_TMPHF" decide "$1" "$_TMPHF/noproj"; }

assert_eq "fc gate: both allowlisted"     "allow" \
  "$(decf 'git log | head -3')"
assert_eq "fc gate: filter not listed"    "fallthrough" \
  "$(decf 'git log | grep x')"
assert_eq "fc gate: upstream not listed"  "fallthrough" \
  "$(decf 'kubectl get pods | head -3')"
rm -rf "$_TMPHF"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
