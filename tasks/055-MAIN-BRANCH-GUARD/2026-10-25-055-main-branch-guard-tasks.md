# 055: Main Branch Guard - Task List

## Relevant Files
- [tasks/055-MAIN-BRANCH-GUARD/2026-10-25-055-main-branch-guard-tech-design.md](2026-10-25-055-main-branch-guard-tech-design.md)
  :: Main Branch Guard - Technical Design
- [tasks/055-MAIN-BRANCH-GUARD/2026-10-25-055-main-branch-guard-prd.md](2026-10-25-055-main-branch-guard-prd.md)
  :: Main Branch Guard - Product Requirements Document
- [plugin/hooks/main-branch-guard.sh](../../plugin/hooks/main-branch-guard.sh)
  :: NEW. The PreToolUse guard (allow / warn / deny).
- [plugin/hooks/main-branch-guard.test.sh](../../plugin/hooks/main-branch-guard.test.sh)
  :: NEW. Fixture tests for the guard.
- [plugin/lib/git-command-lib.sh](../../plugin/lib/git-command-lib.sh)
  :: NEW. Pure functions that recognise git/shell mutations in a command
  string.
- [plugin/lib/git-command-lib.test.sh](../../plugin/lib/git-command-lib.test.sh)
  :: NEW. Tests for the command library.
- [plugin/lib/branch-task-lib.sh](../../plugin/lib/branch-task-lib.sh)
  :: Existing shared branch/task match rule, reused for the mismatch check.
- [plugin/hooks/branch-task-check.sh](../../plugin/hooks/branch-task-check.sh)
  :: Existing fail-open hook; structure to follow.
- [plugin/hooks/branch-task-check.test.sh](../../plugin/hooks/branch-task-check.test.sh)
  :: Existing fixture-test pattern to follow.
- [plugin/hooks/approve-compound.sh](../../plugin/hooks/approve-compound.sh)
  :: Existing separator-split logic to mirror; must stay unchanged.
- [plugin/hooks/hooks.json](../../plugin/hooks/hooks.json)
  :: Register the new PreToolUse entry; update the description.
- [plugin/bin/embo-profile](../../plugin/bin/embo-profile)
  :: Profile reader; its list output shape (flow and block YAML) must be
  parsed.
- [plugin/profiles/default.yaml](../../plugin/profiles/default.yaml)
  :: Add the three workflow fields (also quality, fast, minimal, research).
- [plugin/commands/impl.md](../../plugin/commands/impl.md)
  :: Replace the prose-only branch bullet with a pointer to the guard.
- [CLAUDE.md](../../CLAUDE.md) :: Terse Safety Rules note.
- [README.md](../../README.md) :: Hook list and best-effort limit.

## Notes
- Tests are plain Bash: `bash plugin/hooks/main-branch-guard.test.sh` and
  `bash plugin/lib/git-command-lib.test.sh`. Each case builds a throwaway
  repo with `mktemp -d`, pipes a JSON payload built with `jq -n`, and points
  `EMBO_PROFILE_ACTIVE` at a case-local file so `~/.claude` is never touched.
- The guard emits nothing on the allow path, never runs destructive git, and
  never `eval`s tool input. Paths go to git after `--`.
- Shipped command/agent bodies and README must not carry task numbers or
  `tasks/` paths; hook scripts and tests are exempt.
- Use the bare `embo-profile` wrapper, never an inlined plugin-root path.
- Provisional items to confirm during implementation (tech design): the
  PreToolUse `additionalContext` for warn, deny-vs-allow precedence when two
  PreToolUse hooks match `Bash`, and the `file_path`/`notebook_path` key
  names (pinned by one captured real-payload fixture).

## TDD Planning Guidelines
- Test external behavior only: the hook's stdin/stdout/exit code and the
  library's function results.
- Alternate test then implementation in small chunks; skip TDD for pure
  config and docs edits.

## Tasks
- [ ] 1.0 **User Story:** As a maintainer, I want the profile to carry the
  guard policy with safe defaults so that a branching policy change is a
  profile edit, not a code change [0/0]
  - [ ] 1.1 Add `protected_branches: [main, master]`,
    `protected_branch_mode: block` and `branch_task_mode: warn` under
    `rules.workflow` in `plugin/profiles/default.yaml`, with explanatory
    comments in the file's existing style [verify: code-only]
  - [ ] 1.2 Add the same three fields explicitly to the `quality`, `fast`,
    `minimal` and `research` profiles [verify: code-only]
  - [ ] 1.3 Run `embo-profile get rules.workflow.protected_branches` and
    `embo-profile get rules.workflow.protected_branch_mode`; confirm the
    list prints as `[main, master]` and the mode as `block`
    [verify: manual-run-claude]
  - [ ] 1.4 Document the three fields and the best-effort limit in the
    profile field explanations (locate the profile command's explanation
    section first) [verify: code-only]

- [ ] 2.0 **User Story:** As the guard, I want to recognise git history
  mutations, push targets and shell writes in a command string so that Bash
  denials are decided by a unit-tested parser [0/0]
  - [ ] 2.1 Write `plugin/lib/git-command-lib.test.sh` for `gcl_split`:
    splits on `&&`, `||`, `;`, `|`, `&`, newline, mirroring the separator
    set in `plugin/hooks/approve-compound.sh:12-28` [verify: auto-test]
  - [ ] 2.2 Implement `gcl_split` in `plugin/lib/git-command-lib.sh` (pure
    function, no output side effects or exits, same convention as
    `branch-task-lib.sh`) [verify: auto-test]
  - [ ] 2.3 Write tests for `gcl_is_git_mutation`: commit, merge, rebase,
    cherry-pick, am, and `git reset --hard`/`--soft`/`--mixed` to a ref are
    mutations; status, log, diff, branch listing, bare `switch`/`checkout`/
    `fetch`/`pull`/`stash`/`add`, and bare `git reset` (default unstage) are
    NOT; decide per flag, not per verb [verify: auto-test]
  - [ ] 2.4 Implement `gcl_is_git_mutation` (per-subcommand AND per-flag)
    [verify: auto-test]
  - [ ] 2.4b Write tests for branch-change tracking across a compound:
    `git switch -c <b> && git commit`, `git checkout -b <b> && …`,
    `git worktree add …` leave the protected branch BEFORE the mutation, so
    the mutation is judged against the new branch and is NOT denied; implement
    a `gcl_simulated_branch <subcommands> <current>` helper [verify: auto-test]
  - [ ] 2.5 Write tests for `gcl_push_targets`: implicit current branch,
    `HEAD`, `origin HEAD:main`, explicit `src:dst`, `--all`, `--mirror`,
    `--delete`, and `git push origin feature` while on `main` yields only
    `feature` [verify: auto-test]
  - [ ] 2.6 Implement `gcl_push_targets` [verify: auto-test]
  - [ ] 2.7 Write tests for `gcl_shell_write_paths`: `>` and `>>` targets,
    `tee`, `sed -i`; read-only commands yield none [verify: auto-test]
  - [ ] 2.8 Implement `gcl_shell_write_paths` [verify: auto-test]
  - [ ] 2.9 Write tests for unparseable constructs (`$(`, backticks, `<<`,
    `eval`, `bash -c`, `sh -c`): flagged as a candidate only when a literal
    `git commit|push|merge` or write token is present, otherwise not
    [verify: auto-test]
  - [ ] 2.10 Implement the unparseable-construct handling
    [verify: auto-test]

- [ ] 3.0 **User Story:** As a developer, I want edits to tracked files
  refused while a protected branch is checked out so that the agent must
  branch first [0/0]
  - [ ] 3.1 Create `plugin/hooks/main-branch-guard.test.sh` scaffolding
    (throwaway repo helper, payload builder, profile fixture, assert
    helpers) following `plugin/hooks/branch-task-check.test.sh`
    [verify: auto-test]
  - [ ] 3.2 Write guard tests for Edit/Write/NotebookEdit: tracked file on
    `main` in `block` denies with a message naming the branch and the
    `git switch -c` fix; the same on `warn` allows with a visible warning;
    `off` allows silently; untracked, ignored and out-of-repo paths allow;
    a new untracked file allows; unprotected branch allows
    [verify: auto-test]
  - [ ] 3.3 Implement `plugin/hooks/main-branch-guard.sh` core: parse
    `tool_name`, `tool_input`, `cwd` with `jq`; early exit for non-candidate
    calls before any git or profile call; branch lookup via
    `git -C <cwd> symbolic-ref --short -q HEAD`; tracked-path test via
    `git ls-files --error-unmatch -- <path>` [verify: auto-test]
  - [ ] 3.4 Implement policy loading: three `embo-profile get` calls parsed
    from flow and block YAML list shapes, defaults `main`/`master` and
    `block`/`warn`, unknown mode falls back to the safe default with a
    stderr notice [verify: auto-test]
  - [ ] 3.5 Implement the output contract: allow is silent exit 0 (no
    explicit "allow"); deny is exit 0 with `hookSpecificOutput` carrying
    `hookEventName: "PreToolUse"`, `permissionDecision: "deny"` and the
    `permissionDecisionReason` (branch, why, fix); warn is `hookEventName` +
    `additionalContext` with NO `permissionDecision`, plus a secondary stderr
    line; exit 2 + stderr is the fallback ONLY for a deliberate deny, never an
    internal error. Assert `hookEventName` is present in deny and warn output
    [verify: auto-test]
  - [ ] 3.6 Pin the payload key names with one captured real-payload
    fixture in the test file and confirm `file_path` / `notebook_path`
    [verify: auto-test]

- [ ] 4.0 **User Story:** As a developer, I want commits and pushes refused
  when they target a protected branch so that nothing is committed to or
  published from it [0/0]
  - [ ] 4.1 Write guard tests for Bash on a protected branch in `block`:
    `git commit`, merge, rebase, cherry-pick and redirects or `sed -i` onto
    tracked paths deny; compound forms such as `git add . && git commit`
    deny; BUT `git switch -c feat/x && git commit` and
    `git checkout -b feat/x && git commit` ALLOW (branch-create precedes the
    mutation — a false denial here blocks the deny message's own fix);
    read-only commands allow [verify: auto-test]
  - [ ] 4.2 Write guard tests for push: implicit push on `main`, `HEAD`,
    `origin HEAD:main` from a feature branch, `--all`, `--mirror`,
    `--delete main`, `--force`-to-main and `+src:main` deny;
    `git push origin feature` while on `main` allows; `warn` and `off`
    modes behave per the mode [verify: auto-test]
  - [ ] 4.3 Implement the Bash branch of the guard using
    `git-command-lib.sh`; the push-target rule runs regardless of whether
    the checked-out branch is protected [verify: auto-test]
  - [ ] 4.4 Write tests that denial text states branch, reason and fix, and
    contains no internal task references [verify: auto-test]

- [ ] 5.0 **User Story:** As a developer, I want the guard to fail visibly
  and never silently switch itself off so that a broken guard does not
  repeat the original incident nor wedge the session [0/0]
  - [ ] 5.1 Write tests for the fail policy: no repo and detached HEAD allow
    silently; non-JSON payload or missing `jq` allows with a stderr notice;
    unreadable profile (missing `yq`, no profile, yq error) applies the
    built-in defaults with a stderr notice; absent field uses its default
    [verify: auto-test]
  - [ ] 5.2 Implement the fail policy, including a trap so an unexpected
    internal failure (unbound variable, lib not sourced) allows with a
    stderr notice [verify: auto-test]
  - [ ] 5.3 Add a timing smoke check to the suite for a non-matching tool
    call (no git or profile call) and a candidate call [verify: auto-test]

- [ ] 6.0 **User Story:** As a developer, I want a branch/task mismatch
  reported before the first edit of an implementation run so that work does
  not land on a finished task's branch [0/0]
  - [ ] 6.0a Have `/embo:impl` record the active task number in a small
    project-git-ignored `tmp/` state file (keyed by `session_id`), written via
    an `embo-profile`-style bin; this is the guard's PRIMARY task source,
    since at the first edit the tree is usually clean and code-file edits
    carry no task number (the path/uncommitted derivation silently no-ops in
    the seed's own incident) [verify: auto-test]
  - [ ] 6.1 Write tests for the mismatch check: matching branch silent;
    mismatch in `warn` emits one line with a create/switch suggestion;
    mismatch in `block` denies ONCE then records the marker and does NOT
    re-deny the retry (the single denial delivered the guidance; re-denying
    every call would wedge the run); the per-session marker (keyed by
    `session_id`, under the project git-ignored `tmp/`) suppresses repeats in
    BOTH modes; active-task state file present vs absent (fallback to path
    derivation); no derivable task or a tie stays silent; `off` mode silent
    [verify: auto-test]
  - [ ] 6.2 Implement the mismatch check in the guard: read the active-task
    state file first, else fall back to `branch_task_derive_from_paths`;
    reuse `branch_task_matches` from `plugin/lib/branch-task-lib.sh` (no
    second match definition). Mark FR-5 coverage best-effort when no state
    file and no derivable task [verify: auto-test]
  - [ ] 6.3 Replace the prose-only branch bullet in
    `plugin/commands/impl.md` with a one-line pointer that the guard
    enforces it per the profile mode, with no task numbers
    [verify: code-only]

- [ ] 7.0 **User Story:** As a maintainer, I want the guard registered,
  documented and verified live so that it ships like every other hook
  [0/0]
  - [ ] 7.1 Add a second PreToolUse entry to `plugin/hooks/hooks.json` with
    matcher `Edit|Write|NotebookEdit|Bash` calling the guard, leaving the
    `approve-compound.sh` entry untouched; update the manifest description
    [verify: auto-test]
  - [ ] 7.2 Add a test (or test-file assertion) that checks the registered
    entry with `jq` and that the guard test file exits 0
    [verify: auto-test]
  - [ ] 7.3 Add the terse Safety Rules note to `CLAUDE.md` pointing at the
    hook as the enforcement [verify: code-only]
  - [ ] 7.4 Add the guard to the README hook list and state the best-effort
    limit and the remote-branch-protection complement, with no task
    references [verify: code-only]
  - [X] 7.5 Confirm the provisional behaviours against current hooks docs
    (`additionalContext` for warn, deny precedence with two matching
    PreToolUse hooks) and record the outcome in the design notes — DONE
    (independent review 2026-10-25 against https://code.claude.com/docs/en/hooks;
    recorded in the tech-design "Past Decisions" and final BLOCKED note).
    Note: this gates the 3.5 emission contract, so it belongs FIRST in the
    work order, not last [verify: manual-run-claude]
  - [ ] 7.6 Add an integration fixture that runs BOTH registered PreToolUse
    hooks on `git push origin main` (approve-compound + the guard) and
    confirms a clean deny, and on a compound approve-compound would rewrite
    (`updatedInput`) that the guard still denies against the ORIGINAL command
    [verify: auto-test]
  - [ ] 7.7 After `/reload-plugins`, in a live session on `main`: a real
    Edit of a tracked file is refused with the guard message and
    `approve-compound` still approves a compound Bash command
    [verify: manual-run-user]

## Decisions-taken

The mandatory clarifying-question step was skipped (unattended); each scope
question was decided from evidence.

1. **Scope clarity**: the design is specific (files, fields, outputs,
   test matrix), so no scope question remains open. Evidence: tech design
   "Files to Create/Modify".
2. **Build vs reuse**: reuse `branch-task-lib.sh` and `embo-profile get`;
   build only the new command lib and hook. Evidence: tech design D1, PRD
   story 4 AC3.
3. **Order**: profile fields first (policy exists before the guard reads
   it), then the pure command lib, then edit guard, then Bash guard, then
   fail policy, mismatch check, and registration last so a half-built guard
   is never live. Evidence: dependency chain in tech design Components.
4. **Registration last (7.1)**: avoids a partially implemented hook
   running on every tool call during development. Evidence: hook runs
   once registered per `hooks.json`; reload needed per CLAUDE.md.
5. **Verification tags**: logic and hook behavior are `auto-test` (plain
   Bash fixtures exist as precedent); config and docs are `code-only`;
   the live refusal is `manual-run-user` because it needs a reloaded
   plugin in an interactive session. Evidence: tech design Verification
   Approach table. Tag for 7.5 is `manual-run-claude` as it is a docs
   check.
6. **Granularity**: seven stories, test-then-implement pairs for logic
   (tech design is moderately large; two libs plus hook). Complexity
   estimate not run (RLM step skipped; granularity judged from the design's
   file list).
7. **Claude-mem velocity**: not consulted in unattended mode; granularity
   judged from the design alone (provisional).
8. **Story counts**: `[0/0]` placeholders are intentionally left for
   `/embo:impl` to maintain.

BLOCKED: none.

---

**Next Steps**:
1. Review the task list
2. Run `/embo:impl` to start implementation
