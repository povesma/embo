# 052-START-SLIM: Slim /embo:start Command - PRD

**Status**: Draft
**Created**: 2026-08-19
**Task**: 052-START-SLIM (internal numbering; no external ticket)
**Author**: Claude (via /embo:prd)

---

## Wider Context / Higher Goal

`/embo:start` runs at the beginning of every coding session, so every
line of instruction bloat, every dead template slot, and every
approval-gate trap in it is a recurring per-session tax. The cleanup
exists to cut that recurring cost: fewer tokens loaded per session,
zero approval dialogs during startup, no instructions that invite
meaningless actions.

**Scope amendment (2026-08-22)**: post-smoke-test observation folded
in per user decision. The transcript revealed a second cost driver
larger than the prose bloat itself: `/embo:start` executes as ~7
sequential assistant turns when the data-dependency graph supports 3.
Each assistant turn is an LLM round-trip that resends the whole
accumulated context (prompt caching reduces the per-token rate but
still occupies the context window and still costs input tokens).
Cutting round-trips is the direct fix and lives in the same command
file this task already targets.

## Context

A live execution of `/embo:start` this session surfaced 9 concrete
defects in `plugin/commands/start.md` — duplicated specifications,
template slots no step can fill, contradictory discovery instructions,
and unmeasurable directives. The user requested a slim-down, scoped
in-place (no relocation of the session behavioral rules).

### Current State (observed)

- `plugin/commands/start.md` is 874 lines — verified via:
  `wc -l plugin/commands/start.md`, 2026-08-19.
- `plugin/hooks/behavioral-reminder.sh` extracts the checklist blocks
  from `start.md` at runtime (`START_MD="$HOOK_DIR/../commands/start.md"`)
  — verified via: `grep -n "start.md" plugin/hooks/behavioral-reminder.sh`
  → line 111, 2026-08-19.
- `start.md` contains 5 `<!-- CHECKLIST:… -->` blocks the hook injects
  verbatim on every user prompt — verified via:
  `grep -c "CHECKLIST:" plugin/commands/start.md` → 5, 2026-08-19.
- The hook's extraction depends only on the text from each
  `[<RULE> checklist]` opener line through its `<!-- /CHECKLIST -->`
  closer; it reads neither the RULE bodies nor the comment openers —
  verified via: awk pattern at `plugin/hooks/behavioral-reminder.sh:114`
  (`/^\[.*checklist/` … `/<!-- \/CHECKLIST -->/`), 2026-08-19.
- Rules region span: `start.md:46` ("## Session Behavioral Rules"
  heading) through `start.md:600` (last CHECKLIST closer) = 555 lines;
  non-rules remainder = 319 lines — verified via:
  `grep -n "Session Behavioral Rules"` and `grep -n "/CHECKLIST -->"`
  on `plugin/commands/start.md`, 2026-08-19.
- `plugin/commands/impl.md:33-34` cross-references the heading ("See
  full rule in `start.md` §Session Behavioral Rules", wrapped across
  two lines) — verified via: `grep -n "full rule in"
  plugin/commands/impl.md`, 2026-08-19.
- `start.md:3` frontmatter carries `allowed-tools: Bash(embo-profile *)
  Bash(rlm_repl *) Bash(git log *) Bash(git diff *)`, referenced by
  `install.sh:319` — verified via: `grep -n "allowed-tools"
  plugin/commands/start.md`, 2026-08-19.
- The 9 defects below were each observed in the command body as loaded
  and executed this session — verified via: `/embo:start` run,
  2026-08-19:
  1. The Step 4 output template and the "Example Output" section
     specify the same document twice (~60 lines combined).
  2. Step 3 docs discovery is contradictory and redundant: recursive
     Glob for `**/CLAUDE*.md` then "read the matched files at the
     project root only" — and CLAUDE.md is already injected into
     context by the harness every session, so re-reading double-pays.
     (The step already directs the Glob tool over Bash `find`, so the
     defect here is redundancy and contradiction, not an approval
     trap.)
  3. Two template slots have no producing step: "Key Patterns
     Discovered (RLM)" (no step runs RLM analysis) and "Most Modified
     Files (Past week)" (`git log --oneline -10` yields commits, not
     per-file change frequency). Dead slots invite the model to invent
     extra commands.
  4. Filling "Most Modified Files" honestly requires piped git commands
     outside the pre-approved prefixes → approval dialog at every
     session start that attempts it.
  5. Step 0 names `embo-profile show` but then says "parse the YAML"
     — vague; the wrapper's `get <key>` subcommand exists for
     single-value access and is not named.
  6. "Aim for <30s total time" is unmeasurable by the model and
     produces no behavior.
  7. Three sections ("Context Quality Levels", "Important Notes",
     "Final Instructions") restate overlapping guidance; "do not
     implement anything" appears 3 times.
  8. Step 2's rename fallback uses undefined terms ("near-nothing",
     "inferable prior name") with no threshold and no source.
  9. The template mandates emoji headings, contradicting the repo's
     emoji-minimization policy.
- Command `.md` edits activate on the next prompt with no reload —
  verified via: CLAUDE.md "Picking up local edits" table (itself
  verified against Claude Code docs 2026-08-13).

### Past Similar Features (from claude-mem)

No prior PRD indexed for command-file slimming (claude-mem `type=PRD`
search returned nothing). Related lineage: token-efficiency work
(task 036) and the rule-enforcement architecture that placed the rules
and checklists inside `start.md` (task 047) — the latter is the source
of this feature's main preservation constraint.

## Problem Statement

**Who**: Every embo user, every session — plus the maintainer paying
review cost on an 874-line command file.
**What**: `/embo:start` loads duplicated and dead instruction text into
context, instructs steps that stall on approval dialogs or invite
invented commands, and mandates output that contradicts repo policy.
**Why**: Wasted context window at the moment it matters most (session
start), startup stalls on permission prompts, and unpredictable
model behavior on the unfillable slots.
**When**: Every `/embo:start` invocation.

## Goals

### Primary Goal

Reduce the per-session cost of `/embo:start` — tokens loaded and
approval prompts triggered — to the minimum that preserves its current
behavior and the rule-enforcement contract.

### Secondary Goals

- Make every remaining instruction deterministic: each template slot
  names its producing step; each commanded invocation is a
  pre-approved shape.
- Align the command's output format with the repo's emoji policy.

## User Stories

### Epic

As an embo user, I want a lean `/embo:start`, so that session startup
is cheap, prompt-free, and predictable.

### User Stories

1. **As an** embo user
   **I want** the command's output specified exactly once, with only
   fillable slots
   **So that** each session start loads no duplicated or dead
   instruction text.

   **Acceptance Criteria**:
   - [ ] One compact section spec (required sections + one-line content
     rules) replaces both the full mock template and the "Example
     Output" section.
   - [ ] Every slot in the spec names the step that produces its data;
     the two unfillable slots (finding 3) are removed.
   - [ ] The three overlapping guidance sections are merged into one;
     "do not implement" appears exactly once.

2. **As an** embo user
   **I want** every startup step to run without approval dialogs
   **So that** session start never stalls on a permission prompt.

   **Acceptance Criteria**:
   - [ ] No instruction requires a piped, subshell, or otherwise
     non-pre-approved command shape (finding 4 eliminated with its
     slot).
   - [ ] Step 0 names `embo-profile get` for reading specific profile
     values instead of "parse the YAML".
   - [ ] The CLAUDE.md discovery step is removed (harness already
     injects it); README discovery is a single root-level read, not a
     recursive glob.
   - [ ] Vague/unmeasurable directives (findings 6, 8) are replaced
     with deterministic rules or deleted.

3. **As the** embo maintainer
   **I want** the rule-enforcement contract untouched by the slim-down
   **So that** behavioral enforcement keeps working without hook or
   test changes.

   **Acceptance Criteria**:
   - [ ] All 5 `<!-- CHECKLIST:… -->` blocks and their RULE bodies
     remain in `start.md` with extraction-relevant text unchanged.
   - [ ] `behavioral-reminder.sh` is not modified.
   - [ ] The checklist text the hook extracts is byte-identical before
     and after the change.

4. **As an** embo user
   **I want** the session summary without emoji headings
   **So that** the output matches the repo's emoji-minimization policy.

   **Acceptance Criteria**:
   - [ ] Headings in the output spec are plain text.
   - [ ] Status indicators (for example a check mark in the System
     Status block) are permitted only where they aid scanning.

5. **As an** embo user
   **I want** `/embo:start` to finish in the fewest assistant turns
   the data dependencies allow
   **So that** every extra whole-context resend is eliminated
   (scope amendment, 2026-08-22).

   **Acceptance Criteria**:
   - [ ] The command body directs parallel execution of the 5
     independent discovery calls in a single assistant turn:
     profile, RLM status, `git log`, `git diff`, README read.
   - [ ] The 2 profile-dependent calls (memory overview, session-
     scout) run together in the next assistant turn.
   - [ ] The Bash `test -f README.md` pattern is removed in favor
     of a Read that tolerates a missing file (a Read failing is
     the "skip").
   - [ ] A headless `claude -p "/embo:start"` transcript shows
     ≤ 3 assistant turns containing tool calls (excluding the
     final summary turn and the conditional rename-retry turn).

## Requirements

### Functional Requirements

1. **FR-1**: Single output specification — one compact section spec;
   mock template and "Example Output" both removed.
   - **Priority**: High
   - **Rationale**: Largest duplicated block (finding 1); chosen shape
     per user decision ("compact section spec").
   - **Dependencies**: none.

2. **FR-2**: Every retained output slot names its producing step; slots
   without a producer are removed (findings 3, 4).
   - **Priority**: High
   - **Rationale**: Dead slots invite invented commands and approval
     prompts.
   - **Dependencies**: FR-1.

3. **FR-3**: All commanded invocations are pre-approved shapes: profile
   values via `embo-profile get <key>`; git via the two existing exact
   commands; no piped discovery commands (findings 4, 5).
   - **Priority**: High
   - **Rationale**: Zero approval dialogs during startup.
   - **Dependencies**: `plugin/bin/embo-profile` (exists).

4. **FR-4**: Docs discovery reduced: CLAUDE.md step removed (harness
   injects it); README read once at repo root (finding 2).
   - **Priority**: Medium
   - **Rationale**: Removes double-paying and the glob/root
     contradiction.
   - **Dependencies**: none.

5. **FR-5**: Vague directives removed or made deterministic: "<30s"
   deleted; rename fallback either deleted or given a concrete
   trigger (0 results) and source (findings 6, 8).
   - **Priority**: Medium
   - **Rationale**: Unmeasurable instructions produce no behavior;
     undefined terms produce unpredictable behavior.
   - **Dependencies**: none.

6. **FR-6**: Guidance consolidation — "Context Quality Levels",
   "Important Notes", "Final Instructions" merged into one section
   (finding 7).
   - **Priority**: Medium
   - **Rationale**: Same guidance stated once.
   - **Dependencies**: FR-1.

7. **FR-7**: Emoji removed from headings in the output spec; status
   indicators only where they aid scanning (finding 9; user decision).
   - **Priority**: Low
   - **Rationale**: Repo emoji policy.
   - **Dependencies**: FR-1.

9. **FR-9** (scope amendment, 2026-08-22; **downgraded to
   best-effort 2026-08-23**): the command body documents parallel
   execution as Batch A (5 independent discovery calls) and Batch B
   (2 profile-dependent calls) with explicit "parallel tool_use
   blocks in the same response" wording, so a compliant runner can
   complete `/embo:start` in ≤ 3 assistant turns. The Bash `test -f`
   probe for README is removed in favor of a Read that tolerates a
   missing file.
   - **Priority**: Medium (downgraded from High).
   - **Rationale**: turn count is the direct token-cost lever;
     however, live headless testing (2 runs, original and
     strengthened wording) showed the model serializes single-tool
     turns anyway. Directive-only enforcement is insufficient in
     headless mode. The prose is retained as documentation and
     specification, but the ≤ 3-turn metric is not achievable
     without a real mechanism (Stop-hook, Bash wrapper, or
     tool-choice constraint) — seeded as task 056.
   - **Dependencies**: FR-1 (single output spec), FR-3 (pre-approved
     shapes only).
   - **Related defect discovered**: session-scout return handling —
     when the scout returned an empty/unreadable digest, the model
     replaced the delegation with 15+ inline Read/Grep turns
     against task files. Seeded as task 057.

8. **FR-8** (preservation constraint, amended 2026-08-23): the
   Session Behavioral Rules stay in `start.md` **byte-identical
   except for two named batch carve-outs**, both added inside
   existing CHECKLIST blocks. The hook contract is untouched.
   - **Priority**: High
   - **Rationale**: two distinct locks. The hook contract locks only
     the `[<RULE> checklist]` opener→`<!-- /CHECKLIST -->` closer text
     (awk at `behavioral-reminder.sh:114`); the RULE bodies are locked
     by the chosen in-place scope (policy decision), not by the hook.
   - **Amendment rationale**: a clean-context review of the FR-9
     batching failure (2026-08-23) identified two CHECKLIST rules
     that structurally block parallel `tool_use` in the same response
     and are re-injected on every turn. The AVOID-APPROVAL checklist
     treats parallel tool_use blocks as "chaining"; the DELEGATE
     checklist requires a text line before the 3rd file-opening call,
     which contradicts the Anthropic API's tool-use-only-response
     shape for parallel tool_use. Both rules must gain a one-sentence
     "explicit Batch A/B calls are exempt" carve-out for FR-9 to have
     any chance of working. Every other line in the rules region
     stays byte-identical.
   - **Amended dependencies**: minimal, named edits inside the
     AVOID-APPROVAL and DELEGATE CHECKLIST blocks; nowhere else in
     the rules region.
   - **Editor guard** (unchanged): no new or edited line outside the
     CHECKLIST blocks may start with `[` and contain "checklist".

### Non-Functional Requirements

1. **NFR-1**: Size — the non-rules region (319 lines: `start.md:1-45`
   and `601-874`, per the measured split above) shrinks by at least
   35% (≥ 112 lines); 40% (~128 lines) is the stretch target. The
   conservative estimate of what FR-1–FR-7 delete is 120–140 lines,
   so 35% is safely reachable and 40% is marginal — the hard
   threshold is set below the estimate's floor to keep the metric
   dispute-free.
2. **NFR-2**: Compatibility — no `/reload-plugins` or restart needed:
   command `.md` edits activate on the next prompt (per CLAUDE.md
   activation table). A patch version bump ships the change.
3. **NFR-3**: Behavior preservation — a post-change `/embo:start` run
   produces the same section content (profile, RLM status, memory
   overview, task digest, git state, recommendation) as before, minus
   the removed dead slots.

### Technical Constraints

- Must integrate with: `plugin/hooks/behavioral-reminder.sh` extraction
  (read-only dependency on the CHECKLIST opener→closer text).
- Should follow patterns: pre-approved bare commands (`embo-profile`,
  `rlm_repl`, the two exact git commands); session-scout delegation for
  task files stays as-is.
- Cannot change: RULE/CHECKLIST block text; hook code; the
  `embo-profile` and `rlm_repl` wrappers; other command files; the
  `## Session Behavioral Rules` heading (cross-referenced from
  `plugin/commands/impl.md:33-34` — if it were ever rephrased, impl.md
  must change with it, which is out of this feature's scope); the
  frontmatter `allowed-tools` list (`start.md:3`, referenced by
  `install.sh:319`) must stay consistent with every command shape the
  slimmed body names.

## Out of Scope

- Relocating session rules to a separate file and repointing the hook
  (explicitly declined scope option).
- Fixing `prd.md`'s dead RLM-helper code sample (separate follow-up
  seed).
- Changing any other command's structure, the profiles, or the hooks.
- Changing what `/embo:start` functionally does (steps stay: profile,
  RLM status, memory overview, scout digest, git state, summary,
  recommendation).

## Success Metrics

1. All 9 audit findings + the turn-count concern (FR-9) resolved,
   each mapped to an FR above.
2. Hook contract: extracted checklist text differs from baseline ONLY
   in the AVOID-APPROVAL and DELEGATE blocks, and only by the exact
   carve-out clauses documented in FR-8. `behavioral-reminder.test.sh`
   still passes 30/30.
3. Rules region byte-identical **except for the two named batch
   carve-outs** (FR-8 amendment): a diff of the `## Session
   Behavioral Rules` heading through the last CHECKLIST closer
   before/after shows non-zero differences ONLY inside the
   AVOID-APPROVAL and DELEGATE CHECKLIST blocks, and each of those
   diffs consists of exactly the documented carve-out clause added.
   `behavioral-reminder.test.sh` still passes 30/30, and the hook's
   extraction output diff (Metric 2) is the specific line additions
   from the carve-outs and nothing else.
4. A live `/embo:start` run after the change: 0 approval dialogs, 0
   invented commands, all summary sections filled from named steps.
5. Line reduction of the non-rules region (319 lines): ≥ 35%
   (≥ 112 lines); stretch 40%.
6. **Turn count (FR-9, best-effort)**: prose landed in the command
   body specifying Batch A / Batch B as parallel `tool_use` blocks
   in the same response, and the `test -f` probe for README is
   removed. The ≤ 3-turn target is documented but not enforced —
   two headless runs (original and strengthened wording) produced
   11 and 10 turns respectively; real enforcement is task 056.

## References

### From Codebase

- `plugin/commands/start.md` (874 lines; the sole edit target;
  frontmatter `allowed-tools` at line 3)
- `plugin/hooks/behavioral-reminder.sh:111,114` (extraction contract)
- `plugin/commands/impl.md:33-34` (cross-references the rules heading)
- `install.sh:319` (references the frontmatter permissions)
- `plugin/bin/embo-profile` (named in FR-3)

### From History (Claude-Mem)

- Task 047 lineage: rules + checklists deliberately live in `start.md`
  with Stop-hook measurement — the preservation constraint's origin.
- Task 036 lineage: token-efficiency work this feature continues.

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/embo:tech-design` to create technical design
3. Run `/embo:tasks` to break down into tasks
