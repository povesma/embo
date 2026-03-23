# 008-STATUSLINE: Status Line Configuration & Improvements - PRD

**Status**: Draft
**Created**: 2026-03-19
**Author**: Claude (via rlm-mem analysis)

---

## Introduction/Overview

Claude Code's status line displays live session information — current directory,
git branch, model, token usage, cost, and time. The RLM-Mem installation package
currently does not ship a statusline configuration, meaning each user must
discover and configure it themselves.

Additionally, the user's current status line has two known inaccuracies:

1. **Directory display**: The full home directory path is shown
   (`/Users/dmytrop/povesma/AI/...`) instead of the tilde-abbreviated form
   (`~/AI/...`), wasting horizontal space.

2. **Token/context display**: The pre-calculated `used_percentage` and
   the raw token count are both calculated against a hardcoded 200K baseline,
   regardless of the actual model's context window. This makes the percentage
   meaningless for models with different window sizes. The desired display is
   `30K/200K` or `400K/1M` — absolute numbers in short form — derived from
   the actual context window size provided by Claude Code at runtime.

This feature adds a ready-to-use statusline shell script to the repository,
ships a `statusline-setup` configuration command that installs it for the user,
and updates the installation procedure to include statusline setup as a step.

---

## Objectives & Success Metrics

**Objectives:**
- Ship a statusline script in the repo that any user can install with one command
- Fix tilde abbreviation for home-directory paths
- Replace `ctx N%` with `USED/TOTAL` in short-form (e.g. `30K/200K`, `400K/1M`)
  using the real context window size from Claude Code's runtime JSON

**Success Metrics:**
- A new user following the install guide ends up with the statusline working
  after one additional step
- The directory segment shows `~` instead of `/Users/<name>` when cwd is
  under the home directory
- The token segment correctly reads `context_window.context_window_size` from
  the runtime JSON (not hardcoded) and renders `USED/TOTAL` in short form
- Unknown context window sizes fall back to `?` in the denominator
  (e.g. `30K/?`) only when the runtime value is genuinely absent/null

---

## User Personas & Use Cases

**New Installer**: Just completed `install.sh` and `/discover:init`. Wants
their IDE status bar to show useful session info without researching the
Claude Code docs.

**Existing User (the author)**: Has a working statusline but with two
display bugs — full path instead of tilde, and wrong context window
denominator. Wants targeted fixes applied to the existing script.

---

## User Stories

### Story 1 — Tilde abbreviation

**As a** developer,
**I want** the directory segment of the status line to display `~` when my
working directory is inside my home directory,
**so that** the status line is shorter and leaves room for other segments.

**Acceptance Criteria:**
- [ ] `/Users/dmytrop/povesma/AI/foo` → `~/AI/foo`
- [ ] `/Users/dmytrop` itself → `~`
- [ ] A path outside the home directory (`/etc/nginx`) is shown as-is
- [ ] Works for any user's home directory (not hardcoded to a specific path)

---

### Story 2 — Accurate context window display

**As a** developer,
**I want** the token/context segment to show `USED/TOTAL` in short form
(e.g. `30K/200K`, `4K/200K`, `400K/1M`) using the real context window size,
**so that** I can see at a glance how much context is left, correctly calibrated
for the model in use.

**Acceptance Criteria:**
- [ ] Uses `context_window.context_window_size` from the Claude Code runtime JSON
  (not a hardcoded value)
- [ ] Used tokens = `current_usage.input_tokens + cache_creation_input_tokens +
  cache_read_input_tokens` (matching Claude Code's own `used_percentage` formula)
- [ ] Numbers formatted in short form: values ≥ 1,000,000 → `NM`, values
  ≥ 1,000 → `NK`, values < 1,000 → `N`
  - Examples: `1000000` → `1M`, `200000` → `200K`, `30000` → `30K`, `500` → `500`
- [ ] When `context_window_size` is null or absent, denominator shows `?`
  (e.g. `30K/?`) — only in that genuinely absent case
- [ ] Replaces the current `ctx N%` segment entirely

---

### Story 3 — Statusline script shipped in the repository

**As a** new RLM-Mem installer,
**I want** a ready-to-use statusline script included in the repository,
**so that** I don't have to write one from scratch.

**Acceptance Criteria:**
- [ ] Script exists at `.claude/statusline.sh` in the repo
- [ ] Script is executable (`chmod +x`)
- [ ] Script produces valid single-line output when piped JSON matching the
  Claude Code schema
- [ ] Script contains a comment header explaining its purpose and how to update
  the model map if needed

---

### Story 4 — Installation procedure includes statusline setup

**As a** new installer following the README,
**I want** the installation guide to include a step that installs the statusline,
**so that** I end up with a working status line without extra research.

**Acceptance Criteria:**
- [ ] `README.md` §Installation includes a step for statusline setup
- [ ] The step covers both: (a) copying `statusline.sh` to `~/.claude/` and
  (b) adding the `statusLine` block to `~/.claude/settings.json`
- [ ] Manual steps are provided alongside any script automation (per
  Documentation Rules in CLAUDE.md)
- [ ] `install.sh` copies `statusline.sh` to `~/.claude/statusline.sh` and
  sets executable permission

---

### Story 5 — Statusline-setup command (optional convenience)

**As a** developer who has already installed RLM-Mem,
**I want** to run a single slash command that configures the statusline for me,
**so that** I don't have to manually edit `settings.json`.

**Acceptance Criteria:**
- [ ] A `statusline-setup` agent/skill exists (or the built-in `/statusline`
  command is documented as the recommended approach)
- [ ] Running it results in `settings.json` containing the correct `statusLine`
  block pointing to `~/.claude/statusline.sh`
- [ ] If `settings.json` already has a `statusLine` block, the command warns
  before overwriting

---

## Requirements

### Functional Requirements

**FR-1: Tilde abbreviation in directory segment**
- **What**: Replace `$HOME` prefix in `cwd` with `~`
- **How**: In the shell script, `${CWD/#$HOME/\~}` (bash parameter expansion)
  or equivalent
- **Priority**: High

**FR-2: Real-time context window size from runtime JSON**
- **What**: Read `context_window.context_window_size` from stdin JSON
- **How**: `jq -r '.context_window.context_window_size // empty'`; if
  empty/null, set to `null`
- **Priority**: Critical

**FR-3: Short-form number formatting**
- **What**: Format token counts as `NK` or `NM`
- **How**: Shell arithmetic or awk; thresholds: ≥1,000,000 → `NM`;
  ≥1,000 → `NK`; else raw number
- **Priority**: High

**FR-4: `USED/TOTAL` display replacing `ctx N%`**
- **What**: Render `{used_short}/{total_short}` in the status line
- **Total**: from `context_window.context_window_size`; `?` if null
- **Used**: `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
  from `context_window.current_usage`
- **Priority**: Critical

**FR-5: Script shipped in repo and installed via `install.sh`**
- **What**: `.claude/statusline.sh` checked into the repo; `install.sh` copies
  it to `~/.claude/statusline.sh` with `chmod +x`
- **Priority**: High

**FR-6: `settings.json` `statusLine` block documented**
- **What**: README and install guide explain the required JSON block
- **Content**:
  ```json
  {
    "statusLine": {
      "type": "command",
      "command": "~/.claude/statusline.sh"
    }
  }
  ```
- **Priority**: High

### Non-Functional Requirements

**NFR-1: Performance** — Script must complete in under 200ms on average hardware.
No external network calls. Git branch reading is acceptable (fast local operation).

**NFR-2: No hardcoded paths** — Home directory must be derived from `$HOME`,
not hardcoded to any specific user's path.

**NFR-3: Null safety** — All `jq` reads must use `// 0` or `// empty` fallbacks.
A null field must never crash the script or produce garbled output.

**NFR-4: Portable** — Script must work on macOS (zsh/bash) and Linux (bash).
Uses only POSIX shell + `jq` (which is a Claude Code dependency anyway).

**NFR-5: Output format** — Single line of plain text, no trailing newline.
ANSI color codes are permitted but not required.

### Technical Constraints

- Claude Code passes JSON via **stdin** to the statusline command
- The script must read stdin completely before processing (`input=$(cat)`)
- `context_window.current_usage` may be `null` before the first API call —
  handle gracefully (default used tokens to `0`)
- The existing status line format the user has is:
  ```
  /Users/dmytrop/povesma/AI/claude_code_RLM_mem | feature/007-health-check | Sonnet 4.6 | 4807 tok $0.072 | ctx 17% | 08:32:39
  ```
  The new format target is:
  ```
  ~/AI/claude_code_RLM_mem | feature/007-health-check | Sonnet 4.6 | 30K/200K $0.072 | 08:32:39
  ```

---

## Out of Scope

- **Vim mode indicator** — Not part of this task
- **ANSI color theming** — Nice to have, but the script need not ship with
  colors to be correct
- **Windows / PowerShell support** — Claude Code on Windows is not a target
- **Auto-updating the model map** — Since `context_window_size` is provided
  dynamically by Claude Code, there is no model map to maintain
- **Cost-per-token breakdown** — The `$0.072` cost display format is unchanged;
  only the token/context segment changes

---

## Gherkin Scenarios

```gherkin
Feature: Statusline improvements

  Scenario: Tilde abbreviation under home directory
    Given the user's home directory is /Users/dmytrop
    And the current working directory is /Users/dmytrop/AI/foo
    When the statusline script runs
    Then the directory segment displays "~/AI/foo"

  Scenario: Path outside home directory unchanged
    Given the current working directory is /etc/nginx
    When the statusline script runs
    Then the directory segment displays "/etc/nginx"

  Scenario: Context window from runtime JSON (200K model)
    Given Claude Code passes context_window_size = 200000
    And current_usage.input_tokens = 30000
    And cache tokens are 0
    When the statusline script runs
    Then the context segment displays "30K/200K"

  Scenario: Context window from runtime JSON (1M model)
    Given Claude Code passes context_window_size = 1000000
    And current_usage.input_tokens = 400000
    When the statusline script runs
    Then the context segment displays "400K/1M"

  Scenario: Context window size null/absent
    Given Claude Code passes context_window_size = null
    And current_usage.input_tokens = 5000
    When the statusline script runs
    Then the context segment displays "5K/?"

  Scenario: Before first API call (current_usage null)
    Given current_usage is null
    And context_window_size = 200000
    When the statusline script runs
    Then the context segment displays "0/200K"

  Scenario: New installer runs install.sh
    Given the user has cloned the repo
    When the user runs bash install.sh
    Then ~/.claude/statusline.sh exists and is executable
    And README instructs the user to add the statusLine block to settings.json

  Scenario: New installer follows README manual steps
    Given the user does not want to run install.sh
    When the user follows the manual install steps in README
    Then they copy statusline.sh to ~/.claude/statusline.sh
    And they add the statusLine block to ~/.claude/settings.json
    And the statusline displays correctly on the next Claude Code launch
```

---

## References

### From Codebase
- `install.sh` — Must be updated to copy `statusline.sh`
- `README.md` — §Installation must be extended with statusline step
- `TROUBLESHOOTING.md` — May need a note about null `current_usage` before
  first API call

### From Claude Code Docs (Context7)
- `context_window.context_window_size` — runtime field providing actual max
  tokens for the current model; never null after first API call
- `context_window.current_usage` — `{input_tokens, cache_creation_input_tokens,
  cache_read_input_tokens, output_tokens}` from the last API call; may be null
  before first call
- `statusLine.type = "command"` — script receives full JSON on stdin

---

**Next Steps:**
1. Review and approve this PRD
2. Run `/rlm-mem:plan:tech-design` to design the script and install changes
3. Run `/rlm-mem:plan:tasks` to break down into tasks
