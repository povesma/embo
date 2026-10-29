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

Do NOT silently execute user instructions. Before implementing, evaluate
against: (1) **PRD and tech-design** — does it align with documented
requirements? (2) **Current tasks** — is this covered by an existing
task? (3) **Feasibility** — is it technically sound; could the user be
mistaken even in a clear instruction? (4) **Vague instructions** — ask
for clarification, never interpret-and-implement.

Raise any problem before implementing. The user is the boss, but the
agent is responsible for flagging risks.

When the user challenges a decision with a question, defend the position
if it's correct — don't cave. Full rule in `start.md` §Session
Behavioral Rules.

<!-- RULE:DOCS-FIRST -->
## Scope Verification (Doc-First Development)

Sessions are idempotent: restarted, the code must still match PRD,
tech-design, and tasks.

**Before implementing any instruction**, check whether it maps to a task
in the active task list. If yes, proceed. If no, it is scope drift:

1. **Clarification-level change** (implementation detail, preference,
   minor adjustment): just implement it.
2. **New feature or significant change** (new user story, new component,
   architecture change): update the docs BEFORE implementing —
   - Small: add a subtask to an existing story
   - Medium: add a new story + update tech-design
   - Large: update PRD + tech-design + tasks, and ask the user to
     confirm the doc changes first

**Judgment call**: the clarification-level exception covers only
implementation details inside an existing subtask (equivalent
approaches, whitespace, a variable name). If the change adds behavior,
modifies an API, or touches a file not in the task's "Relevant Files",
it requires a doc update first.

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

When the user corrects how you work, a correction observation is saved
to claude-mem by the PostToolUse hook — no explicit save call, no
announcement, no interruption. Just continue with the corrected approach.

**Capture** behavioral corrections: verification ("check the docs"),
code-style ("don't add comments"), workflow ("add a check for X"),
approach ("that's over-engineered"), process ("always do X before Y").

**Do NOT capture** scope or design changes: "let's do feature B
instead", "make that field optional", "skip task 3".

## Task Completion Rules

Verification methods (`code-only`, `auto-test`, `manual-run-claude`,
`manual-run-user`, `docker`, `e2e`, `observation`) and the `live` vs
`simulated` distinction are defined in the canonical taxonomy in
`/embo:test-plan`.

- **`[X]` (done)**: ONLY when live-tested AND the intended
  functionality demonstrably works — not just "tests pass formally."
  Always seek a live test (actual command run, real output, real
  side-effect). Simulation or mocking is acceptable only when live
  testing is costly, destructive, or impossible — and even then at
  least one live test must be done before `[X]`, with the simulation
  recorded in the evidence note. Alternatively: explicitly confirmed
  by the user.
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

**Compact summary rule**: `<summary>` is one clause stating the outcome
or decision; a second clause only if something unexpected occurred.
Omit how the work was done, superseded intermediate states (TDD red
phases, bugs fixed before `[X]`), and tool invocation details. The
evidence line is a permanent record, not a session log.

Write `→ 3 passed, 0 failed [live] (2026-07-02)`, not `→ wrote tests
first (TDD red: 3 failed), then implemented, then ran again: 3 passed`.

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
  recoverable choice yourself and record it in evidence notes.
  All other rules stay in force in every mode: evidence gates per
  `[verify:]` type, TDD order, docs-first, and the safety rules — a
  mode-3 run NEVER authorizes destructive or shared-state actions
  without their own approval.
- **Delivering to the repo:** when the run pauses with work to deliver,
  offer two paths. **Rapid** (`/embo:git deliver`) — one commit, one
  plan approval, straight to the branch; the default. **Full commit**
  (`/embo:git commit`/`pr`) — split into commits with polished
  messages; only for human-reviewed or genuinely large/mixed work.
  Both keep the plan/commit approval as the single gate — never
  deliver without it.

## Process

### 0. Load Profile

Use the profile already loaded this session (from `/embo:start`). If it
is not in context, run `embo-profile show` — it returns the active
profile, or the canonical `default.yaml` when none is set. Apply the
loaded values to all "per profile" references below. (claude-mem is
always on.)

### 1. Load Context

**Search claude-mem for similar implementations**:
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

Once per session, check for a test plan:
`ls tasks/{feature-id}-{feature-name}/*-test-plan.md`

- **Found**: read it; `[verify: ...]` tags should match the Story
  Coverage table. Flag mismatches before implementing.
- **Not found**, feature has non-`code-only` tasks: warn once —
  _"No test plan found. Consider running `/embo:test-plan` first."_
  Do NOT block.
- **Not found**, all tasks `code-only`: say nothing.

### 2. Load and Understand Current Task

- Read the current task file from
  `/tasks/[JIRA-ID]-[feature-name]/`
- Identify the next incomplete sub-task
- Extract requirements and acceptance criteria
- **Notice the current branch.** Compare `git symbolic-ref --short -q
  HEAD` against the task ID from the folder name. On a mismatch, look
  for a local branch that matches (`git branch --list '*<task-id>*'`)
  and suggest switching; if none exists, mention it and continue. One
  line, no gate — `embo-deliver` warns again at delivery.

### 3. RLM-Powered Context Discovery

**Skip this entire step if profile `tools.rlm` is `false`.**

**Delegation checkpoint (per RULE:DELEGATE).** Apply trigger 1 to
this discovery if it reads many files (`rlm-subcall`, marker
`[delegate:trigger-1]`) and trigger 4 if the story has 3+
independent subtasks (parallel fan-out, marker
`[delegate:trigger-4]`). This is additive — the profile `subagents`
test agents (Testing Guidelines) stay a prescribed, non-optional
spawn.

**3a. Find relevant existing code:**

Use the **Glob tool** (not Bash, not `find`) with patterns derived from
the task keywords — e.g. `**/*ModelPicker*`, `**/stores/jobs*`. Then use
`rlm_repl exec` with `grep` to locate symbols by name. Write the probe
to `tmp/rlm-probe.py`, then run it — `-c` is required and heredocs are
not supported:

```bash
rlm_repl exec -c "$(cat tmp/rlm-probe.py)"
```

```python
# tmp/rlm-probe.py
import json
results = grep(r'def feature_term|class FeatureTerm', max_matches=10)
print(json.dumps([r['snippet'][:200] for r in results]))
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

From the RLM analysis and claude-mem history, state for the sub-task:
discovered patterns (architecture, file organization, testing approach),
relevant past decisions, files to modify (with line references), and
files to create (with purpose).

### 5. Implement Following Discovered Patterns

- Write tests first (TDD) following discovered testing patterns
- Implement matching discovered architectural patterns
- Use the same naming conventions, code structure, and dependency
  injection patterns found in the codebase

### 6. Verify and Index in Claude-Mem

Read the updated tasks file — the PostToolUse hook captures it as a
claude-mem observation automatically. No explicit save call needed.
Evidence notes in the task file (the `→ summary [live] (date)` lines)
are the durable record of what was tested and how.

### 7. Update Task List and Documentation

- Mark sub-task as complete per Task Completion Rules above
- Update "Relevant Files" section in task file
- If parent task completed, update ai-docs/ if present

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
  assignments or an `env` wrapper, which defeats permission-allowlist
  prefix matching and forces a prompt on every run.
- **Function-based structure for shell and test scripts**: wrap logic
  in named functions; keep top-level code to setup, a runner list, and
  the summary. In `.test.sh` files each test case is its own function
  invoked by a runner list — never top-level statements.

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
