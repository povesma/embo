# 052: Merge two claude-mem databases across machines (no paid sync)

**Status**: Seed. Merge script + runbook drafted; not yet run end-to-end
against a real second machine. ChromaDB rebuild trigger unverified.
**Origin**: 2026-08-10. A design/task worktree was done on another
computer; its claude-mem observations live only in that machine's local
DB. Goal: combine both machines' memory without the cmem.ai Pro
subscription.
**Priority**: medium — personal-workflow utility; candidate to become a
shipped embo command if it proves out.

## Problem

claude-mem stores everything locally in `~/.claude-mem/claude-mem.db`
(SQLite) plus an optional local ChromaDB vector store for semantic
search. Working across two machines produces two isolated databases.
The only first-party cross-machine path is the paid cmem.ai Pro SyncHub;
there is no installed, schema-current free merge tool.

## Verified findings (this session)

Confirmed against the LIVE db and installed plugin 13.13.1 — not from
memory or the deep-research report (which was wrong on several points):

- **IDs are `INTEGER AUTOINCREMENT`** on all four core tables → collide
  across machines; cannot carry source ids across.
- **observations / session_summaries link to sessions by the STRING
  `memory_session_id`** (FK, `ON UPDATE CASCADE`), NOT the integer id.
  So those rows merge with a fresh id and the string FK stays valid —
  no integer remap needed. (The deep report claimed `sdk_session_id`
  and invented `observation_files` / `observation_concepts` child
  tables — neither exists. `files_read` / `concepts` are JSON text
  columns on `observations`.)
- **user_prompts link by integer `session_db_id` -> sdk_sessions(id)** →
  this one table needs the FK re-resolved via `content_session_id`.
- **Dedup keys** (real UNIQUE indexes / natural keys): sessions
  `memory_session_id`; observations `(memory_session_id, content_hash)`;
  prompts `(content_session_id, prompt_number)`; summaries have no
  natural UNIQUE (dedup on `memory_session_id + created_at_epoch +
  prompt_number`).
- **The built-in multi-device sync scaffolding is unusable offline.**
  Columns `origin_device_id` / `origin_local_id` / `sync_rev` and the
  `sync_*` tables exist, but `origin_device_id` is NULL on all 2129 obs
  and 649 prompts here (never populated without the hub), and the apply
  path is hub-driven. `sync_outbox` had 3458 queued ops that never
  drained.
- **No installed free sync/export tool.** The plugin package ships only
  hook runtime deps. The published `claude-mem` CLI (v13.14.0) exposes
  no `sync` / `export` / `import` command. The maintainer (Discussion
  #488, Dec 2025) said the old export/import scripts "need updating
  since we changed table names" — i.e. stale against `memory_session_id`.
- **ChromaDB rebuild is free.** Embeddings run via local `onnxruntime`
  (default all-MiniLM); `CHROMA_MODE=local`, no embedding API key. A
  rebuild costs CPU only, no tokens. Vectors are keyed `obs_{id}_*`, so
  they cannot be file-merged and must be rebuilt after the SQLite merge.

## Deliverables in this folder

- `merge_claude_mem.py` — SQLite merge: dynamic-column copy (excludes
  `id`), natural-key dedup, user_prompts FK re-resolution, `--dry-run`
  and `--verify-only` (foreign_key_check + integrity_check).
- `RUNBOOK.md` — full procedure for both machines: stop workers, copy
  DB, back up, dry-run, merge, verify, swap in, rebuild Chroma, confirm,
  rollback.

## Real-run results (2026-08-10)

Merged a real second machine's DB (`2nd-mac/.claude-mem/claude-mem.db`,
schema v49: 7680 sessions / 32385 obs / 10195 summaries / 22425 prompts)
into a COPY of this machine's live DB. Result: all imported, 0 skipped
(disjoint projects), **0 unlinked prompts** (FK remap worked), totals
exact (7722 / 34564 / 10256 / 23079), `integrity_check ok`, FTS index
complete (34564 = obs count, keyword MATCH returns hits).

Two things the real run caught that the schema check had not:
- **Schema drift**: source `session_summaries` has a `discovery_tokens`
  column this machine lacks. Fixed the script to insert only the
  column INTERSECTION and report dropped columns (no silent truncation).
- **The `--dry-run` "unlinked" count is an artifact** (sessions aren't
  inserted in dry-run, so prompt->session lookup finds nothing). The real
  run showed 0 unlinked.

## The swap must run OUTSIDE a live Claude Code session

The claude-mem worker **auto-restarts from Claude Code hooks on every tool
call** — `npx claude-mem stop` inside a session is undone within seconds
(observed: uptime 8s right after stop). The worker holds the DB's WAL open,
so swapping the file in-session risks corruption. Therefore the swap is
packaged as `swap_in.sh`, to be run from a plain terminal with Claude Code
quit; it refuses to run if a worker/port is detected.

Real ChromaDB store dir on macOS is **`~/.claude-mem/chroma/`** (contains
`chroma.sqlite3` + HNSW collection dir), NOT `vector-db/` (the research
report's path — absent here). Chosen rebuild strategy: **full re-embed** —
move `chroma/` + `chroma-sync-state.json` aside and let the worker rebuild
locally (onnxruntime, free) on next start. This sidesteps the count-based
`chroma-sync-state.json` ledger, which is unreliable across a merge.

## Deliverables in this folder (updated)

- `merge_claude_mem.py` — merge with column-intersection, natural-key
  dedup, user_prompts FK re-resolution, `--dry-run`, `--verify-only`.
- `swap_in.sh` — run OUTSIDE a session: fresh re-merge + verify + backup +
  swap + move chroma aside; refuses if a worker is up; prints rollback.
- `RUNBOOK.md` — narrative procedure (note: `chroma/` not `vector-db/`).

## Open items (before this can be called done)

1. **Run `swap_in.sh` for real** with Claude Code quit, then confirm the
   worker re-embeds and semantic search returns other-machine content.
   The merge itself is verified; only the live swap + re-embed remain.
   [verify: manual-run]
2. **Confirm the ChromaDB rebuild trigger in 13.13.1.** Unknown whether
   the worker backfills missing vectors on startup/first-search or a
   manual backfill is required. Test: after Step 6, run a semantic
   search for old-machine-only content; if FTS finds it but semantic
   does not, a manual backfill script (local onnxruntime, collection
   name to confirm) is needed. [verify: manual-run]
3. **Decide whether to productize** as `/embo:*` command or a
   `plugin/bin/` helper once proven. Would need the version-drift guard
   (re-check schema before merging) baked in.

## Related

- claude-mem `cloud-sync` skill (the paid path we are avoiding).
- NotebookLM research notebook `a53b244d-77d9-42ef-a117-53cd4c53b27e`
  ("Merging two claude-mem databases without paid sync").
- Schema source of truth: `sqlite3 ~/.claude-mem/claude-mem.db ".schema"`.
