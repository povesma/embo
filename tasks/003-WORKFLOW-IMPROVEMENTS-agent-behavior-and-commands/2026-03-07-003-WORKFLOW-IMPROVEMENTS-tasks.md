# 003-WORKFLOW-IMPROVEMENTS - Task List

## Relevant Files

- [tasks/003-WORKFLOW-IMPROVEMENTS-agent-behavior-and-commands/
  2026-03-07-003-WORKFLOW-IMPROVEMENTS-prd.md](
  tasks/003-WORKFLOW-IMPROVEMENTS-agent-behavior-and-commands/
  2026-03-07-003-WORKFLOW-IMPROVEMENTS-prd.md)
  :: Product Requirements Document
- [tasks/003-WORKFLOW-IMPROVEMENTS-agent-behavior-and-commands/
  2026-03-07-003-WORKFLOW-IMPROVEMENTS-tech-design.md](
  tasks/003-WORKFLOW-IMPROVEMENTS-agent-behavior-and-commands/
  2026-03-07-003-WORKFLOW-IMPROVEMENTS-tech-design.md)
  :: Technical Design Document
- [.claude/commands/rlm-mem/plan/tech-design.md](
  .claude/commands/rlm-mem/plan/tech-design.md)
  :: RLM-Mem tech-design command template (source of truth)
- [~/.claude/commands/coding/plan/tech-design.md]
  :: Coding tree tech-design command template (installed)
- [~/.claude/commands/rlm/plan/tech-design.md]
  :: RLM tree tech-design command template (installed)
- [.claude/commands/rlm-mem/develop/impl.md](
  .claude/commands/rlm-mem/develop/impl.md)
  :: RLM-Mem impl command template (source of truth)
- [~/.claude/commands/coding/develop/impl.md]
  :: Coding tree impl command template (installed)
- [~/.claude/commands/rlm/develop/impl.md]
  :: RLM tree impl command template (installed)
- [.claude/commands/rlm-mem/plan/check.md](
  .claude/commands/rlm-mem/plan/check.md)
  :: RLM-Mem check command template (source of truth)
- [~/.claude/commands/coding/plan/check.md]
  :: Coding tree check command template (CREATE — does not exist)
- [~/.claude/commands/rlm/plan/check.md]
  :: RLM tree check command template (CREATE — does not exist)
- [.claude/commands/rlm-mem/discover/start.md](
  .claude/commands/rlm-mem/discover/start.md)
  :: RLM-Mem start command template (source of truth)
- [~/.claude/commands/rlm/discover/start.md]
  :: RLM tree start command template (installed)
- [README.md](README.md)
  :: User guide — add allowlist guidance

## Notes

- All changes are markdown command template edits. No Python code
  or plugin changes.
- `/dev` tree is deprecated and excluded from all tasks.
- `check.md` currently only exists in rlm-mem tree. Story 4
  creates it for coding and rlm trees.
- The rlm tree uses a different REPL path:
  `claude_code_RLM/.claude/skills/rlm/scripts/rlm_repl.py`
  (vs `~/.claude/rlm_scripts/rlm_repl.py` in rlm-mem).
- Files in `.claude/commands/rlm-mem/` are the source of truth
  for this repo. Files in `~/.claude/commands/{coding,rlm}/` are
  installed copies edited directly.
- Story 7 (sync) copies rlm-mem source files to `~/.claude/`.

## TDD Planning Guidelines

These are markdown command template files, not application code.
Traditional TDD does not apply. Testing means:
- **Manual invocation**: Run the command and verify agent behavior
- **Content verification**: Check that generated tech-designs
  exclude operational content; check that impl detects scope drift
- **Regression**: Verify existing command behavior is not broken

## Tasks

- [~] 1.0 **User Story:** As a developer, I want tech-design
  commands to enforce content quality rules so that generated
  documents contain only architecture decisions, not operational
  content [3/3]
  - [~] 1.1 Add "Content Quality Rules" section to
    `.claude/commands/rlm-mem/plan/tech-design.md` — insert
    before Step 6 (Synthesize Technical Design). Include DO/DON'T
    lists from tech-design doc. The section must instruct the
    agent to self-evaluate each section against "would a developer
    not know this without reading this section?"
  - [~] 1.2 Add identical "Content Quality Rules" section to
    `~/.claude/commands/coding/plan/tech-design.md` — insert
    before the "Technical Design Structure" section
  - [~] 1.3 Add identical "Content Quality Rules" section to
    `~/.claude/commands/rlm/plan/tech-design.md` — insert before
    the equivalent output/synthesis step
- [~] 2.0 **User Story:** As a developer, I want the agent to
  critically evaluate my instructions before executing so that
  mistakes and vague requests are caught early [4/4]
  - [~] 2.1 Add "Critical Evaluation of Instructions" section to
    `.claude/commands/rlm-mem/develop/impl.md` — insert after
    "Task Completion Rules". Must instruct agent to evaluate
    instructions against PRD, tech-design, tasks, common sense,
    and technical feasibility before implementing. Vague
    instructions must be clarified, not interpreted immediately.
  - [~] 2.2 Add identical section to
    `~/.claude/commands/coding/develop/impl.md` — insert after
    "Task Completion Rules"
  - [~] 2.3 Add identical section to
    `~/.claude/commands/rlm/develop/impl.md` — insert after
    completion protocol section
  - [~] 2.4 Make `.claude/commands/rlm-mem/develop/impl.md`
    self-contained — replace the "See /rlm:develop:impl" reference
    with the full RLM process steps (merged from rlm/develop/impl.md)
    plus rlm-mem additions (claude-mem queries). Agent cannot follow
    markdown references to other commands; the full content must be
    inline.
- [~] 3.0 **User Story:** As a developer, I want scope-drift
  detection in /impl so that out-of-scope changes update docs
  before implementation, maintaining session idempotency [3/3]
  - [~] 3.1 Add "Scope Verification (Doc-First Development)"
    section to `.claude/commands/rlm-mem/develop/impl.md` —
    insert after Critical Evaluation section (from 2.1). Must
    include: check instruction against task list, handle
    clarification-level vs feature-level drift, auto-update docs
    for significant changes, ask user for large changes. Emphasize
    smart judgment — no bureaucratic overhead for minor changes.
  - [~] 3.2 Add identical section to
    `~/.claude/commands/coding/develop/impl.md` — insert after
    Critical Evaluation section (from 2.2)
  - [~] 3.3 Add identical section to
    `~/.claude/commands/rlm/develop/impl.md` — insert after
    Critical Evaluation section (from 2.3)
- [~] 4.0 **User Story:** As a developer, I want /plan:check
  available in all active trees with scope-drift detection so that
  task status reviews work everywhere and untracked changes are
  flagged [4/4]
  - [~] 4.1 Add "Scope Drift Detection" section to
    `.claude/commands/rlm-mem/plan/check.md` — insert after
    Step 4 (Update Task Status). Must instruct agent to flag code
    found that doesn't match any task in the task list. Report
    drift in status summary, do not silently accept untracked
    changes.
  - [~] 4.2 Create `~/.claude/commands/coding/plan/check.md` —
    adapt from rlm-mem check.md: replace RLM exec (Step 1) with
    Glob tool (`tasks/**/*-tasks.md`), replace RLM exec (Step 3)
    with Grep + Read tools for code verification, keep claude-mem
    save, remove ai-docs/ references, include scope-drift
    detection block and same marking rules (`[X]`/`[~]`/`[ ]`).
  - [~] 4.3 Create `~/.claude/commands/rlm/plan/check.md` —
    adapt from rlm-mem check.md: keep RLM exec for task discovery
    and code verification, remove claude-mem save, keep ai-docs/
    update references, include scope-drift detection block and
    same marking rules. Use rlm tree REPL path
    (`claude_code_RLM/.claude/skills/rlm/scripts/rlm_repl.py`).
  - [~] 4.4 Also replace the RLM exec block in rlm-mem check.md
    Step 1 (find task files) with Glob tool — same frictionless
    principle as Story 5 for /start. Keep RLM exec in Step 3
    (code verification) since that's the value-add of RLM.
- [~] 5.0 **User Story:** As a developer, I want /start to use
  only deterministic, allowlist-friendly commands so that session
  startup requires zero permission prompts [2/2]
  - [~] 5.1 Rewrite Step 3 of
    `.claude/commands/rlm-mem/discover/start.md` — replace all
    three `python3 ... exec <<'PY'` blocks (3a: find docs, 3b:
    find tasks, 3c: recent changes) with: (3a) Glob tool for
    `**/README*.md` and `**/CLAUDE*.md`, (3b) Glob tool for
    `tasks/**/*-tasks.md`, (3c) `git log --oneline -10` +
    `git diff --stat HEAD`. Keep Step 1 (`rlm_repl.py status`)
    as the only RLM shell command.
  - [~] 5.2 Rewrite Step 2 of
    `~/.claude/commands/rlm/discover/start.md` — replace
    `python3 ... exec <<'PY'` blocks (2a: find docs, 2c: find
    tasks) with equivalent Glob tool + git instructions. Note:
    this tree uses different REPL path and has rlm-subcall
    delegation; preserve the subcall pattern, only replace the
    exec-based file discovery with Glob.
- [~] 6.0 **User Story:** As a developer, I want allowlist
  guidance in the README so that I can configure frictionless
  /start once [2/2]
  - [~] 6.1 Add "Recommended Allowlist" subsection to README.md
    installation section — list the 3 commands to allow:
    `python3 ~/.claude/rlm_scripts/rlm_repl.py *`,
    `git log *`, `git diff *`
  - [~] 6.2 Add a note in the "Usage Tips" section explaining
    that `/start` is designed to need minimal permissions and
    listing the allowlist as the way to make it fully frictionless
- [~] 7.0 **User Story:** As a developer, I want the rlm-mem
  source files synced to ~/.claude/ so that my installation
  reflects the latest changes [1/1]
  - [~] 7.1 Copy modified rlm-mem command files from this repo to
    `~/.claude/commands/rlm-mem/`: `plan/tech-design.md`,
    `develop/impl.md`, `plan/check.md`, `discover/start.md`
