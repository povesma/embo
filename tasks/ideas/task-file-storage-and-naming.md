# Idea: task-file storage, sharing, search, and naming

Status: **idea only** — not a committed task, no PRD yet. Captured
2026-07-24 from a session exploration (two clean-context examine passes:
research + internal).

## The problem (as raised by the user)

Feature docs live as markdown under `tasks/NNN-FEATURE/` (PRD +
tech-design + task-list with `[ ]/[~]/[X]` markers), usually committed
to git. Convenient, low-token, native to Claude Code — but:

1. **Durability vs git-cleanliness** — not always wanted in git, but
   local-only risks loss. A local-only store contradicts durable
   preservation.
2. **Sharing** — cooperative work needs sharing; files are shareable
   only via a git push.
3. **Search** — grep over markdown is poor; no semantic search.
4. **Naming collision (the clearest point)** — the `tasks/` folder holds
   FEATURE SPECS (each with a PRD), which users call "tasks"; the
   checklist items INSIDE are ALSO called tasks/subtasks. One word, two
   meanings, two levels. Already visible in the repo:
   `tasks/046-.../...-tasks.md`.

## Candidate approaches considered

- **E. Files as a cache; sync canonical copy to a durable/shareable
  store** (claude-mem cloud runtime, or external tracker).
- **F. Machine-readable status in YAML frontmatter** (yq-queryable),
  prose in body.
- **G. Native Claude Code Task tools** (TaskCreate/Update/List) as
  complement/replacement for checklist items.
- **Naming:** rename the container concept, reserve task/subtask for
  checklist items.

## Findings from the two examine passes (research + internal)

**Both passes converged strongly:**

- **Files MUST stay the authoritative store.** `impl.md`'s evidence-note
  protocol (`→ summary [live] (date)` written directly under each marker
  line) and `start.md`'s 80%-done token-compaction (greps `[X]` vs all
  markers in the raw markdown) both HARD-depend on markdown text. E and
  G can only ever be mirrors, at real cost.
- **Reject E as designed.** Every SDD framework surveyed (rlm-mem,
  genkovich/sdd, spec-kit family, OpenSpec, Spec Kitty) keeps
  markdown-in-git as source of truth. Demoting files to a cache trades a
  solved problem (git durability, diff/PR/blame) for an unsolved one
  (live two-way sync: split-brain, staleness, branch-vs-global state).
  If external sync is ever wanted, make it ONE-directional and
  on-demand (export snapshot), matching rlm-mem's own roadmap — never a
  continuous authority swap. E, if pursued, needs its OWN PRD.
- **The claude-mem server-beta note in CLAUDE.md does NOT anticipate
  E.** It is a tool-name migration (`search`→`observation_search`) plus
  a statusline endpoint change — not a file-content sync design. Do not
  build E on that assumption.
- **Reject G as a replacement — it's LESS shareable than the status
  quo.** Native tasks live in `~/.claude/tasks/`, outside the repo, not
  git-trackable, invisible to other clones/collaborators. Legitimate
  only as an in-session ephemeral execution mirror layered ON TOP of the
  git-tracked checklist, never instead of it.
- **"Poor search" is overstated.** Content search already routes through
  claude-mem semantic search (prd/tech-design/tasks commands call it
  before touching the filesystem). The real narrow gap is
  STRUCTURED-STATUS query ("find all task lists still `[ ]`-heavy"),
  which F targets precisely — no bigger migration needed.
- **Durability-vs-git is a BRANCH-HYGIENE problem, not a storage
  problem.** The real complaint ("don't want half-finished planning in
  git") is solved by feature branches / commit-discipline / a
  gitignored `drafts/` subfolder — commit freely to a private branch,
  gate merge-to-main on completion. Reaching for an external store adds
  a failure surface without touching the actual complaint.
- **Naming: rename `tasks/` → `specs/`** (`specs/NNN-FEATURE-NAME/`).
  "spec" is the term the AI-SDD tooling consistently uses (genkovich/sdd
  `docs/features/<slug>/spec.md`). Reserve "task"/"subtask" strictly for
  checklist items. The collision is COSMETIC (no bug found from it), so
  low urgency — but do it atomically in ONE commit, not phased.

**F, scoped down (both passes agree):**

- Adopt YAML frontmatter for PARENT-STORY rollup status only
  (`status: draft|approved|in-progress|done`, owner, id) — additive,
  yq-queryable.
- NEVER move per-subtask `[ ]/[~]/[X]` or evidence notes out of the
  markdown body — that co-location IS the mechanism `impl.md` and
  `start.md` depend on. Splitting it creates a dual-source-of-truth.
- Frontmatter suits SCALARS. If cross-spec DEPENDENCY-GRAPH queries are
  ever needed, use a companion `tasks.json`/`deps.json` per spec — do
  NOT cram a DAG into frontmatter, and do NOT build it speculatively.
- Markdown is already ~15% cheaper in tokens than JSON/XML (Headroom) —
  F fits the cheap-to-load goal; heavier formats fight it.

## Blast radius (internal pass, for the rename)

- 15 files reference `tasks/`. Hooks/bin reference it only in COMMENTS
  (`# See: tasks/...`) — no runtime logic keyed on the path.
- Only executable dependency: `Glob tasks/**/*-tasks.md` in 3 files
  (start.md, check.md, wrapup.md) — trivially find-and-replaceable.
- A rename is a single-commit `git mv` + 15-file update, BUT breaks
  external GitHub bookmarks to `tasks/NNN.../*.md` and stales historical
  claude-mem observations that embed the old path. Note that in the
  commit body.
- `[ ]/[~]/[X]` is load-bearing for exactly ONE consumer found:
  start.md's 80%-done compaction. NOT used by the 046/047 conclusion
  harness (that parses `<!-- CHECKLIST -->` blocks and `<Rule>-check:`
  artifacts in conversation, unrelated to file markers).

## Current lean (not decided)

1. Keep git-tracked markdown as sole source of truth.
2. Adopt F scoped to parent-story rollup status (additive frontmatter).
3. Solve durability-vs-git narrowly (branch hygiene / gitignored drafts
   convention), not a sync layer.
4. Rename `tasks/` → `specs/` as a low-urgency single-commit cleanup;
   reserve task/subtask for checklist items.
5. E (external sync) and G (native Task tools) are, at most, thin
   optional complements later — each with its own PRD if it matters.

## Pointers

- Convention: `CLAUDE.md` "Task Marking Convention"; enforcement in
  `plugin/commands/impl.md` ("Task Completion Rules", evidence notes).
- Commands: `plugin/commands/{prd,tech-design,tasks,impl,start}.md`
- Compaction dependency: `start.md` Step 3 (80%-done rule)
- server-beta note: `CLAUDE.md` "Claude-Mem Integration → Runtime"
