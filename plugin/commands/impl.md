---
description: >
  Implement task-list subtasks one at a time with RLM pattern discovery
  and claude-mem context, enforcing docs-first, TDD, and per-subtask
  evidence before marking work done.
---

# Task Implementation with embo Hybrid

Implement tasks with pattern discovery (RLM) + historical context
(claude-mem).

<!-- RULE:CHALLENGE-INSTRUCTION -->
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

If you spot a problem, raise it before implementing — even if
the instruction seems clear. The user is the boss, but the agent
is responsible for flagging risks.

When the user challenges a decision with a question ("Is this right?",
"Why this approach?"), defend the position if it's correct — explain
the reasoning, don't cave. See full rule in `start.md` §Session
Behavioral Rules.

<!-- RULE:DOCS-FIRST -->
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

**Judgment call**: The clarification-level exception applies only to
implementation details within an existing task subtask — such as
choosing between two equivalent approaches, adjusting whitespace,
or picking a variable name. If the change adds new behavior,
modifies an API, or touches a file not listed in the task's
"Relevant Files" section, it requires a doc update first.

**Docs-first enforcement** (per profile `rules.workflow.docs_first`):
- If `strict`: assess context before editing any code file —
  documented task → proceed; research/POC → allow with note;
  undocumented → warn, suggest documenting first
- If `relaxed`: warn on undocumented changes but proceed
- If `off`: no docs-first checks

**Docs-after: keep documentation in sync.** After any code change
that diverges from or extends what's documented:
- Update the task list (mark done, add new subtasks)
- Update tech-design if architecture/approach changed
- Update PRD if requirements shifted
- Update README.md if user-facing behavior changed (new commands,
  new install steps, changed workflow)
- Update CLAUDE.md if file structure or project constraints changed
Do this immediately — not "later" or "in a follow-up." Stale docs
are worse than no docs.

## Correction Capture

**Skip this section entirely if profile
`rules.workflow.correction_capture` is `false`.**

When the user corrects how you work — redirecting your approach,
fixing your code style, telling you to verify externally, or
suggesting a workflow improvement — silently save a correction
observation to claude-mem. Do NOT announce that you are saving it.
Do NOT interrupt the flow.

**What to capture** (behavioral corrections):
- "Use Context7 / check the web / read the docs" → category: verification
- "Don't add comments / wrong naming / simplify" → category: code-style
- "Skip this step / add a check for X" → category: workflow
- "That's over-engineered / use a simpler approach" → category: approach
- "We should always do X before Y" → category: process

**What NOT to capture** (scope/design changes):
- "Let's do feature B instead" — scope change
- "Make that field optional" — design decision
- "Skip task 3" — task prioritization

Corrections are captured automatically by the claude-mem PostToolUse
hook — no explicit save call needed. Just continue with the corrected
approach. No acknowledgment required.

## Task Completion Rules

Verification methods (`code-only`, `auto-test`, `manual-run-claude`,
`manual-run-user`, `docker`, `e2e`, `observation`) and the `live` vs
`simulated` distinction are defined in the canonical taxonomy in
`/embo:test-plan`.

- **`[X]` (done)**: ONLY when live-tested AND the intended
  functionality demonstrably works — not just "tests pass formally."
  A passing test that doesn't exercise the real behaviour is not
  sufficient. Always seek a live test (actual command run, real
  output, real side-effect). Simulation or mocking is acceptable
  only when live testing is: costly, destructive, or impossible —
  and even then, at least one live test must be done before `[X]`
  is marked. When simulation is used, record it explicitly in the
  evidence note. Alternatively: explicitly confirmed by user.
- **`[~]` (coded, pending testing)**: implementation is written
  but evidence not yet obtainable (state the reason inline)
- **`[ ]` (not started)**: no work done
- Tasks that are tests themselves may be marked `[X]` once the
  test is run and the result is known, even if it reveals bugs
- **FORBIDDEN**: marking `[X]` on a non-`code-only` task without
  showing evidence first. "It looks right" is not evidence.
  "I wrote it" is not evidence.

**Evidence gate by `[verify:]` type:**

- `[verify: code-only]` — mark `[X]` immediately, no evidence needed
- `[verify: auto-test]` — run the test suite; show output summary
- `[verify: manual-run-claude]` — run the command; show actual output
- `[verify: manual-run-user]` — ask user to confirm; record their reply
- `[verify: docker]` — run inside container; show output; if Docker
  unavailable mark `[~]` with reason
- `[verify: e2e]` — run via Playwright/test subagent; show result
- `[verify: observation]` — run claude-mem search; show result snippet

**Evidence note format** (append as indented line below the task):
```
    → <summary> [live] (<date>)
    → <summary> [simulated: <reason>] (<date>)
```

**Compact summary rule**: `<summary>` must be one clause stating the
outcome or decision. Add a second clause only if something unexpected
occurred. Omit: how the work was done, intermediate states that were
superseded (TDD red phases, bug-found states fixed before [X] was
marked), and tool invocation details. The evidence line is a permanent
record, not a session log.

Bad:  `→ wrote tests first (TDD red: 3 failed), then implemented,
      then ran again: 3 passed, 0 failed [live] (2026-07-02)`
Good: `→ 3 passed, 0 failed [live] (2026-07-02)`

Bad:  `→ found a naming conflict in foo.py, renamed to bar.py,
      re-ran, now all pass [live] (2026-07-02)`
Good: `→ renamed foo→bar (naming conflict); 5 passed, 0 failed
      [live] (2026-07-02)`

Examples:
```
- [X] 2.1 Add correction capture [verify: auto-test]
    → pytest: 3 passed, 0 failed [live] (2026-03-26)
- [X] 3.1 Update config file [verify: code-only]
- [~] 4.2 Verify Docker integration [verify: docker]
    → Docker not running in session [simulated: n/a]
```

### Evidence Note Sanitization

Evidence notes follow the parent doc's sanitization rule. Defer to CLAUDE.md "Documentation Sanitization" if defined; otherwise describe
the *shape* of the observation, not the literal output. No working-state exception — sanitize at write time.
- Bad:  `→ curl returned 198.51.100.42 from gw.corp.example.com`
- Good: `→ curl returned the expected egress IP for the corp tunnel`

<!-- RULE:ONE-SUBTASK -->
## Task Implementation Protocol

- **Default: one sub-task at a time.** Do **NOT** start the next
  sub-task without the user's go-ahead (see continuation menu below).
- **Completion protocol:**
  1. When you finish a **sub-task**, update its marker immediately,
     applying the **Task Completion Rules** above (marker semantics
     and the evidence gate for its `[verify:]` type).
  2. If **all** subtasks underneath a parent task are now `[X]`,
     also mark the **parent task** as completed. A parent with any
     `[~]` stays open.
- **Continuation menu:** after completing a sub-task, ask via
  `AskUserQuestion` how to continue:
  1. **Next sub-task only** — implement one more sub-task, then
     ask again (default)
  2. **All sub-tasks of current story** — implement the remaining
     sub-tasks of the current parent task, then ask again
  3. **All tasks until input required** — implement story after
     story, stopping only when user contribution is genuinely
     required (a `manual-run-user` verification, an approval gate,
     a destructive/shared-state action, or a real fork between
     mutually exclusive paths)
  The selected mode stays active until it completes or the user
  interrupts; re-ask only at mode boundaries (story end for mode 2).
  In modes 2 and 3, lean hard on DECIDE-OR-ASK: decide every
  recoverable choice yourself and record it in evidence notes —
  do not interrupt the run with questions a later review can fix.
  All other rules stay fully in force in every mode: evidence gates
  per `[verify:]` type, TDD order, docs-first, and the safety rules
  (a mode-3 run NEVER authorizes destructive or shared-state
  actions without their own approval).
- **Delivering to the repo:** when the run pauses and there is work to
  deliver, offer two paths — rapid is the default:
  1. **Rapid** (`/embo:git deliver`) — one commit of the needed files,
     one plan approval, straight to the branch. The default for most
     changes.
  2. **Full commit** (`/embo:git commit`/`pr`) — split into commits with
     polished messages. For human-reviewed or genuinely large/mixed work.

  Choose full only when the change needs the careful treatment (multiple
  logical commits, human review, mixed concerns); otherwise rapid. Both
  keep the plan/commit approval as the single gate — never deliver
  without it.

## Process

### 0. Load Profile

Read `~/.claude/active-profile.yaml` if it exists. If the file
does not exist, use these defaults:
- `rules.code_style`: line_length=120, comments=minimal,
  naming_convention=handler
- `rules.testing`: approach=tdd, scope=[unit, integration],
  subagents=[test-backend, test-review]
- `rules.workflow`: docs_first=strict, correction_capture=true,
  scope_drift=warn
- `tools`: rlm=true, memory_backend=claude-mem

Apply the loaded values to all "per profile" references below.

### 1. Load Context

**Search claude-mem for similar implementations**
(skip if profile `tools.memory_backend` is `none`):
```
mcp__plugin_claude-mem_mcp-search__search(
  query="{task_keywords} implementation pattern",
  project="{project_name}",
  limit=5
)
```

**Initialize RLM**
(skip if profile `tools.rlm` is `false`):
```bash
rlm_repl status
```
- If not initialized, suggest `/embo:init`

### 1b. Test Plan Check

Check for a test plan for the active feature (once per session, at start):

```bash
ls tasks/{feature-id}-{feature-name}/*-test-plan.md 2>/dev/null
```

- **If found**: read it. Note that `[verify: ...]` tags on tasks
  should match the Story Coverage table. Flag any mismatches before
  implementing.
- **If not found** AND the feature has non-`code-only` tasks: warn
  once — _"No test plan found for this feature. Consider running
  `/embo:test-plan` before proceeding."_ Do NOT block. User can proceed.
- **If not found** AND all tasks are `code-only`: say nothing.

### 2. Load and Understand Current Task

- Read the current task file from
  `/tasks/[JIRA-ID]-[feature-name]/`
- Identify the next incomplete sub-task
- Extract requirements and acceptance criteria

### 3. RLM-Powered Context Discovery

**Skip this entire step if profile `tools.rlm` is `false`.**

**3a. Find relevant existing code:**

Use the **Glob tool** (not Bash, not `find`) with patterns derived from
the task keywords — e.g. `**/*ModelPicker*`, `**/stores/jobs*`. Then use
`rlm_repl exec` with `grep` to locate symbols by name:

```bash
rlm_repl exec <<'PY'
import json
results = grep(r'def feature_term|class FeatureTerm', max_matches=10)
print(json.dumps([r['snippet'][:200] for r in results]))
PY
```

Available exec helpers: `grep(pattern, max_matches, window)`,
`peek(start, end)`, `chunk_indices(size, overlap)`, `write_chunks(out_dir)`.
No other helpers exist — do not call `find_files_by_pattern`,
`find_symbol`, `write_file_chunks`, or `get_related_files`.

**3b. Analyze patterns using rlm-subcall:**
- For each relevant file found in 3a, invoke rlm-subcall with:
  - Query: "Analyze for: (1) architectural patterns, (2) coding
    conventions, (3) how [feature] is currently handled,
    (4) testing approach"
- Collect: code structure, naming conventions, error handling,
  testing patterns, dependency injection approach

**3c. Find existing tests:**

Use the **Glob tool** with patterns `**/*.test.*`, `**/*.spec.*`,
`**/*test*`. Filter results by name similarity to the files found in 3a.

### 4. Synthesize Implementation Plan

Based on RLM analysis and claude-mem history, create a plan:

```
### Implementation Plan for [sub-task]

**Discovered Patterns (RLM):**
- Architecture: [from analysis]
- File organization: [from existing code]
- Testing approach: [from test analysis]

**Past Lessons (Claude-Mem):**
- [Relevant decision from memory]

**Files to Modify:**
- `src/x/handler.py:45` - [change]

**Files to Create:**
- `src/x/new_feature.py` - [purpose]
```

### 5. Implement Following Discovered Patterns

- Write tests first (TDD) following discovered testing patterns
- Implement matching discovered architectural patterns
- Use same naming conventions and code structure
- Follow dependency injection patterns found in codebase

### 6. Verify and Index in Claude-Mem

Read the updated tasks file — the PostToolUse hook captures it as a
claude-mem observation automatically. No explicit save call needed.
Evidence notes in the task file (the `→ summary [live] (date)` lines)
are the durable record of what was tested and how.

### 7. Update Task List and Documentation

- Mark sub-task as complete per Task Completion Rules above
- Update "Relevant Files" section in task file
- If parent task completed, save to claude-mem and update
  ai-docs/ if present

## Context7

When referencing any library, framework, or external API — use the Context7 MCP to look up current documentation rather than guessing. Call `mcp__context7__resolve-library-id` then `mcp__context7__get-library-docs`. Never invent API signatures or assume version-specific behaviour.

## Code Style

**Per profile `rules.code_style`** (defaults shown):

- Focus on readability
- Line length: per profile `line_length` (default: 120)
- Trim empty characters in line ends
- IMPORTANT: Always end files with an empty line
- **Comments policy** per profile `comments`:
  - `minimal` (default): Avoid comments. Write self-documenting code.
    Only add comments for complex business logic.
  - `allowed`: Add comments where helpful for clarity.
  - `none`: No comment policy enforced.
- **Naming convention** per profile `naming_convention`:
  - `handler` (default): Use "handler" for application layer components
  - `none`: No naming convention enforced
- **Allow-listable invocation** (scripts, launchers, documented run
  commands you generate): design them to be invocable as ONE plain
  command. Parameters go in CLI flags, a config file, or an env file
  the script loads itself — never require callers to prepend `VAR=x`
  assignments or an `env` wrapper. Prefixed invocations defeat
  permission-allowlist prefix matching and force prompts on every
  run; a plain invocation stays prompt-free even where no
  approval/capture hook is installed.

## Testing Guidelines

**Per profile `rules.testing`** (defaults shown):

- **Approach** per profile `approach`:
  - `tdd` (default): Write tests first, then implement
  - `test-after`: Implement first, write tests after
  - `none`: No testing requirements
- **Test External Interface Only:** Public APIs, exported
  functions, external interfaces — never internal implementation
- **Test Functionality, Not Implementation:** What the code does,
  not how
- **Focus on Module Contracts:** Inputs, outputs, side effects,
  error conditions
- **Subagents**: invoke agents listed in profile `subagents`
  (default: [test-backend, test-review]). Empty list = no subagents.
- Follow testing patterns discovered via RLM analysis
  (skip if RLM disabled)
