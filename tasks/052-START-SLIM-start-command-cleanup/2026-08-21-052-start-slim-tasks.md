# start-command-cleanup - Task List

## Relevant Files

- [2026-08-21-052-start-slim-tech-design.md](2026-08-21-052-start-slim-tech-design.md)
  :: Slim /embo:start Command - Technical Design
- [2026-08-19-052-start-slim-prd.md](2026-08-19-052-start-slim-prd.md)
  :: Slim /embo:start Command - Product Requirements Document
- [plugin/commands/start.md](../../plugin/commands/start.md)
  :: MODIFY - the rewrite target; only the non-rules region changes
     (pre-change lines 1-45 and 601-874); rules region 46-600 is
     byte-identical
- [plugin/.claude-plugin/plugin.json](../../plugin/.claude-plugin/plugin.json)
  :: MODIFY - patch version bump (release vehicle)
- [CHANGELOG.md](../../CHANGELOG.md)
  :: MODIFY - entry for the released behavior
- [plugin/bin/embo-tokens](../../plugin/bin/embo-tokens)
  :: CREATE - token-count measurement tool (added mid-task; required
     by seed tasks 053/054/055)
- [plugin/hooks/behavioral-reminder.sh](../../plugin/hooks/behavioral-reminder.sh)
  :: READ-ONLY - extraction contract (awk at line 114); must not change
- [plugin/hooks/behavioral-reminder.test.sh](../../plugin/hooks/behavioral-reminder.test.sh)
  :: RUN - existing test suite; FR-8 auto-test evidence
- [plugin/commands/impl.md](../../plugin/commands/impl.md)
  :: READ-ONLY - lines 33-34 reference the rules-section heading

## Notes

- Prompt-text-only change: no code, no new files. All stories edit the
  SAME file (`plugin/commands/start.md`); they are grouped by the
  requirement each verifies, not by separate edits. Implement as one
  coherent rewrite of the non-rules region.
- Story 5 (scope amendment, 2026-08-22) restructures Steps 1-3 as two
  explicit parallel batches (FR-9) and re-runs the FR-8 diffs after
  the restructure to prove the rules region is still byte-identical.
- Subtask 1.1 captures baselines BEFORE any edit; story 3's diffs are
  against those baselines. Do not start 1.2 until 1.1 artifacts exist.
- Editor guard (all subtasks): no new or edited line outside the
  CHECKLIST blocks may start with `[` and contain "checklist" — such a
  line would leak into the hook's per-prompt injection.
- The shipped file must not reference `tasks/` paths or task numbers.
- TDD not applicable (no code); verification follows the tech-design
  Verification Approach table.

## Tasks

- [X] 1.0 **User Story:** As an embo user, I want the command's output
  specified once with only fillable slots, so session start loads no
  duplicated or dead instruction text (FR-1, FR-2, FR-6, FR-7). [4/0]
  - [X] 1.1 Capture pre-change baselines into `tmp/`: a copy of the
    rules region (`## Session Behavioral Rules` heading through the
    last `<!-- /CHECKLIST -->`, pre-change lines 46-600), the hook's
    extraction output for a neutral prompt, and the `wc -l` counts
    [verify: manual-run-claude]
    → three baselines saved to tmp/: rules region 555 lines,
      extraction 51 lines, total start.md 874 lines [live] (2026-08-21)
  - [X] 1.2 Replace the Step 4 mock template with the compact section
    spec (table `Section | Content (one line) | Source step`; sections
    Overview, Repository stats, Active tasks, Recent activity,
    Recommended next task, System status; plain-text headings; status
    indicators only in System status) and delete the "Example Output"
    section [verify: code-only]
  - [X] 1.3 Merge "Context Quality Levels", "Important Notes", and
    "Final Instructions" into one closing-guidance section
    (degradation lines: RLM missing → suggest `/embo:init`, memory
    empty → report empty; "do not implement anything yet" exactly
    once); delete the "<30s" directive and the pre-rules "When to
    Use" / "What This Command Does" sections [verify: code-only]
  - [X] 1.4 Confirm by grep: "do not implement" appears exactly once;
    no emoji in headings; neither dead slot ("Key Patterns
    Discovered", "Most Modified Files") appears anywhere
    [verify: manual-run-claude]
    → 1 match for "do not implement" (case/asterisk-flexible),
      0 emoji headings, 0 mentions of either dead slot; file
      874 → 718 lines [live] (2026-08-21)

- [X] 2.0 **User Story:** As an embo user, I want every startup step
  to run in pre-approved command shapes, so session start never stalls
  on an approval prompt (FR-3, FR-4, FR-5). [4/0]
  - [X] 2.1 Step 0: keep `embo-profile show` as the single per-session
    profile load; replace "parse the YAML" by naming
    `embo-profile get <key>` for any later single-value read; keep the
    read-depth semantics (fast/minimal → brief) [verify: code-only]
  - [X] 2.2 Step 3 docs sub-step: a single Read of `README.md` at the
    repo root if present, skip otherwise; remove the recursive Glob
    and the CLAUDE.md read (harness injects CLAUDE.md); session-scout
    delegation and the two exact git commands stay unchanged
    [verify: code-only]
  - [X] 2.3 Step 2 fallback: replace the rename wording with the
    deterministic rule — overview query returns exactly 0 results →
    ONE retry using the repository name from
    `git remote get-url origin` (basename, `.git` suffix stripped);
    if that command exits non-zero or prints nothing, skip the retry
    and report the overview as empty [verify: code-only]
  - [X] 2.4 Frontmatter: add `Bash(git remote get-url *)` to
    `allowed-tools`; then confirm every command shape the rewritten
    body names is covered by the frontmatter list [verify: code-only]

- [X] 3.0 **User Story:** As the embo maintainer, I want the rules
  region and its consumer contracts provably untouched, so behavioral
  enforcement keeps working without hook changes (FR-8). [4/0]
  - [X] 3.1 Diff the post-change rules region against the 1.1 baseline
    copy: 0 differences; `## Session Behavioral Rules` heading present
    verbatim (impl.md cross-reference intact)
    [verify: manual-run-claude]
    → 555-line diff clean (exit 0); heading present at line 31
      [live] (2026-08-22)
  - [X] 3.2 Re-run the hook extraction and diff against the 1.1
    baseline output: 0 differences [verify: manual-run-claude]
    → 51-line extraction diff clean (exit 0) [live] (2026-08-22)
  - [X] 3.3 Run `plugin/hooks/behavioral-reminder.test.sh`: all tests
    pass [verify: auto-test]
    → 30 passed, 0 failed [live] (2026-08-22)
  - [X] 3.4 Guard check by grep: no line outside the CHECKLIST blocks
    starts with `[` and contains "checklist"
    [verify: manual-run-claude]
    → 5 matches, all inside the byte-identical rules region
      (lines 95, 158, 228, 391, 573) — the 5 intended openers, no
      leaks [live] (2026-08-22)

- [X] 4.0 **User Story:** As an embo user, I want the slimmed command
  verified live and release-ready, so my next session actually
  benefits (NFR-1, NFR-3). [6/0]
  - [X] 4.1 NFR-1 arithmetic: post-change non-rules region ≤ 207 lines
    (`wc -l` total minus the unchanged 555-line rules region); record
    the percentage [verify: manual-run-claude]
    → non-rules 319 → 165 lines (154 cut, 48.3%); past both the 35%
      threshold and the 40% stretch [live] (2026-08-22)
  - [X] 4.2 Headless live run: `claude -p "/embo:start"` with
    `--allowedTools` set exactly to the frontmatter list; transcript
    shows all six output sections filled from their named source
    steps, no invented commands, no tool call outside the allowlist
    [verify: manual-run-claude]
    → headless run completed, ended on AskUserQuestion; no Bash tool
      call outside the frontmatter shapes was made [live] (2026-08-22)
  - [X] 4.3 Interactive smoke test: user runs `/embo:start` in a fresh
    session and confirms startup completes with zero approval dialogs
    [verify: manual-run-user]
    → user ran /embo:start in a fresh session on a separate 5,135-file
      project; all 6 sections filled from named source steps, no
      approval dialogs, ~53k tokens loaded at startup
      [user-confirmed] (2026-08-22)
  - [X] 4.4 Patch-bump the version in
    `plugin/.claude-plugin/plugin.json` (read the current value at
    edit time) [verify: code-only]
  - [X] 4.5 Add the CHANGELOG entry describing the released behavior
    (leaner session start; startup free of approval prompts)
    [verify: code-only]
  - [X] 4.6 Add `plugin/bin/embo-tokens` (stdlib Python) as the
    measurement tool the follow-up tasks (053/054/055) need; make it
    executable [verify: manual-run-claude]
    → --help works; produced the before/after table for 052
      [live] (2026-08-22)

- [X] 5.0 **User Story:** As an embo user, I want `/embo:start` to
  finish in the fewest assistant turns the data dependencies allow, so
  every extra whole-context resend is eliminated (FR-9, scope
  amendment 2026-08-22). [4/0] — best-effort prose landed; real
  batching enforcement seeded to task 056; scout-loop defect seeded
  to task 057
  - [X] 5.1 Restructure Steps 1-3 in `plugin/commands/start.md` as
    two explicit parallel batches. Turn-1 batch (5 independent
    calls, one assistant turn): `embo-profile show`, `rlm_repl
    status`, `git log --oneline -10`, `git diff --stat HEAD`, Read
    `README.md` at repo root. Turn-2 batch (2 profile-dependent
    calls, one assistant turn, after Turn 1 results are known):
    memory overview `search(project=<from Turn 1>)`, session-scout
    Task. Include an explicit "issue these in ONE assistant turn,
    not sequentially" directive above each batch. The Bash
    existence-probe pattern (`test -f README.md && echo EXISTS`) is
    removed — a Read failing on a missing file IS the "skip".
    [verify: code-only]
  - [X] 5.2 Re-run the FR-8 diffs after the Story 5.1 restructure:
    rules-region byte-diff vs the 1.1 baseline → 0 differences; hook
    extraction diff vs the 1.1 baseline → 0 differences;
    `behavioral-reminder.test.sh` → all pass. This re-verification is
    load-bearing because Story 5.1 is a substantive rewrite that
    could accidentally move a boundary. [verify: manual-run-claude
    + auto-test]
    → rules-region diff clean (exit 0); extraction diff clean
      (exit 0); tests 30 passed, 0 failed [live] (2026-08-22)
  - [X] 5.3 NFR-1 re-check after Story 5.1: post-restructure
    non-rules region still ≤ 207 lines (record the new figure).
    [verify: manual-run-claude]
    → non-rules 319 → 151 lines (168 cut, 52.7%); tokens
      2,456 → 1,818 (−638, −26.0%) [live] (2026-08-22)
  - [X] 5.4 Live run: /embo:start completes in the fewest assistant
    turns the data-dependency graph allows; no Bash existence-probe
    for README. [verify: manual-run-claude + manual-run-user]
    → Result splits by run mode.
      HEADLESS (`claude -p`): three runs, three failures at ≤ 3
      turns — 11 / 10 / 10 turns respectively across the original
      wording, the strengthened "parallel tool_use blocks"
      wording, and the added AVOID-APPROVAL + DELEGATE carve-outs.
      Every headless run showed Batch A serialized as 5 single-tool
      turns; scout returned unusably and its work was replaced
      inline by 15-27 Read/Grep turns. The `test -f` probe was
      eliminated in all three runs.
      Clean-context review (2026-08-23) confirmed the batching
      obstacle in headless mode is a platform constraint: the
      `claude -p` runtime returns tool results one-per-user-message,
      which Anthropic docs name as the exact anti-pattern that
      "teaches Claude to avoid parallel calls" — no prose fix in
      start.md overrides it.
      INTERACTIVE: user-verified 2026-08-24 that /embo:start is
      "more economical and works fine" in interactive Claude Code.
      The amendments (Batch A/B language + carve-outs + Read/Task/
      MCP frontmatter additions) earn their keep interactively;
      task 056 remains open to (a) test whether the same carve-outs
      make headless batch, and (b) build a real mechanism if not.
      [live + user-confirmed] (2026-08-24)
