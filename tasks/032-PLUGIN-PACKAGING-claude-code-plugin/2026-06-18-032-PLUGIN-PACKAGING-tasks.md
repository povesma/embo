# Package embo as a Claude Code Plugin - Task List

## Relevant Files

- [2026-06-18-032-PLUGIN-PACKAGING-tech-design.md](./2026-06-18-032-PLUGIN-PACKAGING-tech-design.md)
  :: Plugin Packaging - Technical Design
- [2026-06-17-032-PLUGIN-PACKAGING-prd.md](./2026-06-17-032-PLUGIN-PACKAGING-prd.md)
  :: Plugin Packaging - Product Requirements Document
- `.claude-plugin/plugin.json` :: NEW. Plugin manifest; `name:"embo"`
  forces the `/embo:` command prefix; declares claude-mem dependency.
- `.claude-plugin/marketplace.json` :: NEW. Single-plugin marketplace
  entry, `source:"./"`, for `/plugin marketplace add povesma/embo`.
- `hooks/hooks.json` :: NEW. Registers the 3 event handlers via
  `${CLAUDE_PLUGIN_ROOT}`. `embo-capture.sh` deliberately absent.
- `hooks/fix-hooks.sh` :: NEW. Doctor/migration: detect, report, and
  (with consent) remove duplicate embo hook registrations.
- `hooks/fix-hooks.test.sh` :: NEW. Unit tests for `fix-hooks.sh`.
- `.claude/hooks/approve-compound.sh` :: MODIFY then move. Line 219
  `EMBO_CAPTURE_CMD` default → `${CLAUDE_PLUGIN_ROOT}` + manual fallback.
- `.claude/hooks/approve-compound.test.sh` :: reused to prove the path
  rewrite did not regress behavior (run with var set AND unset).
- `.claude/commands/dev/**` :: MOVE to `commands/*.md` (flatten; rewrite
  `/dev:` and `research:` references).
- `.claude/commands/dev/start.md` :: MODIFY. RLM script path; `/dev:`
  refs. Profile read-path stays `~/.claude` (user-owned).
- `.claude/agents/*.md` :: MOVE to `agents/*.md`.
- `.claude/rlm_scripts/rlm_repl.py` :: MOVE to `rlm_scripts/`.
- `.claude/profiles/*.yaml`, `.claude/statusline.sh` :: MOVE to root.
- `README.md`, `TROUBLESHOOTING.md`, `CLAUDE.md` :: MODIFY. Dual install
  docs; `/embo:` names; command count 11→15.

## Notes

- This repo is markdown + shell, not application code. "Tests" here are
  the existing plain-Bash `*.test.sh` harnesses (sourced-function unit
  tests, no framework). Run a harness with `bash <file>.test.sh`.
- TDD applies to the one piece of real logic: `fix-hooks.sh` (Story
  2.0). Manifests, moves, and doc edits are config/structural — verified
  by `claude plugin validate`, grep gates, and live install, not unit
  tests.
- **Risk-first order**: Stories 1-4 leave the live `.claude/` tooling
  untouched and working. Story 5 is the disruptive `git mv`. Story 8
  proves the result. This protects the capture/approve hooks running
  during implementation.
- **Out of scope for 032** (deferred to follow-up): bundling the 5 test
  subagents (PRD FR-7); Anthropic community-directory submission.

## TDD Planning Guidelines

Story 2.0 (`fix-hooks.sh`) follows write-test → implement cycles: it
parses settings files and conditionally edits them — exactly the logic
that warrants tests. All other stories are config/structural/docs and
are verified by validation, grep gates, or live run.

## Tasks

- [X] 1.0 **User Story:** As a user, I want embo to be discoverable and
  installable as a plugin, so that `/plugin marketplace add
  povesma/embo` then `/plugin install embo@embo` work. [3/3]
  - [X] 1.1 Create `.claude-plugin/plugin.json` with `name:"embo"`,
    `version`, `description`, `author`, `repository`, `license`,
    `keywords`. NO `dependencies` field (not a valid plugin.json key);
    claude-mem requirement is a runtime check, not a manifest dep
    [verify: code-only]
    → created `.claude-plugin/plugin.json`, version 0.1.0 (initial
      development per manifest-ref); `python3 -m json.tool` parses
      clean [live] (2026-06-18)
  - [X] 1.2 Create `.claude-plugin/marketplace.json` with one plugin
    entry (`name:"embo"`, `source:"./plugin"`, `description`,
    `category`) [verify: code-only]
    → created repo-root `.claude-plugin/marketplace.json`,
      `source:"./plugin"` (subdir layout — every Anthropic example
      nests; none use "."); relocated `plugin.json` to
      `plugin/.claude-plugin/plugin.json` to match. Both parse clean
      via `python3 -m json.tool`. Updated tech-design FR-3 + tasks
      5.x to the `plugin/` subdir shape [live] (2026-06-18)
  - [X] 1.3 Run `claude plugin validate --strict` at repo root and
    confirm 0 errors [verify: manual-run-claude]
    → `claude plugin validate --strict .` (marketplace) and
      `... ./plugin` (plugin) both: "✔ Validation passed", 0
      errors/warnings. Confirms source:"./plugin" valid + no-deps
      manifest valid (strict flags unknown fields; none flagged)
      [live] (2026-06-18)

- [X] 2.0 **User Story:** As an existing user, I want a script that
  detects and removes stale embo hook registrations (and flags stale
  command/agent files), so that adopting the plugin does not double-fire
  my capture/approve hooks. [7/7]
  - [X] 2.1 Write `hooks/fix-hooks.test.sh`: seed a temp settings file
    with ONE embo hook entry → detector reports "single, clean", exit 0
    [verify: auto-test]
    → wrote `plugin/hooks/fix-hooks.test.sh` pinning the
      `fix_hooks_detect <file>` contract (one line per embo reg,
      `<token>\t<command>`); TDD red confirmed: `1 passed, 3 failed`
      — fails because fix-hooks.sh not yet implemented (expected)
      [live] (2026-06-18)
  - [X] 2.2 Write tests for the DUPLICATE case: temp settings with the
    same handler registered twice by different paths → detector reports
    duplicates, exit 1 (report-only, no `--fix`) [verify: auto-test]
    → added duplicate-detection tests (`fix_hooks_count_dups`,
      report-only exit 1, file-unchanged); TDD red [live] (2026-06-18)
  - [X] 2.3 Write tests for the `--fix` path: with consent, the stale
    `~/.claude` entry is removed, a backup is written, exit 2; without
    consent, nothing changes [verify: auto-test]
    → added --fix tests: consent y → tilde entry removed, .bak holds
      both pre-edit entries, exit 2; consent n → unchanged, exit 1;
      idempotent re-run → exit 0. TDD red: 5 passed, 13 failed (all
      127/not-found, fix-hooks.sh absent) [live] (2026-06-18)
  - [X] 2.4 Implement `fix-hooks.sh` detection: parse the settings
    file(s), match registrations on the stable hook-script tokens
    (`approve-compound.sh`/`behavioral-reminder.sh`/`context-guard.sh`),
    report source + resolved path [verify: auto-test]
    → `fix_hooks_detect` uses `any(.hooks[]; .command? | strings |
      contains)` (if-field-safe, per verify); jq guard added.
      Independent live check: 3 regs detected correctly across two
      paths [live] (2026-06-18)
  - [X] 2.5 Implement `fix-hooks.sh` removal: `--fix` flag, per-entry
    `y/N` prompt (stdin consent), back up before edit (cp .bak + temp +
    atomic mv), never touch managed/plugin config. Removes ALL stale
    `~/.claude` embo entries (decided: full migration cleanup, not just
    duplicates) [verify: auto-test]
    → live: --fix consent y removed both tilde entries, kept abs-path;
      .bak preserved pre-edit; idempotent re-run exit 0 [live]
      (2026-06-18)
  - [X] 2.6 Run `bash hooks/fix-hooks.test.sh`; all assertions pass
    [verify: auto-test]
    → `18 passed, 0 failed` [live] (2026-06-18)
  - [X] 2.7 Detect stale manual-install command/agent files
    (`~/.claude/commands/dev/`, embo agents in `~/.claude/agents/`) and
    PRINT the exact removal command for the user — advisory only, no
    auto-`rm` (scope added 2026-06-18) [verify: auto-test]
    → `fix_hooks_advise_stale_files` prints `rm -rf` hint, returns 1
      when clean; wired into main (skipped in test mode). Suite: 21
      passed, 0 failed. Independent live check: advice fires, file
      INTACT after [live] (2026-06-18)

- [X] 3.0 **User Story:** As a plugin user, I want hooks and the RLM
  script to resolve their own bundled paths, so that capture/approve and
  RLM analysis work without `~/.claude` paths. [5/5]
  - [X] 3.1 Add a failing assertion to `approve-compound.test.sh`:
    with `CLAUDE_PLUGIN_ROOT` set and `EMBO_CAPTURE_CMD` unset, the
    wrapper path resolves under `${CLAUDE_PLUGIN_ROOT}/hooks/`
    [verify: auto-test]
    → added `default_capture_cmd` tests (plugin-root + token); TDD
      red: 164 passed, 4 failed [live] (2026-06-19)
  - [X] 3.2 Add a failing assertion: with BOTH `CLAUDE_PLUGIN_ROOT` and
    `EMBO_CAPTURE_CMD` unset (manual install), the path falls back to
    `~/.claude/hooks/embo-capture.sh` [verify: auto-test]
    → added home-fallback assertion ($HOME/.claude/hooks/...); red
      [live] (2026-06-19)
  - [X] 3.3 Rewrite `approve-compound.sh:219` default to
    `${EMBO_CAPTURE_CMD:-${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/embo-capture.sh}`
    [verify: auto-test]
    → extracted `default_capture_cmd()` (prefers CLAUDE_PLUGIN_ROOT,
      falls back $HOME/.claude; $HOME not literal ~ so it expands).
      Full suite: 168 passed, 0 failed (164 baseline + 4 new) [live]
      (2026-06-19)
  - [X] 3.4 Update commands that shell out to
    `~/.claude/rlm_scripts/rlm_repl.py` to resolve via
    `${CLAUDE_PLUGIN_ROOT}` with the same manual fallback [verify:
    code-only]
    → rewrote 14 exec refs across 8 command files to
      `"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/rlm_scripts/rlm_repl.py"`.
      Only remaining literal ~/.claude RLM ref is start.md:3
      `allowed-tools` (kept deliberately; added one-time
      "Always allow" note in Step 1 for plugin users). Profile paths
      left under ~/.claude per FR-6b. Expansion verified both modes
      [live] (2026-06-19)
  - [X] 3.5 Run `bash .claude/hooks/approve-compound.test.sh` and
    confirm all assertions pass (set and unset) [verify: auto-test]
    → 168 passed, 0 failed (164 baseline + 4 new covering plugin-root
      and home-fallback resolution) [live] (2026-06-19)

- [X] 4.0 **User Story:** As a plugin user, I want embo's event hooks
  registered automatically on install, so that I do not hand-edit
  settings. [3/3]
  - [X] 4.1 Author `hooks/hooks.json` registering `context-guard.sh`,
    `behavioral-reminder.sh`, `approve-compound.sh` with their correct
    events/matchers, commands via `${CLAUDE_PLUGIN_ROOT}/hooks/...`
    [verify: code-only]
    → `plugin/hooks/hooks.json`: UserPromptSubmit (context-guard +
      behavioral-reminder, no matcher) + PreToolUse/Bash
      (approve-compound). Events/matchers per README hook table
      (lines 405-407) + context-guard.sh header. Top-level `"hooks"`
      wrapper required (caught by strict validate; first draft without
      it failed) [live] (2026-06-19)
  - [X] 4.2 Confirm `embo-capture.sh` is NOT declared as a handler in
    `hooks.json` (it is a subprocess helper; declaring it re-creates the
    double-fire) [verify: code-only]
    → `grep -c embo-capture plugin/hooks/hooks.json` = 0 [live]
      (2026-06-19)
  - [X] 4.3 Validate `hooks.json` parses and matchers match the events
    the current `~/.claude` registration uses (compare against the live
    user registration) [verify: manual-run-claude]
    → matched against README authoritative hook table (did NOT read
      user's private ~/.claude/settings.json). `claude plugin validate
      --strict ./plugin` → "✔ Validation passed" [live] (2026-06-19)

- [X] 5.0 **User Story:** As a maintainer, I want embo's components in a
  `plugin/` subdir per the proven plugin layout, so that the plugin
  loads correctly. [7/7]
  - [X] 5.1 `git mv .claude/hooks/*` → `plugin/hooks/` (preserving the
    modified `approve-compound.sh` and new `fix-hooks.sh`/`hooks.json`)
    [verify: code-only]
    → moved 7 files; all 3 hook suites green at new location (168 +
      60 + 21) [live] (2026-06-19)
  - [X] 5.2 `git mv .claude/agents/*` → `plugin/agents/` [verify:
    code-only]
    → moved 3 tracked agents (approach-validator, examine-advisor,
      rlm-subcall); untracked visual-qa-reviewer prototype left in
      .claude/ (not part of 032) [live] (2026-06-19)
  - [X] 5.3 `git mv .claude/commands/dev/*.md` → `plugin/commands/`;
    FLATTEN `research/examine.md`→`plugin/commands/examine.md`,
    `research/verify.md`→`plugin/commands/verify.md` (flat is the
    documented-safe shape; nested-dir namespacing is unverified)
    [verify: code-only]
    → moved 12 tracked commands + flattened 2 research → top level;
      untracked visual-impl.md prototype left behind [live]
      (2026-06-19)
  - [X] 5.4 `git mv .claude/rlm_scripts/`, `.claude/profiles/`,
    `.claude/statusline.sh` → `plugin/` [verify: code-only]
    → all three moved to plugin/ [live] (2026-06-19)
  - [X] 5.5 Confirm `plugin/.claude-plugin/` contains ONLY `plugin.json`,
    repo-root `.claude-plugin/` contains ONLY `marketplace.json`, and
    RLM state path is still project-local `.claude/rlm_state/`
    [verify: code-only]
    → verified all three; .claude/ retains only settings.local.json,
      rlm_state/, commands-archive/, and untracked prototypes [live]
      (2026-06-19)
  - [X] 5.6 Run `claude plugin validate --strict` on the restructured
    root; 0 errors [verify: manual-run-claude]
    → after 5.7, `claude plugin validate --strict ./plugin` →
      "✔ Validation passed", 0 warnings (manifest + 14 commands + 3
      agents + hooks) [live] (2026-06-19)
  - [X] 5.7 Add YAML `description` frontmatter to the 10 commands that
    lacked it (surfaced by --strict: prd, tech-design, improve, impl,
    init, check, tasks, health, test-plan, profile) [verify: auto-test]
    → added folded `description:` blocks matching existing style; took
      strict validation from 10 warnings → 0. Hook suites still green
      [live] (2026-06-19)

- [X] 6.0 **User Story:** As a user, I want every command reference to
  use `/embo:*`, so that no command or doc points at a non-existent
  name. [4/4]
  - [X] 6.1 Rewrite `/dev:<x>` → `/embo:<x>` across all `commands/*.md`
    [verify: code-only]
    → swept 11 command files (replace_all /dev: → /embo:) [live]
      (2026-06-19)
  - [X] 6.2 Rewrite `research:examine`/`research:verify` references →
    `/embo:examine`/`/embo:verify` (drop the `research:` segment, do not
    rename) in commands and agents [verify: code-only]
    → fixed nested refs in examine.md, verify.md, start.md FIRST
      (specific-before-general) so the broad sweep didn't produce
      /embo:research:* [live] (2026-06-19)
  - [X] 6.3 Rewrite `/dev:` references in `agents/*.md` [verify:
    code-only]
    → agents had 0 /dev: refs; nothing to change. BUT the gate caught
      2 in hooks/ (behavioral-reminder.sh, context-guard.sh) —
      rewritten to /embo:git [live] (2026-06-19)
  - [X] 6.4 Acceptance gate: `grep -rn '/dev:' commands/ agents/` (and
    root docs) returns 0 hits [verify: manual-run-claude]
    → `grep -rn '/dev:' plugin/` = 0 (commands + agents + hooks). Root
      docs (README/CLAUDE.md) still have /dev: refs — deferred to
      Story 7.0 (docs). `claude plugin validate --strict` still passes
      [live] (2026-06-19)

- [X] 7.0 **User Story:** As any user, I want complete plugin AND manual
  install docs, so that either install path works standalone. [6/6]
  - [X] 7.1 README: plugin install section (`/plugin marketplace add
    povesma/embo` + `/plugin install embo@embo`) [verify: code-only]
    → rewrote `## Install` plugin-first (Step 1 plugin, Step 2
      claude-mem, Step 3 /embo:health); added #branch + local-path
      tips; TL;DR + command table → /embo:* [verify: code-only]
  - [X] 7.2 README: manual (standalone) install section covering the
    SAME component set as the plugin (per CLAUDE.md Documentation Rule)
    [verify: code-only]
    → rewrote macOS/Linux manual block to copy from plugin/*, incl.
      the bin/rlm_repl wrapper + the `~/.claude/bin` PATH step, and
      commands → ~/.claude/commands/embo/ (gives /embo:*) [code-only]
  - [X] 7.3 README/TROUBLESHOOTING: the `fix-hooks.sh` migration step
    for existing users adopting the plugin; manual statusline copy
    (FR-11) [verify: code-only]
    → added the fix-hooks.sh migration NOTE in `## Install`; statusline
      copy retained in manual block [code-only]
  - [X] 7.4 README: the exact permission-allowlist entries for zero
    prompts, framed as optional (FR-8 document + graceful degrade)
    [verify: code-only]
    → Hooks §: plugin allow-rules `Bash(rlm_repl *)`,
      `Bash(bash */hooks/embo-capture.sh *)`,
      `Bash(bash */hooks/fix-hooks.sh *)` + "Always allow" fallback;
      manual-install hook registration block [code-only]
  - [X] 7.5 CLAUDE.md: update command count 11→15 and any `/dev:` →
    `/embo:` references in prose [verify: code-only]
    → corrected to 14 (not 15 — the "15" counted the untracked
      visual-impl prototype; plugin ships 14). Overview, architecture,
      install flow, file-structure tree, Modify-Commands, behavioral-
      rules ref all → plugin/ + /embo:* [code-only]
  - [X] 7.6 README: preserve migration-note `/dev:` refs (lines naming
    the OLD commands for removal are intentional) [verify: code-only]
    → verified: only remaining /dev: in README are the 2 migration
      notes (intentional) + the Docker testing section (deferred,
      see follow-up) [code-only]

- [X] 8.0 **User Story:** As a maintainer, I want to prove a clean
  plugin install works end to end, so that we can ship. [9/9]
  - [X] 8.1 From the branch, run `/plugin marketplace add` (local path)
    + `/plugin install embo@embo`; commands appear as `/embo:*` [verify:
    manual-run-user]
    → user ran `/plugin marketplace add /Users/.../embo` → "Successfully
      added marketplace: embo"; `/plugin install embo@embo` → "✓
      Installed embo"; `/reload-plugins` → "6 plugins · 14 skills · 20
      agents · 11 hooks". All 14 /embo:* commands appear in the skill
      list WITH descriptions (5.7 frontmatter renders). /embo:init
      resolved to the plugin command. [live] (2026-06-19)
    → FINDING (live): first RLM command in /embo:init triggered an
      approval dialog ("Contains expansion / Do you want to proceed?")
      — the ${CLAUDE_PLUGIN_ROOT:-...} form is flagged for approval and
      does not match the literal allowed-tools pattern. Expected per
      FR-8; the /embo:start "Always allow" note covers it, but it ALSO
      hits /embo:init (often the first command run). → 7.x docs should
      surface this prominently.
  - [X] 8.2 Run a representative compound Bash command; confirm exactly
    ONE `[embo-capture]` marker (not two) and correct exit code [verify:
    manual-run-claude]
    → observed live UNDER double-registration (this session has both
      the manual ~/.claude approve-compound AND the plugin's
      registered): `git log --oneline -20`, `git status`, and grep
      pipelines each produced EXACTLY ONE `[embo-capture]` marker
      (truncated / filtered view), correct exit=0, no doubled or
      malformed `embo-capture ... embo-capture` command. The feared
      undocumented double-fire conflict did NOT manifest as breakage —
      one marker, clean exit. (fix-hooks.sh still recommended to remove
      the stale entry; this confirms the interim state is not broken.)
      [live] (2026-06-19)
  - [X] 8.3 Confirm RLM `status` works via the plugin and state writes
    to the project's `.claude/rlm_state/` [verify: manual-run-claude]
    → user ran `/embo:init` on a real Drupal project: RLM indexed 299
      files (17,026-file vendor tree excluded via .rlmignore), then
      `/embo:start` produced a full session summary. RLM ran via the
      `rlm_repl` wrapper with no expansion prompt; state project-local
      [live] (2026-06-19)
  - [X] 8.4 Seed a stale `~/.claude` hook entry, run `fix-hooks.sh`, and
    confirm it detects + (with consent) removes the duplicate [verify:
    manual-run-user]
    → ran the REAL `bash fix-hooks.sh --fix` CLI (not sourced test fns)
      on a synthetic SETTINGS_FILES with a duplicate: detected "1
      duplicated embo handler", listed both paths, prompted, consent y
      → removed the tilde entry, wrote .bak, exit 2. After: 1
      approve-compound + 0 tilde refs; .bak holds both. Tested via
      synthetic file — did NOT touch the user's real
      ~/.claude/settings.json [live] (2026-06-19)
  - [X] 8.5 FIX (surfaced by 8.1): replace inline
    `${CLAUDE_PLUGIN_ROOT:-...}/rlm_scripts/rlm_repl.py` with a
    `plugin/bin/rlm_repl` wrapper invoked as a bare command; rewrite 13
    RLM refs + `start.md` allowed-tools to `Bash(rlm_repl *)` (reverses
    FR-5 inline form — see tech-design FR-5 REVISION) [verify:
    auto-test]
    → wrapper resolves rlm_repl.py via symlink-followed $0, keeps state
      project-local; verified via symlink-on-PATH from /tmp.
      `/embo:init` now completes (previously halted on expansion
      prompt). `claude plugin validate --strict` still passes [live]
      (2026-06-19)
  - [X] 8.6 FIX (surfaced by 8.1): `chmod +x` all shipped hook scripts +
    `bin/rlm_repl` + `rlm_repl.py` — the plugin failed with exit 126
    because moved `embo-capture.sh` lost its executable bit (git mv
    preserved the non-exec mode; `approve-compound.sh` invokes it
    directly) [verify: manual-run-claude]
    → set +x on approve-compound.sh, embo-capture.sh,
      behavioral-reminder.sh, context-guard.sh, fix-hooks.sh,
      bin/rlm_repl, rlm_scripts/rlm_repl.py; capture wrapper works
      again (no 126); .test.sh left non-exec [live] (2026-06-19)
  - [X] 8.7 REVERSAL (supersedes 5.3/6.2 flatten): empirically tested
    whether nested command dirs work by restoring
    `commands/research/{examine,verify}.md` and reinstalling. Result:
    they register as `/embo:research:examine` / `/embo:research:verify`
    (typeable nested namespace) — so the `research/` subdir is KEPT,
    not flattened. Restored the subdir; fixed self-refs in
    examine.md/verify.md/start.md back to `/embo:research:*`. Updates
    tech-design FR-4 + External Facts (nested IS supported, both prior
    "flatten" positions retracted) [verify: manual-run-user]
    → live reinstall skill list shows `embo:research:examine` +
      `embo:research:verify`; `claude plugin validate --strict` passes
      [live] (2026-06-19)

## Follow-up Tasks (out of scope for 032)

- Bundle the 5 test subagents (`test-backend`, `test-review`,
  `test-e2e-{planner,generator,healer}`) into `agents/`, preserving
  Playwright-fork attribution (PRD FR-7).
- Submit embo to the Anthropic community plugin directory.
- Rework the README **Docker testing section** (currently describes the
  old cp-install model: `cp -r .claude/commands/dev`, reads
  `health.md` from that path, `/dev:*` invocations). Should use
  `/plugin install` or `claude --plugin-dir`. Needs design + a live
  Docker test, so deferred from 032's doc story.
- Fix `/embo:health` Check 3: it writes/reads a `/tmp` probe to test
  the PostToolUse hook, but the claude-mem hook indexes PROJECT files,
  so the probe can falsely report "hook misconfigured". Probe a
  project-local file instead (surfaced 2026-06-19).
