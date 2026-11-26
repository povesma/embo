# 055: Main Branch Guard - Technical Design

**Status**: Draft
**PRD**: [2026-10-25-055-main-branch-guard-prd.md](2026-10-25-055-main-branch-guard-prd.md)
**Created**: 2026-10-25

## Overview

One new PreToolUse hook, `main-branch-guard.sh`, registered for
`Edit|Write|NotebookEdit|Bash`. Per call it (1) reads the tool payload from
stdin, (2) cheaply exits unless the call is a candidate mutation, (3) looks up
the checked-out branch, (4) reads policy from the profile via
`embo-profile get`, and (5) allows, warns, or denies. Branch/task logic stays
in the existing `plugin/lib/branch-task-lib.sh`; the command-recognition logic
goes in a new sourceable `plugin/lib/git-command-lib.sh` so it is unit-testable
apart from the hook. The work-phase mismatch check (FR-5) is not a second
hook: it is a profile-governed mode consumed by the same guard, scoped to the
first mutation of a session (see Components).

The guard is a habit-enforcing guardrail, not a security boundary (PRD FR-1
known limit). Remote branch protection remains the complement.

## Current Architecture (RLM-verified)

Each inherited PRD claim was re-checked against the working tree on
2026-10-25.

| PRD claim | Result | Source |
|---|---|---|
| Only PreToolUse hook matches `Bash` (compound approver) | Holds | `plugin/hooks/hooks.json:42-52` |
| SessionStart warns, never blocks, fails open | Holds | `plugin/hooks/branch-task-check.sh:15-17`, `:49` |
| Shared match/derive functions exist | Holds; pure functions, no output/exit | `plugin/lib/branch-task-lib.sh:10-48` |
| `embo-profile get` prints empty for absent field | Holds; reads the active profile, else `default.yaml` | `plugin/bin/embo-profile:88-99` |
| `rules.workflow` sub-section exists in default profile | Holds | `plugin/profiles/default.yaml:32-41` |
| Every hook has a sibling `.test.sh` | Holds | `ls plugin/hooks` |
| PreToolUse payload fields and deny contract (assumption) | Resolved: stdin JSON carries `tool_name`, `tool_input`, `tool_use_id` plus common fields (including `cwd`); deny is `hookSpecificOutput.permissionDecision: "deny"` with `permissionDecisionReason` on exit 0, or exit 2 with stderr as the reason. Exit 2 overrides any JSON allow. | Claude Code hooks docs (Context7 `/websites/code_claude`, hooks and hooks-guide pages), 2026-10-25 |
| Can a hook tell Bash is `git commit`/`push` (assumption) | Resolved as best-effort: the command is a string; compound/aliased/wrapped forms are not reliably decidable. Existing precedent already splits on `&& \|\| ; \| & newline` and bails on `$(`, backticks, `<<` | `plugin/hooks/approve-compound.sh:12-28` |

New finding, affects the PRD identifier assumption "the list is read through
`embo-profile get`": `embo-profile get` on a list field prints the YAML as
written, so a flow list prints `[unit, integration]` and a block list prints
`- a` lines (verified by running `embo-profile get rules.testing.scope`,
which printed `[unit, integration]`). The guard must parse both shapes. No PRD
requirement is invalidated.

**Discovered patterns**: fail-open shell hooks with a sibling plain-Bash
`.test.sh` that builds throwaway git repos; shared pure-function libs sourced
via `$HERE/../lib/`; commands call bare wrappers (`embo-profile`) not
`${...}` paths; the work-phase branch note already exists as a prose bullet in
the implementation command (`plugin/commands/impl.md:280-286`) with no
enforcement.

## Past Decisions (Claude-Mem)

Not consulted in this unattended run (memory search is outside the evidence
budget granted here); marked provisional. In-repo precedent substitutes: the
SessionStart hook chose fail-open for a warn-only check
(`branch-task-check.sh:15-17`), which does not transfer to a deny-capable
guard (see Decision D2).

**Independent review (2026-10-25).** The three provisional items below were
checked against the live Claude Code hooks docs
(https://code.claude.com/docs/en/hooks) and the actual plugin source, and all
resolve in this design's favour:
- Deny contract: `permissionDecision: "deny"` + `permissionDecisionReason` on
  exit 0 with `hookEventName: "PreToolUse"` present; exit 2 + stderr is a valid
  deliberate-deny fallback. Confirmed.
- `additionalContext` for warn: honoured on PreToolUse; emit with NO
  `permissionDecision`. Confirmed.
- Two PreToolUse hooks on `Bash`: precedence is **deny > defer > ask > allow**,
  hooks run in parallel, so the guard's deny wins over approve-compound's
  allow. Confirmed. One residual gap: approve-compound may emit `updatedInput`
  (a rewritten command, `approve-compound.sh:443`); the guard sees the
  ORIGINAL command (both hooks get the same input), so add a fixture with a
  rewritten compound and confirm the guard still denies. The claim that
  `embo-profile get` on a flow-style list retains `[a, b]` was not
  independently re-run — provisional.

## Proposed Design

### Architecture

```
PreToolUse stdin JSON
        |
        v
main-branch-guard.sh
  1. parse tool_name / tool_input / cwd          (jq)
  2. classify call -> {edit-path | git-mutation | shell-write | ignore}
        ignore -> exit 0 (no git, no profile read)           [NFR-1]
  3. branch = git -C cwd symbolic-ref --short -q HEAD
        detached / not a repo -> exit 0 (nothing to protect)
  4. policy = embo-profile get (3 fields), parsed, defaulted
        mode=off -> exit 0
  5. protected?  branch in list
        no  -> branch/task check (FR-5) or exit 0
        yes -> tracked-path / command test -> deny | warn | allow
```

Layering is a single shell hook plus two sourced libs; there is no UI,
domain, or data layer.

### Components

**New components**

1. **`plugin/hooks/main-branch-guard.sh`**
   - Purpose: the enforcement point (FR-1, FR-2, FR-3, FR-4, FR-5).
   - Pattern: `branch-task-check.sh` (sourced libs resolved from `$HERE`,
     early `bail` helper), but the exit/emit contract differs (below).
   - Dependencies: `jq`, `git`, `embo-profile` (needs `yq`), the two libs.
2. **`plugin/lib/git-command-lib.sh`**
   - Purpose: pure functions over a command string:
     `gcl_split` (subcommands, reusing the separator set of
     `approve-compound.sh`), `gcl_is_git_mutation <sub>` (commit, push, merge,
     rebase, cherry-pick, `git reset`, `git am`, `git revert`),
     `gcl_push_targets <sub> <current-branch>` (implicit current branch,
     explicit refspec `src:dst`, `HEAD`, `--all`/`--mirror`, `--delete`),
     `gcl_shell_write_paths <sub>` (`> / >>` targets, `tee`, `sed -i`),
     `gcl_walk <command> <current>` (branch in effect per subcommand) and
     `gcl_is_unparseable_candidate <command>`. Words are tokenised with
     quote awareness, so a `>` or `&&` inside a quoted commit message is not
     an operator. Implemented in Bash/awk (Bash 3.2 compatible) with no
     logging or exits, same convention as `branch-task-lib.sh`.
   - Pattern: `plugin/lib/branch-task-lib.sh`.
3. **`plugin/hooks/main-branch-guard.test.sh`** and
   **`plugin/lib/git-command-lib.test.sh`**: fixture tests (Testing Strategy).

**Modified components**

1. **`plugin/hooks/hooks.json:42-52`**: add a second PreToolUse entry with
   matcher `Edit|Write|NotebookEdit|Bash`. Kept separate from the
   `approve-compound.sh` entry so neither hook's matcher or failure mode
   changes (PRD constraint). Both hooks run on `Bash`; a deny from either
   blocks (exit 2 blocks regardless of other hooks' allow per the hooks docs;
   precedence between a JSON deny and another hook's allow is [provisional:
   confirm against the docs on implementation, and fixture-test by running the
   real registered hooks once]). Update the manifest `description`.
2. **`plugin/profiles/default.yaml:32-41`** and the `quality`, `fast`,
   `minimal`, `research` profiles: add the fields below under
   `rules.workflow` with the explanatory comments the file already uses.
   Other profiles inherit through the guard's own defaults if omitted, but
   shipped profiles should state the value explicitly so `embo-profile show`
   is self-documenting.
3. **`plugin/commands/impl.md:280-286`**: replace the prose-only "notice the
   branch" bullet with a one-line pointer that the guard enforces it per the
   profile mode (no task numbers in the text, per the repo rule).
4. **`CLAUDE.md` Safety Rules**: terse human note pointing at the hook (FR-7;
   CLAUDE.md is a dev-only file, so this carries no shipped behavior).
5. **Profile field documentation** (the profile command's field explanations,
   located during implementation) and README hook list: document the fields
   and the best-effort limit.

### Data Models

Profile fields (names decided here; the PRD deliberately left them open):

```yaml
rules:
  workflow:
    protected_branches: [main, master]   # list of exact branch names
    protected_branch_mode: block         # block | warn | off
    branch_task_mode: warn               # block | warn | off
```

Parsed policy (internal, shell variables): `PB_LIST` (newline-separated names),
`PB_MODE`, `BT_MODE`. Normalisation: strip `[` `]`, split on commas and
newlines, strip leading `- `, quotes, whitespace; an unknown mode value is
treated as `block` for `protected_branch_mode` and `warn` for
`branch_task_mode` and a one-line stderr notice is printed (an unreadable value
never silently disables the guard, PRD story 3). Branch matching is exact
string equality, not a glob, to avoid `main*` surprises; globs are a possible
later extension.

### API Design

Hook input: PreToolUse JSON on stdin. Fields used: `tool_name`,
`tool_input.file_path` (Edit/Write), `tool_input.notebook_path`
(NotebookEdit), `tool_input.command` (Bash), `cwd`. [file_path/notebook_path
key names are provisional until fixture-checked against a live payload; the
test suite includes one captured real payload fixture to pin them.]

Hook output contract (confirmed against the Claude Code hooks docs,
https://code.claude.com/docs/en/hooks, 2026-10-25):

| Outcome | Emission |
|---|---|
| allow | exit 0, no output. Note: a silent exit 0 is "no decision" — the call continues through the normal permission flow, it is NOT an approval. The guard never emits an explicit `permissionDecision: "allow"` (that would pre-approve a call that would otherwise prompt). |
| deny (`block`) | exit 0 with `hookSpecificOutput` JSON carrying `hookEventName: "PreToolUse"`, `permissionDecision: "deny"`, and `permissionDecisionReason` per FR-3 (branch, why, fix). The reason is shown to Claude. Exit 2 + stderr is the fallback form ONLY for a deliberate deny if JSON emission fails — never for an internal error (see Error Handling). |
| warn | exit 0 with `hookSpecificOutput` carrying `hookEventName: "PreToolUse"` and `additionalContext` (the warning text), and NO `permissionDecision` — an explicit "allow" would wrongly pre-approve the call. `additionalContext` is honoured for PreToolUse per the docs field table. A stderr line is secondary (shown to the user/debug log, not reliably to the model). |

`hookEventName: "PreToolUse"` is required inside `hookSpecificOutput`
(docs). The deny and warn test cases must assert its presence.

Message template: `main-branch-guard: <branch> is a protected branch; <what
was refused>. Create a feature branch first (git switch -c <type>/<task>-<slug>)
or change rules.workflow.protected_branch_mode in your profile.` No task
numbers beyond the live branch/task being named.

Classification detail:

- **Edit/Write/NotebookEdit**: deny only when the target path is a tracked file
  (`git ls-files --error-unmatch -- <path>` inside the repo) so scratch output
  and untracked/ignored files are not blocked (story 1 AC3). A path outside the
  repo is ignored. A new, not-yet-tracked file in the repo is allowed (it is
  not a modification of tracked history); `git commit` is the choke point that
  prevents it from landing on the protected branch.
- **Bash**: split into subcommands; for each, deny when it is a git mutation
  (commit, merge, rebase, cherry-pick, am) while the current branch is
  protected; `push` is denied when its targets include a protected
  branch (current branch implicit, `HEAD`, explicit refspec, `--all`,
  `--mirror`) so that `git push origin feature` while on `main` is allowed but
  `git push origin HEAD:main` from a feature branch is also denied; shell
  writes (`>`, `>>`, `tee`, `sed -i`) are denied when the target resolves to a
  tracked path. Any unparseable construct (`$(`, backticks, `<<`,
  `eval`, `bash -c`, `sh -c`): treated as a candidate and denied in `block`
  mode only if it contains a literal `git commit|push|merge` or write token;
  otherwise allowed (best-effort limit, documented).
- **Branch-create in a compound must NOT be a false denial.** The branch is
  read once, before the command runs, so a compound whose *first* act leaves
  the protected branch — `git switch -c <b> && git commit`,
  `git checkout -b <b> && …` — would otherwise be denied for being "on
  main", which is the exact corrective action the deny message recommends.
  `gcl_walk` reports the branch in effect at EACH split subcommand, and each
  mutation is judged against the branch at its own position (so
  `git commit && git switch -c b` is still a commit on the protected
  branch). Branch changers: `switch <b>` / `-c` / `-C` / `--orphan`,
  `switch --detach`, `checkout -b` / `-B` / `--orphan`, `checkout --detach`.
  A plain `checkout <x>` is ambiguous (branch or path) and leaves the branch
  unchanged — the conservative reading. `git worktree add` does not move the
  shell, so it changes nothing by itself; a later `cd <that path>` in the
  same compound moves onto the worktree's branch (`-b <b>`, else the
  commit-ish argument, else the path's basename). The walk assumes `&&`
  chaining; a `;` after a failed switch is a known best-effort gap.
- **Mutation classification is per subcommand AND per flag, not per verb.**
  `git reset` (default, non-destructive unstage) and `git revert` are NOT
  blanket mutations; `git reset --hard` on a protected branch is a plausible
  deliberate user action — decide by flag, and state the chosen policy in the
  test matrix. Bare `switch`/`checkout`/`fetch`/`pull`/`stash`/`add`/`status`
  are never mutations. Whether `git pull` (fast-forward) on a protected branch
  is allowed is an explicit matrix entry (default: allowed).
- The push-to-protected-branch rule applies even when the checked-out branch is
  not protected (incident variant), so branch lookup precedes but does not gate
  the push check.

### Integration Points

- `embo-profile get <field>`: three calls, only after a candidate mutation was
  recognised. Called as a bare command, matching the wrapper convention.
- `branch-task-lib.sh`: `branch_task_matches`, `branch_task_derive_from_paths`
  reused for FR-5; no second match definition (story 4 AC3).
- `hooks.json`: new PreToolUse entry. `approve-compound.sh` is unchanged.
- FR-5 trigger: PRD leaves hook-vs-command open. Decided as hook-side (D5), on
  the first mutating call of a session (marker file keyed by `session_id`
  under the guard's own state dir in the project git-ignored `tmp/`, never
  `/tmp`).
  - **Task source (revised — the path-only derivation is too weak).** At the
    first edit the tree is usually clean and code-file edits carry no task
    number, so deriving the task from the call's target path or from
    uncommitted changes silently no-ops in the seed's own incident (code work
    on a finished task's branch). `/embo:impl` therefore records the active
    task number in a small state file (an `embo-profile`-style bin writing the
    project git-ignored `tmp/`), and the guard reads THAT as the primary
    source, falling back to the path/uncommitted derivation only when the
    state file is absent. Without the `/embo:impl` state file, FR-5 coverage
    is best-effort and the PRD claim must be marked so.
  - **Block-mode semantics (made consistent).** The marker suppresses repeats
    in BOTH modes: `warn` emits one line and records the marker; `block`
    denies once with the create/switch suggestion and records the marker, and
    the agent's retry is then NOT re-denied by this check — the one denial has
    delivered the guidance, and re-denying on every subsequent call would
    wedge the run. (The protected-branch guard FR-1/FR-2 still applies on its
    own terms; FR-5 is the softer branch/task-match nudge.) Fail open when no
    single task is derivable.

### Error Handling

State-determination failures follow a defined policy (NFR-2, decision D2):

| Condition | Behaviour |
|---|---|
| Not a git repo, detached HEAD | Allow silently: no branch, nothing to protect |
| `jq` missing / payload not JSON | Allow, stderr line `main-branch-guard: cannot parse payload, guard inactive` (loud, non-blocking) |
| Profile unreadable (`yq` missing, no profile, yq error) | Apply built-in defaults (`main`,`master`, `block`) and print a stderr notice; the guard does not silently go off |
| Field absent | Default for that field |
| Unknown mode value | Safe default + stderr notice |
| Unexpected internal failure (`set -u` trap, lib not sourced) | Allow with stderr notice: a broken guard must never wedge the whole session, but it is announced |

The guard performs no destructive git action (NFR-4): read-only `git`
commands only (`symbolic-ref`, `ls-files`, `rev-parse`, `status`).

### Testing Strategy

Plain-Bash fixtures, same style as `branch-task-check.test.sh`: throwaway repos
built per case in `mktemp -d`; payloads piped to the hook as JSON via `jq -n`;
profile driven through `EMBO_PROFILE_ACTIVE` pointing at a case-local file so
the real `~/.claude` is never touched. Matrix: mode block/warn/off x
protected/unprotected branch x tracked/untracked path x Edit/Write/Bash x
commit/push (implicit, `HEAD`, refspec to `main`, `--all`) x fail-open cases
(no repo, detached HEAD, bad payload, missing profile, unknown mode, list in
flow and block YAML shapes). `git-command-lib.test.sh` covers the splitter and
push-target parser in isolation. FR-5 cases: matching branch silent, mismatch
warn/block, marker suppresses repeat, tie/no-task silent. One real-payload
fixture pins the key names. Suite runs via `bash plugin/hooks/main-branch-guard.test.sh`.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1: deny edits/mutating Bash on protected branch | `auto-test` | unit | guard test: all block-mode cases deny |
| FR-2: deny commit/push to protected branch | `auto-test` | unit | guard + lib tests: implicit, `HEAD`, refspec, `--all` denied |
| FR-3: message names branch, reason, fix | `auto-test` | unit | assertions on reason text content |
| FR-4: policy from profile with defaults | `auto-test` | unit | field absent / unreadable / unknown-mode cases use defaults |
| FR-5: branch/task mismatch before first edit | `auto-test` | unit | mismatch warn/block, marker, tie cases |
| FR-6: registered and tested | `auto-test` | unit | `jq` check of `hooks.json` entry; test file exits 0 |
| FR-7: Safety Rules note | `code-only` | - | - |
| Registered hook denies in a live session | `manual-run-claude` | integration | real Edit on `main` refused with guard message; `approve-compound` still works on Bash |
| Success metric 2: zero false denials | `auto-test` | unit | unprotected/off cases all allow |

## Trade-offs

1. **Option A: extend `approve-compound.sh` or the SessionStart hook.**
   Pros: no new registration. Cons: changes an existing hook's matcher and
   failure mode (forbidden by PRD constraint); SessionStart cannot block.
   Rejected.
2. **Option B: one new PreToolUse hook + command-recognition lib (chosen).**
   Pros: isolated failure mode, testable parser, reuses branch-task lib.
   Cons: two PreToolUse hooks now run on Bash; best-effort Bash parsing.
3. **Option C: deny every Bash mutation by default-deny allowlist.** Pros:
   tighter. Cons: unworkable false-denial rate on a general shell; violates
   success metric 2. Rejected.
4. **Option D: rely on git `pre-commit`/`pre-push` hooks.** Pros: catches all
   shell forms. Cons: PRD out of scope (outside the agent), must be installed
   per clone, not enforceable from a plugin. Rejected, but recommended as the
   user-side complement alongside remote protection.
5. **FR-5 as a separate hook vs inside the guard.** Inside chosen: one payload
   parse, one profile reader, shared marker logic. Alternative (extend the
   `impl.md` prose) is the status quo that this feature exists to replace.

## Implementation Constraints

**From existing architecture**
- Hooks are shell + `jq`; no new runtime deps beyond `yq` (already required).
- Never inline `${CLAUDE_PLUGIN_ROOT}` in command bodies; hooks.json may use it
  as existing entries do.
- Shipped command/agent bodies must not carry task numbers; hook scripts and
  tests are exempt.
- Emit no output on the allow path (a chatty hook on every Edit is noise).

**From past experience**: not consulted (provisional).

## Files to Create/Modify

**Create**
- `plugin/hooks/main-branch-guard.sh` - the guard
- `plugin/hooks/main-branch-guard.test.sh` - fixture tests
- `plugin/lib/git-command-lib.sh` - command recognition
- `plugin/lib/git-command-lib.test.sh` - lib tests

**Modify**
- `plugin/hooks/hooks.json:42-52` - register the PreToolUse entry, update description
- `plugin/profiles/default.yaml:32-41` and `quality|fast|minimal|research.yaml` - three new fields
- `plugin/commands/impl.md:280-286` - point at the guard
- `CLAUDE.md` Safety Rules - terse note
- profile field explanations and README hook list - document fields and best-effort limit

## Dependencies

**External**: `jq` (already used by hooks), `yq` (already required by
`embo-profile`), `git`.
**Internal**: `plugin/lib/branch-task-lib.sh`, `plugin/bin/embo-profile`.

## Security Considerations

Not a security boundary: Bash is Turing-complete, so interpreters, scripts,
aliases, and `bash -c` wrappers can bypass it. Stated in user docs; remote
branch protection is the complement. The guard never executes tool input; the
command string is only pattern-matched, never `eval`ed. Paths from the payload
are passed to git after `--` to prevent option injection. The state marker is
written inside the project `tmp/`.

## Performance Considerations

Non-matching tools exit before any `git` or profile call (one `jq` parse).
Candidate calls cost one `git symbolic-ref` plus up to three `embo-profile get`
runs (each a `yq` invocation); expected well under the interactive threshold
but unmeasured, so the fixture suite includes a timing smoke check and the
three reads can be collapsed to one `embo-profile show | yq` if it matters.

## Rollback Plan

Set `rules.workflow.protected_branch_mode: off` (no code change), or remove the
PreToolUse entry from `hooks.json` and reload plugins. The change is additive:
new files plus one manifest entry and defaulted profile fields; reverting the
commit restores prior behaviour.

## Decisions-taken

The mandatory clarifying-question step was skipped (unattended); each
question was decided from evidence.

1. **D1 Architecture**: a single new PreToolUse hook plus a pure command lib,
   not an extension of existing hooks. Evidence: PRD constraint against
   changing existing hook failure modes; `hooks.json:42-52`.
2. **D2 Fail policy (PRD decision 6 / NFR-2)**: fail open when there is nothing
   to protect (no repo, detached HEAD) or the guard itself breaks, but always
   with a stderr notice; fail to the built-in default policy (block
   `main`/`master`) when the profile is unreadable. Reason: a deny-capable guard
   that silently disables itself reproduces the original incident; one that
   wedges the session on an internal bug is worse. Evidence:
   `branch-task-check.sh:15-17` (precedent is warn-only), PRD story 3 AC3.
3. **D3 Field names**: `rules.workflow.protected_branches`,
   `protected_branch_mode`, `branch_task_mode`. Evidence: seed suggestion
   (`SEED.md:38-44`) and the existing `rules.workflow` group
   (`default.yaml:32-41`).
4. **D4 Deny emission**: JSON `permissionDecision: "deny"` on exit 0, exit 2 as
   fallback. Evidence: hooks docs (decision control table, exit-code-2 section).
5. **D5 FR-5 trigger**: hook-side, first mutation per session, `warn` default.
   Evidence: the existing prose-only bullet at `impl.md:280-286` is
   unenforced; a hook is the only mechanism firing on free-form edits.
6. **D6 Tracked-path rule**: block only tracked files for Edit/Write; allow new
   untracked files. Evidence: PRD story 1 AC3.
7. **D7 Branch list matching**: exact names, no globs, flow- and block-style
   YAML parsed. Evidence for flow/block parsing: observed `embo-profile get`
   list output shape. Evidence for no-glob: a glued glob is a known trap —
   in the existing `approve-compound.sh` deny matcher a rule like
   `Bash(… main*)` silently fails to match (its matcher supports only exact,
   space-star `cmd *`, and colon-star `cmd:*` shapes), verified by executing
   that hook under bash. Exact string equality avoids re-introducing that
   class of silent-no-match bug here. Globs are a possible later extension if
   a real need appears.
8. **D8 Push rule independent of current branch**: deny pushes whose target is
   protected even from a feature branch. Evidence: PRD FR-2 "targeting a
   protected branch".
9. **D9 Shipped profiles state the fields explicitly**: so `show` documents
   them; guard defaults cover omissions.

BLOCKED: none.

Resolved by independent review (2026-10-25, against the live hooks docs):
`additionalContext` honoured for warn (emit with no `permissionDecision`);
deny-vs-allow precedence is deny > defer > ask > allow with parallel
execution, so the guard's deny wins. Remaining provisional: exact
`file_path`/`notebook_path` key names (pin with a real-payload fixture);
the `updatedInput` rewrite interaction (add a fixture); claude-mem history
not consulted. Closed: `embo-profile get` keeps a flow list as written —
`rules.workflow.protected_branches` printed `[main, master]` (2026-10-27).

**Relationship to the shipped stopgap (keep both).** A `permissions.deny`
rule in tracked `.claude/settings.json`
(`Bash(git push origin main *)` / `master`), enforced by the existing
`approve-compound.sh`, already ships as a baseline guard. It needs no `yq`,
no profile, and no hook reload, and it survives a broken or disabled version
of THIS guard — exactly the D2 failure mode. This hook is the profile-driven
superset (it also catches `HEAD:main`, `--all`, implicit push from main, and
Edit/Write on tracked files). Do NOT remove the deny rule when this hook
lands; keep it as defense-in-depth. Both fire on `git push origin main` and
both deny — harmless redundancy; the only visible difference is which reason
the user sees. Revisit only if the two ever produce conflicting messages.
Edit-path resolution note: run `git ls-files` with `-C` on the file's OWN
directory, not the session `cwd` (the target may be in another worktree or
submodule); add fixtures for a path in another repo and a path outside any
repo.

## References

### Code (RLM)
- `plugin/hooks/branch-task-check.sh`: bail/source/fail-open structure to follow
- `plugin/lib/branch-task-lib.sh`: shared match rule to reuse
- `plugin/hooks/approve-compound.sh:12-40`: separator split and redirect stripping to mirror
- `plugin/bin/embo-profile:88-99`: field reader and its list output shape
- `plugin/hooks/branch-task-check.test.sh`: fixture-test pattern

### History (Claude-Mem)
- Not consulted (unattended); provisional.

---

**Next Steps**:
1. Review and approve design
2. Run `/embo:tasks` for task breakdown
