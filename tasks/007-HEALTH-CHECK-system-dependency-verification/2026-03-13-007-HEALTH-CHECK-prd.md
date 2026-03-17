# 007-HEALTH-CHECK: System Dependency Verification - PRD

**Status**: Draft
**Created**: 2026-03-13
**Author**: Claude (via rlm-mem analysis)

---

## Introduction/Overview

When RLM-Mem fails silently — the hook not capturing observations,
the REPL state missing, claude-mem not responding — the developer
has no immediate indication of what is broken. They run `/start`,
get a partial session summary, and only discover hours later that
nothing was persisted to memory.

This feature adds a `/rlm-mem:discover:health` command that verifies
all system dependencies in one shot and reports clearly: what works,
what is broken, and exactly how to fix it.

---

## Objectives & Success Metrics

**Business Objectives:**
- Eliminate silent failures by making system state visible on demand
- Reduce time-to-diagnose from "hours of confused debugging" to
  "one command, one minute"
- Give new installers a confidence check after `/discover:init`

**Success Metrics:**
- Running `/health` on a correctly configured system exits with
  all green in under 5 seconds
- Running `/health` with a broken dependency produces a fix
  instruction that resolves the issue without external research
- Zero false positives: a passing health check means the system
  actually works end-to-end

---

## User Personas & Use Cases

### User Personas

**New Installer**: Just ran `install.sh` and `/discover:init`.
Wants to confirm everything is wired up before starting real work.
- **Need**: Confidence that RLM, claude-mem, and the hook are all
  actually working before investing time in a session

**Confused Developer**: Session context didn't carry over. Claude
seems unaware of past decisions. Suspects something is broken but
doesn't know where to start.
- **Need**: Quick triage — which layer failed?

**Returning User After System Changes**: Upgraded Claude Code,
changed settings.json, or moved the repo. Something might have
broken.
- **Need**: Re-verify system integrity without re-reading all docs

### User Stories

**Story 1 — Verify after install**
As a new installer, I want to run a single command after setup that
tells me all systems are go, so that I can start my first real
session with confidence.

**Acceptance Criteria:**
- [ ] Command runs without any arguments
- [ ] Output shows status of each dependency with ✅ or ❌
- [ ] All green means the full RLM-Mem workflow is usable
- [ ] Completes in under 10 seconds

**Story 2 — Diagnose a broken session**
As a developer whose session context is missing, I want the health
check to identify the broken component and tell me exactly how to
fix it, so that I can restore normal operation in under 2 minutes.

**Acceptance Criteria:**
- [ ] Each ❌ item is accompanied by a one-line diagnosis
- [ ] Each ❌ item is accompanied by the exact command or config
  change needed to fix it
- [ ] Fix instructions are copy-pasteable (no placeholders)

**Story 3 — Verify PostToolUse hook is capturing observations**
As a developer, I want the health check to actually verify the hook
works end-to-end (not just check if it is registered), so that I
know observations are actually being written to claude-mem.

**Acceptance Criteria:**
- [ ] Health check writes a test observation via the write+read
  pattern and verifies it appears in claude-mem search results
- [ ] If the hook is registered but not capturing, ❌ is shown
  (not a false ✅)

---

## Requirements

### Functional Requirements

**FR-1: RLM State Check**
- **What**: Verify `.claude/rlm_state/state.pkl` exists in the
  current project and is readable
- **How**: Run `python3 ~/.claude/rlm_scripts/rlm_repl.py status`
  and parse output for file count and repo path
- **Pass**: state.pkl exists, file count > 0, repo path matches cwd
- **Fail message**: "RLM state missing or empty. Fix: run
  `/rlm-mem:discover:init` to index this repository."
- **Priority**: Critical

**FR-2: claude-mem Plugin Check**
- **What**: Verify the claude-mem MCP tools are available and
  responding
- **How**: Call `mcp__plugin_claude-mem_mcp-search__search` with
  a minimal query and verify it returns (even zero results is OK)
- **Pass**: Tool call completes without error
- **Fail message**: "claude-mem plugin not responding. Fix: verify
  the plugin is installed (`/plugin list`) and the MCP server is
  running."
- **Priority**: Critical

**FR-3: PostToolUse Hook End-to-End Check**
- **What**: Verify the hook is actually capturing file reads as
  claude-mem observations (not just registered)
- **How**:
  1. Write a uniquely-tagged test file:
     `/tmp/claude-mem-health-check-{timestamp}.md`
     with content `# Health Check Test\n[TYPE: HEALTH-CHECK]\n...`
  2. Read the file (triggers PostToolUse hook)
  3. Wait briefly, then search claude-mem for the unique tag
  4. If found → hook is working; if not → hook is broken
- **Pass**: Observation appears in claude-mem search within the
  same session
- **Fail message**: "PostToolUse hook is not capturing observations.
  Fix: verify `~/.claude/settings.json` has the PostToolUse hook
  configured for claude-mem. See README.md §Hook Setup."
- **Priority**: Critical

**FR-4: Summary Report**
- **What**: Output a clean status table at the end
- **Format**:
  ```
  ## RLM-Mem Health Check

  | Component          | Status | Notes                        |
  |--------------------|--------|------------------------------|
  | RLM state          | ✅     | 31 files indexed             |
  | claude-mem plugin  | ✅     | Responding                   |
  | PostToolUse hook   | ✅     | Observation captured         |

  All systems operational. Ready for /rlm-mem:discover:start
  ```
- **Priority**: High

**FR-5: Actionable Fix Instructions on Failure**
- **What**: For each ❌ component, print a specific fix instruction
  immediately below the table
- **Format**:
  ```
  ❌ RLM state missing or empty.
     → Run: /rlm-mem:discover:init
  ```
- **Priority**: High

### Non-Functional Requirements

**NFR-1: Speed** — Full check completes in under 10 seconds.
The hook verification adds a search round-trip; this is acceptable.

**NFR-2: No side effects** — The test observation written for FR-3
should be clearly tagged `[TYPE: HEALTH-CHECK]` so it does not
pollute project memory. It can remain in claude-mem (serves as an
audit trail of health checks run).

**NFR-3: Fail open** — If the health check command itself errors
(e.g., RLM script not found), it must report the error clearly
rather than crashing silently. Never leave the user with no output.

**NFR-4: Works from any project directory** — The command must
correctly detect the project context and RLM state relative to cwd.

### Technical Constraints

- Must use only existing infrastructure: Bash tool (for RLM),
  MCP search tools (for claude-mem), Write + Read tools (for hook
  verification)
- No new scripts or binaries — the command is a pure markdown
  prompt file like all other commands
- Must follow the write+read pattern established in 005-FIX-SAVE-MEMORY
  for all claude-mem interactions

---

## Out of Scope

- **Playwright MCP check** — Optional dependency, not checked.
  Users who need E2E agents can verify Playwright separately.
- **Auto-fix** — The command diagnoses and instructs; it does not
  automatically repair broken configuration.
- **Continuous monitoring** — This is a one-shot check, not a
  background health monitor.
- **Performance benchmarking** — Checking that RLM is fast enough
  is out of scope; only correctness is verified.
- **claude-mem database integrity** — We verify the plugin responds;
  deep database consistency checks are out of scope.

---

## Gherkin Scenarios

```gherkin
Feature: Health Check Command

  Scenario: All systems operational
    Given RLM state.pkl exists with >0 files
    And claude-mem plugin is installed and running
    And PostToolUse hook is registered and capturing
    When I run /rlm-mem:discover:health
    Then I see a table with three ✅ rows
    And the message "All systems operational"
    And the check completes in under 10 seconds

  Scenario: RLM state missing
    Given no .claude/rlm_state/state.pkl in current project
    When I run /rlm-mem:discover:health
    Then I see ❌ for "RLM state"
    And I see the fix instruction "Run /rlm-mem:discover:init"
    And claude-mem and hook checks still run

  Scenario: claude-mem plugin not responding
    Given the claude-mem MCP tool call returns an error
    When I run /rlm-mem:discover:health
    Then I see ❌ for "claude-mem plugin"
    And I see fix instruction referencing /plugin list
    And RLM and hook checks still run (independent)

  Scenario: PostToolUse hook not capturing
    Given the hook is registered but observations are not appearing
    When I run /rlm-mem:discover:health
    Then I see ❌ for "PostToolUse hook"
    And I see fix instruction referencing settings.json configuration
    And RLM and claude-mem checks still run

  Scenario: Multiple failures
    Given RLM state is missing and hook is broken
    When I run /rlm-mem:discover:health
    Then I see ❌ for both affected components
    And each ❌ has its own fix instruction
    And the summary says "2 issues found"
```

---

## References

### From Codebase (RLM)
- `.claude/commands/rlm-mem/discover/init.md` — RLM init and
  verification pattern (Step 1 and Step 5)
- `.claude/hooks/context-guard.sh` — Example of hook-based system
  check pattern
- `.claude/rlm_scripts/rlm_repl.py` — `status` command is the
  basis for FR-1

### From History (claude-mem)
- 005-FIX-SAVE-MEMORY: Established the write+read pattern for
  hook verification — directly applicable to FR-3

---

**Next Steps:**
1. Review and approve this PRD
2. Run `/rlm-mem:plan:tech-design` to design the command structure
3. Run `/rlm-mem:plan:tasks` to break down implementation
