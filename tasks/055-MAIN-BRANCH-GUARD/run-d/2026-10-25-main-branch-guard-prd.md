# PRD — Protected-branch guard

**Task**: 055-MAIN-BRANCH-GUARD
**Status**: Draft for technical design
**Source seed**: `tasks/055-MAIN-BRANCH-GUARD/SEED.md`

## 1. Problem

Nothing in the workflow stops the agent from editing, committing, or
pushing while a protected branch (`main`/`master`) is checked out. The
originating incident: the agent committed a changelog fix directly onto
local `main` and tried to push it, on a repo whose `main` is protected.
The push was rejected; the work had to be redone onto a branch.

A CLAUDE.md sentence was considered and rejected. The agent violated the
rule *after being reminded of it*, which is the evidence this project
treats as decisive: a rule that exists only as prose is unreliable under
load. Per the repository's core principle ("Enforce, Don't Ask"), the
correct response to a repeated violation is a deterministic mechanism
that fails loudly, not more prose.

## 2. Goal

A PreToolUse hook that blocks file edits, commits, and pushes while a
protected branch is checked out, with its branch list and severity read
from the active embo profile. The agent cannot proceed by forgetting the
rule; it must branch first, or the action fails with an explicit reason.

**What this is not**: a complete seal. The guard stops the agent from
*authoring* new work on a protected branch through the paths the
workflow instructs. It does not block every route by which a commit
could reach such a branch — `git merge --no-ff`, `pull` and `rebase`
are deliberately permitted, plumbing (`commit-tree` + `update-ref`) can
advance a protected branch outright, a Bash call that writes a file
bypasses the edit guard, and an obfuscated command can hide a commit.
Each limit is stated in §7 with its reason. Read the mechanism's claims as bounded,
because the honest bound is what makes the rest trustworthy.

## 3. Users

| User | Need |
|---|---|
| The agent (primary) | Be stopped before producing work that lands on, or is rejected from, a protected branch. |
| The repository maintainer | Set the policy once in a profile; no per-session reminding. |
| A user of a repo with no protected branches | Not be obstructed — the guard must be configurable off, and must not fire where it does not apply. |

## 4. Functional requirements

### FR-1 — Block edits to files while on a protected branch

The guard registers on PreToolUse for the file-writing tools and returns
a `deny` decision when the current branch is protected.

**The governing branch is that of the repository containing the TARGET
FILE**, resolved by running git against the target path's directory —
not the session's working directory. A session in a feature worktree
that edits a path inside the main checkout must be denied, because the
edit lands on the main checkout's protected branch. See NFR-4.

**Acceptance criteria**
- With `main` checked out and policy `block`, an `Edit` call on a file
  in that repository **that git does not ignore** is denied; the file on
  disk is unchanged afterwards. The ignored-path exception below is part
  of this criterion, not a later qualification of it.
- The same for `Write` and `NotebookEdit`.
- With a non-protected branch checked out, the identical `Edit` call is
  permitted and the hook emits no decision.
- **A session in a feature worktree editing a path inside the main
  checkout (on a protected branch) is denied**, even though the
  session's own branch is not protected.
- **A gitignored path is permitted** — a path for which `git
  check-ignore -q` exits 0. An ignored file cannot enter the branch's
  history, which is what the guard protects. **The carve-out is broader
  than `tmp/`**: it also permits editing `.claude/settings.local.json`,
  a local `.env`, or any other ignored config while on a protected
  branch. That is intended, for the same reason, and is stated here
  rather than left as a design-level surprise. Raised by d-critic and
  d-techdesign.
- **A path outside any git repository is permitted** (for example
  `~/.claude/...`) — there is no branch to protect.
- The denial reason text names the branch and states the remedy
  ("`main` is protected — create a feature branch first").

**Note on tool coverage**: the matcher must enumerate the write tools by
name. `MultiEdit` and `NotebookEdit` appear nowhere in this plugin
today, so the design must state the exact matcher string and which tool
names it resolves to, rather than assume a family. A matcher of `Edit.*`
would also catch `NotebookEdit` but not `Write`; see D-5.

### FR-2 — Block `git commit` while on a protected branch

The guard must detect `git commit` **in the shape this plugin actually
instructs**, not only in a simple form. `plugin/commands/git.md:239`
tells the agent to run:

```
git commit -m "$(cat <<'EOF' ... EOF)"
```

That string contains both `$(` and `<<`, which are exactly the
constructs `approve-compound.sh:12-15` bails on. A guard that reuses
that parsing approach and fails open on unanalysable commands would let
this plugin's own default commit shape through on a protected branch.
**Resolved (Q-1, maintainer decision): `git.md:239` changes to the `-F
<file>` form.** The instructed shape becomes: write the message to a
temp file under `tmp/`, then `git commit -F <file>`. The guard is *not*
given a rule for refusing unanalysable commands.

The reasoning, which went against the team's own recommendation: a
refuse-unanalysable rule buys a one-time saving (not editing a shipped
file) at the cost of permanent false positives across a whole class of
legitimate commands — `git log --oneline $(git merge-base ...)` on
`main` would be refused forever. Fixing the shape at the source makes
every commit mechanically visible with no false positives. That is the
"Enforce, Don't Ask" move: make the correct thing checkable rather than
teach a parser to cope with an awkward one.

Consequences:
- The message temp file lands under `tmp/`, which the FR-1 gitignore
  carve-out already permits, so writing it on a protected branch is not
  itself blocked.
- **Editing `plugin/commands/git.md` is now in scope** and needs its own
  subtask; it was previously excluded as a shipped-file change.
- **Unanalysable commands that are not the instructed shape are
  PERMITTED, by decision (D-11a).** A command containing `$(...)`,
  backticks, `<(...)` or a heredoc whose `git commit`/`git push` token
  the guard cannot resolve is **allowed** — no refusal, no warning.
  This is a maintainer decision with its own reasoning, not a
  consequence of having rejected the refuse rule, and it is a stated
  accepted gap rather than an oversight (§7.3). The guard's coverage of
  commits rests on the instructed shape being analysable, not on
  defeating deliberate obfuscation.

**Acceptance criteria**
- A `Bash` call using the **new instructed shape** `git commit -F
  <file>` is denied while on a protected branch; `git log` shows no new
  commit. **This is the load-bearing criterion**, because this is the
  shape the workflow will actually produce after Q-1's change.
- A `Bash` call using the **old** `git commit -m "$(cat <<'EOF' ...
  EOF)"` shape is permitted-but-unguarded, and that is accepted: the
  shape is being removed rather than parsed. A test asserting it is
  *denied* would encode a guarantee the design does not make. If
  `git.md` has not yet been changed, the guard does not cover the
  instructed commit — so the `git.md` edit is a prerequisite, not a
  follow-up.
- A `Bash` call whose command is `git commit -m "x"` is denied while on
  a protected branch.
- The guard inspects every subcommand of a compound command: `git add -A
  && git commit -m "x"` is denied as a whole.
- `git commit` on a non-protected branch is not denied by this guard.
- A command that merely contains the word "commit" without invoking it
  (for example `git log --grep commit`) is not denied.
- **The blocked set is the subcommands whose PURPOSE is to create a
  commit**: `commit`, `cherry-pick`, `revert`, `am`.

  This is deliberately **not** "every way a commit can land on a
  protected branch", and the PRD must not be read that way. Measured
  counterexample from d-critic: `git merge --no-ff` writes a two-parent
  commit on `main`, and `git pull` with merge semantics and `git rebase`
  can also write commits. All three are **deliberately allowed** — see
  the limit in §7.6.
- **`merge`, `pull`, `rebase` and `reset` are not denied** by this
  requirement — they are out of scope (§6). Blocking them would stop
  ordinary legitimate work such as updating a local protected branch
  from its remote, which is the common reason to have `main` checked
  out at all.
- **Non-writing flags pass**: `git commit --dry-run`, `--help`/`-h`,
  and the `--abort`/`--quit` forms of `cherry-pick`/`revert`/`am`
  create nothing and are permitted. Reported by d-techdesign.

### FR-3 — Block pushes that would land on a protected branch

**Acceptance criteria**
- `git push` with no refspec, while a protected branch is checked out,
  is denied.
- `git push origin main` is denied *regardless of which branch is
  checked out*, because the destination, not HEAD, is what the remote
  rejects.
- `git push origin feat/x` while on `feat/x` is not denied.
- `git push --force` / `-f` targeting a protected branch is denied, and
  its reason text is distinct, naming the force flag.
- **For an explicit refspec, only the destination is judged.** So `git
  push origin feat/x` while on `main` is permitted by this requirement —
  nothing lands on the protected branch. (The edit guard FR-1 and the
  commit guard FR-2 still apply to that session independently.)
- **`git push --dry-run` / `-n` is permitted** — it writes nothing.
- **`git push --all` / `--mirror` is denied when any local branch
  matches a protected pattern**, because both forms push that branch
  without naming it.
- **Delete forms count as targeting the destination**: `git push origin
  --delete main` and `git push origin :main` are denied under a
  protected `main`.

The last four were reported by d-techdesign.

**Honest limit**: the destination of a bare `git push` depends on
`push.default` and the branch's configured upstream, which the guard
cannot resolve without consulting git config. The design must either
resolve it (`git rev-parse --abbrev-ref @{push}`) or state that bare
`git push` is judged on HEAD only. FR-3's first criterion assumes the
HEAD-based judgement, which is sound for the common case where HEAD is
itself protected.

### FR-3a — Enforce the policy on the `embo-deliver` delivery path

`/embo:git deliver` is this plugin's **default** delivery path, and it
does not run git in Bash. `plugin/commands/git.md:508-512` instructs the
bare command `embo-deliver --plan tmp/git-<timestamp>.txt`; the git
writes happen inside the binary (`plugin/bin/embo-deliver:318` `git
commit`, `:341`/`:344` `git push`, and in `release`/PR modes `:400` `gh
pr create`, `:411` `gh pr merge --squash`, `:463` `git tag`, `:470` `git
push origin "$TAG"`).

A PreToolUse guard inspecting the Bash command string sees only
`embo-deliver --plan tmp/git-1234.txt` — no `git` token, no `commit`, no
`push`. Every FR-2 and FR-3 criterion can pass while the default,
documented, one-approval delivery path commits and pushes to a protected
branch unguarded. No amount of shell parsing closes this; the command
string contains nothing to match.

**The rule is narrow (Q-7, maintainer decision): block ONLY a direct
push to a protected branch, including a force push. Permit everything
else, with a warning.** This inverts the framing this section carried
earlier ("block new work, permit tag and merge"). The reasoning: a
reviewed PR merge is the normal correct route for work reaching `main`,
so blocking it would break the project's own delivery path; tagging and
tag-push are release mechanics, and `embo-deliver:463` tags the base by
design; opening a PR lands no commit by itself.

**Acceptance criteria**
- **A direct push to a protected branch is refused** under policy
  `block`, including the force-push form, and the refusal names the
  branch and the policy as in FR-6.
- **The refusal happens before the commit** at `embo-deliver:318`, so
  after a refused delivery `git log` shows **no new commit** on the
  protected branch and the working tree is unchanged (D-9). A build that
  refuses at the push instead leaves a commit behind and fails this
  criterion.
- **Each of these four is permitted, and emits a warning**: merging a
  reviewed PR into a protected branch (`gh pr merge --squash`); tagging
  a protected branch (`git tag v1.2 origin/main`); pushing a tag to a
  protected branch's remote (`git push origin v1.2`); opening a PR whose
  base is a protected branch (`gh pr create --base main`).
- **The warning for a permitted case** is written to `embo-deliver`'s
  own stderr, in the style of its existing `embo-deliver: WARNING: ...`
  line at `:315`, and names the protected branch and the operation. It
  is a terminal warning, not a hook `additionalContext` line, because
  this enforcement runs inside the binary rather than in a hook.
- Delivery to a non-protected branch is unaffected and emits no
  warning.
- The `release` and PR-merge modes are covered, including the tag push
  and the squash merge — all of which Q-7 **permits with a warning**,
  so "covered" here means the policy is consulted and a warning emitted,
  not that the operation is refused.
- **The commit inside the delivery path is blocked by FR-2, and the
  ordering matters.** `embo-deliver:318` runs `git commit -m "$MESSAGE"`
  **before** the push at `:341`/`:344`. So a Q-7 rule that refuses only
  the push would let the commit land on the protected branch first,
  leaving a committed-but-unpushed protected branch — the refusal would
  arrive after the local damage. **Therefore the delivery path must
  check the destination before the commit at `:318`, not at the push.**
  Blocking "direct push" means refusing the whole commit-and-push
  sequence when its destination is protected, not letting the sequence
  run to the push and failing there. See the FR-2 boundary note below.
- **Tagging a protected branch stays permitted.** `embo-deliver:463` is
  `git tag "$TAG" "origin/$BASE"` — in `release` mode the tag is
  created on the base branch **by design**, and the base in normal use
  *is* the protected branch. A guard that blocked every operation
  touching a protected branch would break releases entirely. Raised by
  d-critic; this criterion exists so FR-3a is not implemented as "block
  everything touching main", and Q-7's narrow rule now makes that
  explicit policy rather than a carve-out.
- The plan's `base` field stays permitted for the same reason; it is the
  merge destination, not a direct write of new work.
- Policy `off` restores the current unguarded behaviour.

**The FR-2 boundary.** FR-2 blocks `git commit` on a protected branch
for Bash calls; Q-7 governs the delivery path. These meet at
`embo-deliver:318`, which is a commit on the destination branch. The
boundary is: FR-2's blocked set still applies to any commit the agent
makes directly, including one that would be the first step of a manual
delivery; Q-7's narrow block governs what `embo-deliver` itself refuses,
and because of the ordering above it refuses the sequence at its start.
**The two agree**, because the delivery path refuses before its commit
(D-9): no commit reaches a protected branch by either route, so there is
no case where one requirement permits what the other forbids. **No FR-2
exemption for the delivery path is needed.** The alternative reading —
"fail at the push call" — was rejected precisely because it would have
permitted a commit FR-2 forbids and made the delivery path the one
sanctioned way to commit onto `main`.

**Enforcement location (Q-7, decided): inside `embo-deliver`.** A
policy-driven check
on the plan's branch in all four modes, before any git change. The
reasons are that the binary already reads a plan carrying the target
branch, so it has the information the hook lacks; that this also covers
invocations which never pass through a PreToolUse hook; and that
`embo-deliver:225-231` **already hardcodes a `main|master` check for
push mode only**, so the feature generalises an existing check rather
than inventing one. That hardcoded check is the natural floor to retain
when the profile or the shared library is unavailable.

Recommended by d-techdesign, which also notes that no environment
override belongs in the binary, because `embo-deliver` runs inside an
agent-controlled Bash call and an override there would be settable by
the very agent being guarded. I have recorded this as the recommendation
rather than as a settled decision: it changes a shipped binary's refusal
behaviour, which is the maintainer's call (Q-7).

### FR-4 — Read the policy from the active profile

A new profile field carries the policy. The guard reads it with
`embo-profile get`, never a hardcoded branch list.

**Acceptance criteria**
- `embo-profile get rules.workflow.protected_branches` returns the
  configured list on a default install **once this feature has
  shipped**. (Verified before the feature: the key does not exist and
  the command prints nothing **and exits 0** — so the field must be
  added, not merely read. The earlier phrasing of this criterion said
  "unmodified install", which contradicted its own parenthetical;
  corrected after d-critic flagged it.)
- **The key is present in all five shipped profiles** — `default`,
  `quality`, `fast`, `minimal`, `research` — because `embo-profile get`
  does not merge an active profile with `default.yaml` (see D-3). A key
  added only to `default.yaml` is invisible to anyone running an active
  profile.
- Branch entries are exact names or `*`/`?` globs; a glob such as
  `release/*` matches accordingly.
- Changing the field to include `develop` causes the guard to deny on
  `develop` with no code change.
- Setting the mode field to `off` causes the guard to emit no decision
  on any branch.
- The field is documented in `default.yaml`'s inline explanations, in
  the same commented style as the surrounding fields.

### FR-5 — Three severities

The mode field takes `block`, `warn`, or `off`.

**Acceptance criteria**
- `block` → PreToolUse `deny`; the action does not run.
- `warn` → the action runs, and a warning naming the branch reaches the
  agent's context **via the JSON `additionalContext` path, not stderr**.
  The documentation states that Claude never sees stderr from a hook
  that exits 0; only exit 2 blocks and surfaces its stderr, and every
  other non-zero exit is non-blocking with the call proceeding. A
  stderr-based warning would therefore be invisible. PreToolUse does
  accept `additionalContext`, delivered next to the tool result — after
  the action runs, which is exactly warn semantics. Confirmed by
  d-critic, who had raised this as a possible defect; it is not one, but
  the mechanism must be the JSON path. **Unproven in one respect**:
  whether `additionalContext` is honoured on a `PreToolUse` result that
  sets no `permissionDecision` — which is exactly warn mode's shape — is
  not confirmed, and this repository has no `PreToolUse` precedent for
  it (its two uses are `UserPromptSubmit` and `SubagentStart`). If it is
  not honoured, `warn` has no delivery channel and the mode would have
  to be dropped or re-specified. This is **Q-10**, a live check of equal
  priority to Q-5's.
- `off` → silence; no decision, no warning.
- A non-empty unrecognised value (for example `blok`) is treated as
  `block`, so a typo cannot silently disable the guard. The bad value is
  reported **in the denial text when the guard fires**, not on every
  tool call — a per-call warning on an unrelated action would be noise.
- An empty or absent value means the built-in default (`block`), not
  silence. Disabling requires the explicit `off` value. (See D-3.)

### FR-6 — Fail loudly, never silently

**Acceptance criteria**
- Every denial carries a `permissionDecisionReason` that states the
  branch, the policy that fired, and the remedy.
- The reason string **contains the current branch name as a
  substring** — a fixture test asserts this, so a generic message
  fails the suite.
- The reason string **begins with the fixed marker `embo
  branch-guard:`** on every denial, which is what makes a denial
  distinguishable from an ordinary permission prompt. A fixture test
  asserts the prefix. Mechanism supplied by the technical design; this
  replaces the earlier unfalsifiable "distinguishable in the transcript"
  wording that d-critic flagged.

### FR-7 — Fail open on uncertainty

**Acceptance criteria**
- Outside a git repository: the hook exits 0 silently and the action
  proceeds.
- Detached HEAD: exits 0 silently (there is no branch name to judge).
- `embo-profile` absent, or `yq` missing so `embo-profile` fails
  (`embo-profile:50-55` exits 3): the hook exits 0 silently rather than
  blocking all work.
- **An empty policy value does NOT fail open** — it means the built-in
  default (`block`, `[main, master]`). Measured: `embo-profile get`
  prints nothing **and exits 0** both for a missing key and for an
  empty-string value (`embo-profile:96` is `yq -r ".${field} // \"\""`,
  collapsing null and empty to the same output), so the two are
  indistinguishable and both resolve to the default. Fail-open is keyed
  to a **non-zero exit** only. See D-3 for why: `get` does not merge
  with `default.yaml`, so empty is the normal reading on every install
  predating this feature.
- **An unborn branch (a repository with no commits yet) fails open.**
  Otherwise `git init` followed by a first `git commit` on the
  default-named branch is denied, which would block creating a new
  repository. Reported by d-techdesign.
- Malformed hook stdin: exits 0 silently.
- In every fail-open case the action proceeds; the guard never halts a
  session because of its own breakage.

This matches the **fail-open discipline** of `branch-task-check.sh`,
which bails silently on every uncertainty by the same reasoning: a
broken guard that blocks everything is worse than an absent one. The
citation is to that discipline only — not to its branch-resolution
mechanism, which NFR-4 explicitly does not follow.

### FR-8 — An explicit, auditable override

A user must be able to do intentional work on a protected branch
without editing their profile mid-session.

**The override is the profile mode, and nothing else** (D-10): a
deliberate bypass means setting `rules.workflow.protected_branch_mode`
to `warn` or `off`. There is no environment variable.

**Acceptance criteria**
- Setting the profile mode to `warn` or `off` permits the action; no
  other mechanism does.
- **Nothing in the command text or the environment changes the
  outcome.** A test sets arbitrary environment variables, including the
  dropped `EMBO_ALLOW_PROTECTED_BRANCH=1`, and embeds override-looking
  text in the command; the decision is unchanged in every case. This is
  what makes "the profile mode is the only control" falsifiable rather
  than a statement of intent.
- The override is explicit — the agent cannot trigger it as a
  side-effect of retrying a denied call, and **there is nothing for an
  agent to set mid-session**, because the only control is a file the
  user edits.
- A denied action that is retried unchanged is denied again identically
  (the guard is stateless, NFR-3).
- `warn` emits its warning per FR-5; `off` is silent by design (FR-5).
- The documentation states plainly where the user changes the mode,
  since a guard the user cannot deliberately switch off is a guard they
  will work around.

**Why this shape.** Dropping the environment variable removes an
untestable claim rather than just a feature: an environment-based
override would have required asserting that an agent cannot alter the
hook's own environment, which is not something this PRD could verify —
it was flagged as only half-testable. With no variable, that inference
is moot. **Accepted cost**: a one-off deliberate commit on a protected
branch now means editing the profile and changing it back, which is
heavier than exporting a variable would have been. That is the trade
taken.
- Without the override, retrying a denied call is denied again
  identically (the guard is stateless; see NFR-3).

### FR-9 — Fixture tests

**Acceptance criteria**
- `plugin/hooks/<name>.test.sh` exists, following the convention of the
  seven existing `*.test.sh` files.
- Cases cover: each of `block`/`warn`/`off`; protected and
  non-protected branch; each blocked surface from FR-1 to FR-3a; each
  fail-open case from FR-7 including the empty-value case; the
  compound-command case from FR-2; the `git push origin main` from a
  feature branch case from FR-3.
- **The `git commit -F <file>` shape is a test case** — the shape
  `git.md` instructs after Q-1's change — not only the simple `-m "x"`
  form.
- **The delivery path (FR-3a) has test cases** for both halves of Q-7's
  rule: a direct push to a protected branch is refused with no commit
  left behind, and each of the four permitted operations succeeds while
  emitting its warning.
- A case asserts the reason string contains the branch name and the
  fixed marker prefix (FR-6).
- **A two-worktree case** asserts NFR-4: same session, two worktrees on
  different branches, each call judged on its own worktree's branch.
- **A conflict case** asserts FR-10: a `git commit` that
  `approve-compound.sh` would auto-approve is still denied on a
  protected branch.
- **A live subagent run is the highest-priority case (Q-5).** Spawn a
  subagent, have it attempt a `git commit` **and an `Edit`** on a
  protected branch, and assert the hook fires and denies. A fixture
  suite cannot answer this — it tests the script, not whether the
  harness invokes a plugin hook inside a subagent. Until this passes,
  the feature's coverage of delegated work is unproven.
- **A live warn-mode check (Q-10)**, equal priority: assert that an
  `additionalContext` line reaches the agent's context from a
  `PreToolUse` result carrying no `permissionDecision` (FR-5). If it
  does not, `warn` has no channel. Like Q-5, a fixture test cannot
  answer it.
- **The registration path is exercised, not only the script in
  isolation.** A suite that invokes the guard script directly would pass
  even if the two-hook registration never lets the guard's decision take
  effect (FR-10, Q-6). At least one case must go through the registered
  hook configuration. Raised by d-critic; this is the gap that would
  otherwise hide the feature's central failure behind a green suite.
- Cases cover the permitted forms that must NOT be denied: gitignored
  and out-of-repo edit targets, `git commit --dry-run`, `git push
  --dry-run`, `git push origin feat/x` from a protected branch, an
  unborn branch, and tagging a protected branch via the release path.
- Tests construct throwaway git repositories; they never depend on the
  branch the suite is run from.
- The suite passes with a non-zero number of assertions reported.

### FR-10 — Registration

**Acceptance criteria**
- The hook is registered in `plugin/hooks/hooks.json` under
  `PreToolUse`, using the same `bash "${CLAUDE_PLUGIN_ROOT}/hooks/..."`
  form as the existing entries.
- `hooks.json`'s `description` field is updated to mention the guard.
- **The conflict case is covered**: a `git commit` on a protected branch
  that `approve-compound.sh` would auto-approve **is still denied**,
  because the documented PreToolUse precedence is `deny` > `defer` >
  `ask` > `allow` (see below). This is the criterion that decides
  whether the feature works at all, and it is now assertable rather than
  conditional.

**The allow/deny precedence problem.** `approve-compound.sh` emits
`permissionDecision: "allow"` for Bash commands whose every subcommand
matches the user's allow rules (`:443`, `:445`) — which includes routine
git commands, since auto-approving those is its purpose. The new guard
emits `deny` for some of those same calls. Both are registered on
PreToolUse with matcher `Bash`.

**Resolved — the precedence is favourable.** The current hooks
documentation states: "When multiple PreToolUse hooks return different
decisions, precedence is `deny` > `defer` > `ask` > `allow`", and
matching hooks run in parallel. So `approve-compound.sh`'s `allow`
**cannot** override the guard's `deny`, and registration order does not
matter. Verified independently by team-lead and d-critic against
https://code.claude.com/docs/en/hooks (the older
`docs.claude.com/en/docs/claude-code/hooks` URL now redirects there).

Consequences: a separate hook file (D-4) is sound, and the fallback this
PRD previously recorded — moving the check into or ahead of the approve
path — is **not needed** and has been withdrawn. FR-10's criterion can
therefore be asserted positively, as above, rather than left as a
dependency. This closes what was the highest-risk unknown in the
document (Q-6).

Three further facts from the same documentation section, each
load-bearing for the design:

- **`allow` is weak by design.** "Deny and ask rules are still
  evaluated regardless of what the hook returns." A hook's `allow` does
  not override the user's own deny/ask rules, which is the documented
  reason the guard should never emit `allow` itself — it has no reason
  to widen permissions, only to narrow them.
- **`defer` is a trap and must not be used.** It "is honored only in
  non-interactive mode (`-p`). In interactive sessions Claude Code logs
  a warning and ignores the hook result." It appears in the precedence
  string above, so this clause exists to stop anyone reaching for it
  later: a guard returning `defer` would be silently ignored in exactly
  the interactive sessions it is meant to protect.
- **Hook-to-hook `updatedInput` visibility is undocumented** and stays
  hedged. It matters because `approve-compound.sh` rewrites commands
  into an `embo-capture.sh --b64 <base64>` form. That each hook receives
  the *original* command rather than another hook's rewrite is an
  **inference from parallel execution, not a documented statement** —
  flagged as such by team-lead and independently unverifiable by
  d-critic. **The design's wrapper-decode hedge must therefore stay**:
  the guard has to cope with receiving either the original text or a
  base64-wrapped rewrite. This is the one sub-point of Q-6 that remains
  unproven, and it is an inference, not a fact.

### FR-11a — Change the instructed commit shape in `git.md`

Brought into scope by Q-1's decision.

**Acceptance criteria**
- `plugin/commands/git.md` instructs `git commit -F <file>` with the
  message written to a file under `tmp/`, replacing the
  `-m "$(cat <<'EOF' ... EOF)"` form at the current `:239`.
- The instructed shape contains no `$(...)`, backtick, `<(...)` or
  heredoc construct, so `approve-compound.sh`'s analysis does not bail
  on it.
- The temp file path is under `tmp/`, which the FR-1 carve-out permits,
  so writing it on a protected branch is not itself blocked.
- This change **precedes or ships with** the guard. Until it lands, the
  guard does not cover the plugin's own instructed commit (FR-2).

### FR-11 — A terse human-facing note

**Acceptance criteria**
- CLAUDE.md § Safety Rules gains a short note stating the rule and
  pointing at the hook as the enforcement.
- The note does not restate the mechanism's internals and contains no
  `tasks/` reference (per the repository's no-internal-references rule).

## 5. Non-functional requirements

- **NFR-1 Latency.** The hook runs on every matched tool call. Its work
  must be a small fixed number of cheap subprocesses (branch read,
  profile read). No repository scan, no network.
- **NFR-2 Dependencies.** Bash plus the tools already required by
  sibling hooks (`jq`, `git`, and `yq` by way of `embo-profile`). No new
  dependency.
- **NFR-3 Stateless.** Like `approve-compound.sh`, the hook holds no
  state between calls. The same input always yields the same decision.
- **NFR-4 Worktree-correct, resolved per tool kind.** The guard must
  judge the branch of the repository the tool call actually affects,
  never a repository-wide assumption. The source differs by tool, and
  conflating the two is the error this NFR exists to prevent:
  - **Edit tools** (FR-1): the governing repository is the one
    containing the **target file**, resolved by running git against the
    target path's directory. The session's working directory is *not*
    authoritative here — a session in a feature worktree can edit a path
    in the main checkout, and that edit must be judged on the main
    checkout's branch. Reported by d-techdesign.
  - **Bash calls** (FR-2, FR-3): the start directory is the **`cwd`
    field of the hook's stdin JSON**, read as `approve-compound.sh:425`
    does (`jq -r '.cwd // empty'`, falling back to `$PWD` only when the
    field is absent). It also resolves relative paths in the command.

  Neither is the process-CWD approach of `branch-task-check.sh:28-33`,
  which resolves `git rev-parse --show-toplevel` relative to the process
  working directory on the strength of its own comment that "Claude Code
  invokes the hook from the session's working directory". That
  assumption is safe for a SessionStart hook, which runs once per
  session; it is not a precedent for a per-tool-call hook. Elsewhere
  this PRD cites `branch-task-check.sh` only for its fail-open
  discipline (FR-7), never for branch resolution.

  This is deliberately *not* the process-CWD approach of
  `branch-task-check.sh:28-33`, which resolves `git rev-parse
  --show-toplevel` relative to the process working directory on the
  strength of its own comment that "Claude Code invokes the hook from
  the session's working directory". That assumption is safe for a
  SessionStart hook, which runs once for the session; it is not a
  precedent for a PreToolUse hook, and NFR-4's own premise is that a
  guard reading the wrong branch is actively harmful. Elsewhere this PRD
  cites `branch-task-check.sh` only for its fail-open discipline
  (FR-7), never for branch resolution.

  **Acceptance criterion**: with two worktrees of the same repository
  checked out on different branches — one protected, one not — a tool
  call made in the non-protected worktree is permitted and a tool call
  made in the protected worktree is denied, in the same session. This
  repository is developed in worktrees, so the case is live rather than
  theoretical.

## 6. Out of scope

- **Work-phase branch/task correspondence** (the "wider blindness" in
  the seed, where edits land on a finished task's branch). Already
  partly covered by `branch-task-check.sh` at SessionStart. It is a
  different check with a different trigger and failure mode, and folding
  it in would make this guard's policy field mean two things.
- Server-side or `pre-commit` git hooks. This guard governs the agent's
  tool calls, not the repository.
- Remote branch-protection configuration on the forge.
- Blocking reads, or branch deletion. Only the surfaces in FR-1 to
  FR-3a.
- **`git merge`, `git pull`, `git rebase`, `git reset` are explicitly
  not blocked**, even though they can write commits to a protected
  branch — `git merge --no-ff` produces a two-parent commit on the
  current branch (measured). See the stated limit in §7.6.
  Blocking them would prevent ordinary maintenance such as updating a
  local `main` from the remote, and the work this feature exists to
  protect is new work the agent authors — which arrives through FR-1 to
  FR-3a. FR-2's blocked set is therefore the commit-*creating*
  subcommands only.
- Any automatic remediation (creating or switching branches for the
  user). The guard denies and explains; the agent acts.

## 7. Where the mechanism does not reach

Stated plainly, because FR-1 to FR-3 must not be read as a complete
seal:

1. **A PreToolUse hook sees only tool calls.** Anything that writes
   without one is unaffected. In particular, a `Bash` call that writes a
   file (`printf ... > file`, `sed -i`, `tee`, `patch`, an editor, a
   build step that regenerates a tracked file) bypasses FR-1 entirely,
   because FR-1 matches the edit tools, not Bash. Covering that class
   would mean interpreting arbitrary shell for write intent, which is
   not reliably decidable. **The guard reduces the probability of the
   failure; it does not make it impossible.** Whether it stops the
   originating incident depends entirely on FR-2's heredoc criterion and
   on FR-3a holding — the incident's commit and push went through paths
   that a naive string match does not see.
2. **The default delivery path (`embo-deliver`).** The largest gap, and
   the reason FR-3a exists. The command string carries no git token at
   all, so shell parsing cannot reach it. Unless the policy is enforced
   inside the binary or the wrapper is matched by name, the documented
   one-approval delivery path is unguarded — including the `release`
   mode's tag push and the PR mode's squash merge.
3. **Obfuscated commands are permitted, by decision.** The sibling
   `approve-compound.sh:12-15` bails on `$(...)`, backticks, `<(...)`
   and heredocs because Bash+jq cannot analyse them safely. The guard
   inherits that limit: a `git commit` or `git push` hidden inside
   command substitution or a heredoc is **not** denied.

   This was the hole that made `plugin/commands/git.md:239` — the
   plugin's own instructed commit — invisible to the guard. Q-1 closes
   it at the source by changing that shape to `git commit -F <file>`,
   not by teaching the guard to parse obfuscation. The maintainer
   rejected a refuse-unanalysable rule because it would permanently
   refuse legitimate commands such as `git log --oneline $(git
   merge-base ...)`.

   So the residual gap is deliberate and bounded: **an agent that
   deliberately obscures a commit can still make one on a protected
   branch.** The guard covers the shapes the workflow produces, not
   adversarial input. That is the honest limit of a string-inspecting
   mechanism, and it is why FR-3a's enforcement lives inside
   `embo-deliver` where the branch is read from data rather than parsed
   from text.

   **This guard stops forgetting, not deliberate circumvention.** An
   agent determined to commit on a protected branch can already set
   `protected_branch_mode` to `off`. Refusing unanalysable commands
   would raise that effort slightly while breaking a whole class of
   legitimate ones — so it is not a trade worth making. The permit
   policy is a decision, not a default: see D-11a.
4. **Other agents and sessions — subagent coverage is PROVISIONAL, and
   this is the largest unverified risk in the feature.** The intent is
   that a delegated edit or commit cannot bypass the guard, and that the
   guard can attribute a denied action to a specific subagent via the
   `agent_id`/`agent_type` input fields.

   **But it is not established.** Firing inside subagents is only
   *implied* by those fields being documented as present when a hook
   fires inside a subagent; it is not explicitly stated for
   `PreToolUse`. More importantly, **whether a plugin's `hooks.json`
   applies inside subagents is not documented at all**, and that is how
   this guard ships. An earlier draft of this section asserted the
   coverage as a documented quote; that assertion is withdrawn (Q-5).

   **If plugin hooks do not fire inside subagents, every spawned agent
   can commit to a protected branch unguarded**, and the feature
   protects only the main session. This plugin delegates heavily, so
   that is not a marginal case. The question is settled by a cheap live
   run (Q-5), which must happen before the feature is believed to work.

   Unchanged: anything running outside a session with the plugin loaded
   is not governed, and hooks defined in a subagent's own frontmatter
   run only while that subagent runs.
5. **`warn` mode does not prevent anything.** It is a notification. Only
   `block` is enforcement, which is why `block` is the default and why
   an invalid mode degrades to `block`, not to `warn`.
6. **Not every way a commit can reach a protected branch is blocked.**
   FR-2 blocks the subcommands whose *purpose* is to create a commit
   (`commit`, `cherry-pick`, `revert`, `am`). Other commands can also
   write commits and are **deliberately permitted**: `git merge --no-ff`
   writes a two-parent commit on the current branch (measured, not
   inferred), and `git pull` with merge semantics and `git rebase` can
   write commits too.

   **Plumbing commands are a separate, also-permitted path.** Measured
   by d-critic: `git write-tree` + `git commit-tree` + `git update-ref
   refs/heads/main <sha>` advances `main` without any porcelain commit
   subcommand. `git symbolic-ref HEAD`, `git fast-import` and `git
   replace` can likewise move a protected branch. None is blocked.

   The two categories differ in *why* they are permitted, and the
   distinction matters for anyone tempted to close one of them.
   `merge`/`pull`/`rebase` are permitted because they are **legitimate
   work** this guard must not obstruct. Plumbing is permitted because it
   is **circumvention, not forgetting** (§7.3): nobody reaches for
   `commit-tree` by accident, and an agent willing to assemble a commit
   from plumbing can more easily set `protected_branch_mode` to `off`.
   Blocking plumbing would add a long, unbounded list of subcommands to
   the matcher for no gain against the failure this feature addresses.

   This is a judgement, not an oversight. Having `main` checked out to
   update it from its remote is normal, legitimate work, and blocking
   `merge`/`pull`/`rebase` would obstruct it for no gain against the
   failure this feature addresses — an agent authoring new work on a
   protected branch. For the merge case the remote's own branch
   protection is the backstop. Raised by d-critic with a measured
   counterexample, after FR-2's earlier phrasing ("the commit-creating
   subcommands") invited the stronger reading.

## 8. Decisions taken

- **D-1 Default branch list `[main, master]`, default mode `block`.**
  From the seed's explicit statement ("Default: block `main`/`master`")
  and from the incident, which concerned `main`. A weaker default would
  not have prevented it.
- **D-2 Policy lives in the profile, not the hook.** The seed records
  this as a direct user request. It is also consistent with the shipped
  `embo-profile` reader, which exists precisely so components stop
  parsing profile YAML themselves.
- **D-3 An empty or absent policy value means the built-in default
  (`block`, `[main, master]`); only a non-zero exit from `embo-profile`
  fails open.** This reverses the previous draft of this decision, which
  made an empty value fail open silently. That was wrong, and the
  evidence is decisive: `embo-profile:114` is `cp "$path" "$ACTIVE"` —
  `set` **copies** the profile file — and `embo-profile:93-94` reads
  *either* the active copy *or* `default.yaml`, with **no merge** of one
  into the other. So every existing install, and any profile that
  predates this feature, has an active copy lacking the new key and
  returns empty. Fail-open-on-empty would therefore leave the guard
  **off for every existing user**, defeating D-1's `block` default
  outright. Reported by d-techdesign; verified in the source above.

  The guard therefore splits on `embo-profile`'s **exit code**, not on
  emptiness: non-zero exit (for example `yq` missing, `embo-profile:50-55`
  exits 3) → fail open and silent (FR-7); exit 0 with empty output →
  built-in default; exit 0 with a non-empty unrecognised value →
  misconfiguration → `block` plus a report (FR-5).

  Cost accepted: a user who sets `mode: ""` intending to disable the
  guard gets `block`, not silence. Disabling requires the explicit
  `off` value. This is the right trade, because the failure direction of
  the alternative is a silently absent safety guard.

  Consequence for FR-4: because `get` does not merge, the key must be
  added to **all five** shipped profiles, not only `default.yaml`.
- **D-4 A separate hook file, not an extension of
  `approve-compound.sh`.** That file is a 450-line permission-matching
  normalizer with its own test suite; its job is to *approve*. Mixing a
  deny-guard into it entangles two decisions and risks regressing a
  working component. Separate files also match the one-concern-per-hook
  pattern across the existing eight. **This decision covers file
  organisation only.** It does not settle how an `allow` from
  `approve-compound.sh` and a `deny` from the guard resolve against each
  other — that is Q-6, and it is the question that can invalidate this
  decision: if `allow` wins, a separate file cannot work and the check
  must move into or ahead of the approve path.
- **D-5 The matcher enumerates tool names explicitly.** Verified from
  the current hooks documentation: a matcher of only letters, digits,
  `_`, `-`, spaces, `,` and `|` is an exact string or a `|`/`,`
  separated list of exact strings; anything else is an unanchored
  JavaScript regex, so `Edit.*` would match `NotebookEdit` too. An
  explicit list is unambiguous and self-documenting. Independently
  re-verified by d-critic against the current documentation, including
  its own `Edit.*` example.

  **Safety consequence worth stating**: exact-list matching is
  whole-name, so a misspelled tool name in the matcher is **silently
  inert** — it raises no error and simply never fires (the docs note a
  bare `mcp__memory` matches nothing). For a safety guard, a typo
  therefore disables protection for that tool with no signal. The
  matcher string needs review as carefully as the logic, and FR-9's
  per-tool cases are what would catch such a typo. All four edit tools
  are listed (Q-4 closed). The technical design covers this with a case
  asserting the registered matcher contains every tool name and that the
  registered entry's own command runs — which is the right shape,
  because it tests the registration rather than the script.
- **D-6 Deny via the JSON decision, not exit code 2.** Verified from the
  current documentation: for PreToolUse both block the call, but
  `hookSpecificOutput.permissionDecision: "deny"` with
  `permissionDecisionReason` carries a structured reason, and the
  documentation states that when a hook prints a blocking JSON decision,
  that decision's reason is used instead of stderr. This satisfies FR-6
  better, and matches the shape `approve-compound.sh` already emits.
- **D-7 Push is judged on its destination, not only on HEAD.** The
  remote rejects based on the target ref. Judging HEAD alone would miss
  `git push origin main` from a feature branch — a real way to hit the
  same rejection the incident produced.
- **D-8 The work-phase branch/task check stays out.** See Out of scope.
- **D-9 The delivery path refuses BEFORE the commit at
  `embo-deliver:318`, not at the push.** No commit lands on a protected
  branch at all. Reasoning: the originating incident *was* a commit on
  `main`; FR-2 forbids that act from a direct Bash call; and the
  delivery path must not become the one sanctioned exception to it. A
  push-time refusal would leave a committed-but-unpushed protected
  branch — the local half of the incident — and would make the two
  requirements disagree depending only on which route produced the
  commit. Raised by this PRD as a conflict in Q-7's literal wording,
  decided by the maintainer in favour of the early check; **no FR-2
  exemption is needed**. The early check is still the direct-push
  condition, because the binary pushes the plan's branch in every mode
  (`:340-346`, ahead of the PR section at `:358`).
- **D-11a Unanalysable commands are PERMITTED, including ones containing
  `git`, on a protected branch — by decision, not by default.** No
  refuse rule and no warning. This is the residual of Q-1, decided
  separately from the `git.md` shape change (FR-11a) that handles the
  instructed commit.

  Reasoning, which is the same reasoning applied twice: refusing them
  would cause permanent false positives on legitimate commands such as
  `git log --oneline $(git merge-base main HEAD)` run on `main` — the
  exact cost the maintainer rejected when deciding Q-1 itself.

  The framing that justifies accepting the gap: **this guard stops
  forgetting, not deliberate circumvention.** An agent determined to
  commit on a protected branch can already set `protected_branch_mode`
  to `off`. A refuse rule would raise that effort slightly while
  breaking a class of legitimate commands. The gap stays a stated limit
  (§7.3), not a defect to be fixed later.
- **D-10 There is no environment-variable override. The profile mode is
  the only bypass.** `EMBO_ALLOW_PROTECTED_BRANCH` is **dropped**, not
  deferred. A deliberate bypass means setting
  `rules.workflow.protected_branch_mode` to `warn` or `off`.

  This decision passed through two earlier shapes, both superseded: a
  plugin-delivered variable, then a user-set variable in
  `settings.json`'s `env` block.

  The plugin-delivered shape fell because **no documented mechanism
  exists for a plugin to set an environment variable its own
  `PreToolUse` hook would read**. A hook reads its parent process's
  environment, and the one injection mechanism the documentation
  describes, `CLAUDE_ENV_FILE`, fails twice over: it is available to
  "SessionStart, Setup, CwdChanged, and FileChanged hooks" and
  explicitly not to other hook events, and it persists variables for
  "the shell commands Claude runs later in the session" rather than for
  the hook process itself.

  The deciding argument is that the variable was carrying an
  unverifiable claim. An environment-based override only works if an
  agent cannot alter the hook's own environment, and this PRD could not
  establish that — it was recorded as half-testable. Removing the
  variable removes the claim with it, so the mechanism's guarantees
  become things the test suite can actually check. **Accepted cost**: a
  one-off deliberate commit on a protected branch requires editing the
  profile and reverting it, heavier than exporting a variable. No
  investigation of plugin hook environment is needed any more, because
  nothing depends on it.

## 9. Open questions

- ~~**Q-1 How to cover `git commit` inside `$(...)`/heredoc.**~~
  **CLOSED — change the shape at the source.** `plugin/commands/git.md`
  moves to `git commit -F <file>` (now FR-11a), and the guard gets **no**
  refuse-unanalysable rule.

  Decided **against** the team's recommendation (d-techdesign's
  "refuse unanalysable only when the branch is protected and the text
  contains `git`", carried as its design D-6). The maintainer's
  reasoning: that rule buys a one-time saving — not editing a shipped
  file — at the cost of permanent false positives on a whole class of
  legitimate commands, since `git log --oneline $(git merge-base ...)`
  on `main` would be refused forever. Fixing the instructed shape makes
  every commit mechanically visible with no false positives, which is
  the "Enforce, Don't Ask" move: make the correct thing checkable rather
  than teach a parser to cope with an awkward one.

  **The residual is also decided** (D-11a): unanalysable commands that
  are not the instructed shape are **permitted**, including ones
  containing `git`, with no refusal and no warning. That is a maintainer
  decision in its own right, not a leftover — the same false-positive
  reasoning applied a second time. It stays a stated bounded gap (§7.3).
  So Q-1 is closed on both halves: the instructed shape is fixed at the
  source, and everything else unanalysable is permitted deliberately.
- ~~**Q-7 Where the delivery-path policy is enforced, and what it
  blocks.**~~ **CLOSED — inside `embo-deliver`, blocking only a direct
  push to a protected branch (force push included) and permitting
  everything else with a warning.** Four cases confirmed permitted: PR
  merge into a protected branch, tagging it, pushing a tag to its
  remote, and opening a PR based on it. Detail and criteria in FR-3a.
  The floor at `embo-deliver:225-231` is retained so delivery is never
  weaker than today.
All questions this PRD raised are now decided. The two items that
remain — Q-5 and Q-10 — are **live-run verifications, not open
decisions**. Both are make-or-break, both are cheap, and neither can be
answered by a fixture suite, because each tests whether the harness
behaves as assumed rather than whether the script is correct.

- **Q-10 Is `additionalContext` honoured on a `PreToolUse` result that
  sets no `permissionDecision`?** That is exactly warn mode's shape
  (FR-5). This repository has no `PreToolUse` precedent for it — its two
  uses are `UserPromptSubmit` and `SubagentStart` — so the mechanism is
  assumed, not demonstrated. **If it is not honoured, `warn` has no
  delivery channel** and the mode must be dropped or re-specified,
  which would change FR-5's three-severity contract. Equal in priority
  to Q-5.
- **Q-2 Exact profile field shape.** The seed proposes
  `rules.workflow.protected_branches: [main, master]` plus a separate
  mode. Still a trapdoor once users hold the key in their profiles, so
  the authority to fix it stays with the maintainer — but the shape is
  now recommended rather than unknown.

  **CLOSED — decided as recommended.** Chosen for consistency with the
  existing flat `rules.workflow.*` style. Known cost accepted: a future
  exempt-path list becomes a third sibling key rather than a nested
  field under one parent.

  **The decided shape**: two **sibling** keys,
  not a nested map — `rules.workflow.protected_branches` (list of exact
  names or `*`/`?` globs; `[]` means none; absent or empty means
  `[main, master]`) and `rules.workflow.protected_branch_mode`
  (`block`/`warn`/`off`; absent or empty means `block`; a non-empty
  invalid value means `block` plus a report). Rationale: flat like the
  existing `docs_first` and `scope_drift` keys, and `embo-profile get`
  takes one dotted path returning one value, so a nested map would need
  two reads or a parse.
  **Resolved — how `embo-profile get` returns a list** (measured, not
  assumed): `embo-profile get rules.testing.scope` prints
  `[unit, integration]` — a flow-style bracketed list on one line, with
  no trailing newline. It is *not* newline-delimited and will not feed a
  `while read` loop. A consumer must strip `[`, `]` and `, ` to recover
  the names. Consequence to document: a branch name containing a comma
  or a bracket cannot be represented this way.
- ~~**Q-3 Override mechanism for FR-8.**~~ **CLOSED — the profile mode
  is the only override; the environment variable is dropped** (D-10).

  This question went through three answers, and the record is kept
  because the reasoning matters: first a plugin-delivered
  `EMBO_ALLOW_PROTECTED_BRANCH` with a precedence rule, then the same
  variable set by the user once no plugin-delivery mechanism was found,
  and finally no variable at all. The precedence rule ("set to `1`
  permits regardless of mode") and the never-parse-from-command-text
  rule are **both withdrawn** — with no variable there is nothing to
  rank against the mode and nothing to parse.

  What the variable was costing: it required asserting that an agent
  cannot alter the hook's own environment, which this PRD could not
  verify. Dropping it removes that unverifiable claim. See D-10 for the
  accepted cost.

  **On the record about the second shape**: the clause "embo delivers
  the variable through the plugin" was a relay imprecision, not the
  maintainer's position — the maintainer had said "if we can deliver it
  via plugin", conditionally. Kept here because this PRD spent a round
  treating a conditional as settled, and the next reader should know
  that is how the user-set shape came to be written down.
- ~~**Q-4 Should `MultiEdit` and `NotebookEdit` be in the matcher?**~~
  **CLOSED.** Matcher semantics are settled (D-5), and listing all four
  edit tools is safe: an exact-list match is whole-name, so a name the
  harness does not provide is inert rather than harmful. See the typo
  warning in D-5.
- **Q-5 (REOPENED) Does a PLUGIN-registered `PreToolUse` hook fire for
  tool calls made by subagents?** This was closed as "verified yes" on a
  quoted passage; that closure is **withdrawn**. The passage could not
  be reproduced from the documentation by a second reader, and the
  specific configuration this feature ships as is not covered at all.

  **What the documentation actually supports**: firing inside subagents
  is *implied* by the documented `agent_id`/`agent_type` fields, which
  are described as present when a hook fires inside a subagent. It is
  **not explicitly stated** for `PreToolUse`. And **whether a plugin's
  `hooks.json` applies inside subagents is not documented anywhere** —
  the docs say plugin hooks merge with user and project hooks, and
  separately that subagent-*frontmatter* hooks run only while that
  subagent runs. Neither sentence covers a plugin hook governing a
  subagent's tool calls, which is exactly this guard's case.

  **Consequence if the answer is no**: this plugin delegates heavily, so
  every spawned subagent could commit to a protected branch with no
  guard at all, and the feature would protect only the main session.
  That is a hole large enough to change what the feature is worth, not a
  detail.

  **Resolution path**: a live run, and it is cheap — spawn any subagent,
  have it attempt a `git commit` on a protected branch, observe whether
  the hook fires. **This is the highest-priority verification item in
  the document**, ahead of every cosmetic check.
- ~~**Q-6 How do two PreToolUse hooks resolve when one allows and the
  other denies?**~~ **CLOSED — `deny` wins.** Documented precedence is
  `deny` > `defer` > `ask` > `allow`, with matching hooks running in
  parallel, so `approve-compound.sh` cannot override the guard and
  registration order is irrelevant. D-4's separate-hook structure is
  sound and the move-into-the-approve-path fallback is withdrawn. Detail
  in FR-10. This was the highest-risk unknown in the document.

## 10. Success criteria

The feature is done when, on a repository with default policy:

1. A fresh session on `main` cannot edit a file, commit, or push without
   an explicit denial naming `main`.
2. The same session on a feature branch is unobstructed and sees no
   guard output.
3. Setting the mode to `off` restores pre-feature behaviour exactly.
4. The fixture test suite passes.
5. The originating incident, replayed step for step **through the paths
   this plugin actually instructs** — the `git commit -F <file>` shape
   from FR-11a and the `embo-deliver` delivery path — is blocked before
   any commit lands on the protected branch. A replay using only a
   simple `git commit -m "x"` does not satisfy this criterion, because
   that is not a shape the workflow produces.
6. A release still works: tagging `main`, pushing the tag, opening a PR
   based on `main`, and merging a reviewed PR into `main` all succeed,
   each with a warning. A build that blocks any of these has
   misimplemented Q-7 and broken the project's own delivery path.
7. **A subagent attempting a commit on a protected branch is denied**
   (Q-5). Until this is observed in a live run, criteria 1 to 5 are
   demonstrated only for the main session, and the feature must not be
   described as guarding delegated work.
