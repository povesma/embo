# 012-PROFILES: Workflow Configuration Profiles - Technical Design

**Status**: Draft
**PRD**: [2026-03-22-012-PROFILES-prd.md](2026-03-22-012-PROFILES-prd.md)
**Created**: 2026-03-22

---

## Overview

A profile is a YAML file that command prompts read at runtime via
the `Read` tool. Command prompts contain conditional blocks:
"if profile says X, do X; otherwise use default." No preprocessing,
no build step, no code execution.

Three new components:
1. **Profile YAML schema** — data contract
2. **`/dev:profile` command** — activate/list profiles
3. **Command file modifications** — conditional sections that read
   the active profile

---

## Component 1: Profile YAML Schema

### File location

```
~/.claude/profiles/<name>.yaml       # user scope
.claude/profiles/<name>.yaml         # project scope
~/.claude/active-profile.yaml        # active (copy, not symlink)
```

Copy not symlink — avoids platform issues (Windows) and ensures
the active profile is self-contained.

### Schema

```yaml
name: quality
description: Full workflow — docs-first, TDD, RLM + claude-mem

rules:
  code_style:
    line_length: 120
    comments: minimal          # minimal | allowed | none
    naming_convention: handler # handler | usecase | none
  testing:
    approach: tdd              # tdd | test-after | none
    scope: [unit, integration] # unit, integration, e2e
    subagents:                 # empty array = no subagents
      - test-backend
      - test-review
  workflow:
    docs_first: strict         # strict | relaxed | off
    correction_capture: true
    scope_drift: warn          # warn | block | off

tools:
  rlm: true
  memory_backend: claude-mem   # claude-mem | none

mcps:
  required: []                 # fail /dev:health if missing
  optional: []                 # warn in /dev:health if missing
```

### Defaults (no profile active)

When `~/.claude/active-profile.yaml` does not exist, commands use
their current hardcoded behavior — equivalent to `quality.yaml`.
This ensures zero regression for existing users.

### Resolution order

When `/dev:profile use <name>` is called:
1. Check `.claude/profiles/<name>.yaml` (project scope)
2. Check `~/.claude/profiles/<name>.yaml` (user scope)
3. First match wins (project > user = most-specific-wins)
4. Copy to `~/.claude/active-profile.yaml`

---

## Component 2: `/dev:profile` Command

### File: `.claude/commands/dev/profile.md`

A new command file with two modes determined by the argument:

**`/dev:profile use <name>`**:
1. Search for `<name>.yaml` in project then user profiles dirs
2. Read and validate the YAML (check `name` field exists)
3. Copy to `~/.claude/active-profile.yaml`
4. Output confirmation with key settings summary

**`/dev:profile list`**:
1. List `~/.claude/profiles/*.yaml` (user)
2. List `.claude/profiles/*.yaml` (project, if exists)
3. Read `name` and `description` from each
4. Read `~/.claude/active-profile.yaml` to mark active
5. Output table: name, description, scope, active marker

**`/dev:profile off`**:
1. Remove `~/.claude/active-profile.yaml`
2. Confirm: "Profile deactivated. Commands using defaults."

### Error handling

- Profile not found → list available profiles with paths
- YAML parse error → show error, don't activate
- No profiles directory → suggest running `install.sh`

---

## Component 3: Command File Modifications

### How commands read the profile

Each command that needs profile data adds a block at the top of
its Process section:

```markdown
### 0. Load Profile (if active)

Read `~/.claude/active-profile.yaml` if it exists. If the file
does not exist, use these defaults:
- code_style: { line_length: 120, comments: minimal,
  naming_convention: handler }
- testing: { approach: tdd, scope: [unit, integration],
  subagents: [test-backend, test-review] }
- workflow: { docs_first: strict, correction_capture: true,
  scope_drift: warn }
- tools: { rlm: true, memory_backend: claude-mem }

Apply the profile values to all sections below. When this prompt
says "per profile" or "if profile says", use the loaded values.
```

### Modified files and sections

**`impl.md`** — heaviest changes:

| Section | Current (hardcoded) | Profile key |
|---------|-------------------|-------------|
| Code Style (line 248) | 120 chars | `rules.code_style.line_length` |
| Code Style (line 254) | "Avoid comments" | `rules.code_style.comments` |
| Code Style (line 257) | "handler" | `rules.code_style.naming_convention` |
| Testing (line 260) | TDD | `rules.testing.approach` |
| Testing (line 263) | External only | `rules.testing.scope` |
| Correction Capture (line 56) | Always on | `rules.workflow.correction_capture` |
| Docs-first (line 52) | Strict | `rules.workflow.docs_first` |
| RLM steps (lines 140-180) | Always run | `tools.rlm` |
| claude-mem calls (lines 129-135) | Always call | `tools.memory_backend` |
| Subagent invocation | test-backend + test-review | `rules.testing.subagents` |

Each section becomes conditional:

```markdown
## Code Style

**Per active profile** (`rules.code_style`):
- Line length: {line_length} characters (default: 120)
- Comments: {comments} (default: minimal)
- Naming: {naming_convention} (default: handler)

If `comments` is `minimal`: avoid comments, write
self-documenting code. If `allowed`: add comments where helpful.
If `none`: no comment policy enforced.
```

**`start.md`** — lighter changes:
- Step 2 (RLM status check): skip if `tools.rlm: false`
- Step 3 (claude-mem queries): skip if `tools.memory_backend: none`
- Docs-first principle section: use `rules.workflow.docs_first`

**`health.md`** — new MCP checks:
- After existing checks, read active profile's `mcps.required`
- For each required MCP, attempt a basic tool call
- Report pass/fail per MCP

**`init.md`** — minimal:
- Skip RLM init if `tools.rlm: false`
- Skip claude-mem bootstrap if `tools.memory_backend: none`

**`prd.md`, `tech-design.md`, `tasks.md`** — minimal:
- Skip claude-mem search steps if `tools.memory_backend: none`
- Skip RLM analysis steps if `tools.rlm: false`

---

## Component 4: Built-in Profiles

### `quality.yaml`

Current hardcoded defaults. Full workflow.

```yaml
name: quality
description: Full workflow — docs-first, TDD, RLM + claude-mem

rules:
  code_style:
    line_length: 120
    comments: minimal
    naming_convention: handler
  testing:
    approach: tdd
    scope: [unit, integration]
    subagents: [test-backend, test-review]
  workflow:
    docs_first: strict
    correction_capture: true
    scope_drift: warn

tools:
  rlm: true
  memory_backend: claude-mem

mcps:
  required: [context7]
  optional: [playwright]
```

### `fast.yaml`

Speed over ceremony. No TDD, relaxed docs-first.

```yaml
name: fast
description: Speed mode — test-after, relaxed docs, no corrections

rules:
  code_style:
    line_length: 120
    comments: allowed
    naming_convention: none
  testing:
    approach: test-after
    scope: [unit]
    subagents: []
  workflow:
    docs_first: relaxed
    correction_capture: false
    scope_drift: off

tools:
  rlm: true
  memory_backend: claude-mem

mcps:
  required: []
  optional: [context7]
```

### `minimal.yaml`

Bare bones. No RLM, no memory, no ceremony.

```yaml
name: minimal
description: Bare bones — no RLM, no memory, no ceremony

rules:
  code_style:
    line_length: 120
    comments: allowed
    naming_convention: none
  testing:
    approach: none
    scope: []
    subagents: []
  workflow:
    docs_first: off
    correction_capture: false
    scope_drift: off

tools:
  rlm: false
  memory_backend: none

mcps:
  required: []
  optional: []
```

---

## Component 5: install.sh Changes

Add after the commands/dev sync block:

```bash
# profiles
mkdir -p "$TARGET/profiles"
cp "$REPO_DIR/.claude/profiles/"*.yaml "$TARGET/profiles/"
echo "  profiles: $(ls "$REPO_DIR/.claude/profiles/"*.yaml |
  wc -l | tr -d ' ') files"
```

---

## Component 6: Docker Test Environment

### Dockerfile

```dockerfile
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl git python3 jq nodejs npm && \
    npm install -g @anthropic-ai/claude-code

# Auth volume mount point
VOLUME /root/.claude

WORKDIR /workspace
COPY . /workspace/

RUN bash install.sh

CMD ["claude"]
```

### Usage

```bash
# Build
docker build -t dev-test .

# Run (mount auth for persistence)
docker run -it \
  -v claude-auth:/root/.claude \
  -v $(pwd):/workspace \
  dev-test

# First run: authenticate manually inside container
# Subsequent runs: auth persists via named volume
```

The named volume `claude-auth` persists `/root/.claude` across
container restarts, keeping the subscription auth alive.

**Limitation**: MCP servers that require local sockets (e.g.
Playwright) won't work inside the container. Profile testing
for MCP-dependent features requires host-based testing.

---

## Files to Create

| File | Purpose |
|------|---------|
| `.claude/commands/dev/profile.md` | Profile command |
| `.claude/profiles/quality.yaml` | Built-in profile |
| `.claude/profiles/fast.yaml` | Built-in profile |
| `.claude/profiles/minimal.yaml` | Built-in profile |
| `Dockerfile` | Test environment |

## Files to Modify

| File | Change |
|------|--------|
| `.claude/commands/dev/impl.md` | Add profile load step; make Code Style, Testing, RLM, claude-mem sections conditional |
| `.claude/commands/dev/start.md` | Conditional RLM/claude-mem steps |
| `.claude/commands/dev/health.md` | Add MCP validation from profile |
| `.claude/commands/dev/init.md` | Conditional RLM/claude-mem init |
| `.claude/commands/dev/prd.md` | Conditional RLM/claude-mem steps |
| `.claude/commands/dev/tech-design.md` | Conditional RLM/claude-mem steps |
| `.claude/commands/dev/tasks.md` | Conditional RLM/claude-mem steps |
| `install.sh` | Add profiles copy block |
| `README.md` | Add profiles documentation |
| `CLAUDE.md` | Add profiles to file structure |

---

## Trade-offs

### Runtime Read vs Build-time Injection

**Chosen: Runtime Read.** Command prompt tells Claude to read
`~/.claude/active-profile.yaml` at the start of each command.

- Pro: No build step, no preprocessing, works immediately
- Pro: Profile changes take effect on next command invocation
- Con: LLM must parse YAML and apply it — best-effort
- Con: Adds ~30 lines of YAML to context per command

Rejected: Build-time injection (template engine replaces
placeholders in `.md` files). Adds complexity, requires a build
step, and makes debugging harder — the `.md` files wouldn't match
what Claude actually sees.

### Copy vs Symlink for active profile

**Chosen: Copy.** `cp` the profile to `~/.claude/active-profile.yaml`.

- Pro: Works on all platforms (Windows has symlink issues)
- Pro: Active profile is self-contained, readable
- Con: Editing the source profile doesn't auto-update active
  (must re-run `/dev:profile use`)

### Single active profile vs per-project active

**Chosen: Single global active.** One `active-profile.yaml` at
user scope.

- Pro: Simple — one place to check
- Con: Switching projects requires re-activating profile
- V2 can add per-project active profile via `.claude/active-profile.yaml`

---

**Next Steps:**
1. Review and approve this design
2. Run `/dev:tasks` for task breakdown
