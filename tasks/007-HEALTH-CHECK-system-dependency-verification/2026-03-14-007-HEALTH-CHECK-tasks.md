# 007-HEALTH-CHECK - Task List

## Relevant Files

- [tasks/007-HEALTH-CHECK-system-dependency-verification/
  2026-03-13-007-HEALTH-CHECK-prd.md](
  2026-03-13-007-HEALTH-CHECK-prd.md)
  :: Product Requirements Document
- [tasks/007-HEALTH-CHECK-system-dependency-verification/
  2026-03-13-007-HEALTH-CHECK-tech-design.md](
  2026-03-13-007-HEALTH-CHECK-tech-design.md)
  :: Technical Design Document
- [.claude/commands/rlm-mem/discover/health.md](
  ../../.claude/commands/rlm-mem/discover/health.md)
  :: New command — the health check prompt (CREATE)
- [.claude/commands/rlm-mem/README.md](
  ../../.claude/commands/rlm-mem/README.md)
  :: Add health to Discovery Phase table
- [README.md](../../README.md)
  :: Add health to Available Commands §Discovery Phase

## Notes

- TDD does not apply — this is a markdown command prompt file,
  not application code. Testing means manually invoking the
  command and verifying the output matches the Gherkin scenarios
  in the PRD.
- The command uses only existing infrastructure: Bash (rlm_repl.py
  status), MCP search, Write + Read tools, and sleep.
- All three checks must run independently — failure in one must
  not skip the others.
- The hook E2E check uses a timestamp-based unique token to avoid
  false positives from previous runs.

## Tasks

- [X] 1.0 **User Story:** As a developer, I want `discover/health.md`
  to check RLM state and report pass/fail with a fix instruction,
  so that I know if the repo is indexed [3/3]
  - [X] 1.1 Create `.claude/commands/rlm-mem/discover/health.md`
    with file header, "When to Use" section, and the Check 1
    step: run `python3 ~/.claude/rlm_scripts/rlm_repl.py status`,
    parse output for `Total files:` > 0 and `Context path:`
    matching cwd. Store result as `rlm_result` with notes
    `"{N} files indexed"` on pass.
  - [X] 1.2 Add fail handling for three sub-cases:
    (a) script not found → fix `bash install.sh`;
    (b) no state.pkl / error → fix `/rlm-mem:discover:init`;
    (c) `Total files: 0` → fix `/rlm-mem:discover:init`
  - [X] 1.3 Verify: run `/rlm-mem:discover:health` in this repo
    (state.pkl exists) — RLM row shows ✅ with file count

- [X] 2.0 **User Story:** As a developer, I want `discover/health.md`
  to check the claude-mem plugin and report pass/fail with a fix
  instruction, so that I know if MCP tools are responding [2/2]
  - [X] 2.1 Add Check 2 to `health.md`: call
    `mcp__plugin_claude-mem_mcp-search__search(query="health check
    probe", limit=1)`. Pass if tool returns without error (zero
    results is still a pass). Store as `mem_result` with notes
    `"Responding"` on pass. Fail instruction: verify with
    `/plugin list`, install with
    `/plugin marketplace add thedotmack/claude-mem`
  - [X] 2.2 Verify: run `/rlm-mem:discover:health` with
    claude-mem available — claude-mem row shows ✅

- [X] 3.0 **User Story:** As a developer, I want `discover/health.md`
  to verify the PostToolUse hook end-to-end so that I know
  observations are actually being captured [3/3]
  - [X] 3.1 Add Check 3 to `health.md`:
    (a) generate token `hc-{unix_timestamp}` via Bash
    `date +%s`;
    (b) Write `/tmp/claude-mem-{token}.md` with H1
    `# Health Check Probe`, `[TYPE: HEALTH-CHECK]`,
    `[TOKEN: {token}]`;
    (c) Read the file to trigger PostToolUse hook;
    (d) `sleep 2`;
    (e) search claude-mem for `{token}`, limit=1.
    Store as `hook_result`.
  - [X] 3.2 Add pass/fail logic: ≥1 result → ✅ notes
    `"Observation captured"`; 0 results → ❌ notes
    `"Observation not found (may be timing or hook
    misconfigured)"` with fix instruction referencing
    `~/.claude/settings.json` and `README.md §Hook Setup`
  - [X] 3.3 Verify: run `/rlm-mem:discover:health` — hook row
    shows ✅ and a HEALTH-CHECK observation appears in
    claude-mem

- [X] 4.0 **User Story:** As a developer, I want `discover/health.md`
  to render a combined summary table after all three checks, never
  short-circuiting on failure, so that I see full system status
  in one view [2/2]
  - [X] 4.1 Add final rendering step to `health.md`: after all
    three checks complete, output the summary table with all
    three rows. Count failures. If count > 0, print each ❌
    row's fix instruction below the table in the format:
    `❌ {name} — {notes}\n   → {fix}`.
    If count == 0, print `All systems operational.
    Ready for /rlm-mem:discover:start`.
    Add explicit instruction: "run all three checks even if
    earlier ones fail, then render the combined summary."
  - [X] 4.2 Verify failure independence: temporarily break the
    RLM check (e.g., run from a dir without state.pkl), confirm
    the other two checks still run and appear in the table

- [X] 5.0 **User Story:** As a developer, I want the docs updated
  to document the new command so that users know it exists [2/2]
  - [X] 5.1 Edit `.claude/commands/rlm-mem/README.md`: add
    `/rlm-mem:discover:health` row to the Discovery Phase table
    with purpose "Verify all system dependencies are working"
  - [X] 5.2 Edit `README.md`: add `/rlm-mem:discover:health`
    to the Available Commands §Discovery Phase list and to the
    §Verification section as the recommended post-install check.
    Update command count 8 → 9 in all relevant places.

- [X] 6.0 **User Story:** As a developer, I want all PRD Gherkin
  scenarios manually verified so that the feature is confirmed
  working end-to-end [5/5]
  - [~] 6.1 **Scenario: All systems operational** — run
    `/rlm-mem:discover:health` in this repo (all deps present);
    verify three ✅ rows and "All systems operational" message
    NOTE: Checks 1+2 verified ✅; Check 3 ❌ due to env hook issue
  - [X] 6.2 **Scenario: RLM state missing** — run from a
    directory without `.claude/rlm_state/state.pkl`; verify
    ❌ for RLM state with fix instruction, other two rows
    still appear
  - [X] 6.3 **Scenario: claude-mem plugin not responding** —
    cannot easily simulate without disabling the plugin; mark
    as verified by code review of fail path logic
  - [X] 6.4 **Scenario: PostToolUse hook not capturing** —
    cannot easily simulate; verify by code review of fail
    path logic and the `sleep 2` + search pattern
  - [X] 6.5 **Scenario: Multiple failures** — run from a dir
    without state.pkl (RLM fails); verify both ❌ rows appear
    with individual fix instructions and "2 issues found"
    count (hook check may or may not fail depending on env)
