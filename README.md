# embo

**A spec-driven Claude Code workflow** - PRD -> tech-design ->
tasks -> impl, backed by a persistent codebase index (RLM) and
cross-session memory (claude-mem).

> **TL;DR**
> - **Category:** spec-driven development workflow for Claude Code
> - **Differentiator:** the only framework with **both** persistent
> codebase indexing **and** cross-session memory
> - **Install:** **two plugins, inside Claude Code** — (1)
> `/plugin install embo@embo`, (2) install the **claude-mem** plugin.
> See [Install](#install) below.
> - **First session:** `/embo:init` -> `/embo:start` -> `/embo:prd`
> - **Compare to alternatives:** [Comparison](#comparison)
> - **Why this exists:** [Why](#why-this-exists) |
> full evidence: [docs/WHY.md](docs/WHY.md)

<!-- ARCHITECTURE-DIAGRAM-ANCHOR -->
![embo architecture: commands, parallel context engines (RLM + claude-mem), and verified outputs feeding /embo:impl](assets/diagrams/architecture-overview.png)

<sub>Source prompt: [`assets/diagrams/architecture-overview.prompt.md`](assets/diagrams/architecture-overview.prompt.md) — regenerate via Claude Design.</sub>

![embo workflow sequence: waterfall with self-correction — every downstream command can revise upstream specs when reality contradicts the plan](assets/diagrams/workflow-sequence.png)

<sub>Source prompt: [`assets/diagrams/workflow-sequence.prompt.md`](assets/diagrams/workflow-sequence.prompt.md) — regenerate via Claude Design.</sub>

## Install

embo installs as a **Claude Code plugin**. Two required steps, both
typed **inside Claude Code** (at the `/` prompt, not a terminal).

### Step 1 — Install embo (inside Claude Code)

```text
/plugin marketplace add povesma/embo
/plugin install embo@embo
```

This registers all `/embo:*` commands, agents, and hooks. Read
`install <plugin-name>@<marketplace-name>` — both are `embo`.

> [!TIP]
> To try a specific branch before it merges, add the marketplace with
> a `#ref` suffix: `/plugin marketplace add povesma/embo#some-branch`.
> To develop locally, point the marketplace at a working copy:
> `/plugin marketplace add /path/to/embo`.

### Step 2 — Install the claude-mem plugin (inside Claude Code) — REQUIRED

```text
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem
```

> [!WARNING]
> **Install the plugin named exactly `claude-mem`, from the
> `thedotmack/claude-mem` marketplace.** claude-mem is MANDATORY —
> embo verifies it at runtime and its commands fail with a clear
> error without it. (It is a separate plugin, not a bundled
> dependency.) When the `/plugin` menu lists unrelated plugins
> (`frontend-design`, `figma`, …), do not pick those.

### Step 3 — Verify (inside Claude Code)

```text
/embo:health
```

Must report RLM, claude-mem, and the capture hook as operational.

### First session (inside Claude Code, in any of your code repos)

```text
/embo:init    # one-time: index the repo + bootstrap memory
/embo:start   # every session: load context
/embo:prd     # plan a feature spec-first
```

> [!NOTE]
> **Upgrading from the old `cp`-into-`~/.claude/` install?** The old
> manual install registered the embo hooks in your
> `~/.claude/settings.json`; the plugin registers its own. Two
> registrations of the same hook fire twice. Run the migration doctor
> once to remove the stale entries (it prompts per entry and backs up
> first):
> ```bash
> $ bash "${CLAUDE_PLUGIN_ROOT}/hooks/fix-hooks.sh" --fix
> ```
> It also flags any stale `~/.claude/commands/dev/` files (the old
> `/dev:*` copies) to remove.

Full per-platform details, the manual (no-plugin) install, and
dependency versions are under [Reference](#reference).

## Comparison

How embo positions against other Claude Code workflow plugins.
Snapshot 2026-06-07; sources for every cell are in
[`tasks/017-.../comparison-data.md`](tasks/017-README-ONBOARDING-spec-driven-positioning/comparison-data.md).

| Project | Spec phases | Code navigation | X-session memory | TDD | Profiles | Agent model | Worktrees |
|---|---|---|---|---|---|---|---|
| **embo** *(this)* | yes | index (RLM) | yes | yes | yes (4) | focused (1+5 test) | no |
| [Superpowers](https://github.com/obra/superpowers) | yes | grep-only | optional | yes | partial | skills (20+) | yes |
| [BMAD-METHOD](https://github.com/aj-geddes/claude-code-bmad-skills) | yes | none | yes | partial | yes | roles (9) | no |
| [Oh-My-ClaudeCode](https://github.com/Yeachan-Heo/oh-my-claudecode) | partial | LSP+AST | yes | no | yes | swarm (29) | yes |
| [claude-code-workflows](https://github.com/shinpr/claude-code-workflows) | yes | grep-only | no | yes | yes | roles (variants) | no |
| [claude-workflow-template](https://github.com/nicholasmartin/claude-workflow-template) | yes | none | partial | no | no | single (1) | no |

Legend: `yes` = built-in · `partial` / `optional` = partial or
optional · `no` / `none` = absent. **Code navigation**: how the tool
locates code — a persistent `index`, live `LSP+AST` lookups, plain
`grep`, or `none`. **Agent model**: the shape of the agent roster
(a `focused` set, a large `swarm`, role-based, or a `single` agent) —
not a quality score; more agents is not inherently better.

**Pick embo if:** you want both *spatial* (where is code?)
and *temporal* (why did we decide this in February?) context
auto-loaded into every spec, design, and impl. No other tool here
has both a persistent codebase index **and** cross-session memory.

**Pick something else if:**
- you need **git-worktree isolation** for parallel agents —
  Superpowers or OMC
- you want **maximum agent throughput / parallel swarms** — OMC or
  shinpr
- you rely on **LSP/AST "go-to-definition" navigation** rather than a
  text index — OMC
- you want **self-looping verification** (audit-fix-retry until a
  pass signal) — OMC (`ralph`) or shinpr's quality gates

## Why this exists

Three measurable failures of unstructured ("vibe") AI coding,
each from peer-reviewed or industry-leader sources:

- **AI tooling slowed experienced developers by 19%** in a
 controlled RCT - overhead of prompting and reviewing
 outweighs the generation speed-up
 ([METR study, 2025](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/))
- **Failed agent attempts cost 4x more than successful ones**
 due to the Token Snowball Effect - ~8.8M tokens / 658s
 burned on a single failed loop
 ([SWE-Effi, 2025](https://arxiv.org/abs/2509.09853))
- **Spec-driven workflows recover the loss**: TDFlow scored
 **88.8% on SWE-bench Lite** when given human-written tests -
 a 27.8 pp absolute improvement over the next best baseline
 ([TDFlow, 2025](https://arxiv.org/abs/2510.23761))

embo is the smallest framework that delivers both halves:
**enforced decomposition** (PRD -> tech-design -> tasks -> impl)
to dodge Token Snowball, **and** persistent memory (RLM index +
claude-mem) so the structure compounds across sessions instead
of resetting to zero every morning.

-> Full evidence and citations: [**docs/WHY.md**](docs/WHY.md)

## Available Commands

| Phase | Command | Purpose |
|---|---|---|
| Discovery | `/embo:init` | Index repo + bootstrap claude-mem (one-time) |
| Discovery | `/embo:start` | Load session context (every session) |
| Discovery | `/embo:health` | Verify dependencies |
| Planning | `/embo:prd` | Generate PRD with codebase + memory awareness |
| Planning | `/embo:tech-design` | Architecture design grounded in real code |
| Planning | `/embo:test-plan` | Map stories to verification methods |
| Planning | `/embo:tasks` | Break tech-design into TDD-ready subtasks |
| Planning | `/embo:check` | Audit task completion status |
| Development | `/embo:impl` | Implement subtasks one at a time, evidence-gated |
| Development | `/embo:git` | Generate commit messages and PR descriptions |
| Research | `/embo:research:examine` | Independent two-pass critique of a decision or doc → reconciled recommendation |
| Research | `/embo:research:verify` | Prove a chosen approach meets its acceptance criteria before building |
| Config | `/embo:profile` | Switch workflow profile (quality / fast / minimal / research) |

Full per-command reference under [Reference](#reference).

## Test subagents

Five specialised agents run in **isolated contexts** during
`/embo:impl` to prevent implementation bias:

- **test-backend** (Haiku) - writes & runs unit/integration
 tests; auto-detects pytest/vitest/jest/go/cargo/phpunit
- **test-review** (Sonnet) - adversarial gap analysis,
 read-only
- **test-e2e-planner / -generator / -healer** (Sonnet,
 forked from Playwright) - Playwright MCP required

Full agent reference under [Reference](#reference).

---

## Reference

Everything below this line is reference material. Skip on first
read; come back when you need depth on a specific feature.

### Prerequisites

#### Required

1. **Claude Code** - Anthropic's official CLI
 - Install from: https://claude.ai/download
 - Version: Latest stable

2. **Python 3.8-3.12** - For RLM REPL
 - macOS: Pre-installed or via Homebrew (`brew install python@3.12`)
 - Windows: `winget install Python.Python.3.12`
 - Note: Python 3.13+ is not compatible with ChromaDB (used by claude-mem)

3. **Claude-Mem plugin** - For semantic memory
 - Install in Claude Code: `/plugin marketplace add thedotmack/claude-mem` then `/plugin install claude-mem`
 - Repository: https://github.com/thedotmack/claude-mem

4. **Git repository** - Your code must be in a git repo

#### Nice to Have

5. **Frontend Design Plugin** - For UI/UX design work
 - Step 1 - add to marketplace: `/plugin marketplace add anthropics/claude-code`
 - Step 2 - install: `/plugin install frontend-design@claude-code-plugins`

6. **Context7 MCP Server** - For library documentation lookups (no authentication required)
 - `claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp`

### Installation

#### macOS / Linux Installation

**The recommended install is the plugin** — see [Install](#install)
(`/plugin marketplace add povesma/embo` + `/plugin install embo@embo`).
The steps below are the **manual (no-plugin) alternative**: they place
the same components under `~/.claude/` by hand. The plugin path is
simpler and self-updating; use manual only if you cannot use the
plugin system.

The repo ships everything under `plugin/`. Copy from there:

```bash
git clone https://github.com/povesma/embo ~/embo
cd ~/embo

# 1. RLM script + the bin/ wrapper that runs it as a plain `rlm_repl`
mkdir -p ~/.claude/rlm_scripts ~/.claude/bin
cp plugin/rlm_scripts/rlm_repl.py ~/.claude/rlm_scripts/
cp plugin/bin/rlm_repl ~/.claude/bin/
chmod +x ~/.claude/rlm_scripts/rlm_repl.py ~/.claude/bin/rlm_repl

# 2. Put ~/.claude/bin on PATH so commands can call `rlm_repl` directly
#    (add to your shell profile, e.g. ~/.zshrc or ~/.bashrc):
#    export PATH="$HOME/.claude/bin:$PATH"

# 3. Agents
mkdir -p ~/.claude/agents
cp plugin/agents/*.md ~/.claude/agents/

# 4. Commands — copy into an `embo/` namespace dir so they invoke as
#    /embo:* (the research/ subdir gives /embo:research:examine etc.)
mkdir -p ~/.claude/commands/embo
cp -r plugin/commands/* ~/.claude/commands/embo/

# 5. Hooks
mkdir -p ~/.claude/hooks
cp plugin/hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh

# 6. Register hooks in ~/.claude/settings.json — see §Hook Setup.
#    (The plugin does this automatically; a manual install must add the
#    PreToolUse + UserPromptSubmit entries by hand.)

# 7. Status line (optional; requires jq: brew install jq)
cp plugin/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
# Then add to ~/.claude/settings.json:
# { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }

# 8. Verify
python3 --version          # 3.8+
~/.claude/bin/rlm_repl --help
```

> [!NOTE]
> Manual installs that predate the plugin used `~/.claude/commands/dev/`
> (giving `/dev:*`). The current layout uses `~/.claude/commands/embo/`
> (`/embo:*`). If upgrading, remove the old tree:
> `rm -rf ~/.claude/commands/dev`.

**Expected output:**
```
usage: rlm_repl [-h] [--state STATE]
 {init,init-repo,status,reset,export-buffers,exec} ...
```

#### Windows Installation

##### Windows Prerequisites

| Dependency | Required | Purpose | Install |
|------------|----------|---------|---------|
| **Python 3.8-3.12** | Yes | RLM REPL | `winget install Python.Python.3.12` |
| **Git** | Yes | Version control, RLM file indexing | `winget install Git.Git` |
| **Claude Code** | Yes | CLI tool | https://claude.ai/download |
| **bash** | Recommended | Hooks, statusline | Included with Git for Windows |
| **jq** | Recommended | Statusline JSON parsing | `winget install jqlang.jq` |
| **Node.js** | Recommended | claude-mem plugin | `winget install OpenJS.NodeJS.LTS` |
| **gh** | Optional | GitHub PR creation | `winget install GitHub.cli` |

> **Important**: Hooks and statusline require **bash**. If you install
> Git for Windows with "Add to PATH" enabled, bash is included. Without
> bash, any `.sh` hook already registered in `settings.json` will cause
> **prompts to be silently dropped** - Claude Code shows the command
> list but typed text disappears. The install script detects this and
> offers to clean up stale hook entries.

```powershell
# 1. Install required dependencies
winget install Python.Python.3.12 # 3.13+ breaks ChromaDB (used by claude-mem)
winget install Git.Git # includes bash
winget install jqlang.jq # for statusline
winget install OpenJS.NodeJS.LTS # for claude-mem

# 2. Clone this repository
cd $env:USERPROFILE
git clone https://github.com/povesma/embo
cd embo

# 3. Run the install script
powershell -ExecutionPolicy Bypass -File install.ps1
```

The script checks all dependencies and reports what's missing before
proceeding. Optional dependencies can be skipped - features that need
them will be unavailable.

**Or install manually:**

```powershell
cd embo

# Create directories
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\rlm_scripts"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\agents"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\commands\dev"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\profiles"

# Copy RLM scripts and agents
Copy-Item .claude\rlm_scripts\rlm_repl.py "$env:USERPROFILE\.claude\rlm_scripts\"
Copy-Item .claude\agents\*.md "$env:USERPROFILE\.claude\agents\"

# Copy commands and profiles
Copy-Item .claude\commands\dev\* "$env:USERPROFILE\.claude\commands\dev\" -Recurse
Copy-Item .claude\profiles\*.yaml "$env:USERPROFILE\.claude\profiles\"

# Copy hooks (only if bash is available)
if (Get-Command bash -ErrorAction SilentlyContinue) {
 New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\hooks"
 Copy-Item .claude\hooks\*.sh "$env:USERPROFILE\.claude\hooks\"
}

# Verify
python --version # Should show 3.8+
python "$env:USERPROFILE\.claude\rlm_scripts\rlm_repl.py" --help
```

**Note for Windows users:**
- Use `python` or `py -3` instead of `python3` in commands
- Use backslashes `\` instead of forward slashes `/` in paths
- Commands in this guide use Unix syntax; translate as needed

### What Gets Installed

After installation, your `~/.claude/` directory will contain:

```
~/.claude/
├── agents/
│ ├── rlm-subcall.md # RLM subagent for chunk analysis
│ ├── approach-validator.md # Verifies a chosen approach vs its criteria (dev:research:verify)
│ ├── examine-advisor.md # Examines a decision/doc, two passes (dev:research:examine)
│ ├── test-backend.md # Backend test writer (pytest/vitest/jest/etc.)
│ ├── test-review.md # Adversarial coverage gap analyzer
│ ├── test-e2e-planner.md # E2E test plan generator (requires Playwright MCP)
│ ├── test-e2e-generator.md # Playwright test code generator (requires Playwright MCP)
│ └── test-e2e-healer.md # Failing test debugger/repair (requires Playwright MCP)
├── commands/
│ └── dev/ # dev commands (flat + research/ subdir)
│ ├── init.md, start.md, health.md, profile.md
│ ├── prd.md, tech-design.md, test-plan.md, tasks.md, check.md
│ ├── impl.md, git.md
│ └── research/ # examine.md, verify.md (dev:research:*)
├── profiles/
│ ├── quality.yaml # Full workflow profile
│ ├── fast.yaml # Speed mode profile
│ ├── minimal.yaml # Bare bones profile
│ └── research.yaml # Evidence-driven research profile
├── hooks/
│ ├── context-guard.sh # Context window warning hook (optional)
│ ├── behavioral-reminder.sh # Behavioral rule reminder hook (optional)
│ └── approve-compound.sh # Auto-approve compound/redirected Bash cmds (optional)
├── rlm_scripts/
│ └── rlm_repl.py # Persistent REPL for RLM
└── statusline.sh # Status line script (optional)
```

### Hooks

The hooks below are included. **With the plugin install they register
automatically** (via the plugin's `hooks/hooks.json` — nothing to
configure). A **manual install** must register them by hand in
`~/.claude/settings.json` (see setup below). All hooks require `jq`.

| Hook | Event | Purpose | Disable |
|------|-------|---------|---------|
| `context-guard.sh` | `UserPromptSubmit` | Warns when context window is ≥ threshold before new dev work | Set `CONTEXT_GUARD_THRESHOLD=101` in `settings.json` env |
| `behavioral-reminder.sh` | `UserPromptSubmit` | Injects rule tag reminders before each prompt; targeted on criticism, implementation, and git requests | Set `BEHAVIORAL_REMINDER_DISABLED=1` in `settings.json` env |
| `approve-compound.sh` | `PreToolUse` (Bash) | Auto-approves a Bash command when every subcommand (after stripping redirects/env/wrappers, splitting on `&& \|\| ; \| &`) already matches your `permissions.allow` and none matches `deny`. Removes the prompt that a redirect or pipe otherwise triggers. Falls through to the normal prompt on anything it cannot parse; never overrides `deny` or protected-dir checks | Remove the `PreToolUse` matcher from `settings.json` |
| `embo-capture.sh` | (invoked by `approve-compound.sh`, not registered as a hook) | Output capture wrapper: approved commands are rewritten to run through it; full output is saved to `tmp/cap/` in your project, small output prints inline, large output prints a preview plus a `[embo-capture]` marker with the file path and real exit code. Pipelines ending in a filter (`\| head`, `\| grep`, ...) are decomposed: the upstream's full unfiltered output is saved first, the filter runs on the saved copy, and a `filtered view` marker reports both the upstream's and the filter's exit codes | Remove the `approve-compound.sh` registration (wrapping is part of its rewrite) |

All hooks fail open - any error exits silently with code 0 and never
blocks Claude from responding.

#### approve-compound + embo-capture setup

**Plugin install:** registration is automatic. To get fully
prompt-free operation, add these to `permissions.allow` in your
`~/.claude/settings.json` (the plugin cannot set permissions for you):

```json
"Bash(rlm_repl *)",
"Bash(bash */hooks/embo-capture.sh *)",
"Bash(bash */hooks/fix-hooks.sh *)"
```

`rlm_repl` is the bin/ wrapper (RLM); the other two are the capture
wrapper and the migration doctor. Without these you get a one-time
"allow?" prompt per command — choose **"Always allow"** and it does
not recur. (RLM is invoked as a bare `rlm_repl`, never with `${...}`
expansion, specifically so a simple allow rule like the above
matches — Claude Code prompts unconditionally for any command
containing shell expansion.)

**Manual install:** also register the hooks yourself in
`~/.claude/settings.json`:

```json
"hooks": {
  "PreToolUse": [
    { "matcher": "Bash",
      "hooks": [ { "type": "command",
                   "command": "bash ~/.claude/hooks/approve-compound.sh" } ] }
  ],
  "UserPromptSubmit": [
    { "hooks": [
        { "type": "command", "command": "bash ~/.claude/hooks/context-guard.sh" },
        { "type": "command", "command": "bash ~/.claude/hooks/behavioral-reminder.sh" }
    ] }
  ]
}
```

and add the capture wrapper allow-rule:
`"Bash(~/.claude/hooks/embo-capture.sh *)"`. Without it, rewritten
commands fail allowlist matching and the prompts come back.

**Your allowlist stays yours.** The hook only auto-approves commands
whose every segment already matches *your* `permissions.allow` rules.
embo ships no allowlist beyond the wrapper rule above — what runs
without prompting is entirely the user's decision. Compound commands
(`&&`, `||`, `;`, `|`) are approved segment-by-segment and captured
as one unit; `$(...)`, backticks, heredocs, backgrounded (`&`) and
interactive commands (`ssh`, `vim`, `sudo`, ...) are never
auto-wrapped, and unparseable commands always fall back to the
normal permission prompt.

**Filtered pipelines.** A pipeline whose trailing segments are pure
filters (`head`, `tail`, `grep`, `sed`, `awk`, `cut`, `wc`, `sort`,
`uniq`, `jq`, `tr`, `column`) is decomposed by the rewrite: the
upstream runs alone with its full unfiltered stdout saved to the
capture file (stderr kept separate), then the filter chain runs over
the saved copy. The inline result is the filtered view plus a marker:

```
[embo-capture] filtered view — full output:
  <path>  (<N> lines, <M> bytes, upstream exit=<EU>, filter exit=<EF>)
```

The wrapper exits with the filter's code (native pipe semantics);
the upstream's true code is in the marker. If the filter missed
something, the full output is already on disk — no re-run needed.
Decomposition is skipped (the command runs as a normal whole-compound
wrap or falls through) for: follow/streaming forms (`tail -f`,
`watch`, `journalctl -f`, `yes`), early-exit filters (`grep -q`),
in-place filters (`sed -i`), `xargs`, quoted pipes, and anything
ambiguous — ambiguity always falls back to existing behavior.

Tuning (env, in `settings.json`): `EMBO_CAPTURE_MAX_LINES` /
`EMBO_CAPTURE_MAX_BYTES` (inline thresholds, default 10/300),
`EMBO_CAPTURE_PREVIEW_LINES` (default 5), `EMBO_CAPTURE_DIR`
(default `tmp/cap`).

#### context-guard rationale

`context-guard` warns when context window usage exceeds a threshold
(default 85%) and the user starts new development work. See
`context-guard.sh` source for details.

#### Docs-first enforcement (prompt-based, not a hook)

The docs-first principle is enforced through prompt instructions in
the command files, not via a hook. Claude assesses semantic context
before editing code files: documented task -> proceed; research /
POC -> allow with note; undocumented change -> warn and suggest
documenting first.

A PreToolUse hook approach was attempted and abandoned: it broke
Shift+Tab "Allow all edits" and could not reason about semantic
context. See `tasks/010-DOCS-FIRST-GUARD/` for the full history.

### Statusline

The included `statusline.sh` displays live session info in your IDE status bar:

```
~/AI/my-project | feature/my-branch | Sonnet 4.6 | 30K/200K $0.072 | ctx 6% | mem:2m | 09:32:39
```

Shows: tilde-abbreviated path | git branch | model | used/total context | cost | context % | claude-mem freshness | time.

The `mem:` segment shows minutes since the most recent claude-mem
observation, with traffic-light coloring:

- `mem:Xm` **green** when the last observation is ≤10 min old
- `mem:Xm` **yellow** when 11–30 min old
- `mem:Xm` **red** when >30 min old
- `mem:idle` **yellow** — worker reachable but the observation DB is empty
- `mem:DOWN` **red** — worker unreachable or returned unparseable data
- `mem:NOCURL` **red** — `curl` not on PATH

The freshness check is loopback-only (`127.0.0.1:37777`) with a 2 s
timeout, so a hung worker cannot stall the statusline.

#### Prerequisites

- **jq** - required for JSON parsing: `brew install jq` (macOS) / `apt install jq` (Linux)
- **Claude Code** v1.0 or later

#### Setup (after install.sh)

`install.sh` copies the script and optionally patches `settings.json` for you.
If you skipped that step, choose one option:

**Option A - ask Claude (recommended):**

In any Claude Code session, say:
> "use the existing script at ~/.claude/statusline.sh"

Claude's built-in `statusline-setup` agent will detect the file and update
`settings.json` automatically.

> ⚠️ **Claude Code version note:** The `statusline-setup` agent is a built-in
> Claude Code feature as of v1.0. Its behaviour may change in future Claude Code
> releases. If it no longer works as described, fall back to Option B.

**Option B - manual:**

Add to `~/.claude/settings.json`:
```json
{
 "statusLine": {
 "type": "command",
 "command": "~/.claude/statusline.sh"
 }
}
```

Restart Claude Code after editing `settings.json`.

#### Switching scripts

If you have multiple statusline scripts (e.g. `statusline.sh`, `statusline-minimal.sh`),
ask Claude in a session:
> "switch my statusline to ~/.claude/statusline-minimal.sh"

The built-in `statusline-setup` agent handles the `settings.json` update.

---

### Profiles

Profiles let you customize workflow behavior per project or context.
A profile controls code style, testing approach, workflow strictness,
RLM/memory enablement, and MCP requirements.

#### Built-in Profiles

| Profile | Description |
|---------|-------------|
| `quality` | Full workflow - docs-first, TDD, RLM + claude-mem, Context7 required |
| `fast` | Speed mode - test-after, relaxed docs, no corrections |
| `minimal` | Bare bones - no RLM, no memory, no ceremony |

#### Usage

```bash
/embo:profile list # See available profiles
/embo:profile use quality # Activate a profile
/embo:profile off # Deactivate, use defaults
```

Profiles live in `~/.claude/profiles/` (user) and `.claude/profiles/`
(project). Project profiles override user profiles with the same name.

#### Creating Custom Profiles

Copy a built-in profile and edit:
```bash
cp ~/.claude/profiles/quality.yaml ~/.claude/profiles/my-project.yaml
# Edit my-project.yaml to match your needs
```

See `.claude/profiles/quality.yaml` for the full schema.

#### Current Limitations

Profiles are currently **prompt-based** - they instruct `/embo:*` commands to
skip or include steps, but do not modify system infrastructure. This means:

- **claude-mem hooks** continue capturing observations even under `minimal`
 (memory_backend: none)
- **MCP servers** remain connected regardless of profile
- **StatusLine** keeps running if configured

**Future direction:** Make profiles deterministic by toggling hooks and MCP
connections in `settings.json` on `profile use` / `profile off`. This would
give profiles hard control over the runtime environment, not just behavioral
guidance.

---

### Test Subagents

embo ships five specialized test subagents that run in isolated contexts to prevent implementation bias. Invoke them via the `Task` tool from within `/embo:impl`.

#### Agents Overview

| Agent | Model | Purpose | Requires |
|-------|-------|---------|----------|
| `test-backend` | Haiku | Write & run unit/integration tests. Auto-detects pytest, vitest, jest, go test, cargo test, phpunit. | Test framework in project |
| `test-review` | Sonnet | Adversarial gap analysis - finds what tests missed. Does NOT write tests. | Nothing extra |
| `test-e2e-planner` | Sonnet | Explore live app and produce a markdown test plan. | Playwright MCP server |
| `test-e2e-generator` | Sonnet | Convert test plan into executable `.spec.ts` files, verifying selectors live. | Playwright MCP server |
| `test-e2e-healer` | Sonnet | Debug and repair failing Playwright tests. Patches selectors, timing, and data issues. | Playwright MCP server |

#### When to Use Each Agent

- **After backend changes**: run `test-backend` then `test-review`
- **After frontend changes**: run `test-e2e-planner` -> `test-e2e-generator` -> `test-e2e-healer` (if failures)
- **After any change**: run `test-review` last - it finds gaps the other agents missed

#### Playwright MCP Setup (for E2E agents)

Add the Playwright MCP server to your global Claude config (`~/.claude/mcp.json`):

```json
{
 "mcpServers": {
 "playwright-test": {
 "command": "npx",
 "args": ["@playwright/mcp@latest"]
 }
 }
}
```

#### Updating Playwright Forks

The E2E agents (`test-e2e-planner`, `test-e2e-generator`, `test-e2e-healer`) are forks of Playwright's official agents. Each file contains an `UPSTREAM SOURCE` header with the source URL and fetch date.

To update a Playwright fork when Playwright releases a new version:

```bash
# 1. Download the latest upstream agent
curl -o /tmp/playwright-test-planner.agent.md \
 https://raw.githubusercontent.com/microsoft/playwright/main/packages/playwright/src/agents/playwright-test-planner.agent.md

# 2. Diff against your local copy
diff /tmp/playwright-test-planner.agent.md \
 ~/.claude/agents/test-e2e-planner.md

# 3. Apply upstream changes manually, preserving lines marked # CUSTOM
# Lines between <!-- # CUSTOM --> and <!-- # END CUSTOM --> are local additions
# - keep them when merging upstream changes

# 4. Update the fetched date in the UPSTREAM SOURCE header:
# <!-- fetched: YYYY-MM-DD -->

# 5. Copy updated file back to installation
cp .claude/agents/test-e2e-planner.md ~/.claude/agents/
```

Repeat for `test-e2e-generator.md` and `test-e2e-healer.md`.

### Usage Tips

#### Command Tree Overview

All commands live under the `/dev` tree:



#### Recommended Allowlist

`/start` is designed to need minimal shell permissions. To make
session startup fully frictionless (zero permission prompts),
add these to your Claude Code allow-list in settings:

```
python3 ~/.claude/rlm_scripts/rlm_repl.py *
git log *
git diff *
```

On macOS/Linux: Claude Code settings -> Permissions -> Add allowed
commands. On Windows, use the equivalent paths with backslashes.

Once configured, `/embo:start` runs without any
interruptions.

#### Performance Expectations

- **Init**: 30-60s (one-time per repo)
- **Start**: 20-30s (per session, zero prompts with allowlist)
- **Planning**: 30-60s per command
- **Implementation**: +20s overhead per task

**Trade-off**: Slower but significantly higher quality

#### Cost Considerations

embo uses:
- **Opus** for orchestration (main LLM)
- **Haiku** for chunk analysis (sub-LLM)

Estimated cost: ~2-3x vs pure claude-mem, but saves hours in debugging/refactoring.

#### Excluding Vendor Paths

RLM's `init-repo` indexes every tracked file by default, which can
bloat the index on repos that contain large vendor trees (e.g. a
PHP `html/` directory with 17,000 third-party files). Keep the
index small with a committed `.rlmignore`:

```gitignore
# .rlmignore - gitignore-lite syntax
html/**
vendor/**
!vendor/CHANGELOG.md # rescue specific files with leading !
```

`rlm_repl.py init-repo` auto-discovers `.rlmignore` from cwd, walks
up to the repo root, and applies the patterns before indexing. The
summary block shows a per-pattern breakdown so you can confirm the
expected trees were dropped.

One-off CLI alternative (no file needed):

```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py init-repo . \
 --exclude 'html/**' --exclude 'vendor/**'
```

Other flags: `--include 'scripts/**'` turns on allowlist mode
(only matching files kept); `--exclude-from FILE` reads patterns
from an arbitrary file; `--no-rlmignore` suppresses
auto-discovery.

### Configuration

#### Customizing Chunk Size

Edit `~/.claude/rlm_scripts/rlm_repl.py` to change default chunk size:

```python
# Line ~200,000 chars default
python3 ~/.claude/rlm_scripts/rlm_repl.py exec -c "chunk_indices(size=150000)"
```

#### Customizing File Indexing

By default, RLM indexes all git-tracked files. To customize:

1. Add patterns to `.gitignore`
2. Or modify `_discover_git_files()` in `rlm_repl.py`

#### Adding Custom Languages

Edit `LANGUAGE_MAP` in `rlm_repl.py`:

```python
LANGUAGE_MAP = {
 '.your_ext': 'YourLanguage',
 # ... existing mappings
}
```

### Documentation

- **Troubleshooting**: See `TROUBLESHOOTING.md`

### Related Projects

- **[claude_code_RLM](https://github.com/brainqub3/claude_code_RLM)**: Original RLM for text files (our foundation). embo extends it to entire code repositories - adding multi-language indexing, git integration, and a full development workflow - and integrates claude-mem for persistent cross-session memory.
- **[RLM Paper](https://arxiv.org/abs/2512.24601)**: Research paper on Recursive Language Models
- **[Claude Code](https://claude.ai/download)**: Anthropic's official CLI

### Verification

After installation, verify everything works:

```bash
# 1. Check REPL script
python3 ~/.claude/rlm_scripts/rlm_repl.py --help
# Expected: usage: rlm_repl [-h] ...

# 2. Start Claude Code
cd /path/to/test/project
claude

# 3. Initialize repo
/dev:init
# Should index your repo and create .claude/rlm_state/

# 4. Run the health check (recommended post-install verification)
/dev:health
# All three rows should show yes
```

### Getting Help

#### Troubleshooting

See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) for common issues:
- Python not found
- Permission errors
- Commands not appearing
- RLM initialization fails
- Claude-mem not working

#### Support

1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) first
2. Review command documentation in `.claude/commands/dev/`
3. Check Claude Code documentation
4. File an issue (if this is a public repo)

### Updating

To update to the latest version:

```bash
# 1. Pull latest changes
cd ~/embo # Or wherever you cloned
git pull

# 2. Re-run installation steps (or just run install.sh again)
# macOS/Linux:
cp .claude/rlm_scripts/rlm_repl.py ~/.claude/rlm_scripts/
cp .claude/agents/rlm-subcall.md ~/.claude/agents/
cp .claude/agents/test-*.md ~/.claude/agents/
cp -r .claude/commands/dev ~/.claude/commands/
cp .claude/hooks/*.sh ~/.claude/hooks/
cp .claude/statusline.sh ~/.claude/statusline.sh

# Windows: See installation section above
```

### License

MIT License - See LICENSE file for details

**Note**: This project extends [claude_code_RLM](https://github.com/brainqub3/claude_code_RLM) which is also MIT licensed. We maintain the same open-source spirit.

### Docker Development & Testing

A Docker environment is provided for testing commands in isolation.

#### Quick Start

```bash
docker compose build
docker compose run --rm dev-test claude
```

#### Non-Interactive Testing

Run commands via `-p` flag (no MCP plugin support):

```bash
docker compose run --rm dev-test bash -c \
 'claude -p "$(cat /workspace/.claude/commands/dev/health.md)"'
```

#### Interactive Testing via tmux

For full plugin support (claude-mem MCP), use tmux inside the container:

```bash
# Start container in background
docker compose run -d --name rlm-test dev-test bash -c 'sleep infinity'

# Launch Claude in a tmux session
docker exec rlm-test tmux new-session -d -s claude 'claude'

# Send commands
docker exec rlm-test tmux send-keys -t claude '/dev:health' Enter

# Read output
docker exec rlm-test tmux capture-pane -t claude -p -S -50

# Attach interactively (from your terminal)
docker exec -it rlm-test tmux attach -t claude

# Clean up
docker rm -f rlm-test
```

#### What's Included

| Component | Status |
|-----------|--------|
| Auth persistence | Named volume (`claude-auth`) |
| RLM REPL | Pre-installed, auto-indexes |
| All `/dev:*` commands | Copied from repo at startup |
| claude-mem plugin | Auto-installed on first run |
| Chroma vector search | Disabled in container (SQLite search works) |

#### Known Limitations

- **`-p` mode**: MCP plugin tools time out ([known issue](https://github.com/anthropics/claude-code/issues/34131)). Use tmux for full testing.
- **Chroma disabled**: The chroma-mcp spawn storm ([#1063](https://github.com/thedotmack/claude-mem/issues/1063)) causes timeouts in containers. Does not affect native installs.

### Contributing

Contributions welcome! This is a community-driven workflow.

Areas for contribution:
- Additional language support
- Performance optimizations
- New command workflows
- Documentation improvements

### Acknowledgments

**Built on the foundation of [claude_code_RLM](https://github.com/brainqub3/claude_code_RLM)** by [Brainqub3](https://brainqub3.com/).

The original project provided the core RLM implementation for text processing. We extended it for code repositories and integrated claude-mem for historical context.

**Thank you to:**
- **[claude_code_RLM](https://github.com/brainqub3/claude_code_RLM)**: Original RLM implementation and inspiration
- **RLM Paper**: [Recursive Language Models](https://arxiv.org/abs/2512.24601) by Zhang, Kraska, Khattab (MIT CSAIL)
- **Claude Code**: Anthropic's official CLI
- **Claude-Mem**: Semantic memory plugin
