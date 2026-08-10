#!/usr/bin/env python3
"""
Merge one claude-mem SQLite database into another, without the paid
cmem.ai SyncHub. Verified against claude-mem plugin 13.13.1 schema
(the `memory_session_id` string-FK schema, post table-rename).

WHAT IT DOES
  Copies sessions, observations, session_summaries and user_prompts
  from a SOURCE db into a DEST db, de-duplicating by natural keys and
  letting the DEST assign fresh integer ids. It never carries a source
  integer `id` across (they auto-increment from 1 on both machines and
  would collide).

WHY IT IS SAFE ON IDs
  - observations / session_summaries link to their session by the STRING
    column `memory_session_id` (FK, ON UPDATE CASCADE). So inserting them
    with a fresh integer id keeps the parent link intact as long as the
    parent session row exists in DEST with the same memory_session_id.
  - user_prompts link by the INTEGER `session_db_id` -> sdk_sessions(id).
    That integer differs in DEST, so this script re-resolves it via the
    string `content_session_id`.

WHAT IT DOES NOT TOUCH
  - The FTS5 virtual tables: they are kept in sync by INSERT triggers, so
    every row this script inserts is indexed automatically.
  - The sync_* tables and schema_versions: device/sync-local state; merging
    them would corrupt sync bookkeeping.
  - ChromaDB: vectors are keyed by the OLD integer id (obs_{id}_*), so they
    cannot be carried across. Rebuild the vector store after the merge
    (see RUNBOOK.md) — with local onnxruntime embeddings this is free.

USAGE
  # preview only, writes nothing:
  python3 merge_claude_mem.py --src /path/source.db --dest /path/dest.db --dry-run
  # perform the merge (operate on a COPY of dest, never the live file):
  python3 merge_claude_mem.py --src /path/source.db --dest /path/dest.db
  # verify an already-merged db:
  python3 merge_claude_mem.py --dest /path/dest.db --verify-only
"""

import argparse
import os
import sqlite3
import sys


CORE_TABLES = ["sdk_sessions", "observations", "session_summaries", "user_prompts"]


def columns(cur, table):
    cur.execute(f"PRAGMA table_info({table})")
    return [r[1] for r in cur.fetchall()]


def table_exists(cur, table):
    cur.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
    )
    return cur.fetchone() is not None


def insert_without_id(dest_cur, table, cols, row, overrides=None):
    """Insert a row copying all columns except `id`, applying overrides.

    Only columns that also exist in the DEST table are inserted; source-only
    columns (schema drift between machines) are dropped. Use report_dropped_cols()
    up front so the drop is not silent.
    """
    overrides = overrides or {}
    dest_cols = set(columns(dest_cur, table))
    use_cols = [c for c in cols if c != "id" and c in dest_cols]
    values = []
    for c in use_cols:
        if c in overrides:
            values.append(overrides[c])
        else:
            values.append(row[c])
    placeholders = ", ".join(["?"] * len(use_cols))
    collist = ", ".join(use_cols)
    dest_cur.execute(
        f"INSERT INTO {table} ({collist}) VALUES ({placeholders})", values
    )


def merge_sessions(src_cur, dest_cur, dry_run):
    cols = columns(src_cur, "sdk_sessions")
    src_cur.execute("SELECT * FROM sdk_sessions")
    src_cur.row_factory = sqlite3.Row
    rows = [dict(zip(cols, r)) for r in src_cur.fetchall()]
    imported = skipped = 0
    for row in rows:
        msid = row.get("memory_session_id")
        exists = None
        if msid is not None:
            dest_cur.execute(
                "SELECT id FROM sdk_sessions WHERE memory_session_id = ?", (msid,)
            )
            exists = dest_cur.fetchone()
        if exists is None:
            dest_cur.execute(
                "SELECT id FROM sdk_sessions WHERE platform_source = ? AND content_session_id = ?",
                (row.get("platform_source"), row.get("content_session_id")),
            )
            exists = dest_cur.fetchone()
        if exists:
            skipped += 1
            continue
        if not dry_run:
            insert_without_id(dest_cur, "sdk_sessions", cols, row)
        imported += 1
    return imported, skipped


def merge_observations(src_cur, dest_cur, dry_run):
    cols = columns(src_cur, "observations")
    src_cur.execute("SELECT * FROM observations")
    rows = [dict(zip(cols, r)) for r in src_cur.fetchall()]
    imported = skipped = 0
    for row in rows:
        msid = row.get("memory_session_id")
        chash = row.get("content_hash")
        if chash is not None:
            dest_cur.execute(
                "SELECT id FROM observations WHERE memory_session_id = ? AND content_hash = ?",
                (msid, chash),
            )
        else:
            # content_hash NULL: the UNIQUE index cannot dedup NULLs, so
            # fall back to a content-identity triple.
            dest_cur.execute(
                "SELECT id FROM observations WHERE memory_session_id = ? "
                "AND IFNULL(title,'') = IFNULL(?, '') AND created_at_epoch = ?",
                (msid, row.get("title"), row.get("created_at_epoch")),
            )
        if dest_cur.fetchone():
            skipped += 1
            continue
        if not dry_run:
            # reset per-device sync bookkeeping so merged rows look local/unsynced
            insert_without_id(
                dest_cur, "observations", cols, row,
                overrides={"synced_at": None, "origin_device_id": None,
                           "origin_local_id": None, "sync_rev": "1"},
            )
        imported += 1
    return imported, skipped


def merge_summaries(src_cur, dest_cur, dry_run):
    cols = columns(src_cur, "session_summaries")
    src_cur.execute("SELECT * FROM session_summaries")
    rows = [dict(zip(cols, r)) for r in src_cur.fetchall()]
    imported = skipped = 0
    for row in rows:
        # No natural UNIQUE besides origin; dedup on a content-identity triple.
        dest_cur.execute(
            "SELECT id FROM session_summaries WHERE memory_session_id = ? "
            "AND created_at_epoch = ? AND IFNULL(prompt_number,-1) = IFNULL(?, -1)",
            (row.get("memory_session_id"), row.get("created_at_epoch"),
             row.get("prompt_number")),
        )
        if dest_cur.fetchone():
            skipped += 1
            continue
        if not dry_run:
            insert_without_id(
                dest_cur, "session_summaries", cols, row,
                overrides={"synced_at": None, "origin_device_id": None,
                           "origin_local_id": None, "sync_rev": "1"},
            )
        imported += 1
    return imported, skipped


def merge_prompts(src_cur, dest_cur, dry_run):
    cols = columns(src_cur, "user_prompts")
    src_cur.execute("SELECT * FROM user_prompts")
    rows = [dict(zip(cols, r)) for r in src_cur.fetchall()]
    imported = skipped = unlinked = 0
    for row in rows:
        csid = row.get("content_session_id")
        pnum = row.get("prompt_number")
        dest_cur.execute(
            "SELECT id FROM user_prompts WHERE content_session_id = ? AND prompt_number = ?",
            (csid, pnum),
        )
        if dest_cur.fetchone():
            skipped += 1
            continue
        # Re-resolve the integer session FK via the string content_session_id.
        dest_cur.execute(
            "SELECT id FROM sdk_sessions WHERE content_session_id = ? ORDER BY id LIMIT 1",
            (csid,),
        )
        sess = dest_cur.fetchone()
        new_session_db_id = sess[0] if sess else None
        if new_session_db_id is None:
            unlinked += 1
        if not dry_run:
            insert_without_id(
                dest_cur, "user_prompts", cols, row,
                overrides={"session_db_id": new_session_db_id,
                           "synced_at": None, "origin_device_id": None,
                           "origin_local_id": None, "sync_rev": "1"},
            )
        imported += 1
    return imported, skipped, unlinked


def report_dropped_cols(src_cur, dest_cur):
    """Warn about source columns absent in dest (schema drift) — these are
    dropped on insert. No silent truncation."""
    any_dropped = False
    for t in CORE_TABLES:
        dest_cols = set(columns(dest_cur, t))
        dropped = [c for c in columns(src_cur, t) if c not in dest_cols]
        if dropped:
            any_dropped = True
            print(f"[!] {t}: source columns not in dest, will be DROPPED: {dropped}")
    if not any_dropped:
        print("[*] column schemas match across all core tables.")


def counts(cur):
    out = {}
    for t in CORE_TABLES:
        cur.execute(f"SELECT COUNT(*) FROM {t}")
        out[t] = cur.fetchone()[0]
    return out


def verify(dest_db):
    # NOTE: claude-mem runs with FK enforcement OFF and legitimately stores
    # observations/summaries whose memory_session_id has no session row.
    # So foreign_key_check is INFORMATIONAL (report the orphan count); success
    # is judged by integrity_check only.
    conn = sqlite3.connect(dest_db)
    cur = conn.cursor()
    print(f"[verify] db = {dest_db}")
    for k, v in counts(cur).items():
        print(f"  {k:20} {v}")
    cur.execute("PRAGMA foreign_key_check;")
    fk = cur.fetchall()
    print(f"  foreign_key_check    {len(fk)} orphan row(s) (pre-existing in claude-mem; informational)")
    cur.execute("PRAGMA integrity_check;")
    integ = cur.fetchone()[0]
    print(f"  integrity_check      {integ}")
    conn.close()
    return integ == "ok"


def main():
    ap = argparse.ArgumentParser(description="Merge a claude-mem SQLite db into another.")
    ap.add_argument("--src", help="source db (the other machine's claude-mem.db)")
    ap.add_argument("--dest", required=True, help="destination db (operate on a COPY, not the live file)")
    ap.add_argument("--dry-run", action="store_true", help="report only, write nothing")
    ap.add_argument("--verify-only", action="store_true", help="just run integrity/fk checks on --dest")
    args = ap.parse_args()

    if args.verify_only:
        ok = verify(args.dest)
        sys.exit(0 if ok else 1)

    if not args.src:
        ap.error("--src is required unless --verify-only")
    for p in (args.src, args.dest):
        if not os.path.exists(p):
            ap.error(f"db not found: {p}")

    # FK enforcement stays OFF (SQLite default) to match claude-mem's own
    # behavior — it stores rows whose memory_session_id has no session row,
    # and enforcing here would reject those legitimate rows.
    dest = sqlite3.connect(args.dest)
    dest_cur = dest.cursor()
    src = sqlite3.connect(args.src)  # copy of the other machine's db; we only SELECT
    src_cur = src.cursor()

    for t in CORE_TABLES:
        if not table_exists(src_cur, t) or not table_exists(dest_cur, t):
            print(f"[!] table missing on one side: {t} — schema mismatch, aborting.")
            sys.exit(2)

    print(f"[*] {'DRY RUN — ' if args.dry_run else ''}merging {args.src} -> {args.dest}")
    report_dropped_cols(src_cur, dest_cur)
    print(f"[*] dest before: {counts(dest_cur)}")

    si, sk = merge_sessions(src_cur, dest_cur, args.dry_run)
    print(f"[+] sdk_sessions       imported {si:5}  skipped {sk}")
    oi, ok_ = merge_observations(src_cur, dest_cur, args.dry_run)
    print(f"[+] observations       imported {oi:5}  skipped {ok_}")
    mi, mk = merge_summaries(src_cur, dest_cur, args.dry_run)
    print(f"[+] session_summaries  imported {mi:5}  skipped {mk}")
    pi, pk, pu = merge_prompts(src_cur, dest_cur, args.dry_run)
    print(f"[+] user_prompts       imported {pi:5}  skipped {pk}  (unlinked session: {pu})")

    if args.dry_run:
        dest.rollback()
        print("[*] dry run — no changes written.")
    else:
        dest.commit()
        print(f"[*] dest after:  {counts(dest_cur)}")
        cur = dest.cursor()
        cur.execute("PRAGMA foreign_key_check;")
        fk = cur.fetchall()
        print(f"[*] foreign_key_check: {len(fk)} orphan row(s) (pre-existing in claude-mem; informational)")
    src.close()
    dest.close()


if __name__ == "__main__":
    main()
