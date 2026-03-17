# Workflow Improvements - Technical Design Document

**Status**: Draft
**PRD**: [2026-03-07-003-WORKFLOW-IMPROVEMENTS-prd.md](
2026-03-07-003-WORKFLOW-IMPROVEMENTS-prd.md)
**Created**: 2026-03-07

## Reference Documents

- **PRD**: `tasks/003-WORKFLOW-IMPROVEMENTS-agent-behavior-and-commands/
  2026-03-07-003-WORKFLOW-IMPROVEMENTS-prd.md`
- **Existing tech-design commands**: `*/plan/tech-design.md` (4 trees)
- **Existing impl commands**: `*/develop/impl.md` (4 trees)
- **Existing start commands**: `*/discover/start.md` (4 trees)

## Overview

All changes are to **markdown command templates** — no Python code,
no plugin code, no new files. The work is inserting rule blocks
into existing `.md` command definitions across 3 active command
trees (rlm-mem, coding, rlm). The `/dev` tree is deprecated and
excluded from this work.

## Component Boundaries

Three independent rule blocks, each inserted into a specific
command template type:

```
┌─────────────────────────────────────────────────┐
│ tech-design.md  ← Story A: Content Quality Rules│
│ impl.md         ← Story B: Scope Verification   │
│ start.md        ← Story C: Deterministic /start  │
└─────────────────────────────────────────────────┘
         × 3 trees (rlm-mem, coding, rlm)
```

Each story is self-contained. No cross-dependencies between A, B,
and C. Implementation order doesn't matter.

## Story A: Tech-Design Content Quality Rules

### What Changes

Insert a `## Content Quality Rules` section into each
tech-design.md, positioned **before** the output template section
(so the agent sees the rules before generating content).

### Rule Block (identical across trees)

```markdown
## Content Quality Rules

Every section must answer: "what would a developer not know
without this?" If a section reads like a user manual, it does
not belong in tech design.

**DO include:**
- Component boundaries and responsibilities
- Data contracts (interfaces/types between components)
- Communication patterns (sequence diagrams)
- Reliability/failure handling patterns
- Performance feasibility estimates
- Rejected alternatives with reasons

**DO NOT include:**
- Setup guides, workflow steps (→ README)
- CLI usage examples, sample output (→ README)
- Algorithm parameter values, thresholds (→ code)
- Installation instructions (→ README)
- User-facing documentation (→ README)
```

### Insertion Points

| Tree | File | Insert Before |
|------|------|---------------|
| rlm-mem | `.claude/commands/rlm-mem/plan/tech-design.md` | Step 6 (Synthesize) — so rules govern output generation |
| coding | `~/.claude/commands/coding/plan/tech-design.md` | "Technical Design Structure" section |
| rlm | `~/.claude/commands/rlm/plan/tech-design.md` | Step 6 equivalent |

### Tree-Specific Adjustments

None needed. The rule block is format-agnostic — it constrains
content, not structure. All three trees generate the same kind of
document.

## Story B: Scope Verification + Critical Evaluation

### What Changes

Insert two sections into each impl.md:

1. **Critical Evaluation of Instructions** — agent must evaluate
   ALL instructions against PRD/tech-design/common sense before
   executing
2. **Scope Verification** — detect out-of-scope instructions and
   auto-update docs before implementing

### Rule Block: Critical Evaluation

```markdown
## Critical Evaluation of Instructions

Do NOT silently execute user instructions. Before implementing
any instruction, evaluate it against:

1. **PRD and tech-design**: Does the instruction align with
   documented requirements and architecture?
2. **Current tasks**: Is this covered by an existing task?
3. **Common sense and feasibility**: Is this technically sound?
   Could the user be mistaken, even in a clear instruction?
4. **Vague instructions**: Never interpret-and-implement
   immediately. Ask for clarification first.

If you spot a problem, raise it before implementing — even if the
instruction seems clear. The user is the boss, but the agent is
responsible for flagging risks.
```

### Rule Block: Scope Verification

```markdown
## Scope Verification (Doc-First Development)

Sessions are idempotent. If a session is restarted, code must
match PRD, tech-design, and tasks. Therefore:

**Before implementing any instruction**, check:
- Does this map to a task in the active task list?
- If YES → proceed normally
- If NO → this is scope drift. Handle it:

**Scope drift handling:**
1. **Clarification-level change** (implementation detail, matter
   of preference, minor adjustment): Just implement it. Updating
   docs would create unnecessary overhead.
2. **New feature or significant change** (new user story, new
   component, architecture change): Auto-update the relevant docs
   BEFORE implementing:
   - Small: add subtask to existing story in tasks file
   - Medium: add new story to tasks file + update tech-design
   - Large: update PRD + tech-design + tasks, ask user to
     confirm the doc changes before proceeding

**Judgment call**: Be smart. The goal is maintaining idempotency
for changes that matter, not creating bureaucratic overhead for
every instruction. If updating docs costs more context/time than
the change itself, skip the update.
```

### Insertion Points

| Tree | File | Insert After |
|------|------|-------------|
| rlm-mem | `.claude/commands/rlm-mem/develop/impl.md` | After "Task Completion Rules" section |
| coding | `~/.claude/commands/coding/develop/impl.md` | After "Task Completion Rules" section |
| rlm | `~/.claude/commands/rlm/develop/impl.md` | After completion protocol section |

### Scope Verification in /plan:check

Additionally, add scope-drift detection to `plan/check.md`.
The `check.md` command currently only exists in rlm-mem. Create
it for coding and rlm trees as well (each tree needs its own
variant).

#### Scope Drift Detection Block

Add to all check.md files:

```markdown
## Scope Drift Detection

If code is found that doesn't match any task in the task list,
flag it as potential scope drift. Report it in the status
summary — do not silently accept untracked changes.
```

#### check.md Variants Per Tree

| Tree | File | Status | Variant |
|------|------|--------|---------|
| rlm-mem | `.claude/commands/rlm-mem/plan/check.md` | Exists | Add scope-drift block. Keep RLM exec for code verification + claude-mem save. |
| coding | `~/.claude/commands/coding/plan/check.md` | **CREATE** | No RLM — use Glob/Grep/Read for code verification. Use claude-mem for save. Task-finding via Glob instead of RLM exec. |
| rlm | `~/.claude/commands/rlm/plan/check.md` | **CREATE** | Use RLM exec for code verification (same as rlm-mem). No claude-mem save. |

#### coding/plan/check.md Design

Adapted from rlm-mem check.md with these changes:
- **Step 1**: Replace RLM exec with `Glob` tool
  (`tasks/**/*-tasks.md`) to find task files
- **Step 3**: Replace RLM exec with `Grep` + `Read` tools to
  verify task implementation against code
- **Step 4**: Keep same marking rules (`[X]`/`[~]`/`[ ]`)
- **Step 4 save**: Keep claude-mem save (coding tree has mem)
- Remove `ai-docs/` update references (coding doesn't use them)
- Add scope-drift detection block

#### rlm/plan/check.md Design

Adapted from rlm-mem check.md with these changes:
- **Step 1**: Keep RLM exec for task file discovery
- **Step 3**: Keep RLM exec for code verification
- **Step 4 save**: Remove claude-mem save (rlm tree has no mem)
- Keep `ai-docs/` update references (rlm tree uses them)
- Add scope-drift detection block

### Tree-Specific Adjustments

- **rlm-mem impl.md**: Currently a thin wrapper ("See
  /rlm:develop:impl for detailed process"). The scope
  verification block goes directly into this file — it's
  rlm-mem-specific behavior, not inherited from /rlm.
- **coding impl.md**: Full standalone file. Insert after existing
  "Task Completion Rules".
- **rlm impl.md**: Full standalone file. Insert after completion
  protocol.

## Story C: Frictionless /start Command

### Problem

The rlm-mem start.md contains 3 inline `python3 ... exec <<'PY'`
blocks that:
- Generate unique code each run (non-deterministic)
- Require user permission approval each time
- Add 3+ permission prompts to every session start

### Solution: Replace Inline Exec with Standard Tools

**Current commands** (rlm-mem start.md Step 3):

| Block | Purpose | Replace With |
|-------|---------|-------------|
| 3a: Find doc files via Python exec | Find README/CLAUDE.md | `Glob` tool: `**/{README,CLAUDE}*.md` |
| 3b: Find task files via Python exec | Find task .md files | `Glob` tool: `tasks/**/*-tasks.md` |
| 3c: Recent changes via Python exec | Git log analysis | `Bash`: `git log --oneline -10` + `git diff --stat HEAD` |

**Replacement approach**: Remove Step 3 entirely. Replace with
instructions to use built-in tools:

```markdown
### Step 3: Codebase Context

**3a. Find project documentation:**
Use the Glob tool to find documentation files:
- Pattern: `**/README*.md`
- Pattern: `**/CLAUDE*.md`
- Read top-level docs for project overview

**3b. Find active task files:**
Use the Glob tool: `tasks/**/*-tasks.md`
Read task files to identify current work.

**3c. Recent git activity:**
Run: `git log --oneline -10`
Run: `git diff --stat HEAD`
```

### Why This Works

- `Glob` and `Read` are built-in Claude Code tools — no shell
  permission needed
- `git log` and `git diff` are standard commands users typically
  allow
- `python3 ~/.claude/rlm_scripts/rlm_repl.py status` (Step 1)
  is the ONE RLM command needed — users can allowlist this single
  command
- Total shell commands: 3 (status, git log, git diff) vs
  previous 4 (status + 3 exec blocks)

### Per-Tree Changes

| Tree | File | Current State | Change |
|------|------|--------------|--------|
| rlm-mem | `.claude/commands/rlm-mem/discover/start.md` | 3 Python exec blocks | Replace Step 3 with Glob + git |
| rlm | `~/.claude/commands/rlm/discover/start.md` | Likely similar exec blocks | Same replacement |
| coding | `~/.claude/commands/coding/discover/start.md` | No exec blocks (claude-mem only) | No change needed — already frictionless |

### Allowlist Guidance

Add to README (installation section):

```markdown
### Recommended Allowlist

To avoid permission prompts during `/start`, add to your Claude
Code settings:
- Allow: `python3 ~/.claude/rlm_scripts/rlm_repl.py *`
- Allow: `git log *`
- Allow: `git diff *`
```

## Files to Modify

### Story A (tech-design quality rules)

| File | Action |
|------|--------|
| `.claude/commands/rlm-mem/plan/tech-design.md` | Insert Content Quality Rules section |
| `~/.claude/commands/coding/plan/tech-design.md` | Insert Content Quality Rules section |
| `~/.claude/commands/rlm/plan/tech-design.md` | Insert Content Quality Rules section |

### Story B (scope verification)

| File | Action |
|------|--------|
| `.claude/commands/rlm-mem/develop/impl.md` | Insert Critical Evaluation + Scope Verification |
| `~/.claude/commands/coding/develop/impl.md` | Insert Critical Evaluation + Scope Verification |
| `~/.claude/commands/rlm/develop/impl.md` | Insert Critical Evaluation + Scope Verification |
| `.claude/commands/rlm-mem/plan/check.md` | Insert Scope Drift Detection |
| `~/.claude/commands/coding/plan/check.md` | **CREATE** — adapted from rlm-mem (Glob/Grep instead of RLM, no ai-docs) + Scope Drift Detection |
| `~/.claude/commands/rlm/plan/check.md` | **CREATE** — adapted from rlm-mem (RLM, no claude-mem) + Scope Drift Detection |

### Story C (frictionless /start)

| File | Action |
|------|--------|
| `.claude/commands/rlm-mem/discover/start.md` | Replace Python exec blocks with Glob + git |
| `~/.claude/commands/rlm/discover/start.md` | Same replacement |
| `README.md` | Add allowlist guidance |

## Excluded: /dev Tree

The `/dev` tree is deprecated (documented in README). It uses
`ai-docs/` files instead of claude-mem and is superseded by
`/coding`. No changes will be made to `/dev` commands.

## Trade-offs

### Considered: Hook-based approach for /start
Instead of rewriting start.md, use Claude Code hooks to
auto-approve known commands.
- **Rejected**: Hooks are user-configured, not shipped with the
  package. We can't guarantee hook setup. Minimizing commands is
  simpler and more reliable.

### Considered: Strict scope-drift blocking
Always require doc updates before any out-of-scope work.
- **Rejected**: Creates unnecessary friction for minor changes.
  The smart judgment approach (clarification = skip, feature =
  update) balances idempotency with developer velocity.

### Considered: Separate "scope check" command
Create a new `/check-scope` command instead of embedding in impl.
- **Rejected**: Adds a step to the workflow. Embedding in impl
  makes it automatic and invisible when in-scope.

## Implementation Constraints

- All changes are markdown edits to command templates
- No changes to `rlm_repl.py` or claude-mem plugin
- Changes to this repo's `.claude/commands/rlm-mem/` must be
  copied to `~/.claude/commands/rlm-mem/` after implementation
  (standard install flow)
- Changes to `coding` and `rlm` trees are made directly in
  `~/.claude/commands/` (they're not in this repo)

## Next Steps

1. Review and approve this design
2. Run `/rlm-mem:plan:tasks` for task breakdown
