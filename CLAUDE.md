# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

embo is a **Claude Code plugin** that combines:
- **RLM**: Analyzes large codebases via persistent Python REPL
- **Claude-Mem** (MANDATORY): Semantic memory of past decisions
- **17 Commands**: Complete development workflow (`/embo:*`, incl.
  `/embo:research:examine` / `/embo:research:verify` and the
  experimental `/embo:visual-impl` design-to-code loop)
- **Test Subagents**: Isolated testing agents invoked via Task tool
  (shipped separately — see task 033)

Users install via `/plugin install embo@embo` (a manual `~/.claude/`
install is documented as a fallback). All shipped components live
under `plugin/`; the manifests are `.claude-plugin/marketplace.json`
(repo root) and `plugin/.claude-plugin/plugin.json`.

## Architecture

### Three Components

1. **RLM REPL** (`.claude/rlm_scripts/rlm_repl.py`)
   - Pure Python stdlib, no dependencies
   - Indexes repositories: `python3 rlm_repl.py init-repo .`
   - Stores state in `.claude/rlm_state/state.pkl`
   - Detects 50+ languages via `LANGUAGE_MAP` (line 60-130)

2. **RLM Subagent** (`.claude/agents/rlm-subcall.md`)
   - Haiku-powered chunk analysis
   - Returns JSON with patterns/dependencies/symbols

3. **Test Subagents** (`.claude/agents/test-*.md`)
   - Five specialized agents invoked via `Task` tool during `/impl`
   - **test-backend** (Haiku): writes & runs unit/integration tests, auto-detects
     pytest/vitest/jest/go/cargo/phpunit
   - **test-review** (Sonnet): adversarial gap analysis — finds untested state
     transitions, auth boundaries, error paths. Reads code only, writes nothing.
   - **test-e2e-planner** (Sonnet): explores live app via Playwright MCP, produces
     markdown test plan. Forked from `microsoft/playwright`.
   - **test-e2e-generator** (Sonnet): converts plan to `.spec.ts` files, verifies
     selectors live. Forked from `microsoft/playwright`.
   - **test-e2e-healer** (Sonnet): debugs failing tests, patches selectors/timing/
     data, marks environmental blockers with `test.fixme()`. Forked from
     `microsoft/playwright`.
   - All agents use YAML input/output contracts and degrade gracefully without
     claude-mem or RLM

4. **Commands** (`plugin/commands/`)
   - 17 commands: 15 flat (`/embo:<name>`) + `research/` subdir
     (`/embo:research:examine`, `/embo:research:verify`)
   - Each integrates RLM + claude-mem via Bash and MCP tools
   - Commands invoke RLM as a bare `rlm_repl` (the `plugin/bin/`
     wrapper) — never inline `${CLAUDE_PLUGIN_ROOT}/...rlm_repl.py`,
     which Claude Code flags for an approval prompt

### Installation Flow

```text
# Inside Claude Code (recommended):
/plugin marketplace add povesma/embo
/plugin install embo@embo
```

Manual (no-plugin) fallback copies `plugin/*` into `~/.claude/` —
see README §macOS / Linux Installation.

## Claude-Mem Integration (MANDATORY)

Commands use MCP tools (requires plugin):
- `mcp__plugin_claude-mem_mcp-search__search`
- `mcp__plugin_claude-mem_mcp-search__save_memory`

Commands should **fail with clear error** if claude-mem unavailable.

### Runtime: stay on worker tools (do not migrate to server-beta yet)

These commands target the **worker** runtime (`CLAUDE_MEM_RUNTIME=worker`)
and use `search` / `get_observations` / `save_memory`. As of the
2026-06-07 plugin update, claude-mem also exposes a `server-beta`
runtime with a REST backend (`/v1/*`) and a new tool family
(`observation_search`, `observation_context`, `observation_add`,
`memory_*`). Those tools are **beta and refuse to run under the worker
runtime**, so the commands intentionally stay on the worker tools to
avoid building against a moving target.

**Migration trigger:** when server-beta leaves beta (GA), open a task to
switch the commands. Tool mapping for that migration:
`search` → `observation_search`, the `search` + `get_observations`
two-step → `observation_context` (single call), `save_memory` →
`observation_add` / `memory_add`. The statusline (`cmem_segment` in
`.claude/statusline.sh`) also moves from `/api/observations` to the
`/v1/*` endpoint. Server-beta enables centralized, `projectId`-scoped
memory shared across developers and agents.

## Development

### Test RLM REPL
```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py --help
python3 ~/.claude/rlm_scripts/rlm_repl.py init-repo .
python3 ~/.claude/rlm_scripts/rlm_repl.py status
```

### Modify Commands
Edit `plugin/commands/<name>.md` directly. With the plugin installed
from a local marketplace, run `/plugin marketplace update embo` +
`/reload-plugins` to pick up changes.

### Add Language Support
Edit `rlm_repl.py` → `LANGUAGE_MAP` dict.

## File Structure

```
.claude-plugin/marketplace.json  # marketplace entry, source: ./plugin
plugin/                          # THE PLUGIN ROOT (${CLAUDE_PLUGIN_ROOT})
├── .claude-plugin/plugin.json   # manifest (name:"embo")
├── bin/rlm_repl                 # PATH wrapper → runs rlm_scripts/rlm_repl.py
├── agents/
│   ├── rlm-subcall.md           # RLM chunk analysis subagent (Haiku)
│   ├── examine-advisor.md       # /embo:research:examine agent
│   ├── approach-validator.md    # /embo:research:verify agent
│   └── visual-qa-reviewer.md    # /embo:visual-impl judge (experimental)
├── commands/                    # 17 commands; research/ → nested ns
│   ├── visual-impl.md           # design-to-code loop (experimental)
│   └── research/                # examine.md, verify.md
├── profiles/                    # quality.yaml, fast.yaml, minimal.yaml
├── hooks/
│   ├── hooks.json               # registers the 3 event handlers
│   ├── context-guard.sh         # Context window warning hook
│   ├── behavioral-reminder.sh   # Behavioral rule reminder hook
│   ├── approve-compound.sh      # Auto-approve compound Bash + rewrite
│   ├── embo-capture.sh          # Output capture wrapper (helper, not
│   │                              # a registered hook)
│   └── fix-hooks.sh             # migration doctor (+ tests for each)
├── rlm_scripts/rlm_repl.py      # REPL (.rlmignore + --exclude/...)
└── statusline.sh                # Status line (manual install only)

# repo-level (NOT shipped in the plugin):
.claude/                         # the repo's OWN dogfood config + rlm_state
commands-archive/dev/            # deprecated tree (reference only)
README.md  TROUBLESHOOTING.md    # user docs
```

Note: the 5 test subagents (`test-backend`, `test-review`,
`test-e2e-*`) are documented but ship separately — task 033.

## Documentation Rules

- **Manual steps required alongside automation**: Any install script or automation must be accompanied by equivalent manual steps in the docs. If the script fails, the user must be able to complete the task by hand.

## Key Constraints

- **No dependencies**: REPL uses stdlib only
- **Claude-mem required**: Not optional
- **Local state**: `.claude/rlm_state/` never committed (in `.gitignore`)
- **Quality over speed**: Commands intentionally thorough
- **CLAUDE.md is NOT a deliverable**: This file is for developing this
  repo only. Users have their own CLAUDE.md. All behavioral rules for
  the workflow must live in the command files we ship
  (`plugin/commands/`), not here.

## Emoji Usage

Minimize emoji in all files. Only use them when they meaningfully aid
comprehension (e.g., status indicators in output, warning symbols).
Never add emoji to section headings, commit messages, or prose unless
the surrounding context already uses them extensively and consistency
requires it.

## Commit Messages

Conventional style takes priority. Goal: enough to find the right
commit later — what and (if non-obvious) why. Add a body only when
the diff doesn't answer *why*; never restate the diff. A one-line
commit is fine when the subject is enough.

## Safety Rules

**STRICTLY FORBIDDEN** to run any command that can lead to loss of work or
data without first explaining the intent and getting explicit user approval.
This includes but is not limited to:

- `git reset` (any form)
- `git stash` / `git stash pop` / `git stash drop`
- `git clean`
- `git rm`
- `git branch -D` (force delete)
- `git push --force`
- `rm` / `rm -rf`
- Any command with flags like `-f`, `--force`, `--hard` that bypass safety checks

**Protocol**: State what you intend to do and why, then wait for the user to
explicitly approve before running the command.

## Task Marking Convention

- **`[X]`** — done: ONLY when tested/verified AND passing, or explicitly confirmed by user
- **`[~]`** — coded, pending testing: implementation written but not yet verified
- **`[ ]`** — not started
- Never mark `[X]` based on writing code alone. Assume it doesn't work until proven.

## Related

Extends [claude_code_RLM](https://github.com/brainqub3/claude_code_RLM) for code repos + claude-mem. Based on [RLM paper](https://arxiv.org/abs/2512.24601) (MIT CSAIL).
