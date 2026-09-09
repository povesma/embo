# 065: Session Telemetry Log — Technical Design

**Status**: Draft — reworked post examine-advisor review 2026-09-09
**PRD**: [2026-09-09-065-observability-session-telemetry-log-prd.md](2026-09-09-065-observability-session-telemetry-log-prd.md)
**Created**: 2026-09-09

---

## Overview

Three hook scripts + one bin command implement session-level telemetry
using **per-session JSONL files**. The `Stop` hook is the primary
writer: on each turn it parses the transcript and overwrites this
session's record file (last write wins → the final turn's record is the
complete one). A `SubagentStop` hook accumulates subagent tool counts
that a flat parent-transcript scan cannot see. A `SessionStart` hook
records the start time. An `embo-usage` bin aggregates the per-session
files at read time.

**Architecture history (why this shape).** Two earlier framings were
rejected during review:

1. **PRD's `Stop`-writes-a-shared-file** — abandoned because a shared
   `telemetry.jsonl` with in-place trimming has a read-modify-overwrite
   race that destroys records when two sessions (e.g. two git worktrees,
   a first-class feature on this branch) end near-simultaneously.
2. **First tech-design's `SessionEnd`-as-primary-writer** — abandoned
   because `SessionEnd` runs under a **1.5-second timeout** (a
   transcript parse blows past it → silent cancellation) and **does not
   fire on `max_turns`, SIGKILL, or crash** — exactly the heavy sessions
   most worth measuring. Both facts are documented Claude Code behavior
   (Context7 `/websites/code_claude` hooks docs, 2026-09-09).

**The chosen shape:** `Stop` (600-second budget, fires reliably per
turn) does the heavy work into a **per-session file**
(`.claude/embo_state/telemetry/<session_id>.jsonl`). Per-session files
eliminate the trim race, the concurrent-append corruption (records >4 KB
exceed `PIPE_BUF`), and the O(n) idempotency scan — the filename *is*
the dedup key, and overwriting is inherently idempotent. Retention is
whole-file deletion by age (`find -mtime +90 -delete`), which has no
concurrency hazard.

---

## Current Architecture (verified)

**Verified facts** (re-checked this session against source; the
transcript-schema and event-choice rows were CORRECTED after the first
draft asserted them wrong):

| Claim | Source | Status |
|---|---|---|
| `hooks.json` events present: SessionStart, UserPromptSubmit, SubagentStart, PreToolUse, PostToolUse, Stop | `plugin/hooks/hooks.json` read 2026-09-09 | ✓ |
| No `SessionEnd` or `SubagentStop` entry in `hooks.json` | same | ✓ — SubagentStop needs adding; SessionEnd NOT used |
| **Transcript JSONL shape: each line is `{"message":{"role":..., "content":[...]}}` — selector is `select(.message.role == "assistant")`, content under `.message.content`; there is NO top-level `.type`** | `capture-correction.sh:119-124` read directly 2026-09-09 | ✓ CORRECTED (first draft wrongly used `.type == "assistant"`) |
| `Stop` fires per-turn with a 600 s timeout; fires reliably on normal exits | Context7 `/websites/code_claude` hooks docs 2026-09-09 | ✓ |
| `SessionEnd` fires once per session BUT has a 1.5 s timeout and does not fire on max_turns/SIGKILL/crash | Context7 `/websites/code_claude` hooks docs 2026-09-09 | ✓ — disqualifies it as primary writer |
| Stdin contract for Stop/PostToolUse hooks: `transcript_path`, `session_id`, `hook_event_name` | `capture-correction.sh:12-14,50,54,55` 2026-09-09 | ✓ (Stop confirmed; SessionEnd NOT relied on) |
| Subagent tool calls write to a separate `agent_transcript_path`, invisible to a parent-transcript scan | Context7 / transcript-format prior art 2026-09-09 | ✓ — requires SubagentStop hook |
| `embo-profile get name` needs `yq` (violates NFR-2 stdlib-only) | `plugin/bin/embo-profile:50-55,89` | ✓ — read active-profile file directly instead |
| `.claude/embo_state/` does not exist; covered by existing gitignore | filesystem check + `.gitignore:33` 2026-09-09 | ✓ — created at runtime; no new gitignore entry |
| Worktree resolver: `git rev-parse --path-format=absolute --git-common-dir` | `capture-correction.sh:68-76` 2026-09-09 | ✓ — required in all new hooks and in embo-usage |
| Transcript assistant-text extraction pattern (jq `select(.message.role=="assistant") \| .message.content`) | `capture-correction.sh:119-124` 2026-09-09 | ✓ — reuse selector base for tool_use parse |
| Test harness pattern: synthetic JSONL transcripts, isolated temp dirs, bash assertions | `capture-correction.test.sh` (obs #35699) | ✓ — reuse; ADD a synthetic tool_use fixture (none exists) |

**Existing hooks that define the pattern:**

- `capture-correction.sh` — the closest precedent: reads stdin JSON, resolves the worktree, parses the transcript via `transcript_path` with the correct `.message.role` selector, appends to `.claude/corrections.jsonl`. **This is the file to copy from.**
- `statusline-refresh.sh` — the existing `SessionStart` hook; the new SessionStart writer is a second entry in the same matcher's `hooks` array (the `UserPromptSubmit` precedent), not a merge.

---

## Proposed Design

### Component Map

```
SessionStart ──► embo-telemetry-start.sh
                   writes $TMPDIR/embo-session-<id>.start
                   (Unix epoch integer, not ISO — enables plain
                    integer subtraction, no cross-platform date parse)

Stop         ──► embo-telemetry-write.sh         (PRIMARY writer, per turn)
                   reads transcript_path + session_id from stdin
                   resolves .claude/ via worktree resolver
                   parses transcript (correct .message.role selector)
                   merges subagent counts from the sidecar (below)
                   OVERWRITES .claude/embo_state/telemetry/<id>.jsonl
                   (last turn wins → final record is complete;
                    overwrite is inherently idempotent, no scan)

SubagentStop ──► embo-telemetry-subagent.sh      (accumulator)
                   reads agent_transcript_path + session_id from stdin
                   counts subagent tool_use entries
                   appends to sidecar
                   .claude/embo_state/telemetry/<id>.sub

embo-usage   ──► plugin/bin/embo-usage           (reader CLI)
                   resolves main-tree .claude/ (worktree-safe)
                   aggregates all <id>.jsonl files at read time
                   renders table / --json / --stats
```

### New Components

**1. `plugin/hooks/embo-telemetry-start.sh`**
- **Event**: `SessionStart` (second entry in the existing matcher's `hooks` array, beside `statusline-refresh.sh`)
- **Purpose**: Record session start time for duration calculation
- **Input**: stdin JSON, `session_id`
- **Output**: `$TMPDIR/embo-session-<session_id>.start` containing a **Unix epoch integer** (`date -u +%s`) — integer form avoids all cross-platform ISO parsing
- **Failure mode**: If `session_id` is absent/empty, skip silently; exit 0

**2. `plugin/hooks/embo-telemetry-write.sh`** (primary writer)
- **Event**: `Stop` (600 s budget, fires reliably per turn)
- **Purpose**: Parse transcript, merge subagent counts, overwrite this session's record
- **Input**: stdin JSON, `session_id`, `transcript_path`
- **Processing sequence**:
  1. Read `session_id`, `transcript_path` from stdin (`capture-correction.sh:50-55` pattern)
  2. Guard: if `transcript_path` is missing or zero bytes, write a minimal record (`tool_call_count: null`, `status: "transcript_unavailable"`) and exit 0
  3. Resolve `.claude/` to the main tree via the worktree resolver (`capture-correction.sh:68-76`)
  4. `mkdir -p .claude/embo_state/telemetry/`
  5. Parse the transcript with the CORRECT selector (`select(.message.role == "assistant")`, content under `.message.content`) — see parse block below
  6. Merge subagent counts: sum any `.claude/embo_state/telemetry/<session_id>.sub` records into `tool_breakdown`
  7. Compute duration: primary = transcript last-minus-first message epoch; fallback = `$TMPDIR/embo-session-<id>.start`; else `null`
  8. Read active profile WITHOUT `yq`: grep `name:` from `~/.claude/active-profile.yaml`, default `"default"`, hard-fallback `"unknown"` — never call `embo-profile` (yq dependency violates NFR-2)
  9. Compose the record and **overwrite** `<session_id>.jsonl` (`> file`, not `>>`) — the last turn's record supersedes earlier turns; overwriting the session's own file is inherently idempotent
- **Exit**: Always 0; errors to stderr, never propagated

**3. `plugin/hooks/embo-telemetry-subagent.sh`** (subagent accumulator)
- **Event**: `SubagentStop` (separate adequate timeout budget)
- **Purpose**: Capture tool calls that subagents make in their OWN transcript, invisible to the parent scan
- **Input**: stdin JSON, `session_id`, `agent_transcript_path`
- **Processing**: parse `agent_transcript_path` for `tool_use` entries (same selector); append a `{tool: count}` fragment to `.claude/embo_state/telemetry/<session_id>.sub`
- **Rationale**: without this, `tool_breakdown` systematically undercounts — embo spawns RLM, test, and examine subagents constantly, so the omission is large, not marginal
- **Cleanup**: the `.sub` sidecar is removed by the retention sweep alongside the session's `.jsonl`

**4. `plugin/bin/embo-usage`** (reader CLI)
- **Location**: `plugin/bin/embo-usage` (follows `embo-profile`, `embo-tokens`)
- **Language**: Python stdlib
- **Path resolution**: resolve the main-tree `.claude/` via `subprocess` `git rev-parse --path-format=absolute --git-common-dir` (do NOT rely on cwd) — same logic as the hooks, in Python
- **Behaviour**: glob `telemetry/*.jsonl`, read one record per file, aggregate in memory
- **Flags**: default table (date, short session-ID, profile, duration, tool calls, top commands); `--last N`; `--profile <name>`; `--stats` (totals, mean/median tool calls, profile distribution); `--json` (stats as a JSON object for `/embo:retro`)

### Modified Components

**`plugin/hooks/hooks.json`**
- Add `embo-telemetry-start.sh` as a **second entry in the existing `SessionStart` matcher's `hooks` array** (parallel to `statusline-refresh.sh` — the `UserPromptSubmit` two-hook precedent), not a new array element
- Add a new `Stop` entry for `embo-telemetry-write.sh` (the existing `Stop` runs `capture-correction.sh`; add ours in the same matcher's `hooks` array)
- Add a new `SubagentStop` matcher for `embo-telemetry-subagent.sh`
- No `SessionEnd` entry — deliberately not used (1.5 s budget, unreliable on abnormal exits)
- No existing entries removed or changed

### Data Contract

**Per-session file: `.claude/embo_state/telemetry/<session_id>.jsonl`** (one JSON object, overwritten each turn):

```json
{
  "schema": 1,
  "ts": "2026-09-09T01:58:00Z",
  "session_id": "abc12345-...",
  "profile": "default",
  "duration_s": 2847,
  "duration_source": "transcript",
  "tool_call_count": 43,
  "failed_calls": 3,
  "tool_breakdown": {"Bash": 18, "Read": 12, "Write": 5, "mcp__plugin_claude-mem_mcp-search__search": 8},
  "commands": ["start", "prd", "research:examine"],
  "status": "ok"
}
```

**Field definitions:**

| Field | Type | Notes |
|---|---|---|
| `schema` | int | `1`; increment on any structural change (safe field addition since consumers filter by it) |
| `ts` | string | ISO-8601 UTC at last write |
| `session_id` | string | From stdin; also the filename stem |
| `profile` | string | From `~/.claude/active-profile.yaml` `name:` field; `"default"` when unset, `"unknown"` on read failure |
| `duration_s` | int\|null | Elapsed seconds; null if no source available |
| `duration_source` | string | `"transcript"` (primary) \| `"start_file"` (fallback) \| `"null"` |
| `tool_call_count` | int\|null | Count of `tool_use` entries (parent + subagents); null if transcript unavailable |
| `failed_calls` | int | Count of tool results with `is_error: true` — retries inflate raw counts, so they are tracked separately, not folded into `tool_call_count` |
| `tool_breakdown` | object | `{tool_name: count}` merged from parent transcript + subagent sidecars |
| `commands` | array | embo command names from Bash `tool_input.command` |
| `status` | string | `"ok"` \| `"transcript_unavailable"` |

**Transcript parse (jq — CORRECTED selector; verified against `capture-correction.sh:119-124`):**

```bash
# tool_call_count (parent transcript; NON-error tool_use entries)
jq -c 'select(.message.role == "assistant")
       | .message.content[]? | select(.type == "tool_use")' \
  "$TRANSCRIPT_PATH" | wc -l

# per-tool breakdown
jq -r 'select(.message.role == "assistant")
       | .message.content[]? | select(.type == "tool_use") | .name' \
  "$TRANSCRIPT_PATH" | sort | uniq -c

# failed calls (tool_result blocks with is_error true)
jq -c 'select(.message.role == "user")
       | .message.content[]? | select(.type == "tool_result" and .is_error == true)' \
  "$TRANSCRIPT_PATH" | wc -l

# embo commands from Bash tool calls
jq -r 'select(.message.role == "assistant")
       | .message.content[]? | select(.type == "tool_use" and .name == "Bash")
       | .input.command' "$TRANSCRIPT_PATH" 2>/dev/null |
  grep -oE '/embo:[a-z:]+|embo-[a-z-]+' | sort -u   # bin form has no leading slash
```

**First subtask before shipping:** add a synthetic `tool_use` block to the test fixture — `capture-correction.test.sh` fixtures contain only `text` blocks, so the `tool_use` path has never been exercised. Confirm the exact `tool_use` / `tool_result` shape against a real Claude Code transcript before finalising the `is_error` and `.input.command` selectors.

### Retention Strategy (per-session files, age-based deletion)

No in-file trimming — each session owns one file, so there is no shared-file
write race and no trim step. A sweep deletes old files:

```bash
find .claude/embo_state/telemetry/ -type f -mtime +90 -delete
```

Run the sweep opportunistically at the top of the `Stop` writer (cheap;
`find` over a small directory). Whole-file deletion has no concurrency
hazard: a file being deleted is either a completed prior session or gone,
never the one being written this session.

### Idempotency (no scan needed)

The per-session-file design makes idempotency structural: the `Stop`
writer **overwrites** `<session_id>.jsonl` each turn (`> file`). A second
write for the same session replaces, never duplicates. No full-file scan,
no `mkdir` sentinel, no dedup logic. The last turn's record is the
authoritative one.

### Duration (transcript-primary)

```
SessionStart hook (epoch integer, no ISO parsing):
  SESSION_ID=$(jq -r '.session_id // ""' <<< "$INPUT")
  [ -n "$SESSION_ID" ] && date -u +%s > "$TMPDIR/embo-session-${SESSION_ID}.start"

Stop writer:
  # Primary: transcript first/last message epoch delta
  FIRST=$(jq -r 'select(.timestamp) | .timestamp' "$TRANSCRIPT_PATH" | head -1)
  LAST=$(jq -r 'select(.timestamp) | .timestamp' "$TRANSCRIPT_PATH" | tail -1)
  # (parse both to epoch via python3 stdlib datetime.fromisoformat, subtract)
  # duration_source = "transcript"
  #
  # Fallback if transcript timestamps unavailable:
  #   read $TMPDIR/embo-session-<id>.start (epoch int), subtract from now
  #   duration_source = "start_file"
  # Else duration_s = null, duration_source = "null"
```

The transcript is the authoritative source (it always exists when the
`Stop` hook fires and survives machine sleep/restart, unlike `$TMPDIR`).
`duration_s` then means "elapsed since first user message" — an acceptable
approximation for profile comparison. All ISO-to-epoch math is done in
`python3` (`datetime.fromisoformat`), never with `date -d`/`-jf`, which
differ across GNU and BSD.

SessionEnd hook:
  START_FILE="$TMPDIR/embo-session-${SESSION_ID}.start"
  if [ -f "$START_FILE" ]; then
    START_TS=$(cat "$START_FILE")
    DURATION_S=$(( $(date -u +%s) - $(date -u -d "$START_TS" +%s 2>/dev/null || date -u -jf %Y-%m-%dT%H:%M:%SZ "$START_TS" +%s) ))
    DURATION_SOURCE="start_file"
    rm -f "$START_FILE"   # clean up
  else
    # Fallback: first and last message timestamps from transcript
    FIRST_TS=$(jq -r 'select(.timestamp) | .timestamp' "$TRANSCRIPT_PATH" | head -1)
    LAST_TS=$(jq -r 'select(.timestamp) | .timestamp' "$TRANSCRIPT_PATH" | tail -1)
    # compute delta if both present, else null
    DURATION_SOURCE="transcript" or "null"
  fi
```

`date -u -d` is GNU; `date -u -jf` is BSD/macOS. The hook must handle both (same platform concern as other hook scripts — verify existing hooks for the pattern used).

---

## Trade-offs

### Retention: single shared file (rejected)
- **What**: one `telemetry.jsonl`, append per session, trim to 500 via append-then-tail
- **Why rejected**: read-modify-overwrite race destroys records when two worktree sessions trim concurrently; records >4 KB exceed `PIPE_BUF` and interleave on concurrent append; needs `flock` (not portable to macOS without homebrew). Per-session files remove all three hazards.

### Primary event: `SessionEnd` (rejected)
- **What**: write the full record once at session close
- **Why rejected**: 1.5 s timeout cancels a transcript parse silently; does not fire on `max_turns`/SIGKILL/crash — the heavy sessions most worth measuring vanish. `Stop` has a 600 s budget and fires reliably per turn.

### Primary event: `Stop` writing per-session file (chosen)
- **What**: `Stop` overwrites `<session_id>.jsonl` each turn; last write wins
- **Pros**: reliable, ample timeout budget, overwrite is inherently idempotent (no scan/sentinel), per-session files remove all concurrency hazards
- **Cons**: re-parses the transcript each turn (cost is bounded by the 600 s budget and the transcript is read with streaming jq)
- **Why chosen**: the only option that is both reliable and race-free; simpler than the rejected options, not more complex

### Subagent counting: parent scan only (rejected) vs `SubagentStop` sidecar (chosen)
- A flat parent-transcript scan misses every tool call a subagent makes (subagents write to their own `agent_transcript_path`). embo spawns subagents constantly, so the undercount is large. The `SubagentStop` accumulator is required for `tool_breakdown` to be trustworthy.

---

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1: Stop writes per-session record | `auto-test` | unit | synthetic transcript → `<id>.jsonl` appears with expected fields |
| FR-1: overwrite idempotency (re-run same session) | `auto-test` | unit | run writer twice for one session_id → exactly one file, latest content |
| FR-1: transcript-unavailable guard | `auto-test` | unit | empty/missing transcript → record with `status: "transcript_unavailable"`, `tool_call_count: null` |
| FR-2: schema field present | `auto-test` | unit | `.schema == 1` on every record |
| FR-2: tool_call_count matches (CORRECT selector) | `auto-test` | unit | fixture with N `tool_use` blocks under `.message.content` → count == N |
| FR-2: subagent counts merged | `auto-test` | unit | `.sub` sidecar present → its counts appear in `tool_breakdown` |
| FR-2: failed_calls counted separately | `auto-test` | unit | fixture with `is_error:true` tool_result → `failed_calls` matches, not folded into tool_call_count |
| FR-2: commands extracted | `auto-test` | unit | transcript with `/embo:start` Bash call → `"start"` in commands |
| FR-2: worktree sessions write to main tree | `auto-test` | unit | simulate worktree env → path resolves to main `.claude/` |
| FR-2: profile read without yq | `auto-test` | unit | active-profile file present → correct name; absent → `"default"`; unreadable → `"unknown"` |
| FR-3: `embo-usage` aggregates per-session files | `manual-run-claude` | integration | multiple `<id>.jsonl` → table with one row each |
| FR-3: `embo-usage --json` | `auto-test` | unit | valid JSON with expected keys |
| FR-3: `embo-usage --profile fast` filters | `auto-test` | unit | mixed-profile files → only `fast` rows |
| FR-3: `embo-usage` worktree path resolution | `auto-test` | unit | run from worktree cwd → reads main-tree telemetry |
| FR-4: age-based retention sweep | `auto-test` | unit | file mtime > 90 days → deleted; recent file kept |
| FR-5: SessionStart writes epoch start file | `auto-test` | unit | hook invoked → `$TMPDIR/embo-session-<id>.start` holds an integer |
| FR-5: duration from transcript (primary) | `auto-test` | unit | transcript with first/last timestamps → `duration_source: "transcript"` |
| NFR-1: Stop hook overhead acceptable | `manual-run-claude` | integration | `time` writer on a large transcript within 600 s budget (target < 2 s) |
| NFR-2: no external deps (no yq, no non-stdlib) | `code-only` | — | scripts use bash + jq + python3 stdlib only |

---

## Files to Create / Modify

**Create:**
- `plugin/hooks/embo-telemetry-start.sh` — SessionStart: write epoch start file
- `plugin/hooks/embo-telemetry-start.test.sh` — unit tests
- `plugin/hooks/embo-telemetry-write.sh` — Stop: primary per-session writer
- `plugin/hooks/embo-telemetry-write.test.sh` — unit tests (incl. new synthetic `tool_use` / `tool_result` fixtures)
- `plugin/hooks/embo-telemetry-subagent.sh` — SubagentStop: subagent count accumulator
- `plugin/hooks/embo-telemetry-subagent.test.sh` — unit tests
- `plugin/bin/embo-usage` — reader CLI (Python stdlib, worktree-aware)
- `plugin/bin/embo-usage.test.sh` — unit tests

**Modify:**
- `plugin/hooks/hooks.json` — add `embo-telemetry-start.sh` to the SessionStart matcher's `hooks` array; add `embo-telemetry-write.sh` to the Stop matcher's `hooks` array; add a `SubagentStop` matcher for `embo-telemetry-subagent.sh`
- `CHANGELOG.md` — add a released-version entry when this ships

**Does NOT create:**
- `.claude/embo_state/telemetry/` — created at runtime via `mkdir -p`
- `.gitignore` — `.claude/embo_state/` already covers it

---

## Implementation Constraints

- jq is a required system dep (already used by `capture-correction.sh`, `behavioral-reminder.sh`) — no change
- **All ISO↔epoch math in `python3` stdlib** (`datetime.fromisoformat`), never `date -d`/`-jf` — those differ across GNU/BSD and no existing hook does date arithmetic to copy
- **Do not call `embo-profile`** from the hook — it requires `yq` (violates NFR-2). Read `name:` from `~/.claude/active-profile.yaml` with grep/python; default `"default"`, hard-fallback `"unknown"`
- Hooks resolve their own dir via `SCRIPT_DIR="$(dirname "$(realpath "$0")")"` — do not assume the plugin bin is on PATH
- `tmp/cap/` is NOT used for tool counting (the PRD proxy was abandoned for transcript parsing)

---

## Security Considerations

- Records contain no user content, no code, no file paths — only counts, names, timestamps
- `$TMPDIR` start files hold a single epoch integer; no sensitive data
- `transcript_path` / `agent_transcript_path` are read, never modified
- No network egress

---

## Performance Considerations

- Transcript parse is O(n); streaming jq (`-c`) avoids loading the whole file
- The `Stop` writer re-parses each turn, but the 600 s budget absorbs it; a large transcript should still complete in ~1-2 s
- Retention sweep is `find` over a small directory — negligible
- No profile subprocess dependency on yq — one file read instead

---

## Rollback Plan

- Remove the three new `hooks.json` entries — telemetry stops, no other hook affected
- Delete the four new hook scripts, `embo-usage`, and their tests
- `.claude/embo_state/telemetry/` can be left (gitignored) or deleted; nothing else reads it

---

## References

### From Codebase
- `plugin/hooks/capture-correction.sh:50-55` — stdin contract (session_id, transcript_path)
- `plugin/hooks/capture-correction.sh:68-76` — worktree resolver (mandatory reuse in all hooks + embo-usage)
- `plugin/hooks/capture-correction.sh:119-124` — CORRECT transcript selector (`.message.role`, `.message.content`)
- `plugin/hooks/capture-correction.test.sh` — bash test harness to reuse; ADD synthetic `tool_use`/`tool_result` fixtures (only `text` blocks exist today)
- `plugin/hooks/hooks.json` — SessionStart/Stop/SubagentStop wiring
- `~/.claude/active-profile.yaml` — read `name:` directly (no yq / no embo-profile)
- `plugin/bin/embo-tokens` — Python stdlib bin pattern to follow

### From History (claude-mem)
- Obs #35699 (task 041): bash test harness with synthetic transcripts + temp dirs — reuse
- Obs #42379 (this session): schema versioning is a day-one requirement → `"schema": 1`

### External
- Context7 `/websites/code_claude` hooks docs, 2026-09-09: `Stop` per-turn, 600 s budget, reliable; `SessionEnd` per-session but 1.5 s budget and skips max_turns/SIGKILL/crash; subagents write to a separate `agent_transcript_path`

---

**Next Steps:**
1. Review and approve this reworked design
2. Run `/embo:tasks` to break into implementable subtasks
3. **First subtask (blocking):** capture a real Claude Code transcript and confirm the exact `tool_use` / `tool_result` / `is_error` / `.input.command` shapes, then add synthetic fixtures — the parse selectors depend on shapes the existing fixtures never exercised
