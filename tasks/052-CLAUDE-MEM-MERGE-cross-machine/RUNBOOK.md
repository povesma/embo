# Runbook: merge two claude-mem databases (no paid sync)

Combine the claude-mem memory of an **OLD** machine into a **THIS**
machine (the destination), keeping both machines' observations. No
cmem.ai Pro subscription required.

Verified against claude-mem plugin **13.13.1** (the `memory_session_id`
string-FK schema). If your plugin version differs, re-check the schema
first: `sqlite3 ~/.claude-mem/claude-mem.db ".schema" `.

## What gets merged / what does not

| Merged | Not merged (intentionally) |
|---|---|
| `sdk_sessions`, `observations`, `session_summaries`, `user_prompts` | `sync_*` tables, `schema_versions`, `pending_messages` (transient) |
| FTS5 search index (auto-rebuilt by triggers on insert) | ChromaDB vectors — rebuilt after the merge (keyed by old ids) |

Dedup keys: sessions by `memory_session_id`; observations by
`(memory_session_id, content_hash)` (falls back to
`memory_session_id + title + created_at_epoch` when `content_hash` is
NULL); summaries by `memory_session_id + created_at_epoch + prompt_number`;
prompts by `content_session_id + prompt_number`. Re-running the merge is
safe — already-present rows are skipped.

## Step 1 — Stop the worker on BOTH machines

A live worker holds a write lock and may be mid-write. On each machine:

```bash
npx --yes claude-mem stop
pkill -f worker-service.cjs   # belt-and-suspenders; ignore "no process"
pkill -f chroma-mcp
```

## Step 2 — Bring the OLD machine's DB to THIS machine

On the OLD machine, copy its database file (WAL included — checkpoint
first so all writes are in the main file):

```bash
sqlite3 ~/.claude-mem/claude-mem.db "PRAGMA wal_checkpoint(TRUNCATE);"
cp ~/.claude-mem/claude-mem.db /tmp/old-claude-mem.db
```

Transfer `/tmp/old-claude-mem.db` to THIS machine (USB / scp / AirDrop)
into `~/cm_merge/old.db`.

## Step 3 — Back up THIS machine's DB and work on a COPY

Never merge into the live file directly.

```bash
mkdir -p ~/cm_merge
sqlite3 ~/.claude-mem/claude-mem.db "PRAGMA wal_checkpoint(TRUNCATE);"
cp ~/.claude-mem/claude-mem.db ~/cm_merge/dest.db          # working copy
cp ~/.claude-mem/claude-mem.db ~/cm_merge/dest.backup.db   # safety backup
```

## Step 4 — Dry run, then merge

```bash
# preview — writes nothing:
python3 merge_claude_mem.py --src ~/cm_merge/old.db --dest ~/cm_merge/dest.db --dry-run

# if the counts look right, perform the merge on the working copy:
python3 merge_claude_mem.py --src ~/cm_merge/old.db --dest ~/cm_merge/dest.db

# verify the merged copy:
python3 merge_claude_mem.py --dest ~/cm_merge/dest.db --verify-only
```

`--verify-only` must report `foreign_key_check OK` and
`integrity_check ok`. If it does not, stop and keep the backup.

## Step 5 — Install the merged DB

```bash
# remove stale WAL/SHM sidecars from the live location, then swap in the merged file
rm -f ~/.claude-mem/claude-mem.db-wal ~/.claude-mem/claude-mem.db-shm
cp ~/cm_merge/dest.db ~/.claude-mem/claude-mem.db
```

## Step 6 — Rebuild the ChromaDB vector store

The vectors are keyed by the OLD integer ids (`obs_{id}_narrative`,
etc.), which the merge re-assigned. The two vector stores cannot be
file-merged. Clear and rebuild:

```bash
rm -rf ~/.claude-mem/vector-db ~/.claude-mem/chroma
npx --yes claude-mem start          # restart worker
npx --yes claude-mem doctor         # confirm bun/uv/worker healthy
```

Embeddings are computed **locally** by onnxruntime (the default
all-MiniLM model) — the rebuild costs CPU time, **no API tokens**.

> OPEN ITEM (verify live): the exact trigger that repopulates the vector
> store in 13.13.1 is not yet confirmed. Candidates: the worker backfills
> missing vectors on startup / first search, or a manual backfill is
> needed. After Step 6, run a semantic search and check it returns
> old-machine observations:
> `npx --yes claude-mem search "something only the old machine knew"`.
> If semantic results are empty while FTS results appear, a manual
> backfill is required — see SEED.md "Open items".

## Step 7 — Confirm

```bash
sqlite3 ~/.claude-mem/claude-mem.db \
  "SELECT 'observations', COUNT(*) FROM observations
   UNION ALL SELECT 'sessions', COUNT(*) FROM sdk_sessions;"
npx --yes claude-mem status
```

Counts should equal (this machine's originals) + (old machine's
non-duplicate rows). Keep `~/cm_merge/dest.backup.db` until you have
used the merged memory for a few sessions and are satisfied.

## Rollback

```bash
npx --yes claude-mem stop
cp ~/cm_merge/dest.backup.db ~/.claude-mem/claude-mem.db
rm -rf ~/.claude-mem/vector-db ~/.claude-mem/chroma
npx --yes claude-mem start
```
