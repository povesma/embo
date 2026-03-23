# 008-STATUSLINE - Task List

## Relevant Files

- [tasks/008-STATUSLINE-config-and-improvements/
  2026-03-19-008-STATUSLINE-prd.md](
  2026-03-19-008-STATUSLINE-prd.md)
  :: Product Requirements Document
- [tasks/008-STATUSLINE-config-and-improvements/
  2026-03-19-008-STATUSLINE-tech-design.md](
  2026-03-19-008-STATUSLINE-tech-design.md)
  :: Technical Design Document
- [.claude/statusline.sh](../../.claude/statusline.sh)
  :: New statusline script (CREATE)
- [.claude/agents/statusline-setup.md](
  ../../.claude/agents/statusline-setup.md)
  :: New statusline-setup skill (CREATE)
- [install.sh](../../install.sh)
  :: Add statusline copy + settings.json prompt
- [README.md](../../README.md)
  :: Add statusline setup step and Statusline section
- [CLAUDE.md](../../CLAUDE.md)
  :: Add statusline.sh to File Structure listing

## Notes

- TDD does not apply to the shell script or markdown skill files —
  manual verification against Gherkin scenarios in the PRD is the
  test method.
- The statusline script must be manually tested by running it with
  sample JSON piped via stdin (see verification tasks).
- `jq` is required for the script and for the install.sh patch
  logic. Tests should verify both jq-present and jq-absent paths.
- The `statusline-setup` skill is a markdown prompt file; testing
  means invoking it in Claude Code and verifying the behaviour.

## Tasks

- [X] 1.0 **User Story:** As a developer, I want `.claude/statusline.sh`
  to read the cwd from stdin JSON and display it with tilde
  abbreviation, so that the path is shorter under the home directory
  [4/4]
  - [X] 1.1 Create `.claude/statusline.sh` with shebang
    `#!/usr/bin/env bash`, `set -euo pipefail`,
    `input=$(cat)`, and `jq` availability check that
    prints `[statusline: jq not found]` and exits 0 if
    missing
  - [X] 1.2 Extract `DIR` via
    `jq -r '.workspace.current_dir // .cwd // ""'`
    and apply tilde substitution:
    `DIR="${DIR/#$HOME/\~}"`
  - [X] 1.3 Extract `BRANCH` via
    `git branch --show-current 2>/dev/null`; if empty,
    omit the branch segment from output
  - [X] 1.4 Verify: pipe sample JSON with
    `cwd=/Users/$USER/foo` and confirm output starts with
    `~/foo`; pipe JSON with `cwd=/etc/nginx` and confirm
    no tilde substitution

- [X] 2.0 **User Story:** As a developer, I want the statusline to
  show `USED/TOTAL` token counts in short form using the real
  context window size, so that I can accurately gauge remaining
  context [5/5]
  - [X] 2.1 Add `short_num()` helper function to
    `statusline.sh` per tech design spec: returns `NM`
    for ≥1M, `NK` for ≥1K, raw number otherwise, `?` for
    null/empty input
  - [X] 2.2 Extract `CTX_SIZE` via
    `jq -r '.context_window.context_window_size // "null"'`
  - [X] 2.3 Extract `USED` via single `jq` expression
    summing `input_tokens + cache_creation_input_tokens +
    cache_read_input_tokens` from `current_usage`, all
    with `// 0` fallbacks (handles null `current_usage`)
  - [X] 2.4 Assemble context segment as
    `$(short_num $USED)/$(short_num $CTX_SIZE)`
  - [X] 2.5 Verify: pipe JSON with
    `context_window_size=200000`, `input_tokens=30000`,
    cache=0 → segment shows `30K/200K`; pipe with
    `context_window_size=null` → shows `0/?` or `NNN/?`;
    pipe with null `current_usage` → shows `0/200K`

- [X] 3.0 **User Story:** As a developer, I want the statusline to
  show model name, cost, and time alongside the directory and
  context segments, so that the full status line matches the
  target format [3/3]
  - [X] 3.1 Extract `MODEL` via
    `jq -r '.model.display_name // "Unknown"'`,
    `COST` via
    `jq -r '.cost.total_cost_usd // 0'`
    formatted as `printf '$%.3f'`, and
    `TIME` via `date +%H:%M:%S`
  - [X] 3.2 Assemble and print final output line:
    `DIR | BRANCH | MODEL | USED/CTX $COST | TIME`
    (omit `| BRANCH` segment if branch is empty);
    output must be a single line with no trailing newline
  - [X] 3.3 Verify end-to-end: pipe a realistic full JSON
    blob and confirm output matches the target format from
    the tech design:
    `~/AI/repo | main | Sonnet 4.6 | 30K/200K $0.072 | 08:32:39`

- [X] 4.0 **User Story:** As a new installer, I want `install.sh`
  to copy `statusline.sh` and offer to configure
  `settings.json`, so that setup requires minimal manual steps
  [4/4]
  - [X] 4.1 Add statusline block to `install.sh` after the
    hooks section: copy `.claude/statusline.sh` to
    `$TARGET/statusline.sh` and `chmod +x`
  - [X] 4.2 Add `jq` detection: if absent, print install
    instructions (`brew install jq` / `apt install jq`)
    and the required JSON block; continue without patching
  - [X] 4.3 Add `settings.json` prompt: if `statusLine`
    already present skip with message; otherwise prompt
    `[y/N]`, on `y` patch atomically via
    `jq … > /tmp/_rlm_settings.tmp && mv`
  - [X] 4.4 Verify: run `install.sh` in a temp dir with
    and without jq present; confirm script copies the
    file, prompts correctly, and never exits non-zero

- [X] 5.0 **User Story:** As a developer, I want a way to
  configure and switch statusline scripts without manually
  editing JSON, so that I don't need to know the settings.json
  schema [1/1]
  - [X] 5.1 Live UX test confirmed: the built-in
    `statusline-setup` subagent (Claude Code built-in, not
    a file) handles initial setup and script switching.
    Invoke it by asking Claude: "use the existing script at
    ~/.claude/statusline.sh". No custom subagent needed —
    document this in README instead (covered by 6.3).

- [X] 6.0 **User Story:** As a new installer following the README,
  I want the installation guide to include statusline setup
  steps, so that I end up with a working status line without
  external research [4/4]
  - [X] 6.1 Add step 6 to macOS/Linux manual install block
    in `README.md`: copy `statusline.sh`, `chmod +x`, and
    manual `settings.json` snippet; note `jq` prerequisite
  - [X] 6.2 Add equivalent step to Windows manual install
    block in `README.md`: copy step only (no `jq` patch);
    show JSON snippet to add manually
  - [X] 6.3 Add `statusline.sh` entry to "What Gets
    Installed" tree in `README.md`; add §Statusline section
    with Option A (built-in agent) + Option B (manual JSON),
    version disclaimer for the built-in agent, and
    multi-script switching instructions
  - [X] 6.4 Update `CLAUDE.md` File Structure listing to
    include `statusline.sh`

