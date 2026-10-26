# Tech design — Protected-branch guard

**Task**: 055-MAIN-BRANCH-GUARD
**Input**: `run-d/2026-10-25-main-branch-guard-prd.md` (11 FR, 4 NFR, 8 PRD decisions, 5 questions)
**Status**: Draft for task breakdown

Facts marked **[verified]** were checked against the repository or the
current Claude Code hooks documentation. Facts marked **[provisional]**
were not independently confirmed and must be proven by the live run
named in the verification table.

## 1. Summary

One new PreToolUse hook, `plugin/hooks/branch-guard.sh`, one new shared
library, `plugin/lib/branch-guard-lib.sh`, and two profile keys. The hook
is a single process that dispatches on `tool_name`:

- `Edit`, `Write`, `MultiEdit`, `NotebookEdit`: judge the repository that
  owns the target file.
- `Bash`: parse the command with a quote-aware tokenizer, find `git
  commit` and `git push` invocations (including inside compound
  commands, `bash -c`, `eval` of a literal, and `$(...)` bodies), judge
  each.

The hook never inspects anything it can decide from the command text
alone before spawning a subprocess: a Bash command that does not contain
the substring `git` exits before any `git`, `yq` or profile work.

```
stdin JSON
   |
   v
 tool_name? --Edit-family--> file dir -> branch -> protected? -> ignored? -> decide
   |
   +--Bash--> contains "git"? -no-> exit 0
                 |yes
                 v
        tokenize + classify (pure Bash, no subprocess)
                 |
        no commit/push/unclassifiable found --> exit 0
                 |
                 v
        resolve branch (git) -> protected? (yq) -> mode (yq) -> decide
                 |
                 v
   block: deny JSON | warn: additionalContext JSON | off: nothing (D-9)
```

## 2. Decisions

### D-1 One hook file, one lib, dispatching on `tool_name`

`branch-guard.sh` handles all matched tools. The classifier and the
list/mode helpers live in `plugin/lib/branch-guard-lib.sh`, sourced by the
hook and by the lib's own test. Mirrors the established split
(`branch-task-check.sh` + `branch-task-lib.sh`): the hook owns I/O, exit
codes and JSON; the lib holds pure functions with no output and no exits.

*Rejected*: two hooks (edit guard, bash guard). Doubles process spawns
for no isolation benefit; both share the same branch/profile/decision
code. *Rejected*: extending `approve-compound.sh` (PRD D-4 stands; that
file is 456 lines, is an approver, and its normalizer is deliberately not
quote-aware, see D-4).

### D-2 Profile schema (resolves Q-2)

```yaml
rules:
  workflow:
    # Branches the agent must not edit, commit to, or push to. Entries are
    # exact names or `*`/`?` glob patterns (e.g. release/*). `[]` disables
    # branch protection entirely; an absent key means [main, master].
    protected_branches: [main, master]
    # What happens on a protected branch. `block` = the action is denied;
    # `warn` = the action runs and the agent is warned; `off` = no check.
    # An unrecognised value is treated as `block`.
    protected_branch_mode: block
```

- Sibling keys, not a nested map. Matches the flat shape of
  `docs_first` and `scope_drift`, and `embo-profile get` takes one dotted
  path to one value.
- **[verified]** `embo-profile get rules.testing.scope` prints
  `[unit, integration]`: yq preserves the source's flow style, so a
  flow-style list arrives as one line `[a, b]`. A block-style list would
  arrive as `- a` lines. The parser (`bg_parse_list`) accepts both, plus
  comma/space separated bare scalars and quoted items.
- **[verified]** `embo-profile get` reads only the *active* profile file
  or `default.yaml`. It does not merge. The active profile is a copy
  taken at `embo-profile set` time, so every user with an existing
  active profile, and the four shipped non-default profiles, lack the
  keys. Therefore **absent key = built-in default** (`[main, master]`,
  `block`), applied in the hook, and the keys are also added explicitly
  to all five shipped profiles so the shipped state is self-documenting.
  Without this, the guard would be silently off for every existing
  install.
- Absent versus empty: `get` prints nothing for absent and `[]` for an
  explicit empty list. The hook distinguishes them: nothing = default
  list; `[]` = no protected branches.
- Globs: matched with Bash `case` after `[`/`]` are stripped from the
  list text, so only `*` and `?` are live. A plain name is the degenerate
  case, so adding glob support later would not have been compatible-
  breaking, but it is free now.

*Rejected*: a nested map (`protected_branch: {mode:, branches:}`); mode
and list as one string; hardcoding. *Trapdoor note*: the key names freeze
once users copy them into profiles. These names follow the seed's
`rules.workflow.protected_branches` exactly.

### D-3 Invalid mode degrades to `block`; reported when the guard acts

`bg_normalize_mode` lower-cases the value; `block|warn|off` pass through;
anything else becomes `block` and sets `BG_MODE_INVALID=1`. The denial
text then appends `(unrecognised protected_branch_mode '<value>',
treated as block)`. Because the degraded value is `block`, a typo
surfaces itself the first time the guard denies; on a feature branch the
guard stays silent and nothing needs reporting.

**Disagreement with the PRD as amended (D-3/FR-5/FR-7: empty value =
fail open).** This design does the opposite for an empty or absent
*mode*: it applies the built-in default (`block`). Evidence:
`embo-profile set` copies the profile file (`embo-profile:113`) and `get`
does not merge with `default.yaml`, so every existing install and every
profile shipped without the key returns empty. Failing open on empty
would leave the guard off for every existing user until they re-run
`set`, defeating the default-`block` decision (PRD D-1). The cost of the
opposite choice is one exotic case: a user who writes `mode: ""` gets
`block` instead of silence; they get a denial that names the profile key
and can set `off`. Failure to read at all (non-zero exit from
`embo-profile`) still fails open. Sent to `d-prd` as a correction; if the
maintainer prefers the PRD's version, only `bg_normalize_mode`'s
empty-case line changes, and the shipped profiles and a profile-refresh
step in `/embo:start` would then become required.

*Limit*: a typo is not reported on branches where the guard does not
fire. Accepted; reporting on every call would add noise to every tool
call in every session.

### D-4 The Bash tokenizer is quote-aware and recursive, not `approve-compound`'s splitter

`approve-compound.sh` splits with `sed` on `[;|&]` regardless of quoting
and bails on `$(`, backticks, `<(`, `<<`. That is correct for an approver
(bailing means "ask the user"). For a guard it is wrong in both
directions:

- Splitting inside quotes produces fragments such as `git commit"` from
  `echo "x; git commit"`, a false positive.
- The shape the agent uses most often to commit,
  `git commit -m "$(cat <<'EOF' ... EOF)"`, contains both `$(` and a
  heredoc. A bail-and-allow policy would let the single most common
  commit shape through unchecked; a bail-and-deny policy would deny every
  commit message the agent writes.

So the guard has its own tokenizer (`bg_tokenize`): a single left-to-right
pass tracking single quote, double quote, backslash escape, and nesting
depth of `$(`/backtick/`(`; it emits words, separators and redirect
operators, collects `$(...)`, backtick and `<(...)`/`>(...)` bodies, and
skips heredoc bodies. Substitution bodies and `-c` strings are classified
recursively (depth cap 5; beyond it the shape is unclassifiable, D-6).

*Rejected*: reusing `split_subcommands` (false positives above); calling
`python3 -c 'import shlex'` (extra process, ~30 ms, not Bash-only per
NFR-2, and shlex does not model `$(...)` or heredocs anyway);
`bash -n` / `declare -f` tricks (executes nothing but also yields no
structure).

### D-5 Matcher string and tool coverage (resolves Q-4)

```
"matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash"
```

`Edit`, `Write` and `NotebookEdit` are documented live tool names;
`MultiEdit` is described as legacy and may not be callable, so it is
listed as harmless-if-absent. The stdin common fields are `session_id`,
`transcript_path`, `cwd`, `permission_mode`, optional `agent_id` and
`agent_type`, `tool_name`, `tool_input`, `tool_use_id` (`d-researcher`);
the per-tool `tool_input` field names were not found in the docs, hence
the defensive `file_path // notebook_path` read and a fixture case per
tool plus a live run. All characters are letters and `|`, so per the hooks documentation
**[verified, per PRD D-5]** this is an exact-name list, not a regex. All
five names are listed. A name the harness does not provide is inert;
omitting one it does provide is a hole. Which of `MultiEdit` and
`NotebookEdit` exist in the current harness is **[provisional]**
pending `d-researcher`; the list does not depend on the answer. The
path field differs: `file_path` for `Edit|Write|MultiEdit`,
`notebook_path` for `NotebookEdit` **[provisional]**; the hook reads
`.tool_input.file_path // .tool_input.notebook_path`.

This is a separate `hooks.json` entry from the `approve-compound.sh`
entry (matcher `Bash`). Two hooks matching one call run side by side;
their decisions are combined by the harness. The guard emits only `deny`
or `additionalContext`, never `allow`, so it can never grant permission
that `approve-compound.sh` or the user did not. See D-10 for ordering.

### D-6 What the classifier does with a shape it cannot classify (resolves Q-1)

**Maintainer decisions: (Q-1) the instructed commit shape is changed so
the parser can read it; (Q-1 residual, decided separately) an
unclassifiable command is never refused. The warning half of this rule
depends on `additionalContext` working on PreToolUse (Q-10, V-11): if that
check fails, the unclassifiable case silently becomes allow-with-no-warning.
This guard stops forgetting, not deliberate circumvention.** The
earlier recommendation here ("refuse when the branch is protected and the
text contains `git`") is withdrawn: it would accept permanent false
positives on legitimate commands to avoid a one-time edit of a shipped
file.

Stated as a rule, with no ambiguity:

> A Bash command is **unclassifiable** when a segment's behaviour depends
> on text the parser cannot see: a command word that is dynamic
> (`$X commit`), `eval` or `bash -c` with a non-literal argument, `xargs`
> / `find -exec` / `parallel` followed by `git`, a parse error
> (unbalanced quote or paren), recursion deeper than 5, or a `git`
> invocation whose subcommand word is dynamic (`git $SUB`).
>
> An unclassifiable command is **allowed**. If the governing branch is
> protected and the command text contains `git` (case-insensitive), the
> hook adds a warning to the agent's context (`additionalContext`, the
> D-9 warn channel) saying the command could not be analysed. It never
> refuses and never changes the command.

Consequences, each stated so none is a surprise:

- An unclassifiable `git commit` or `git push` on a protected branch, or
  a dynamic push destination from a feature branch (`git push origin
  "$BR"` with `$BR` = `main`), **goes through**. These are holes, accepted:
  the alternative is false positives on legitimate commands, and the
  remote's own branch protection is the backstop for pushes.
- The warning costs nothing to a legitimate command (it does not block)
  and makes the hole visible instead of silent. It is emitted only when
  the branch is protected, so feature-branch sessions never see it.
- The instructed shapes must never be unclassifiable. The shipped
  `git commit` instruction (`git.md`) changes from
  `git commit -m "$(cat <<'EOF' ... EOF)"` to writing the message to a
  file under the git-ignored `tmp/` and running `git commit -F <file>`
  (D-16). The parser still understands substitutions and heredocs (an
  agent can write them unprompted), but nothing the workflow itself
  instructs depends on that.

Hole that is outside any classifier, and stays open by design (restating
PRD section 7): aliases and shell functions from the user's shell profile
(`gp` for `git push`), scripts that run git internally (`./release.sh`),
persistent git aliases from config files (`git ci`; inline `-c alias.`
is handled, D-14), `GIT_*` configuration that remaps behaviour, and
any non-git tool that writes a tracked file. The guard sees command
text, not behaviour.

*Rejected*: refuse-when-protected-and-text-contains-git (maintainer: false
positives forever, e.g. a `git log` inside a substitution refused on
`main`); deny every unclassifiable command (denies `eval "$(ssh-agent)"`).
Silent fail-open was also rejected in favour of the warning above.

### D-16 The instructed commit shape becomes `git commit -F <file>`

Edit `plugin/commands/git.md` (the line instructing
`git commit -m "$(cat <<'EOF' ... EOF)"`): the message is written to a
file under `tmp/` with the Write tool, then `git commit -F tmp/<file>` is
run. `tmp/` is git-ignored, so the Write is allowed even on a protected
branch (D-8) and the commit is then judged on its own merits. The edit
must not mention task numbers or `tasks/` paths. The PR-body instruction
(`gh pr create --body "$(cat <<'EOF'...)"`) is not a git write and is
left alone. Consequence for the guard on a protected branch: both calls
are simple and fully classifiable; the Write is allowed (ignored path),
the commit is refused.

### D-7 Blocked subcommands: those whose purpose is to create a commit, plus push

The blocked git subcommands are a single list in the lib,
`BG_BLOCKED_SUBCOMMANDS="commit cherry-pick revert am push"`. The first
four exist to create a commit on the current branch, which is what FR-2
exists to prevent; leaving them out would ship a known way to make the
incident's commit.

**The list does not stop every way a commit can land on a protected
branch, and must not be read as if it did.** `git merge --no-ff` and a
three-way merge create a merge commit on the current branch (measured by
`d-critic`: a `--no-ff` merge on `main` created a two-parent commit and
advanced HEAD), and so can `git pull` with merge semantics on diverged
branches and `git rebase` onto the current branch. The plumbing family
also advances or repoints a branch with no blocked subcommand in sight:
`git write-tree` + `git commit-tree` + `git update-ref refs/heads/main
<sha>` moved `main` to a new commit (measured by `d-critic`), and
`git symbolic-ref HEAD refs/heads/main`, `git fast-import` and `git
replace` are of the same kind. These are circumvention, not forgetting,
are not how an agent commits, and are deliberately not blocked (blocking
`update-ref` would catch legitimate uses and widen the surface beyond
FR-2). (`git notes add` writes a notes ref only; `git stash` creates
commit objects without advancing the branch; neither is a gap.) The
merge, pull and rebase cases are deliberately not blocked: PRD section 6 excludes merge, rebase and reset; updating a
local mirror of `main` (fast-forward merge or pull, which create no
commit) is a legitimate use; and the remote's own branch protection is
the backstop for what such a commit would do next. `git stash` and
`git tag` are likewise not blocked (stash does not advance the branch;
`stash pop`/`apply` change the working tree only; unmeasured beyond that).
Blocking only the commit-creating forms (`merge` without `--ff-only`,
`pull` without `--ff-only`) is a possible later tightening; it adds
option parsing and obstructs legitimate updating of `main`, so it is not
done now. The set is data, so it is a one-token change per subcommand.
**Asks `d-prd` to amend FR-2** to name the blocked subcommands and the
not-blocked commit-capable ones. Resolves N-1.

### D-8 Branch and repository resolution

- **Edits**: the governing repository is the one that contains the
  *target file*, not the session `cwd`: `git -C "<nearest existing
  ancestor dir of the file>" symbolic-ref --short -q HEAD`. This is
  stricter than the PRD's NFR-4 wording ("resolved from `cwd`"). **This
  supersedes NFR-4 for the edit tools**, and `d-prd` is asked to amend
  NFR-4 to match; V-24 tests this rule. NFR-4's intent (judge the right
  worktree) is preserved and the `cwd` field of stdin is used as the
  starting directory for Bash and for relative edit paths. Correct for
  worktrees: a session in a feature worktree that edits a
  file by absolute path in the main checkout must be judged against the
  main checkout's branch. For a file inside the session's own worktree
  the two agree.
- **Bash**: the governing directory starts at the hook's `cwd`, then is
  moved by `cd <literal>` segments and `git -C <path>`, and the context
  args `--git-dir=`, `--work-tree=` and the env prefixes `GIT_DIR=` /
  `GIT_WORK_TREE=` are replayed to the branch lookup (`bg_branch_of`).
  A `cd` with a non-literal target is ignored (later segments are judged
  on the directory before the `cd`); stated limit. Subshell parentheses
  scope a `cd`.
- **Ignored files**: an edit to a path that `git check-ignore -q`
  reports as ignored is allowed. Reasoning, stated as the rule: the guard
  protects the branch's history, and an ignored file cannot enter it. This
  also permits editing ignored files that matter locally
  (`.claude/settings.local.json`, a local `.env`); that is intended and is
  a carve-out from FR-1's literal wording, so `d-prd` is asked to add it
  to FR-1. `git check-ignore` has three outcomes **[verified]**: exit 0
  ignored, 1 not ignored, 128 outside the repository or other fatal.
  `bg_is_ignored` returns 0 only for exit 0; 1 and 128 both mean "not
  ignored", the call is made with stderr suppressed and its status
  captured explicitly (`rc=$?` in an `if`/`||` context) so the ERR trap
  cannot turn a 128 into an accidental exit.
- **Outside any repository**: `symbolic-ref` fails (exit 128) and the
  hook exits 0. This also covers edits to `~/.claude/...`.
- **Detached HEAD**: `symbolic-ref -q` prints nothing; exit 0.
- **Unborn branch** (no commits yet): `git rev-parse -q --verify HEAD`
  fails; exit 0. New finding, not in the PRD: without it the first commit
  of `git init && git commit` on `main` would be denied. There is nothing
  to protect on a branch with no history.

### D-9 Output contract per mode; no override variable (resolves Q-3, Q-9)

| Mode | Candidate action on protected branch | Hook stdout | Exit |
|---|---|---|---|
| `block` | refused | `permissionDecision: "deny"` + reason | 0 |
| `warn` | runs | `additionalContext` (no `permissionDecision`) | 0 |
| `off` | runs | nothing | 0 |

- **[verified, hooks docs, confirmed independently by `d-critic`]**
  `additionalContext` is accepted on PreToolUse and appears "next to the
  tool result", i.e. after the action has run. That is exactly warn
  semantics: it is not a pre-action prompt. Also documented: "Deny and
  ask rules are still evaluated regardless of what the hook returns",
  and `defer` is honoured only in non-interactive (`-p`) mode, so the
  guard does not use it (a rung of D-10's precedence list that is inert
  in interactive sessions).
- **[verified]** A PreToolUse hook that exits 0 with stderr only is
  invisible to the model (stderr from an exit-0 hook is never shown to
  Claude; `branch-task-check.sh` is therefore not a precedent for a
  model-visible warning). Warn mode must use JSON `additionalContext`.
  That field on PreToolUse is documented but **[provisional]** until a
  live run (add to V-11: LR confirms the model sees the warning).
- **[documented, hooks guide, via `d-researcher`]** A `deny` blocks the
  tool even in `bypassPermissions` mode and with
  `--dangerously-skip-permissions`, so the guard holds in those sessions.
- The hook **never** emits `permissionDecision: "defer"`: it is ignored
  in interactive sessions, which are exactly the sessions the guard
  protects. A fixture test asserts the hook's output contains only `deny`
  or no `permissionDecision` at all (V-11, V-12).
- The hook **never** emits `permissionDecision: "allow"`. In `warn` it
  omits the decision so the normal permission flow continues; emitting
  `allow` would bypass a user prompt the user would otherwise have seen.
- **The profile mode is the only control; there is no override
  variable (maintainer decision, Q-9).** The hook reads no environment
  variable and honours nothing in the command text. A deliberate one-off
  commit on a protected branch means setting `protected_branch_mode: off`
  (or `warn`) in the profile and reverting it afterwards; the change
  takes effect on the next tool call and needs no restart. That is the
  accepted cost.
- Known limit: the agent can edit `~/.claude/active-profile.yaml` (a path
  outside any repository, so the guard allows it) and set the mode to
  `off`, including after a denial. The guard prevents forgetting, not
  deliberate circumvention; that is the same boundary as PRD section 7.

*Rejected*: an environment-variable override (no documented way for a
plugin to set one for its own hooks, and a user-set one adds an
unverifiable assumption about what a Bash call can change); honouring an
in-command env prefix (the agent would set it after the first denial); a
marker file (state, violates NFR-3).

### D-10 Interaction with `approve-compound.sh`

Both hooks are PreToolUse entries on Bash. **[verified against the
primary source, https://code.claude.com/docs/en/hooks, quoted by
`team-lead`: "When multiple PreToolUse hooks return different decisions,
precedence is `deny` > `defer` > `ask` > `allow`"; matching hooks run in
parallel. A live run (V-18) still confirms it end to end.]** Matching hooks run in parallel, the most restrictive
decision wins (deny > defer > ask > allow), and each receives the
original command, so `approve-compound`'s `allow` cannot override the
guard's `deny` and the guard sees the unwrapped text (if wrong, the
two-hook structure fails invisibly, since fixture tests run the guard in
isolation; hence V-18 is a live run and the decode below is kept).
**[unverified]** Whether one hook's `updatedInput` is visible to another
hook on the same event is undocumented; parallel execution makes "the
original command" the expected answer, but the decode is kept precisely
because that sub-point is not settled. Also documented: the matcher in
D-5 is an exact-name list, so a wrong tool name is silently inert, and
`defer` is honoured only in non-interactive mode.
**[same source and status]** Any
exit code other than 0 or 2, a crash, or malformed JSON is a
non-blocking error and the call proceeds, so a broken guard fails open
by construction; the `trap 'exit 0' ERR` in D-12 only keeps that quiet.
Two consequences handled in the design (the decode in point 1 is
load-bearing, not belt-and-braces: "the guard sees the original command"
is an inference, so the guard must cope with either the original text or
the `embo-capture.sh --b64` rewrite, and must not be simplified away):

1. If hooks run in parallel, both receive the original command and the
   guard sees the unwrapped text. If they ran sequentially with
   `updatedInput` chaining, the guard would see
   `embo-capture.sh --b64 <base64>`. To be safe in either case,
   `bg_decode_capture_wrapper` recognises `*embo-capture.sh --b64 <b64>`
   and `--filter-b64 <b64> --b64 <b64>` and classifies the decoded
   command. This costs one `base64 -d` only when the wrapper pattern is
   present, and is covered by a test.
2. The guard must not change the input. It never emits `updatedInput`.

### D-11 Push destination analysis

Parsed from the words after `push` (details in section 5). Decision:

- A push is refused if **any destination ref is protected**, whatever the
  current branch (PRD D-7).
- `--all` and `--mirror` refuse whenever at least one protected-pattern
  branch exists locally (`bg_local_protected_exists`, one `git
  for-each-ref`); they push every local branch.
- A bare push (`git push`, `git push origin`) is refused if HEAD is
  protected **or** the resolved push target is protected. The target is
  resolved with `git rev-parse --abbrev-ref --symbolic-full-name @{push}`
  (stderr suppressed) and then stripping **exactly the first path
  segment**, `${ref#*/}`, never the last (`${ref##*/}`): `origin/release/1.2`
  becomes `release/1.2`, so a `release/*` pattern still matches. The
  remote name is whatever precedes the first `/`, not literally `origin`
  (measured here: `@{push}` prints `origin/feat/teammates`). A remote
  whose own name contains `/` is unsupported and falls to the HEAD
  fallback. If resolution fails, the target is HEAD.
  This resolves the PRD's "honest limit": the guard resolves rather than
  judging on HEAD alone. Both-conditions OR is conservative and matches
  FR-3's first criterion verbatim.
- `--dry-run` / `-n` is allowed (changes nothing). `--delete`, `-d` and
  `:main` count as destination `main` and are refused. Force flags
  (`-f`, `--force`, `--force-with-lease[=...]`, `--force-if-includes`, a
  leading `+` on a refspec, and clusters such as `-fu`) set a force flag
  that selects the distinct denial text; a force push to an unprotected
  destination is not this guard's business.
- A blocked subcommand (`commit`, `cherry-pick`, `revert`, `am`) is
  refused except when its words include a non-writing flag:
  `--dry-run`, `--help`, `-h`, `--abort`, `--quit`. (`push` has its own
  rules above; `--help`/`-h` also pass.)

### D-13 The delivery path is enforced inside `embo-deliver` (resolves FR-3a)

`/embo:git deliver` runs `embo-deliver --plan <file>`; the command text
contains no `git`, `commit` or `push`, so no Bash parsing can see it
(PRD FR-3a). **Chosen: enforce inside `plugin/bin/embo-deliver`, using the
same lib and the same profile fields as the hook.** The hook does not
special-case the wrapper by name.

What the binary does today **[verified, `plugin/bin/embo-deliver:225-231`]**:
a hardcoded `is_protected` (`main|master`) refuses `mode: push` with
`plan.branch` protected, exit 7; before committing it reconciles the
working tree onto `plan.branch` and never commits on the ambient branch
(`:214-265`). So ambient-`main` is already handled; what is missing is
(a) the policy is hardcoded and ignores the profile list and mode, and
(b) only `push` mode is checked.

Change:

- Replace the hardcoded `is_protected` with `bg_is_protected` against the
  profile list, and honour the mode: `block` -> existing `fail ... 7`
  with the guard's reason text; `warn` -> stderr warning, proceed; `off`
  -> no check. The lib is sourced from `$EMBO_BIN_DIR/../lib` as
  `branch-task-lib.sh` already is.
- **Maintainer rule (Q-7): block ONLY a direct push to a protected
  branch, force pushes included. Everything else proceeds, with a
  warning.** The binary pushes `plan.branch` in every mode
  **[verified, `embo-deliver:340-346`: `git push` or `git push -u origin
  "$BRANCH"`, before the PR section starts at `:358`]**. So "direct push
  to a protected branch" means exactly: `plan.branch` matches the
  protected list, in any of the four modes. That is the refusal, and it
  is the only one.
- Run the check before the reconcile and before any staging, so a
  refusal makes no git change (exit 7 is already documented as "NO git
  changes made"). It must precede `git commit` at `:318`: a refusal after
  the commit would leave a local commit on the protected branch.
- **Permitted with a warning (maintainer-confirmed):** a PR whose `base`
  is protected (`gh pr create --base`); merging the reviewed PR into it
  (`gh pr merge --squash`); `release` mode's `git tag "$TAG"
  "origin/$BASE"` and the tag push (`:463`, `:470`). None is a direct push
  of a branch. The warning is emitted when `plan.base` matches the
  protected list and mode is not `off`.
- **Warning channel for the binary.** `embo-deliver` is not a hook, so
  `additionalContext` does not apply. It writes the warning as lines
  prefixed `embo-deliver: WARNING:` to **stderr**, exactly like its
  existing warnings (`:277-281`, `:315`); the Bash tool returns stderr in
  the call's result, so the agent sees it. Text names the base, the mode
  and what was permitted (`PR into protected base 'main': permitted by
  policy; merge and tag are not blocked`). One line per permitted step
  (PR, merge, tag, tag push). In `mode: off` no warning.
- **Floor**: if the lib, `embo-profile` or `yq` is unavailable, the
  binary falls back to today's hardcoded `main|master` check for `push`
  mode. The change never makes delivery weaker than it is now.
- **The only control is the profile mode**, as in the hook (D-9). The
  binary reads no override variable; an env prefix on its Bash call would
  be agent-controlled anyway. State this in the README.

Why not recognise the wrapper in the hook: the hook would parse the plan
file to learn the branch, duplicating the binary's own plan parser, and
would miss any invocation that bypasses PreToolUse (another editor, a
terminal, another agent). The binary is the single place every path to
the git writes passes through.

**The `git` substring fast path (section 4.1 step 2) is valid only because
of this decision.** It is an optimisation that skips commands which
cannot invoke git. Its stated exceptions are: (1) `embo-deliver`, which
is covered in the binary; (2) the unseen classes already listed under
D-6 (aliases, functions, scripts). Any future shipped wrapper that runs
git internally must be enforced the same way (inside the wrapper) or
added to the hook's name list; a test (V-32) fails if a shipped
`plugin/bin/*` script contains a `git commit`/`git push` and is neither
`embo-deliver` nor listed as exempt.

### D-14 Inline git aliases are resolved, not skipped

`git -c alias.zz=commit zz` makes a blocked subcommand run under a name
the classifier does not know **[measured by `d-critic`: both a commit and
a push path are real]**. Everything in it is literal, so D-6's
unclassifiable net would never engage; the text shows the alias, so the
guard must read it. Rule, applied while skipping global options:

- A `-c <key>=<value>` whose key, compared case-insensitively, starts
  with `alias.` is recorded in a per-invocation alias map.
- The subcommand word is looked up in the map before the blocked-list
  test, repeatedly up to 5 levels (git expands chains; the cap also stops
  loops). The expansion's first word replaces the subcommand and its
  remaining words are prepended to the arguments.
- A value beginning with `!` is a shell alias: the rest is classified
  recursively as a command (D-4), with the original arguments appended.
- `--config-env=alias.<name>=<VAR>` takes its value from the environment,
  which the parser cannot read: the segment is unclassifiable (D-6).
- Persistent aliases from config files (`git config alias.ci commit`) are
  invisible to the guard and remain an opaque hole (D-6), distinct from
  this case, which is visible in the command text.
- Other executable `-c` keys (`core.hooksPath`, `core.editor`,
  `sequence.editor`, `credential.helper`) cannot turn a non-blocked
  subcommand into a commit and are skipped, not treated as unclassifiable.

Lib impact: `bg_classify` carries `BG_ALIASES` (associative-free: a
newline list of `name=value`, since bash 3.2 on macOS has no associative
arrays; **the lib must stay bash 3.2 compatible**, see D-15).

### D-15 Bash 3.2 compatibility

macOS ships `/bin/bash` 3.2. The hook is invoked as `bash` (PATH-resolved,
may be 3.2). The lib therefore avoids associative arrays, `mapfile`,
`${var,,}`, `${var^^}` and `declare -n`; lower-casing uses `tr`. The
tokenizer's parallel arrays (indexed) are fine in 3.2. V-38 runs the
suites under `/bin/bash` on macOS.

### D-12 Fail-open scope is narrow and explicit

Fail open, exit 0 and silent, on: unparseable stdin or missing
`tool_name`; no `jq`; not a git repository; detached HEAD; unborn branch;
`embo-profile` missing, non-zero exit (yq absent exits 3), or unreadable;
unrecognised tool name. **Not** fail-open: an unrecognised *mode value*
(D-3). Unclassifiable Bash (D-6) is not fail-open or refused: it is
allowed with a context warning on a protected branch.

The hook runs `set -u` and `trap 'exit 0' ERR` as `approve-compound.sh`
does; nothing may leak a non-zero status. `embo-profile` is invoked by
explicit path `$HERE/../bin/embo-profile`, not a bare name: a hook does
not depend on the Bash tool's PATH **[provisional]**, and an explicit
path works in manual installs as well. Overridable for tests with
`EMBO_PROFILE_BIN` (as `EMBO_CAPTURE_CMD` is in the sibling).

*Visibility of a silently broken guard* is not solved inside the hook (FR-7
requires silence). Carried as N-2: have `/embo:health` report a missing
`yq`.

## 3. Data contracts

### 3.1 Hook input (stdin)

Fields the hook reads; other fields ignored. State of the evidence:
`tool_input.command` for Bash is documented. `file_path` for `Edit` and
`Write` is evidenced by official examples (a PostToolUse example uses
`${tool_input.file_path}` with matcher `Write|Edit`) but is not in a
published schema. `notebook_path` for `NotebookEdit` and the existence of
`MultiEdit` are **not documented anywhere found**. All are **[provisional]**
and are settled by a schema capture (V-2), not by a teammate. **If an
edit-family call carries no readable path, the hook judges it by the
branch of the stdin `cwd`** (so a wrong field name still protects, instead
of silently disabling `NotebookEdit`); a fixture test covers it.

```json
{
  "session_id": "string",
  "cwd": "/abs/path/of/session",
  "hook_event_name": "PreToolUse",
  "tool_name": "Edit | Write | MultiEdit | NotebookEdit | Bash",
  "tool_input": {
    "file_path": "/abs/or/relative/path",
    "notebook_path": "/abs/path.ipynb",
    "command": "git add -A && git commit -m \"x\""
  }
}
```

Extraction (all `jq -r`, each with `// empty`):
`.tool_name`, `.cwd`, `.tool_input.file_path // .tool_input.notebook_path`,
`.tool_input.command`. A relative `file_path` is resolved against `cwd`.

### 3.2 Hook output (stdout, exit 0 always)

Deny:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse",
  "permissionDecision":"deny",
  "permissionDecisionReason":"embo branch-guard: <what> refused on protected branch 'main' (protected_branches: main master; mode: block). <remedy>"}}
```

Warn:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse",
  "additionalContext":"embo branch-guard warning: <what> on protected branch 'main' ..."}}
```

Silence is empty stdout. The `embo branch-guard:` prefix is on every
denial and distinguishes it from an ordinary permission prompt (FR-6).

Reason text, by case (the `<remedy>` is the part the agent acts on):

| Case | Text after the prefix |
|---|---|
| edit | `editing <relpath> refused on protected branch '<b>'. Create a feature branch first: git switch -c <name>.` |
| commit | `git commit refused on protected branch '<b>'. Create a feature branch first (git switch -c <name>), then commit there.` |
| push, HEAD protected | `git push refused: '<b>' is protected. Push a feature branch and open a pull request.` |
| push, destination protected | `git push refused: destination '<dst>' is protected. Push your feature branch and open a pull request.` |
| force push | `force push to protected branch '<dst>' refused.` (distinct wording naming the force flag) |
| unclassifiable (a warning in `additionalContext`, never a denial; D-6) | `embo branch-guard warning: could not analyse this command on protected branch '<b>'; if it runs git commit or git push it is not blocked.` |

### 3.3 Profile fields

| Key | Type | Default (hook, when absent) | Default (shipped YAML) |
|---|---|---|---|
| `rules.workflow.protected_branches` | list of name/glob | `[main, master]` | `[main, master]` |
| `rules.workflow.protected_branch_mode` | `block\|warn\|off` | `block` | `block` |

Both keys are added, commented in the surrounding style, to
`default.yaml`, `quality.yaml`, `fast.yaml`, `minimal.yaml`,
`research.yaml`. Reads: two `embo-profile get` calls, in the order list
then mode, each only after the cheaper checks passed (section 6).

### 3.4 Environment

| Variable | Read by | Meaning |
|---|---|---|
| `EMBO_PROFILE_BIN` | hook | Test seam: path of the `embo-profile` to call. Default `$HERE/../bin/embo-profile`. |
| `EMBO_PROFILE_ACTIVE`, `EMBO_PROFILE_DIRS` | `embo-profile` | Existing test seams, passed through. |

### 3.5 Library: `plugin/lib/branch-guard-lib.sh`

Convention (as `branch-task-lib.sh`): sourced, no top-level output, no
`exit`. Functions return via stdout or the globals named. Prefix `bg_`.

```bash
BG_BLOCKED_SUBCOMMANDS="commit push"      # data, D-7

# --- policy helpers -------------------------------------------------
bg_parse_list <text>                       # stdout: one name/glob per line.
                                           # Accepts "[a, b]", "- a\n- b", "a b", quoted items.
                                           # "[]" -> no output.
bg_is_protected <branch> <patterns>        # rc 0 if <branch> matches any pattern
                                           # (patterns: newline-separated; case-glob).
bg_normalize_mode <raw>                    # stdout: block|warn|off. Invalid/empty-as-invalid
                                           # -> "block" and BG_MODE_INVALID=1. (Caller treats
                                           # an *absent* value as "block" without flagging.)
bg_local_protected_exists <dir> <patterns> # rc 0 if any local branch matches (one for-each-ref).

# --- git resolution -------------------------------------------------
bg_branch_of <dir> [git-global-arg ...]    # stdout: current branch short name.
                                           # rc 1 and no output when not a repo, detached,
                                           # or unborn (all fail-open cases, D-8).
bg_is_ignored <file>                       # rc 0 if `git check-ignore -q` says ignored.
bg_push_target <dir> [git-global-arg ...]  # stdout: branch part of @{push}; empty if
                                           # unresolvable (caller falls back to HEAD).

# --- Bash command analysis (pure, no subprocess) ---------------------
bg_decode_capture_wrapper <command>        # stdout: decoded inner command if <command> is an
                                           # embo-capture wrapper call, else <command> unchanged.
bg_tokenize <command>                      # rc 0 ok / 1 parse error. Fills:
                                           #   BG_TOK_KIND[]  W word | S separator | O "(" | C ")" | R redirect
                                           #   BG_TOK_VAL[]   word value, quotes removed
                                           #   BG_TOK_DYN[]   1 if the word holds an unquoted/
                                           #                  double-quoted $ or backtick expansion
                                           #   BG_SUBS[]      bodies of $(..), `..`, <(..), >(..),
                                           #                  and unquoted-heredoc expansions
bg_classify <command> <dir> <depth>        # appends to BG_FINDINGS (see below); recurses into
                                           # BG_SUBS, bash/sh/zsh -c strings, eval of literals.
bg_decide <findings> <mode> <patterns> <head-branch>
                                           # stdout: one of  deny:<reason> | warn:<text> | allow
                                           # (pure: given findings already resolved by the caller).

# --- output ---------------------------------------------------------
bg_deny_json <reason>                      # stdout: the deny document (jq -n --arg)
bg_context_json <text>                     # stdout: the additionalContext document
```

`BG_FINDINGS` is a newline-separated list of tab-separated records:

```
commit    <dir>  <ctx>                              # one git commit
push      <dir>  <ctx>  <force 0|1>  <dest-list>    # dest-list: comma-separated branches,
                                                    # or the tokens @HEAD @ALL @BARE
unclass   <dir>  <reason>                           # D-6
```

`<ctx>` is the space-joined replayable git global args
(`-C /p --git-dir=/g`). Edits do not go through `bg_classify`.

## 4. The Bash command-parsing problem

### 4.1 Algorithm

1. `bg_decode_capture_wrapper` (D-10).
2. Cheap exit: command has no `git` (case-insensitive) -> exit 0. This
   is an optimisation, valid only with the exceptions in D-13
   (`embo-deliver` is enforced in the binary; the opaque classes are in
   D-6).
3. `bg_tokenize` (state machine below).
4. Split the token stream at separators into segments; parentheses push
   and pop the tracked directory.
5. Per segment: drop leading reserved words (`if then elif else do while
   until ! { }`); drop redirect operators and their target word; strip
   env assignments (`NAME=val`, remembering `GIT_DIR`/`GIT_WORK_TREE`);
   strip wrappers (table below); then act on the first word.
6. First word (after path stripping, `/usr/bin/git` -> `git`):
   - `cd <literal>`: move tracked directory. `cd` dynamic: ignored.
   - `git`: parse global options, find subcommand, dispatch (4.3).
   - `bash|sh|zsh|dash|ksh` with a `-c` cluster: the next word, if
     literal, is classified recursively; if dynamic, unclassifiable.
   - `eval`: join the remaining words; classify recursively if all are
     literal, else unclassifiable.
   - `xargs`, `parallel`, `find` (with `-exec`/`-execdir`): unclassifiable
     if any later word is `git` (path-stripped); otherwise benign.
   - dynamic first word (`$X ...`): unclassifiable.
   - anything else: benign (`echo`, `ls`, a script path).
7. Recurse into every `BG_SUBS` body with the tracked directory at the
   point of occurrence.

State machine for `bg_tokenize`: normal, in `'...'` (no escapes, no
expansion), in `"..."` (backslash escapes `" \ $ \``; `$(`, `` ` `` are
expansions), after backslash. Separators in normal state only: `&&`,
`||`, `;`, `|`, `|&`, newline, `&`. The `&` of `>&N`, `N>&M`, `&>` is a
redirect, not a separator. `(` and `)` in normal state are `O`/`C`
unless they belong to `$(`, `<(`, `>(`. A heredoc operator `<<`, `<<-`
followed by a delimiter word ends the current line's tokenisation of the
body: the body, up to the line equal to the delimiter (leading tabs
stripped for `<<-`), is skipped if the delimiter was quoted (`<<'EOF'`,
`<<"EOF"`, `<<\EOF`), or scanned for `$(...)`/backtick bodies only if
unquoted. `<<<` is a redirect with a word target.

### 4.2 Wrappers stripped before the command word

| Wrapper | Handling |
|---|---|
| `env`, `env -i`, `env -u NAME`, `env NAME=v` | options and assignments removed |
| `command`, `exec`, `builtin`, `nohup`, `time` | word removed |
| `nice [-n N]`, `stdbuf -o L`, `setsid` | options removed |
| `timeout [opts] DURATION` | options and duration removed |
| `sudo [-u U] [-E] [--]`, `doas` | options removed |
| leading backslash (`\git`) | removed |

Unrecognised option shape after a wrapper: the segment is treated as
unclassifiable (D-6), not guessed.

### 4.3 Shapes the classifier must recognise, and the outcome

Branch column: where the protected branch is `main`. "Refused" means
`deny` in `block` mode; the same rows produce a warning in `warn` mode.

| # | Command shape | On `main` | On `feat/x` | Notes |
|---|---|---|---|---|
| 1 | `git commit -m "x"` | refused | allowed | FR-2 |
| 2 | `git add -A && git commit -m x` | refused | allowed | each segment judged |
| 3 | `git add . ; git status; git commit -am x` | refused | allowed | `;` separator |
| 4 | `git status \| git commit` / `a \|\| git commit` / `(cd d && git commit)` | refused | allowed | `\|`, `\|\|`, parens |
| 5 | `git commit -m "fix; git commit later"` | refused (first segment) | allowed | `;` inside quotes is not a separator; one commit, not two |
| 6 | `echo "git commit"` | allowed | allowed | quoted text, head is `echo` |
| 7 | `git log --grep commit`, `git show HEAD`, `git status` | allowed | allowed | subcommand is not blocked (FR-2) |
| 8 | `FOO=1 BAR=2 git commit -m x` | refused | allowed | env prefixes stripped |
| 9 | `GIT_DIR=/r/.git git commit` | judged on `/r` | judged on `/r` | context replayed to branch lookup |
| 10 | `FOO=1 git commit` and any other in-command assignment | refused | allowed | nothing in the command text can disable the guard (D-9) |
| 11 | `git -C /other/repo commit -m x` | judged on `/other/repo` | judged on `/other/repo` | `-C` moves the governing dir |
| 12 | `git -c user.name=a -c core.x=y commit -m x` | refused | allowed | `-c k=v` skipped (takes one arg) |
| 12a | `git -c alias.zz=commit zz -m x`, `git -c alias.pp=push pp origin main`, `git -c 'alias.x=!git commit -m y' x` | refused | allowed | inline aliases are resolved (D-14) |
| 12b | `git --config-env=alias.zz=VAR zz` | unclassifiable | allowed | value comes from the environment (D-14) |
| 13 | `git --no-pager commit`, `git -p commit`, `git --git-dir=g --work-tree=w commit` | refused | allowed | global options skipped |
| 14 | `/usr/bin/git commit`, `\git commit`, `command git commit`, `exec git commit` | refused | allowed | path/wrapper stripped |
| 15 | `cd /repo && git commit` | judged on `/repo` | judged on `/repo` | literal `cd` tracked; `cd "$X" && git commit`: judged on the pre-`cd` dir (stated limit) |
| 16 | `bash -c 'git commit -m x'`, `sh -lc "git commit -m x"` | refused | allowed | literal `-c` string recursed |
| 17 | `bash -c "$CMD"`, `eval "$CMD"` | unclassifiable: **allowed**, with a context warning if the text contains `git` | allowed, no warning | D-6 |
| 18 | `eval 'git commit -m x'` | refused | allowed | literal eval recursed |
| 18a | `git commit -F tmp/msg.txt`, `git commit --file=tmp/msg.txt`, `git commit -F tmp/msg.txt && git push` | refused | allowed | **the instructed shape** (D-16): plain words, fully classifiable |
| 19 | `git commit -m "$(cat <<'EOF'\nmsg\nEOF\n)"` | refused | allowed | no longer instructed, but an agent can still write it: the commit is top-level and found; the `$()` body is classified too and is benign |
| 20 | `git commit -F - <<'EOF'\nmsg\nEOF` | refused | allowed | heredoc body skipped |
| 21 | `cat <<EOF\n$(git commit -m x)\nEOF` | refused | allowed | unquoted heredoc: expansion body classified |
| 22 | `echo $(git commit -m x)`, `` echo `git commit -m x` `` | refused | allowed | substitution bodies recursed |
| 23 | `diff <(git commit) x` | refused | allowed | process substitution recursed |
| 24 | `git commit -m x > out.log 2>&1` | refused | allowed | redirects dropped, `&` of `2>&1` is not a separator |
| 25 | `git commit -m x &` | refused | allowed | trailing `&` is a separator |
| 26 | `git commit --dry-run` | allowed | allowed | D-11 |
| 27 | `git push` / `git push origin` | refused (HEAD protected) | refused only if `@{push}` resolves to a protected branch | D-11 |
| 28 | `git push origin main` | refused | refused | destination judged, not HEAD (PRD D-7) |
| 29 | `git push origin feat/x` | allowed | allowed | explicit destination is not protected; see note below |
| 30 | `git push origin HEAD` | refused | allowed | `HEAD` = current branch |
| 31 | `git push origin HEAD:main`, `HEAD:refs/heads/main` | refused | refused | dest after `:`, `refs/heads/` stripped |
| 32 | `git push origin feat/x:main`, `+feat/x:main` | refused | refused | leading `+` = force, dest `main` |
| 33 | `git push origin :main`, `git push --delete origin main`, `git push -d origin main` | refused | refused | delete = destination `main` |
| 34 | `git push origin main:feat/x` | allowed | allowed | destination `feat/x` is not protected; the source is irrelevant |
| 35 | `git push --all`, `git push --mirror origin` | refused if a protected branch exists locally | same | pushes every local branch |
| 36 | `git push --force origin main`, `-f`, `--force-with-lease`, `-fu` | refused, force text | refused, force text | distinct reason |
| 37 | `git push --force origin feat/x` on `feat/x` | allowed | allowed | not this guard's concern |
| 38 | `git push --dry-run origin main`, `-n` | allowed | allowed | D-11 |
| 39 | `git push -o ci.skip origin main` | refused | refused | `-o` takes an argument; it is skipped |
| 40 | `git push origin "$BR"`, `git push $REMOTE` | unclassifiable: **allowed** + warning | allowed, no warning | dynamic destination; accepted hole (D-6) |
| 41 | `git $SUB`, `$G commit` | unclassifiable: allowed + warning | allowed | D-6 |
| 42 | `xargs -n1 git push` | unclassifiable: allowed + warning | allowed | D-6 |
| 43 | unbalanced quote or paren | unclassifiable | allowed | parse error |
| 44 | `./release.sh`, `make deploy`, alias `gp` | allowed | allowed | opaque by design (D-6 holes) |
| 45 | Tokenizer cap: > 5 recursion levels | unclassifiable | allowed | |

Note on rows 29 and 34: for an *explicit refspec* only the destination
matters. On `main`, `git push origin feat/x` has destination `feat/x`,
which is not protected, so the push guard allows it; the commit guard is
what stops commits being made on `main` in the first place. Only the
**bare** forms (row 27) consult HEAD, because there the destination is
derived from HEAD and its upstream. `git push origin HEAD` (row 30)
resolves `HEAD` to the current branch, so it is refused on `main`. V-14
asserts rows 29 and 34 explicitly. Unclassifiable rows (17, 40-43, 45)
are allowed; on a protected branch with `git` in the text they carry a
context warning, otherwise they are silent (`eval "$(ssh-agent)"`).

### 4.4 What happens to what cannot be parsed

Repeated from D-6 so a reader of this section does not have to look:
an unclassifiable command is **always allowed**. On a protected branch,
when the text contains `git`, the hook adds a context warning that the
command could not be analysed; in every other case it is silent.

## 5. Components and files

| File | Change |
|---|---|
| `plugin/hooks/branch-guard.sh` | new; dispatch, I/O, fail-open, decision |
| `plugin/lib/branch-guard-lib.sh` | new; section 3.5 |
| `plugin/hooks/branch-guard.test.sh` | new; fixture tests of the hook end to end |
| `plugin/lib/branch-guard-lib.test.sh` | new; unit tests of the classifier (rows of 4.3), list/mode helpers |
| `plugin/bin/embo-deliver` | replace hardcoded `is_protected` with the policy check on `plan.branch` (the pushed branch), all modes, before any git change; stderr warnings for protected `base` steps (D-13) |
| `plugin/bin/embo-deliver.test.sh` | cases: protected `branch` refused in each of the four modes with no git change; protected `base` in `pr`/`pr-merge`/`release` proceeds with stderr warnings; mode `off` and `warn`; floor when `embo-profile` is stubbed to fail |
| `plugin/commands/git.md` | commit instruction becomes write-message-to-`tmp/`-file then `git commit -F <file>` (D-16); no task references |
| `plugin/hooks/hooks.json` | new PreToolUse entry (matcher D-5) after the `approve-compound` entry; `description` mentions the guard |
| `plugin/profiles/{default,quality,fast,minimal,research}.yaml` | add the two keys with comments |
| `CLAUDE.md` (repo) Safety Rules | one short note pointing at the hook |
| `README.md` | profile field table row; how to do a deliberate one-off commit (set the mode to `off`, revert afterwards); where-it-does-not-reach list |

`hooks.json` entry:

```json
{
  "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash",
  "hooks": [
    { "type": "command",
      "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/branch-guard.sh\"" }
  ]
}
```

Shipped files (`plugin/**`) carry no task numbers and no `tasks/` paths;
header comments say what the code does in plain terms. The repo
`CLAUDE.md` note also has none (FR-11).

## 6. Runtime order and cost (NFR-1)

Edit family: stdin parse (`jq`) -> branch of the file's repo (1 `git`)
-> `get protected_branches` (1 `yq`) -> not protected: exit. Protected:
`get mode` (1 `yq`), `check-ignore` (1 `git`), then decide. A feature-
branch edit costs one `jq`, one `git`, one `yq`.

Bash: `jq`, then a pure-Bash substring test. No `git`: exit with no
other process. With `git`: pure-Bash parse; if no commit/push/
unclassifiable record, exit. Otherwise branch lookup, list, mode as
above; a bare push adds one `rev-parse @{push}`; `--all` adds one
`for-each-ref`.

## 7. Resolution of the PRD's open questions

| Q | Status | Resolution |
|---|---|---|
| Q-1 and its residual | **Decided by the maintainer** (two separate decisions) | Change the instructed commit to `git commit -F <file>` (D-16); unclassifiable commands are allowed with a warning on a protected branch, never refused (D-6). My earlier recommendation is withdrawn. |
| Q-2 | Resolved | D-2: sibling keys; `embo-profile get` returns flow lists verbatim (`[a, b]`, verified), block lists as lines; absent = default; `[]` = none. |
| Q-3 / Q-9 | **Decided by the maintainer** | No override variable. The profile mode is the only control (D-9); a deliberate one-off commit means editing the profile and reverting it. The environment-variable route, its delivery question (N-4) and its verification (V-15) are removed. |
| Q-10 | Open, live check | Warn mode's `additionalContext` on PreToolUse is honoured and reaches the model (V-11). One of the two checks that decide whether the feature works, with Q-5. **If it fails, two behaviours degrade silently:** `warn` mode becomes `off`-equivalent, and the unclassifiable-command warning (D-6) disappears, leaving allow-with-no-warning. |
| Q-4 | Resolved | D-5: list all four edit tools; inert if absent. Which exist is **[provisional]** and does not change the string. |
| Q-5 | **Open, decides whether the feature works** | Does a plugin-registered PreToolUse hook fire for subagent tool calls? Not documented: only that `agent_id` is "present when the hook fires inside a subagent" (implies hooks fire there), and that plugin hooks "merge with your user and project hooks"; nothing connects a plugin's `hooks.json` to subagent tool calls. The guard ignores `agent_id`/`agent_type` (a subagent, if reached, is judged identically). **Consequence if plugin hooks do not reach subagents: the guard protects the main session only, and every spawned agent bypasses it.** In a plugin that delegates as much as this one, that is large enough to question shipping the feature in this form. Settled by V-19, a priority live check. |
| Q-7 | **Decided by the maintainer** | Enforce inside `embo-deliver` (D-13) with the floor; block only a direct push of a protected branch (force included); PR into, merge into, tag of, and tag push on a protected branch proceed with warnings on stderr. |
| Q-6 | Resolved | Hook precedence `deny` > `defer` > `ask` > `allow`, parallel execution (D-10); a separate hook file is sound and no fallback is needed. |

New questions raised:

- **N-1** (resolved, D-7) `cherry-pick`, `revert`, `am` are blocked;
  FR-2 to be amended.
- **N-4** (closed by Q-9) The override variable and the question of how
  a plugin would deliver it are removed; no investigation task is needed.
- **Q-8** (decided by the maintainer) The `embo-deliver` refusal happens
  before the commit, not at the push: no commit lands on a protected
  branch (D-13).
- **N-2** A guard silently off because `yq` is missing (FR-7) is invisible.
  Should `/embo:health` check for it?
- **N-3** Invalid mode is reported only when the guard fires (D-3). Is a
  SessionStart report wanted?

## 8. Verification table

Methods: **FT** fixture test (`branch-guard.test.sh`, throwaway repos),
**UT** unit test (`branch-guard-lib.test.sh`), **CI** code inspection,
**LR** live run in a real Claude Code session.

| ID | Requirement | Verification |
|---|---|---|
| V-1 | FR-1 edit denied on `main`, file unchanged | FT: pipe `Edit` JSON on `main`; assert deny JSON; LR: ask the agent to edit on `main`, `git diff` empty |
| V-2 | FR-1 `Write`, `NotebookEdit` (and `MultiEdit`) denied; real field names | FT: one case per tool name, plus a case with no readable path (judged by `cwd`, denied on `main`); CI: matcher string; LR schema check without any throwaway script: trigger each tool on `main` in a real session; the denial text names the file path the hook extracted, so a denial naming the file proves the field name, and a denial naming only the branch exposes a wrong one; `/hooks` shows the entry. Whether `MultiEdit` exists is read from the session's tool list |
| V-3 | FR-1 non-protected branch: no output | FT: assert empty stdout, exit 0 |
| V-4 | FR-1 reason names branch and remedy | FT: assert substrings `'main'` and `git switch -c` |
| V-5 | FR-1 gitignored path allowed; path outside any repo allowed | FT: `tmp/x` ignored; `/tmp/otherdir/file`; edit in a second repo on `main` while cwd is a feature repo is denied |
| V-6 | FR-2 commit denied; compound denied; word "commit" in `log --grep commit`/`echo` allowed | UT rows 1-7, 19-25; FT end to end for rows 1, 2, 7; LR: `git commit` on `main`, `git log` shows no new commit |
| V-7 | FR-3 bare push denied on `main`; `push origin main` denied from `feat/x`; `push origin feat/x` allowed on `feat/x`; force distinct text | UT rows 27-39; FT rows 27, 28, 36 (assert the word `force`); LR: replay push |
| V-8 | FR-3 `@{push}` resolution | FT: repo with upstream `origin/main` set on a bare local remote; push target resolution asserted |
| V-9 | FR-4 field exists in default.yaml; `get` returns it; `develop` added -> denied; commented style | FT: set `EMBO_PROFILE_ACTIVE` to fixtures; CI: diff of `default.yaml` |
| V-10 | FR-4 shipped non-default profiles carry the keys | FT: loop `embo-profile get` over the five profiles via `EMBO_PROFILE_DIRS` and assert both keys non-empty |
| V-11 | FR-5 `block`/`warn`/`off`; invalid -> block + report | FT: four cases; assert `warn` output has `additionalContext` and no `permissionDecision`; `off` empty; `blok` denies with `unrecognised` |
| V-12 | FR-6 reason non-empty, prefixed `embo branch-guard:` | FT: every deny case asserts the prefix and non-empty remedy |
| V-13 | FR-7 fail-open cases | FT: non-repo dir; detached HEAD; unborn branch; `EMBO_PROFILE_BIN` stub that exits 3; stdin `not json`; empty stdin; unknown tool. Each asserts empty stdout, exit 0 |
| V-14 | Table 4.3 rows 29 and 34 behave as corrected in the note | UT: both rows asserted explicitly |
| V-15 | FR-8 (as revised: the profile mode is the only control; no override variable) | FT: `off` and `warn` modes change the outcome with no restart (profile edited between two calls); nothing in the command text (`FOO=1 git commit`, `EMBO_ALLOW_PROTECTED_BRANCH=1 git commit`) changes the outcome; retry of a denied call is denied identically (call twice, equal output) |
| V-16 | FR-9 suite has cases for every listed item, uses throwaway repos, non-zero assertion count, independent of the branch the suite runs from | CI + running the suite from this worktree (branch `feat/teammates`) and from a detached checkout; assert `PASS > 0` footer |
| V-17 | FR-10 registered; `approve-compound` entry intact; description updated | CI on `hooks.json`; `jq` validity; existing `approve-compound.test.sh` still passes; LR: a compound allow-listed command is still auto-approved and wrapped while the guard is registered |
| V-18 | D-10 deny outranks allow; guard sees the unwrapped command | LR: `git add -A && git commit` on `main` (allow-listed by `approve-compound`) is still denied; FT: wrapper-decode case |
| V-19 | **Priority.** Q-5: a plugin-registered hook fires for subagent tool calls (one of two checks that decide whether the feature works at all, with warn-mode `additionalContext`, V-11) | LR: with the plugin installed, spawn a subagent on `main`, have it try `git commit` and an `Edit`; observe two denials. If it does not fire, escalate to the maintainer before any further work |
| V-20 | FR-11 note exists, has no `tasks/` | CI: read the note; `jq`-free string check by reviewer |
| V-21 | NFR-1 cost: non-git Bash costs no `git`/`yq` | FT: put stub `git`, `yq` on PATH that record calls; run `ls -la` and `git status`; assert no `yq` call and, for `ls`, no `git` call |
| V-22 | NFR-2 no new dependency | CI: the hook and lib call only `bash`, `jq`, `git`, `base64`, `embo-profile` |
| V-23 | NFR-3 stateless | CI: no file writes in hook or lib; FT: same input twice yields identical output |
| V-24 | NFR-4 worktree-correct | FT: create a worktree with `git worktree add`; main checkout on `main`, worktree on `feat/x`; edit a main-checkout path with cwd in the worktree -> denied; edit a worktree path -> allowed |
| V-25 | D-8 unborn branch | FT: fresh `git init -b main`, first commit allowed |
| V-26 | Success criterion 5: originating incident replay | LR: on `main`, edit changelog, `git commit`, `git push`; blocked at the first edit (and at the commit if the edit is made through Bash) |
| V-27 | D-6 unclassifiable is allowed, never refused | UT rows 17, 40-43, 45 on `main`: output has no `permissionDecision`, has a warning in `additionalContext` iff the text contains `git`; on `feat/x`: empty output; a `main` case with no `git` substring: empty output |
| V-28 | D-4 no false positive on quoted separators | UT rows 5, 6 |
| V-29 | FR-3a delivery path refuses a direct push of a protected `plan.branch`, in all four modes, with no commit/push/tag/PR/merge | `embo-deliver.test.sh` against throwaway repos with `git`/`gh` stubs that record calls; assert exit 7, reason names branch and policy, stub call log empty, HEAD unchanged |
| V-30 | FR-3a PR into, merge into, tag of and tag push on a protected base **proceed with a warning** | same suite: `branch: feat/x`, `base: main`, modes `pr`, `pr-merge`, `release`: exit 0, stub log shows `gh pr create`, `gh pr merge`, `git tag`, tag push; stderr contains `embo-deliver: WARNING:` naming `main` once per permitted step |
| V-31 | FR-3a policy `off` and `warn`; floor | same suite: `off` no check and no warning; `warn` on a protected `plan.branch` warns and proceeds; a stubbed failing `embo-profile` still refuses `push` mode to `main` |
| V-32 | No shipped `plugin/bin/*` runs git writes unguarded (fast-path exception list, D-13) | CI/test: scan `plugin/bin/*` for `git commit`/`git push`; fail unless the file is `embo-deliver` or in the test's exemption list |
| V-33 | FR-2 load-bearing: the commit shape the shipped command file instructs is refused on `main`, allowed on a feature branch | after D-16, the instructed shape is `git commit -F tmp/<file>`: UT row 18a; FT end to end; a test extracts the commit line from `plugin/commands/git.md` and feeds it to the classifier, so the test follows the file if the instruction changes; LR: the shipped instructions run on `main` (the `tmp/` Write is allowed, the commit refused). Row 19 (heredoc) stays as a regression row, not as the load-bearing one |
| V-34 | `git commit --help`/`-h`, `cherry-pick --abort` are not refused | UT |
| V-35 | D-11 slashed branch on the push path | UT/FT: repo whose upstream is `origin/release/1.2`, pattern `release/*`, bare `git push` from `release/1.2` and from a feature branch with that upstream: refused; upstream `origin/feat/a`: allowed; a remote not named `origin` |
| V-36 | D-8 `check-ignore` exit 128 | FT: edit of a path outside any repo and of an ignored path in a repo: no error, correct decision, empty stderr |
| V-37 | FR-9 a test goes through the registered configuration, not only the script | FT: read `plugin/hooks/hooks.json` with `jq`, select the PreToolUse entry whose command names `branch-guard.sh`, assert its matcher string equals D-5's and contains each of the five tool names, then run the entry's own `command` string with `CLAUDE_PLUGIN_ROOT` set to `plugin/` and a deny-case stdin, asserting the deny JSON. A wrong path, matcher or quoting in `hooks.json` fails this test |
| V-38 | D-14 inline alias bypass closed; D-15 bash 3.2 | UT rows 12a, 12b on `main` (refused) and `feat/x` (allowed), including alias chains and a `!` shell alias; run both suites under `/bin/bash` and a newer bash where available |
| V-39 | D-12 hook works without the plugin `bin/` on PATH; detached HEAD yields no branch | FT: run the hook under `env PATH=<dir with only jq, git, yq, bash>` (precedent: the subagent-rules test uses `env PATH=/nonexistent`) and assert the correct decision; detached HEAD: `bg_branch_of` returns rc 1 (it uses `symbolic-ref -q`, which prints nothing and exits 1 there, **[measured by `d-researcher`]**; `rev-parse --abbrev-ref HEAD` would print the literal `HEAD` and is not used; a result of the literal `HEAD` is also treated as no branch) |
| V-40 | D-16 the shipped file contains no `git commit -m "$(cat` shape and no task reference | CI: string check on `plugin/commands/git.md` |

## 9. Risks

- **Parser errors are the main risk.** A bug yields either a false
  denial (obstruction on `main` only) or a missed commit. Mitigation: the
  table is the spec, every row is a UT, and the failure mode of a parser
  crash is fail-open (D-12), never a block.
- **Provisional harness facts** (D-5, D-9, D-10, V-19) are each backed by
  a live run in the verification table rather than trusted.
- **`yq` flow-style dependency** for list parsing: covered by V-9/V-10
  with both list styles.
