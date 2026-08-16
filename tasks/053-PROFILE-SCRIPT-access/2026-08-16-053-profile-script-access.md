# 053: Read the active profile through a pre-approved script, not a file read

Compact combined doc (problem + decisions + scope + tasks), same style
as tasks 040/042.

## Problem

Every embo command that adapts to the active profile reads
`~/.claude/active-profile.yaml` directly — as `cat ~/.claude/...`
(`start.md`, `git.md`) or a prose "Read `~/.claude/active-profile.yaml`"
that becomes a `Read`/`cat` (`prd.md`, `tech-design.md`, `tasks.md`,
`impl.md`, `health.md`, `init.md`, `profile.md`).

Each such read is an approval-gate risk. The only way to pre-approve a
raw file read is to whitelist reading under `~/.claude/` — far too
broad for a single file, and no one will grant it. The plugin already
solved this exact shape for RLM and corrections with a bin wrapper
(`rlm_repl`, `embo-corrections`): a bare command on PATH auto-approves
under a narrow `Bash(<cmd> *)` allow rule, with no env-var expansion and
no absolute path. The profile read should use the same mechanism.

Verified 2026-08-16:
- `start.md:33` runs `cat ~/.claude/active-profile.yaml 2>/dev/null ||
  echo "NO_PROFILE"`, pre-authorized by a frontmatter
  `Bash(cat ~/.claude/active-profile.yaml *)` entry — verified via:
  `plugin/commands/start.md:3,33`.
- 9 command files reference `~/.claude/active-profile.yaml` — verified
  via: `grep -rln active-profile.yaml plugin/`.
- No profile file is present in this environment; commands fall back to
  defaults — verified via: `cat ~/.claude/active-profile.yaml` → absent.

## Decisions

1. **A bin wrapper on PATH owns the full profile lifecycle** — new
   `plugin/bin/embo-profile`, modelled on `plugin/bin/rlm_repl` and
   `plugin/bin/embo-corrections` (self-resolves its own location via
   `BASH_SOURCE`, follows symlinks). Rather than a read-only helper, it
   owns every profile operation, the same way `embo-corrections` owns
   the corrections lifecycle. Subcommands:
   - `show` — print the active profile's contents, or the literal
     `NO_PROFILE` when absent (the string `start.md` already keys on).
   - `get <field>` — print one field (e.g. `tools.rlm`,
     `git.commit_style`), so a command can query just what it needs
     without parsing YAML.
   - `set <name>` — make a named/built-in profile active (copy
     `profiles/<name>.yaml` → `active-profile.yaml`); absorbs
     `profile.md`'s switch step.
   - `reset` — remove `active-profile.yaml` so defaults apply; absorbs
     `profile.md`'s reset step.
   The file access happens inside the wrapper, off the approval path.
2. **Load once at session start, reuse from context** — `/embo:start`
   calls `embo-profile show` once and echoes the profile into the
   session summary. Later commands read the profile from session
   context, NOT by re-invoking the script every action: the profile is
   session-stable and rarely changes mid-session (and if it does, the
   change is visible in the session). A command run WITHOUT a prior
   `/embo:start` (profile not in context) falls back to calling
   `embo-profile show` itself — gate-free, since the command is
   whitelisted.
3. **Whitelist a single narrow rule** — `Bash(embo-profile *)`, the same
   convention as `Bash(rlm_repl *)`. This replaces the need to whitelist
   `Read(~/.claude/...)` or `Bash(cat ~/.claude/active-profile.yaml *)`.
3a. **Script emits raw VALUES, never resolved rules (design A)** — the
   wrapper's `show`/`get` output config data (`rlm: false`); the
   *interpretation* ("skip RLM analysis") stays in the authored command
   text. A rejected alternative (design B) had the script emit the
   directive itself. Rejected because a directive arriving as tool/Bash
   output sits below authored instructions in the model's instruction
   hierarchy and is actively down-weighted by prompt-injection defenses
   — so a script-emitted rule is obeyed LESS reliably than the same rule
   in a command file. Two independent `/embo:research:examine` passes
   agreed (2026-08-16; sources incl. Wallace et al. 2024 "The
   Instruction Hierarchy", Anthropic model-spec "tool results are
   untrusted data"). A "authored file says: obey this output"
   meta-directive does not fix it — it is itself prose the model may
   drop, the exact failure "Enforce, Don't Ask" exists to remove.
   Consequence: `get <field>` stays (raw value = safe datum); no
   `load --rules` directive output.

   B is rejected under the CURRENT architecture, not in principle — it
   would be better (resolution logic in one script, not prose duplicated
   across commands) IF tool-output authority could be raised to
   authored-rule level. FOLLOW-UP RESEARCH: whether such elevation is
   achievable (e.g. a hook promoting a trusted command's stdout into the
   instruction tier). Until then, A stands.

4. **Fixture-tested** — `embo-profile` gets its own `.test.sh`
   (following `embo-corrections.test.sh`): `show` present → contents;
   `show` absent → `NO_PROFILE`; `get <field>` → the value; `set` →
   active file written from the named profile; `reset` → active file
   removed; runs from an arbitrary CWD with no env var set. Paths
   overridable (active-file path AND profiles-dir) so tests target temp
   files, never the real `~/.claude`.

## Acceptance criteria

- **AC-1 (no raw profile file read in commands):** no command file
  reads `~/.claude/active-profile.yaml` via `cat`/`Read`; all acquire
  it through `embo-profile` (or from session context after start).
- **AC-2 (bare command, no env/abs-path):** the wrapper resolves its own
  location; commands invoke a bare `embo-profile`, no
  `${CLAUDE_PLUGIN_ROOT}`, no absolute path.
- **AC-3 (absent-file contract):** `embo-profile show` prints
  `NO_PROFILE` when the file is absent, so existing default-fallback
  logic is unchanged.
- **AC-4 (load once):** `/embo:start` loads the profile once and echoes
  it; downstream commands take it from context, not a re-read.
- **AC-5 (full lifecycle):** `embo-profile` performs show/get/set/reset;
  `profile.md`'s switch and reset steps call the wrapper instead of
  copying/removing the file inline.
- **AC-6 (tests pass live):** `bash plugin/bin/embo-profile.test.sh`
  passes.

## Scope

- New `plugin/bin/embo-profile` wrapper (show/get/set/reset) +
  `embo-profile.test.sh`.
- `/embo:start`: load the profile once via `embo-profile show`, echo it
  into the session summary; add `Bash(embo-profile *)` to allowed-tools,
  drop the `cat`/`Read` profile entries.
- Downstream commands (`prd.md`, `tech-design.md`, `tasks.md`,
  `impl.md`, `git.md`, `health.md`, `init.md`): read the profile from
  session context when present; otherwise fall back to
  `embo-profile show`. Remove the raw-file-read instruction.
- `profile.md`: its switch/reset steps call `embo-profile set`/`reset`;
  its read step calls `embo-profile show`.
- Add `plugin/bin/embo-profile` to the CLAUDE.md File Structure tree.

## Tasks

- [X] 1.0 **User Story:** As a plugin user, one pre-approved command owns
  every profile operation, so profile access never triggers an approval
  gate and never needs a broad `~/.claude` read whitelist.
  - [X] 1.1 Write `plugin/bin/embo-profile.test.sh` (fixture, following
    `embo-corrections.test.sh`), with overridable active-file path AND
    profiles-dir so tests target temp files: `show` present → contents;
    `show` absent → `NO_PROFILE`; `get <field>` → the value; `set
    <name>` → active file written from the named profile; `reset` →
    active file removed; runs from an arbitrary CWD with
    `$CLAUDE_PLUGIN_ROOT` unset. [verify: auto-test]
      → 8 test functions (13 assertions): show/get/set/reset/unknown/
        bare-no-env; EMBO_PROFILE_ACTIVE + EMBO_PROFILE_DIRS overrides
        target temp files. Decision: yq hard-required, no skip guard —
        test errors loudly if yq absent [live] (2026-08-16)
  - [X] 1.2 Implement `plugin/bin/embo-profile` (self-resolving;
    show/get/set/reset/list) to pass 1.1. [verify: auto-test]
      → 13 passed, 0 failed. yq hard-required (rc 3 + install hint when
        absent); show works without yq (raw cat / NO_PROFILE) [live]
        (2026-08-16)
  - [X] 1.3 Verify the wrapper runs as a bare command from an arbitrary
    CWD with `$CLAUDE_PLUGIN_ROOT` unset (AC-2). [verify: manual-run-claude]
      → from /tmp, env unset, `list` printed all 4 shipped built-ins
        (fast/minimal/quality/research), rc=0; self-resolved to the
        plugin's profiles/ dir [live] (2026-08-16)

- [X] 2.0 **User Story:** As a plugin user, `/embo:start` loads my
  profile once and downstream commands reuse it, with no raw file read
  anywhere.
  - [X] 2.1 `start.md`: replace the `cat` profile read with
    `embo-profile show`, echo the profile into the session summary; add
    `Bash(embo-profile *)` to allowed-tools, drop the `cat`/`Read`
    profile entries (AC-4). [verify: code-only]
  - [X] 2.2 Downstream commands (`prd.md`, `tech-design.md`, `tasks.md`,
    `impl.md`, `git.md`, `health.md`, `init.md`): read the profile from
    session context when present, else fall back to `embo-profile show`
    (`get git.commit_style` in git.md); remove the raw-file-read
    instruction. [verify: code-only]
      → impl.md's direct `Read` (flagged by both research passes) fixed
        to `embo-profile show`; git.md's two `cat` reads → `get`/`show`.
  - [X] 2.3 `profile.md`: `use`/`list`/`off` call `embo-profile
    set`/`list`/`reset`. [verify: code-only]
  - [X] 2.4 Grep the command tree: no command reads
    `active-profile.yaml` via `cat`/`Read` for its value (AC-1). Only
    git.md Step 3's single-field `yq -i` write remains, flagged for the
    deferred storage redesign (task 054). [verify: code-only]
  - [X] 2.5 Add `plugin/bin/embo-profile` + `plugin/profiles/default.yaml`
    to the CLAUDE.md File Structure tree. [verify: code-only]

- Extension decisions (2026-08-16, mid-task):
  - **Canonical `default.yaml`** added (`plugin/profiles/default.yaml`):
    all fields, brief inline explanations. `embo-profile show`/`get`
    fall back to it when no active profile is set, so no command
    hardcodes defaults and `NO_PROFILE` only appears when even the
    default is unreachable.
  - **`memory_backend` removed** from all profiles + default.yaml and
    the "skip claude-mem if none" logic stripped from 7 commands —
    claude-mem is a mandatory core system, not a toggle. `minimal`
    profile's `memory_backend: none` (an inconsistency) fixed.
  - **MCP rename** (separate concern, same branch): the agents
    (`examine-advisor`, `approach-validator`) and research commands
    referenced the retired `mcp__notebooklm-mcp__*`; the live server is
    `gemini-notebook-mcp`. Renamed everywhere; added a HARD STOP so a
    skipped external check can no longer be silently reconciled under a
    confident verdict. This fixed the silent research-degrade observed
    this session.
  - **Deferred:** profile storage-model redesign (active-as-pointer,
    preset durability across plugin updates, single-field editing of a
    named profile) → task 054 seed.

- [X] 3.0 **User Story:** As the maintainer, the change is tested and the
  wrapper is proven to avoid the approval gate.
  - [X] 3.1 Run `embo-profile.test.sh`; all pass (AC-6). [verify: auto-test]
      → 15 passed, 0 failed [live] (2026-08-16)
  - [X] 3.2 Live: run the profile load as `/embo:start` does, confirm no
    approval prompt. [verify: manual-run-claude]
      → live: `embo-profile show` auto-approved (bare command, no
        prompt), returned default.yaml (no active profile set);
        `get git.commit_style`→conventional, `get tools.rlm`→true.
        Gate avoided as designed [live] (2026-08-16)
