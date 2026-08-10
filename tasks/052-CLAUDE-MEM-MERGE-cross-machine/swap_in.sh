#!/usr/bin/env bash
# Install the merged claude-mem database on THIS machine (Direction A:
# this machine is the base, the other machine's data is merged in).
#
# RUN THIS FROM A PLAIN TERMINAL WITH CLAUDE CODE FULLY QUIT.
# The claude-mem worker auto-restarts from Claude Code hooks on every tool
# call, so the swap cannot be done safely from inside a live session — the
# worker holds the DB's WAL open and would race the file swap.
#
# It does a FRESH merge at run time (captures the latest local observations),
# verifies, backs everything up, then swaps and moves the vector store aside
# so the worker rebuilds embeddings locally (free) on next start.
#
# Usage (from the repo root):
#   bash tasks/052-CLAUDE-MEM-MERGE-cross-machine/swap_in.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERGE_PY="$HERE/merge_claude_mem.py"
STAGE="$HERE/../../tmp/cm_merge"          # created earlier; holds old.db
OLD_DB="$STAGE/old.db"                      # the other machine's db (source)
LIVE="$HOME/.claude-mem/claude-mem.db"
CHROMA_DIR="$HOME/.claude-mem/chroma"
CHROMA_STATE="$HOME/.claude-mem/chroma-sync-state.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "[*] merge script : $MERGE_PY"
echo "[*] source db    : $OLD_DB"
echo "[*] live db      : $LIVE"

# 1. Refuse to run if a worker is up (it would race the swap).
if command -v npx >/dev/null 2>&1; then
  if npx --yes claude-mem status 2>/dev/null | grep -q "Worker is running"; then
    echo "[!] claude-mem worker is RUNNING. Quit Claude Code / editors and try again."
    echo "    (npx claude-mem stop is not enough inside a live session — hooks respawn it.)"
    exit 1
  fi
fi
# also fail if the worker port answers
if curl -s "http://127.0.0.1:37701/api/sync/status" >/dev/null 2>&1; then
  echo "[!] Something is answering on the worker port 37701. Ensure the worker is down."
  exit 1
fi

[ -f "$OLD_DB" ]  || { echo "[!] source db not found: $OLD_DB"; exit 1; }
[ -f "$LIVE" ]    || { echo "[!] live db not found: $LIVE"; exit 1; }

# 2. Fresh working copy of the live db + safety backup.
WORK="$STAGE/merged-$STAMP.db"
BACKUP="$STAGE/live-pre-swap-$STAMP.db"
echo "[*] backing up live db -> $BACKUP"
sqlite3 "$LIVE" ".backup $BACKUP"
cp "$BACKUP" "$WORK"

# 3. Merge the other machine's data into the working copy.
echo "[*] merging..."
python3 "$MERGE_PY" --src "$OLD_DB" --dest "$WORK"

# 4. Verify.
echo "[*] verifying..."
python3 "$MERGE_PY" --dest "$WORK" --verify-only

# 5. Swap in. Keep the current live db as an extra backup, then install.
cp "$LIVE" "$STAGE/live-replaced-$STAMP.db" 2>/dev/null || true
rm -f "$LIVE-wal" "$LIVE-shm"
cp "$WORK" "$LIVE"
echo "[+] installed merged db at $LIVE"

# 6. Move the vector store aside (reversible) to force a clean local re-embed.
if [ -d "$CHROMA_DIR" ]; then
  mv "$CHROMA_DIR" "$HOME/.claude-mem/chroma.pre-merge-$STAMP.bak"
  echo "[+] moved chroma/ aside -> chroma.pre-merge-$STAMP.bak"
fi
[ -f "$CHROMA_STATE" ] && mv "$CHROMA_STATE" "$HOME/.claude-mem/chroma-sync-state.pre-merge-$STAMP.json" || true

echo
echo "[DONE] Merged database installed. Backups in $STAGE and ~/.claude-mem/*.pre-merge-$STAMP.*"
echo "Next:"
echo "  1) Relaunch Claude Code (the worker will start and begin embedding)."
echo "  2) Re-embedding ~34k observations locally takes ~10-30 min (free, CPU)."
echo "  3) Verify semantic search:  npx claude-mem search \"something only the other machine knew\""
echo "  4) Once satisfied, delete ~/.claude-mem/chroma.pre-merge-$STAMP.bak and $STAGE."
echo
echo "Rollback:  cp \"$BACKUP\" \"$LIVE\" && rm -rf \"$CHROMA_DIR\" && mv ~/.claude-mem/chroma.pre-merge-$STAMP.bak \"$CHROMA_DIR\""
