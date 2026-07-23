# 045: Cut `/embo:start` Context Cost (drop duplication, read tasks lazily)

Combined doc (problem + decisions + scope + tasks), compact style —
same convention as tasks 040/042. Records a live context-cost audit of
`/embo:start` (2026-07-23) and the work to make its reads smaller and
user-controllable without losing the session summary's value.

## Problem

A fresh `/embo:start` in this repo consumes ~84k tokens before any real
work begins. A `/context` measurement (2026-07-23, Opus 4.8 / 1M) showed
the resident floor is small — MCP tools are lazy-loaded (419 resident,
not the ~105k the tool list would imply), skills ~10k, memory ~5.9k,
agents ~3.1k. **The variable cost is `Messages` (87k), and the largest
controllable contributor is what `/embo:start` itself reads.** Three
defects:

**D1 — Recent-work search duplicates the SessionStart injection.**
claude-mem's own SessionStart hook injects a "recent context" block
(legend + ~20 recent observations + stats) into context *before*
`/embo:start` runs. Step 2 (start.md:545) then runs
`search(query="implementation completed features recent work", limit=10,
orderBy="created_at DESC")` — which re-surfaces the same recent
observations already injected. Verified live 2026-07-23: the Step 2
results (S9708, S9652, 32387, 32360, #31702) overlapped heavily with the
SessionStart dump. The recent-work observations are paid for twice.

**D2 — Every task file is read in full.** Step 3 (start.md:568-579)
globs `tasks/**/*-tasks.md` and reads each surviving file. This repo has
~15 task files; even with the ≥80%-complete compaction rule
(start.md:573), this is the single largest variable read. Most of it is
context for tasks the user will not touch this session.

**D3 — Depth is fixed regardless of profile or intent.** Step 2 always
runs 3 searches (limit 5+10+5) + `get_observations`; Step 3 always reads
all docs + all tasks. There is no lever to ask for a cheaper start when
the user just wants to resume quickly, and the profile (quality/fast/
minimal) does not influence read depth.

## Decisions

1. **Step 2 stops re-searching for recent work; it reads the injected
   block instead.** The SessionStart context already lists recent
   observations. Step 2 keeps only the queries that add something the
   dump does not cover — project overview/architecture (topical, not
   recency-ordered) — and drops the `recent work` recency query
   entirely. Where the summary needs recent activity, it draws from the
   already-injected SessionStart block, not a fresh search. Retires D1.
   - Fallback preserved: if NO SessionStart block is present (claude-mem
     not installed, or a runtime that does not inject), Step 2 falls
     back to one recency query so the summary is not empty.

2. **Task discovery is delegated to a subagent (REVISED 2026-07-23,
   user).** The first cut of this decision was "lazy read on the main
   context — headers for all, one file in full." Two problems the user
   raised: (a) headers-for-all still scales with the backlog (this repo
   has ~40 task dirs) and grows forever; (b) even the header bulk lands
   in the main context. Revised design:
   - A new lightweight agent **`embo:session-scout`** (Haiku, Read/Grep/
     Glob) reads `tasks/**/*-tasks.md` in ITS OWN context, ranks by
     modification recency + presence of open markers, and returns a
     compact digest (top ~5 active tasks: path, title, open-subtask
     count, one-line status; a recommended next task + one-line why;
     older active files listed by name only, unread). Bulk file content
     never enters the main context — only the ~200-token digest does.
   - `/embo:start` Step 3 spawns this agent instead of reading task
     files itself. Full read of a task is deferred to when the user
     selects it (main-context read then, as before).
   - In brief depth, the scout still runs (it is cheap and off-main-
     context) but returns names + open-marker counts only, no per-task
     status prose.
   - This is the RULE:DELEGATE many-file-exploration case applied to the
     command's own discovery step. Retires D2 and caps cost at O(digest)
     regardless of backlog size.

3. **Depth is profile-driven (no argument).** `fast`/`minimal` → brief
   (skip the memory search, rely on the SessionStart block; headers-only
   for all tasks); anything else → full. An override argument was
   considered and dropped (2026-07-23, user): the profile already
   determines depth, so a `--full`/`--brief` argument is a redundant
   second control. Retires D3.

4. **The summary template degrades honestly.** When a section's source
   was not read (brief mode, or a deferred task body), the summary says
   so ("N active task files — headers shown; full read on selection")
   rather than silently omitting, so the user knows what was skipped and
   can ask for more. Consistent with the honest-degrade principle in
   task 040 decision 9.

## Acceptance criteria

- **AC-1 (no recent-work duplication):** in a session where the
  SessionStart block is present, Step 2 issues NO recency-ordered
  "recent work" search; the summary's recent-activity content is sourced
  from the injected block. Verified by inspecting the command's own tool
  calls in a live run.
- **AC-2 (delegated discovery):** Step 3 spawns `embo:session-scout`;
  no `tasks/**/*-tasks.md` file content is read into the MAIN context
  during start (only the scout's digest is). Verified by the main
  context's read set in a live run (no task-file Reads by the main loop).
- **AC-3 (profile depth control):** a `fast`/`minimal` profile yields
  brief (memory search skipped, no full task read); any other profile
  yields full. Verified live at both settings.
- **AC-4 (honest degrade):** every section whose source was skipped is
  labelled as skipped in the summary, not omitted silently.
- **AC-5 (fallback intact):** with NO SessionStart block, Step 2 still
  produces a non-empty recent-activity summary via one fallback query.

## Scope

- Rewrite `plugin/commands/start.md` Step 2 (drop the recent-work query,
  add the SessionStart-block-first rule + fallback), Step 3 (delegate
  task discovery to `session-scout`), and add profile-driven depth.
- New `plugin/agents/session-scout.md` discovery agent.
- Update the Step 4 summary template for honest-degrade labelling.
- Out of scope: the claude-mem SessionStart injection itself (not an
  embo file); global plugin/skill disabling (a separate lever the user
  deferred); CLAUDE.md trimming (separate).

## Tasks

- [X] 1.0 **User Story:** As an embo user, `/embo:start` does not pay
  twice for recent observations — it reads the SessionStart block that
  is already in context instead of re-searching for it.
  - [X] 1.1 Rewrite Step 2: remove the `recent work` recency query; keep
    the overview/architecture query; add the "read recent activity from
    the injected SessionStart block, do not re-search it" rule; keep the
    one-query fallback for when no block is present. [verify: code-only]
    → done: Step 2 compressed 37→24 lines; recency query removed,
      overview-only + no-block fallback retained (2026-07-23)
  - [X] 1.2 Live: run `/embo:start`, confirm no recency "recent work"
    search is issued and the summary's recent-activity section is
    populated from the injected block (AC-1, AC-5). [verify: manual-run-claude]
    → verified live 2026-07-23 in this repo: /context after /embo:start
      showed Messages 87.3k → 40.3k and total 84k → 64.9k; the duplicate
      recency search was gone.

- [X] 2.0 **User Story:** As an embo user, `/embo:start` discovers my
  tasks without pulling their file content into the main context, and
  the cost does not grow with my backlog.
  REVISED 2026-07-23 (user): superseded the "lazy read on main context"
  design with subagent delegation (see Decision 2).
  - [X] 2.1 (superseded) First cut: headers-for-all + one file in full,
    read on the main context. Kept in git history; replaced by 2.3/2.4.
    → the interim main-context lazy-read paragraph is REMOVED from Step 3
      by 2.4 (2026-07-23)
  - [X] 2.2 Live: confirm no task-file content is read into the main
    context during start; the digest recommends a sensible next task
    (AC-2). [verify: manual-run-claude]
    → verified live 2026-07-23 on two projects: `embo:session-scout`
      registered (129 tokens under Plugin agents) and total held at
      ~49-65k with Messages ~40-45k on a separate LARGE project — task
      bulk absorbed in the scout's context, not main.
  - [X] 2.3 Create `plugin/agents/session-scout.md` (Haiku; Read/Grep/
    Glob): reads `tasks/**/*-tasks.md` (skip `/archive/`), ranks by
    mtime + open markers, returns a compact digest (top ~5 active:
    path/title/open-count/status; recommended next + why; older active
    by name only). Brief-depth variant = names + counts only.
    [verify: code-only]
    → done: agent written, ~250-token digest contract, one-full-read-max
      rule, full/brief output shapes (2026-07-23)
  - [X] 2.4 Rewrite Step 3 task handling to spawn `embo:session-scout`
    and consume its digest; remove the interim main-context lazy-read
    text. Update Step 0 + Step 4 depth lines + CLAUDE.md agent tree.
    [verify: code-only]
    → done: Step 3 tasks bullet now spawns the scout; Step 0/Step 4
      depth lines reworded; session-scout added to CLAUDE.md tree
      (2026-07-23)

- [~] 3.0 **User Story:** As an embo user, start depth follows my
  profile.
  DESIGN CHANGE (2026-07-23, user): the `--full`/`--brief` argument was
  dropped — depth is fully determined by the profile, so a separate
  argument is a redundant second control. Depth = brief for
  fast/minimal, full otherwise.
  - [X] 3.1 Add depth resolution to start.md as a one-line rule in
    Step 0 (profile-only: fast/minimal=brief, else full); Steps 2/3
    reference it. No argument. [verify: code-only]
    → done: one-line depth rule folded into Step 0, no new section
      (2026-07-23)
  - [X] 3.2 Add honest-degrade depth line to the Step 4 summary
    template's System Status block (AC-4). [verify: code-only]
    → done: "Read depth: {full|brief} … label any skipped section"
      (2026-07-23)
  - [ ] 3.3 Live: verify brief (fast/minimal profile) and full behave
    per AC-3; skipped sections are labelled (AC-4). [verify: manual-run-claude]

- [X] 4.0 **User Story (FOLLOW-UP, broader scope — user 2026-07-23):**
  As the maintainer, other commands that bulk-read files into the main
  context use the same subagent-digest pattern, so context cost is
  bounded across the workflow, not just at start.
  [audited 2026-07-23: `start` was the only command with the qualifying
  shape; no other command needs the change — see 4.1.]
  - [X] 4.1 Audit `impl.md`, `check.md`, `wrapup.md`, `prd.md` for bulk
    main-context reads; list each with its read shape. [verify: code-only]
    → findings (2026-07-23):
      · **check** — globs all task files but reads only the ONE active
        file (Step 2); per-task RLM verification needs the file content
        in the main context to decide marks. Single-file read + decision
        locality → does NOT qualify.
      · **wrapup** — reads only git-modified task files (`git diff
        --name-only`), a set already bounded to this session's changes,
        and it EDITS them (compaction). A read-only digest agent cannot
        do the write → does NOT qualify.
      · **impl** — keyword-glob source/test discovery already carries a
        `[delegate:trigger-1]` checkpoint offering `rlm-subcall`; the
        delegation path exists → no new work.
      · **prd** — file discovery runs inside `rlm_repl exec` (RLM), off
        the main context by construction → no new work.
      Conclusion: `start` was the genuine outlier (read EVERY task file
      for a summary a digest gives equally). No other command shares that
      shape; story closed with no code change.
  - Subtask 4.2 (apply the pattern elsewhere) REMOVED — 4.1 found no
    other command qualifies.

## Related

- `plugin/commands/start.md` — the command being made cheaper.
- `plugin/agents/session-scout.md` — new discovery agent (this task).
- RULE:DELEGATE (`start.md`) — the principle Decision 2 applies to the
  command's own discovery read.
- claude-mem SessionStart hook — the injection Step 2 must stop
  duplicating (not an embo file; behavior observed, not modified).
- Task 040 decision 9 — the honest-degrade principle reused here.
- Task 036 (token-efficiency task-file compaction) — the ≥80% compaction
  rule this task extends to every task file.
