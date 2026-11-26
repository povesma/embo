# 065: Session Telemetry Log — PRD

**Status**: Draft — amended post examine-advisor review 2026-09-09
**Created**: 2026-09-09
**Author**: Claude (via /embo:prd)

---

## Wider Context / Higher Goal

embo claims to control token costs through profiles and enforced spec decomposition — but has no runtime data to verify that claim. The profile system (`fast`/`minimal`/`quality`/`research`) changes what gets loaded, but there is no way to confirm what a session actually cost, which commands were used, or which subagents fired. The immediate enabler is: a future `/embo:retro` command that can identify waste patterns and workflow bottlenecks. The deeper goal is making embo's own "enforce over prose" principle apply to cost — verifiable, not just asserted.

Inspired by Eigenwise Toolshed's observability plugin (Grafana + local metadata logs). embo's version is deliberately smaller: no server, no dashboard, just a structured local log and a CLI reader.

---

## Context

### Current State (observed)

- `embo-capture.sh` writes per-call bash output to `tmp/cap/cap-<PID>-<ns>.log` — verified via: `plugin/hooks/embo-capture.sh:28,54`, 2026-09-09. These files are transient scratch, not telemetry.
- `.claude/corrections.jsonl` exists as a structured JSONL log written by `capture-correction.sh` — verified via: `plugin/hooks/capture-correction.sh:142-149`, 2026-09-09. This is the only persistent structured log in the system.
- `.claude/embo_state/` directory does **not exist** — verified via: filesystem check, 2026-09-09. Clean slate for schema design.
- `embo-tokens` measures static token cost of shipped prompt files (chars/4 and words\*4/3 heuristics) — verified via: `plugin/bin/embo-tokens:17-18`, 2026-09-09. This is pre-session, not runtime.
- `plugin/hooks/hooks.json` wires six lifecycle events — verified via: `plugin/hooks/hooks.json`, 2026-09-09. No hook currently captures per-session runtime metadata (tool counts, session duration, command invocations).
- `conclusion-probe.log` (task 047) records checklist artifact emissions — `[assumption, verify in tech-design]` that this file still exists and is actively written.

### Past Similar Features (from claude-mem)

- **Task 041** (correction capture): established `.claude/corrections.jsonl` as the precedent for persistent JSONL logs written by hooks. Same pattern applies here.
- **Task 055** (token audit): defined `cost = size × load_frequency` as the measurement unit for shipped prompts. The runtime telemetry log should produce the "actual sessions" denominator for that formula — how often each command actually fires.
- **embo-tokens tool**: already exists for static measurement; the new feature is the runtime complement.

---

## Problem Statement

**Who**: embo users (developers running `/embo:start`, `/embo:impl`, etc. daily)
**What**: No runtime data exists about what a session actually costs — which commands fired, how many tool calls were made, how long the session ran, or whether a profile change had any measurable effect.
**Why**: Without this data, cost claims are unverifiable, profile tuning is guesswork, and a future `/embo:retro` has no input to analyze.
**When**: Every session — the gap is felt after switching profiles and having no way to compare.

---

## Goals

### Primary Goal

Write a structured JSON-lines session telemetry log to `.claude/embo_state/telemetry.jsonl` across every session, capturing enough per-event and per-session metadata to answer: "what did this session cost, and was the active profile working?"

### Secondary Goals

- Provide `embo-usage` CLI to read and summarize the log (per-session, per-command, or totals)
- Keep log growth bounded (rolling retention by record count or age)
- Make the log the input for a future `/embo:retro` command
- Verify that profile switching produces measurably different tool-call and session counts

---

## User Stories

### Epic

As an embo user, I want to see what my sessions cost in tool calls and time, so that I can verify that profiles work and identify expensive workflow patterns.

### User Stories

**1. As an** embo user  
**I want** a log entry written at the end of every session  
**So that** I can see how many tool calls were made, which embo commands ran, what profile was active, and how long the session lasted

**Acceptance Criteria**:
- [ ] A JSONL record is appended to `.claude/embo_state/telemetry.jsonl` at session end (Stop event)
- [ ] Each record contains: timestamp, session ID, active profile, duration, tool call count, embo commands invoked, and exit reason
- [ ] The log file is created on first write if absent
- [ ] Log survives across git worktrees (lives in `.claude/`, same as `corrections.jsonl`)

---

**2. As an** embo user  
**I want** to run `embo-usage` and see a per-session summary table  
**So that** I can compare sessions and spot cost regressions after config changes

**Acceptance Criteria**:
- [ ] `embo-usage` prints a table: date, session ID (short), profile, duration, tool calls, commands used
- [ ] `embo-usage --last N` limits output to the N most recent sessions
- [ ] `embo-usage --profile <name>` filters to sessions that used a given profile
- [ ] Output is human-readable plain text; no external dependencies required

---

**3. As an** embo developer  
**I want** the log to record which embo commands were invoked each session  
**So that** `embo-tokens`'s frequency estimates (cost = size × load_frequency) can be calibrated against real usage

**Acceptance Criteria**:
- [ ] Command names (e.g. `start`, `impl`, `prd`) are extracted from tool calls and recorded per session
- [ ] Frequency data is usable by future `/embo:retro` without additional processing

---

**4. As an** embo user  
**I want** the log to stay bounded in size  
**So that** it does not grow unbounded across months of daily use

**Acceptance Criteria**:
- [ ] A configurable retention limit (default: 500 records) is enforced on write — oldest records trimmed first
- [ ] `embo-usage --stats` reports total records, oldest entry, newest entry, and log file size

---

## Requirements

### Functional Requirements

**FR-1**: Session telemetry record written at Stop event, with SessionEnd fallback
- **Priority**: High
- **Rationale**: Stop fires for normal exits and is the primary write path. However, Stop does not fire reliably for `max_turns` exits, context-limit compaction stops, or SIGKILL — exactly the heavy sessions most worth profiling. A `SessionEnd` hook registered as a secondary fallback checks whether a record already exists for the session ID and writes one (with `exit_type: "session_end_fallback"`) if not. This two-hook defence ensures survivorship bias does not exclude the sessions that matter most.
- **Dependencies**: Two new hook script entries in `hooks.json`: one under `Stop`, one under `SessionEnd`. Both are new scripts, not extensions of existing ones (separation of concerns).

**FR-2**: Per-record schema (JSONL, one object per line)
- **Priority**: High
- **Rationale**: JSONL matches the existing `corrections.jsonl` precedent; append-only, grep-able, no parse dependency
- **Schema fields** (class description, not exhaustive identifiers — tech-design validates exact keys):
  - Session identity: timestamp (ISO-8601), session ID (UUID or harness-provided), active profile name
  - Duration: session start time (from SessionStart hook) and end time (Stop hook), or elapsed seconds if start is not capturable
  - Schema version: integer, starting at `1`; increment on any structural field change so consumers can filter or migrate safely
  - Tool call count: exact count of `type == "tool_use"` entries in assistant messages, parsed from the `transcript_path` JSONL provided in the Stop hook's stdin payload — verified same source used by `capture-correction.sh`; also produce a per-tool breakdown map (e.g. `{"Read": 12, "Bash": 8}`) from the same parse so session character is distinguishable without per-event granularity
  - Commands invoked: list of embo command names extracted by filtering `tool_use` entries in the transcript for `tool_input.command` values matching `/embo:` or `embo-` prefixes — same transcript parse as tool count; no separate mechanism needed
  - Exit type: one of `"stop"`, `"max_turns"`, `"context_limit"`, `"api_error"`, `"interrupted"`, `"session_end_fallback"`, `"unknown"` — marked by the hook that fired the write

**FR-3**: `embo-usage` bin command
- **Priority**: High
- **Rationale**: Log without a reader is invisible; the bin pattern is established (`embo-profile`, `embo-tokens`, `embo-corrections`)
- **Dependencies**: Reads `telemetry.jsonl`; pure stdlib (Python or bash); follows existing bin wrapper conventions

**FR-4**: Bounded log retention via append-then-tail
- **Priority**: Medium
- **Rationale**: Without bounds, the log grows forever. Trim-on-write (rewriting the file atomically on every append) has crash-corruption risk and is O(n). The correct pattern: append the record first (safe), then in a separate step rewrite the file tail if it exceeds 500 lines — write to a temp file, then `mv` atomically. 500 records at ~400 bytes each ≈ 200 KB. Alternative: per-month files (`telemetry-2026-09.jsonl`) with deletion of files older than 6 months — tech-design picks one; either eliminates mid-file corruption risk.
- **Dependencies**: Enforced in the Stop/SessionEnd hook writer as a post-append step

**FR-5**: SessionStart hook writes session start timestamp to transient state
- **Priority**: Medium
- **Rationale**: Stop hook needs session start time to compute duration. Session ID is delivered via stdin JSON field `session_id` (same mechanism as `capture-correction.sh:54` — not an env var). SessionStart hook reads `session_id` from its stdin JSON and writes a temp file at `$TMPDIR/embo-session-${session_id}.start` containing the ISO-8601 start timestamp. Stop hook reads its own `session_id` from stdin and looks up the corresponding `.start` file. If the `.start` file is absent (hook missed, crash, etc.), the hook falls back to computing duration from the transcript's first and last record timestamps, or writes `"duration_s": null` rather than erroring.
- **Dependencies**: New `SessionStart` entry in `hooks.json` (second entry, separate from `statusline-refresh.sh`)

### Non-Functional Requirements

**NFR-1**: Performance — hook overhead must be under 200 ms per session end; log write is a single append, not a scan
**NFR-2**: No external dependencies — stdlib only (bash + optional Python); same constraint as `embo-tokens` and `embo-capture.sh`
**NFR-3**: Idempotency — if the Stop hook fires twice (harness quirk), the second write is a no-op or produces a duplicate that is harmless; deduplication by session ID is acceptable but not required in v1
**NFR-4**: Privacy — log contains no user content, no code, no file paths — only counts, names, and timestamps. No sanitization pass required.
**NFR-5**: Worktree safety — both the Stop and SessionEnd hook scripts MUST implement the same worktree resolver used in `capture-correction.sh:68-76`: resolve `.claude/` to the main tree via `git rev-parse --path-format=absolute --git-common-dir` before writing `telemetry.jsonl`. Without this, sessions running inside a git worktree (a first-class embo feature as of task 062) write to the worktree's ephemeral `.claude/`, which disappears on `embo-worktree-remove`. Concurrent worktree sessions append safely once resolved to the main tree (file-level append is atomic on macOS/Linux for small writes). Note: `telemetry.jsonl` is already covered by the existing `.claude/embo_state/` gitignore entry; no additional entry is needed.

### Technical Constraints

- Must follow the hook script pattern: shell script registered in `plugin/hooks/hooks.json`
- Must follow the bin wrapper pattern: pure command, no `${CLAUDE_PLUGIN_ROOT}` expansion, added to `plugin/bin/`
- Session ID: delivered via stdin JSON field `session_id` in both SessionStart and Stop hooks (same as `capture-correction.sh:54`) — not an env var; no UUID fallback needed
- Tool call count: parsed from the `transcript_path` JSONL field in the Stop hook's stdin; count `type == "tool_use"` entries in assistant messages via jq — exact count, no approximation, no cross-session contamination; same parse produces the per-tool breakdown map and command list
- Command detection: filter the same transcript parse for `tool_input.command` values matching `/embo:` or `embo-` prefixes — corollary of the tool-count parse, not a separate mechanism
- `embo-usage` must support a `--json` flag from day one so `/embo:retro` can consume stats programmatically without parsing table output

---

## Out of Scope

- No Grafana or external dashboard — plain file + CLI reader only
- No network egress — log stays local
- No token count in the log (Anthropic API token counts are not available to hooks; the approximation from `embo-tokens` is pre-session only) — `[assumption, verify in tech-design]`
- No per-tool-call records — session-level granularity only in v1; per-call records can be added in v2 if retro needs them
- No automatic log shipping or aggregation across machines
- Per-agent model routing (separate feature idea from the Eigenwise comparison)
- Scoped rule injection (separate feature idea)

---

## Success Metrics

1. **Coverage**: 100% of sessions (where the Stop hook fires) produce a telemetry record within one week of shipping
2. **Retention**: Log file stays under 200 KB for a user running 3 sessions/day for 30 days (target: ~150 KB at 500-record cap)
3. **Utility**: `embo-usage` output is enough to answer "did switching to `fast` profile reduce tool calls?" — i.e., profile name and tool-call count are both present and correct
4. **Retro readiness**: the log schema is accepted by a future `/embo:retro` command without a migration — schema is versioned from day one

---

## References

### From Codebase
- Hook lifecycle: `plugin/hooks/hooks.json` — six events, Stop already runs `capture-correction.sh`
- Correction log precedent: `plugin/hooks/capture-correction.sh:142-149` — JSONL schema pattern
- Capture scratch files: `plugin/hooks/embo-capture.sh:28,54` — `tmp/cap/cap-<PID>-<ns>.log`
- Token measurement: `plugin/bin/embo-tokens` — bin wrapper pattern, stdlib-only
- Profile access: `plugin/bin/embo-profile` — `embo-profile get name` returns current profile name; returns `"default"` when no active profile is set (verified: `plugin/bin/embo-profile:88-98`, `plugin/profiles/default.yaml:1`)

### From History (claude-mem)
- Task 041: correction capture — JSONL log written by hook; established `.claude/` as the persistence path for hook-written logs
- Task 055 (obs #39219): `cost = size × load_frequency` — runtime frequency data from this feature feeds that formula
- Task 047: `conclusion-probe.log` — precedent for hook-written observability files in `.claude/embo_state/`

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/embo:tech-design` to validate the session-ID handoff mechanism and token-count proxy
3. Run `/embo:tasks` to break into implementable subtasks
