# embo Reference

Depth on each feature. For install and first use, see the
[README](../README.md). For common errors, see
[TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

## Prerequisites

### Required

1. **Claude Code** — Anthropic's official CLI (https://claude.ai/download).
2. **Python 3.8–3.12** — for the RLM REPL.
   - macOS: `brew install python@3.12` · Windows: `winget install Python.Python.3.12`
   - Python 3.13+ is not compatible with ChromaDB (used by claude-mem).
3. **claude-mem plugin** — semantic memory (MANDATORY):
   `/plugin marketplace add thedotmack/claude-mem` then
   `/plugin install claude-mem`.
4. **Git repository** — your code must be in a git repo.

### Nice to have

- **Context7 MCP** — library docs lookups (no auth):
  `claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp`
- **Frontend Design plugin** — UI/UX work:
  `/plugin marketplace add anthropics/claude-code` then
  `/plugin install frontend-design@claude-code-plugins`
- **Playwright MCP** — for the E2E test agents (see [Test subagents](#test-subagents)).

## Manual (no-plugin) install

The recommended install is the plugin (see [README](../README.md#install)).
These steps place the same components under `~/.claude/` by hand — use
only if you cannot use the plugin system. Everything the plugin ships
lives under `plugin/`.

### macOS / Linux

```bash
git clone https://github.com/povesma/embo ~/embo
cd ~/embo

# 1. RLM script + the bin/ wrapper that runs it as a plain `rlm_repl`
mkdir -p ~/.claude/rlm_scripts ~/.claude/bin
cp plugin/rlm_scripts/rlm_repl.py ~/.claude/rlm_scripts/
cp plugin/bin/rlm_repl ~/.claude/bin/
chmod +x ~/.claude/rlm_scripts/rlm_repl.py ~/.claude/bin/rlm_repl

# 2. Put ~/.claude/bin on PATH (add to ~/.zshrc or ~/.bashrc):
#    export PATH="$HOME/.claude/bin:$PATH"

# 3. Agents
mkdir -p ~/.claude/agents
cp plugin/agents/*.md ~/.claude/agents/

# 4. Commands — into an `embo/` namespace dir so they invoke as /embo:*
#    (the research/ subdir gives /embo:research:examine etc.)
mkdir -p ~/.claude/commands/embo
cp -r plugin/commands/* ~/.claude/commands/embo/

# 5. Hooks (register them — see "Hook setup" below)
mkdir -p ~/.claude/hooks
cp plugin/hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh

# 6. Status line (optional; requires jq: brew install jq)
cp plugin/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# 7. Verify
python3 --version          # 3.8+
~/.claude/bin/rlm_repl --help    # usage: rlm_repl [-h] ...
```

> Upgrading from a pre-plugin manual install (`~/.claude/commands/dev/`,
> giving `/dev:*`)? See the README's
> [Migrating from a manual install](../README.md#migrating-from-a-manual-install).

### Windows

Required: Python 3.8–3.12, Git (includes bash), Claude Code. Recommended:
jq (statusline), Node.js (claude-mem). Optional: gh.

> **Hooks and statusline require bash.** Git for Windows provides it.
> Without bash, a `.sh` hook registered in `settings.json` silently
> drops prompts (the command list shows but typed text disappears).

```powershell
winget install Python.Python.3.12   # 3.13+ breaks ChromaDB
winget install Git.Git              # includes bash
winget install jqlang.jq
winget install OpenJS.NodeJS.LTS

git clone https://github.com/povesma/embo $env:USERPROFILE\embo
cd $env:USERPROFILE\embo

New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\rlm_scripts","$env:USERPROFILE\.claude\bin","$env:USERPROFILE\.claude\agents","$env:USERPROFILE\.claude\commands\embo","$env:USERPROFILE\.claude\profiles"
Copy-Item plugin\rlm_scripts\rlm_repl.py "$env:USERPROFILE\.claude\rlm_scripts\"
Copy-Item plugin\bin\rlm_repl "$env:USERPROFILE\.claude\bin\"
Copy-Item plugin\agents\*.md "$env:USERPROFILE\.claude\agents\"
Copy-Item plugin\commands\* "$env:USERPROFILE\.claude\commands\embo\" -Recurse
Copy-Item plugin\profiles\*.yaml "$env:USERPROFILE\.claude\profiles\"
if (Get-Command bash -ErrorAction SilentlyContinue) {
  New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\hooks"
  Copy-Item plugin\hooks\*.sh "$env:USERPROFILE\.claude\hooks\"
}
python --version
```

Windows notes: use `python` / `py -3` instead of `python3`; backslash
paths; add `~/.claude/bin` to PATH.

## Hooks

embo ships these hooks. **Plugin install registers them automatically**
(via `hooks/hooks.json`). A **manual install** must register them by
hand (see below). All require `jq`; all fail open (any error exits 0,
never blocks Claude).

| Hook | Event | Purpose | Disable |
|------|-------|---------|---------|
| `context-guard.sh` | `UserPromptSubmit` | Warns when context window is ≥ threshold before new dev work | `CONTEXT_GUARD_THRESHOLD=101` in `settings.json` env |
| `behavioral-reminder.sh` | `UserPromptSubmit` | Injects rule-tag reminders; targeted on criticism, implementation, git requests | `BEHAVIORAL_REMINDER_DISABLED=1` in `settings.json` env |
| `approve-compound.sh` | `PreToolUse` (Bash) | Auto-approves a Bash command when every subcommand (after stripping redirects/env/wrappers, splitting on `&& \|\| ; \| &`) already matches your `permissions.allow` and none matches `deny`. Falls through to the normal prompt on anything unparseable; never overrides `deny` or protected-dir checks | Remove the `PreToolUse` matcher |
| `embo-capture.sh` | (helper, not a registered hook) | Output capture wrapper: approved commands are rewritten through it; full output saved to `tmp/cap/`, small output inline, large output a preview + `[embo-capture]` marker (path + real exit code). Filter-tail pipelines are decomposed (see below) | Remove the `approve-compound.sh` registration |

### Hook setup

**Plugin install:** registration is automatic. For fully prompt-free
operation, add to `permissions.allow` in `~/.claude/settings.json`
(plugins cannot set permissions for you):

```json
"Bash(rlm_repl *)",
"Bash(bash */hooks/embo-capture.sh *)",
"Bash(bash */hooks/fix-hooks.sh *)"
```

Without these you get a one-time "allow?" per command — choose **Always
allow**. (RLM runs as a bare `rlm_repl`, never inline `${...}`, so a
simple rule matches — Claude Code prompts unconditionally for any
command containing shell expansion.)

**Manual install:** also register the hooks:

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

and add `"Bash(~/.claude/hooks/embo-capture.sh *)"` to `permissions.allow`.

**Your allowlist stays yours.** The hook only auto-approves commands
whose every segment already matches *your* rules. `$(...)`, backticks,
heredocs, backgrounded (`&`) and interactive commands (`ssh`, `vim`,
`sudo`, …) are never auto-wrapped; unparseable commands fall back to the
normal prompt.

### Filtered pipelines

A pipeline whose trailing segments are pure filters (`head`, `tail`,
`grep`, `sed`, `awk`, `cut`, `wc`, `sort`, `uniq`, `jq`, `tr`, `column`)
is decomposed: the upstream runs alone with its full unfiltered stdout
saved (stderr separate), then the filter chain runs over the saved copy:

```
[embo-capture] filtered view — full output:
  <path>  (<N> lines, <M> bytes, upstream exit=<EU>, filter exit=<EF>)
```

The wrapper exits with the filter's code (native pipe semantics); the
upstream's true code is in the marker. If the filter missed something,
the full output is already on disk — no re-run. Decomposition is skipped
(runs as a normal whole-compound wrap, or falls through) for: follow
forms (`tail -f`, `watch`, `journalctl -f`, `yes`), early-exit
(`grep -q`), in-place (`sed -i`), `xargs`, quoted pipes, and anything
ambiguous.

Tuning (env in `settings.json`): `EMBO_CAPTURE_MAX_LINES` /
`EMBO_CAPTURE_MAX_BYTES` (inline thresholds, default 10/300),
`EMBO_CAPTURE_PREVIEW_LINES` (default 5), `EMBO_CAPTURE_DIR`
(default `tmp/cap`).

### Docs-first enforcement (prompt-based, not a hook)

Enforced through command-file instructions, not a hook. Claude assesses
context before editing: documented task → proceed; research/POC → allow
with note; undocumented → warn and suggest documenting first. A
PreToolUse hook approach was attempted and abandoned (it broke Shift+Tab
"Allow all edits" and could not reason about semantic context) — see
`tasks/010-DOCS-FIRST-GUARD/`.

## Statusline

`statusline.sh` shows live session info:

```
~/AI/my-project | feature/my-branch | Sonnet 4.6 | 30K/200K $0.072 | ctx 6% | mem:2m | 09:32:39
```

path | git branch | model | used/total context | cost | context % |
claude-mem freshness | time.

The `mem:` segment = minutes since the most recent claude-mem
observation, traffic-light colored: green ≤10 min, yellow 11–30,
red >30; `mem:idle` (worker up, DB empty), `mem:DOWN` (unreachable),
`mem:NOCURL` (no `curl`). Freshness check is loopback-only
(`127.0.0.1:37777`, 2 s timeout) so a hung worker can't stall it.

Plugins cannot set the main statusline, so install it manually. Copy
`plugin/statusline.sh` to `~/.claude/statusline.sh`, then either ask
Claude ("use the existing script at ~/.claude/statusline.sh" — the
built-in `statusline-setup` agent wires it), or add manually:

```json
{ "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }
```

Restart Claude Code after editing `settings.json`.

## Profiles

A profile controls code style, testing approach, workflow strictness,
RLM/memory enablement, and MCP requirements.

| Profile | Description |
|---------|-------------|
| `quality` | Full workflow — docs-first, TDD, RLM + claude-mem, Context7 required |
| `fast` | Speed mode — test-after, relaxed docs, no corrections |
| `minimal` | Bare bones — no RLM, no memory, no ceremony |
| `research` | Evidence-driven research profile |

```text
/embo:profile list           # available profiles
/embo:profile use quality    # activate
/embo:profile off            # defaults
```

Profiles live in `~/.claude/profiles/` (user) and `.claude/profiles/`
(project); project overrides user by name. Create a custom one by
copying a built-in (`plugin/profiles/quality.yaml` is the schema).

**Current limitation:** profiles are prompt-based — they instruct
`/embo:*` commands to skip/include steps but do not toggle hooks or MCP
connections. So claude-mem hooks still capture under `minimal`, MCP
servers stay connected, and the statusline keeps running.

## Test subagents

Five specialized test agents run in isolated contexts (to prevent
implementation bias), invoked via the `Task` tool from `/embo:impl`.
(They are documented here but ship separately — see task 033.)

| Agent | Model | Purpose | Requires |
|-------|-------|---------|----------|
| `test-backend` | Haiku | Write & run unit/integration tests; auto-detects pytest, vitest, jest, go test, cargo test, phpunit | Test framework in project |
| `test-review` | Sonnet | Adversarial gap analysis — finds what tests missed; writes nothing | — |
| `test-e2e-planner` | Sonnet | Explore live app, produce a markdown test plan | Playwright MCP |
| `test-e2e-generator` | Sonnet | Convert plan into `.spec.ts`, verifying selectors live | Playwright MCP |
| `test-e2e-healer` | Sonnet | Debug & repair failing Playwright tests | Playwright MCP |

Order: after backend changes, `test-backend` → `test-review`; after
frontend, `test-e2e-planner` → `test-e2e-generator` → `test-e2e-healer`;
run `test-review` last — it finds gaps the others missed.

**Playwright MCP** (for E2E agents) — add to `~/.claude/mcp.json`:

```json
{ "mcpServers": { "playwright-test": {
  "command": "npx", "args": ["@playwright/mcp@latest"] } } }
```

**Updating the Playwright forks.** The three E2E agents are forks of
Playwright's official agents; each carries an `UPSTREAM SOURCE` header
with source URL + fetch date. To update: download the upstream agent,
diff against your copy, re-apply changes preserving lines between
`<!-- # CUSTOM -->` / `<!-- # END CUSTOM -->`, bump the `fetched:` date,
and copy back.

## RLM usage

### Excluding vendor paths

`init-repo` indexes every tracked file by default, which bloats the
index on repos with large vendor trees (e.g. a PHP `html/` with 17,000
third-party files). Keep it small with a committed `.rlmignore`:

```gitignore
# .rlmignore — gitignore-lite syntax
html/**
vendor/**
!vendor/CHANGELOG.md   # rescue specific files with leading !
```

`rlm_repl init-repo` auto-discovers `.rlmignore` from cwd up to the repo
root and prints a per-pattern breakdown. One-off alternative:

```bash
rlm_repl init-repo . --exclude 'html/**' --exclude 'vendor/**'
```

Other flags: `--include 'scripts/**'` (allowlist mode — only matching
files kept), `--exclude-from FILE`, `--no-rlmignore`.

### Chunk size & languages

```bash
rlm_repl exec -c "chunk_indices(size=150000)"   # ~200,000 chars default
```

To add languages, edit `LANGUAGE_MAP` in `rlm_repl.py`. To change which
files are indexed, adjust `.gitignore` or `_discover_git_files()`.

## Performance & cost

- **Init**: 30–60s (one-time per repo) · **Start**: 20–30s/session ·
  **Planning**: 30–60s/command · **Implementation**: +20s/task overhead.
- Trade-off: slower but higher quality.
- Models: Opus (orchestration), Haiku (chunk analysis). ~2–3× the cost
  of pure claude-mem, but saves hours of debugging/refactoring.

## Docker development & testing

> **Not re-verified post-plugin.** The flow below was updated for the
> plugin layout but not re-run end-to-end in a container;
> `docker-compose.yml` may still reference the old `cp` setup. Treat as
> a starting point.

With the repo mounted at `/workspace`, load the plugin from its dir:

```bash
docker compose build
docker compose run --rm dev-test claude --plugin-dir /workspace/plugin
```

Non-interactive (no MCP tools — claude-mem unavailable, memory steps
degrade):

```bash
docker compose run --rm dev-test bash -c \
 'claude --plugin-dir /workspace/plugin -p "$(cat /workspace/plugin/commands/health.md)"'
```

Interactive via tmux (full plugin support; install both plugins):

```bash
docker compose run -d --name embo-test dev-test bash -c 'sleep infinity'
docker exec embo-test tmux new-session -d -s claude 'claude'
docker exec embo-test tmux send-keys -t claude '/plugin marketplace add /workspace' Enter
docker exec embo-test tmux send-keys -t claude '/plugin install embo@embo' Enter
docker exec embo-test tmux send-keys -t claude '/embo:health' Enter
docker exec embo-test tmux capture-pane -t claude -p -S -50
docker rm -f embo-test
```

Limitations: `-p` mode times out on MCP tools
([known issue](https://github.com/anthropics/claude-code/issues/34131));
Chroma vector search is disabled in containers (SQLite search works) due
to the chroma-mcp spawn storm
([#1063](https://github.com/thedotmack/claude-mem/issues/1063)) — neither
affects native installs.

## Related projects

- **[claude_code_RLM](https://github.com/brainqub3/claude_code_RLM)** —
  original RLM for text files (embo's foundation); embo extends it to
  code repos (multi-language indexing, git integration, full workflow)
  and adds claude-mem for cross-session memory.
- **[RLM Paper](https://arxiv.org/abs/2512.24601)** — Recursive Language
  Models (Zhang, Kraska, Khattab, MIT CSAIL).
