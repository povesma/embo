# 041: Correction Capture — Technical Design

**Status**: Complete
**PRD**: [2026-07-15-041-correction-capture-prd.md](./2026-07-15-041-correction-capture-prd.md)
**Created**: 2026-07-15

## Overview

Ship two new embo commands, `/embo:enable-corrections` and
`/embo:disable-corrections`, that automate a claude-mem custom-mode
configuration proven working this session (observation 29191: a real
`type=correction` row captured live). `/embo:improve` is rewritten to
read those observations via free-text search (the `type=` filter is
broken in claude-mem 13.11.0) and to persist its own curation state in
a project-local JSON file, since no `save_memory`-equivalent write tool
exists in the worker runtime.

## Current Architecture (RLM-verified)

**Claimed in PRD/FINDINGS — re-verified live, 2026-07-15:**

- `~/.claude-mem/modes/code-embo.json` exists and matches the recipe in
  `code-embo.build.jq` — confirmed via `find ~/.claude-mem -maxdepth 2`.
- `~/.claude-mem/settings.json` currently has `"CLAUDE_MEM_MODE":
  "code-embo"` — confirmed via direct read. The mode is **already
  active on this machine** from this session's manual testing; the new
  commands must be idempotent against this pre-existing state, not
  assume a clean slate.
- `~/.claude-mem/worker.pid` exists, confirming the worker is a
  standalone long-running process (restart-by-file-touch is not
  sufficient; it must be stopped and a new one spawned).
- **New finding, not in the PRD**: `~/.claude-mem/settings.json` also
  carries `CLAUDE_MEM_CONTEXT_OBSERVATION_TYPES:
  "bugfix,feature,refactor,discovery,decision,change"` — this is a
  **separate** allowlist that filters which observation types get
  injected into session-start context. It does **not** include
  `correction`. This does not block capture (capture is governed by
  the mode file's `observation_types`, already patched), but it means
  captured corrections will silently NOT appear in the automatic
  session-start summary unless this setting is also patched. This
  resolves the PRD's open question "should corrections show up in the
  session-start summary": they will not, unless a follow-up task adds
  `correction` to `CLAUDE_MEM_CONTEXT_OBSERVATION_TYPES` — out of scope
  for this design since the PRD's goals don't require it, and changing
  it would alter session-start behavior for every observation type,
  not just corrections.
- `plugin/claude-mem/code-embo.build.jq` exists (untracked from this
  session) and is confirmed correct by its one live application
  (produced the file that captured 29191).
- **Conflicting artifact to remove**: `plugin/claude-mem/correction-
  capture.md` also exists (untracked, from this session) — a full
  **manual** setup guide. Verified by reading it: its Step 2 sets
  `CLAUDE_MEM_MODES_DIR` via a **shell-profile `export`**
  (`~/.zshrc`/`~/.bashrc`), a *different and conflicting* mechanism to
  this design's chosen path (writing the env var into Claude Code's own
  `~/.claude/settings.json` `env` block). A user who followed that doc
  and then ran `/embo:enable-corrections` would have the same env var
  set through two channels with unclear precedence. It also contradicts
  the corrected requirement recorded in obs #29205 (manual setup docs
  were explicitly rejected in favor of command automation). This design
  **deletes** it (see Files to Create/Modify); the "manual fallback"
  that CLAUDE.md's documentation rule requires is satisfied *inside*
  `enable-corrections.md` (a "what this did by hand, if it failed"
  section describing the same settings.json mechanism), not by a
  separate file using a divergent mechanism.
- `plugin/commands/improve.md` calls
  `mcp__plugin_claude-mem_mcp-search__save_memory` at **two** call sites,
  lines **90** and **99** (verified live against the current file) —
  **confirmed dead**: task 041's SEED verified via `ToolSearch
  select:...save_memory` → "No matching deferred tools found" in the
  worker runtime. This invalidates `improve.md`'s Step 4 (the curation
  log + status writes, lines 85-103) and its Step 1 read-back of
  `CORRECTION-STATUS` observations (the second search call, lines
  33-39); both are replaced below.
- claude-mem version installed: **13.11.0**, runtime: **worker**
  (`~/.claude/plugins/cache/thedotmack/claude-mem/13.11.0/`).

**Relevant existing components:**
- `plugin/commands/health.md` — the closest existing pattern for a
  command that runs a sequence of checks and renders a pass/fail table
  with fix guidance. `enable-corrections`'s verification step (Check
  worker log for `Mode loaded: code-embo`) follows this shape.
- `plugin/hooks/fix-hooks.sh` — the repo's existing "migration doctor"
  pattern: a script that detects drifted state and repairs it. Same
  shape as what `enable-corrections` needs (detect version → rebuild
  mode file → verify), but that one is a hook installer; this one
  configures claude-mem itself.
- `plugin/commands/profile.md` — the only other command that manages a
  machine/user-level (not project-level) setting
  (`~/.claude/active-profile.yaml`). Confirms the precedent for a
  command writing outside the project directory — **but only that
  aspect**. `profile.md`'s own "off" path is a blunt delete of the
  active-profile file, with no memory of the prior value; it is **not**
  a precedent for this design's restore-to-prior-value rollback
  (record prior state → restore it on disable). That rollback pattern
  is novel to this design and correspondingly deserves more test
  scrutiny (see Verification Approach).

## Past Decisions (claude-mem)

- **#29221** (decision): the 5-step automated sequence (detect version
  → build mode file via jq → write `CLAUDE_MEM_MODES_DIR` into CC's own
  `~/.claude/settings.json` env block → set `CLAUDE_MEM_MODE` → stop+
  start worker) is the mechanism CC itself can execute with no manual
  user action. This design adopts that sequence as `enable-corrections`
  Step 1-5 verbatim — it was proven, not re-derived here.
- **#29205** (correction): the user explicitly rejected a manual
  setup-instructions doc in favor of plugin automation. Confirms
  building this as a command, not a README section.
- **#29239** (correction): the PRD had to be rewritten jargon-free for
  a non-technical reader. This tech-design is the technical
  counterpart and is allowed to use precise terms (env var, mode file,
  MCP tool) that the PRD deliberately avoided.
- **Lesson from task 041 SEED itself**: the original assumption ("no
  write path exists, so corrections need a local file") was wrong for
  *capture* but turns out right for *curation state* — this design
  reuses that original fallback (a local JSON file), but scoped
  narrowly to curation bookkeeping, not correction capture itself.

## Proposed Design

### Architecture

Three components, no new runtime dependencies:

1. **`plugin/commands/enable-corrections.md`** — idempotent setup
   command. Runs the 5-step sequence from FINDINGS/#29221, using the
   existing `plugin/claude-mem/code-embo.build.jq`. Verifies via worker
   log grep, following `health.md`'s check/report pattern.
2. **`plugin/commands/disable-corrections.md`** — full undo. Reverts
   the three touched settings to their pre-enable values (see Data
   Models below for what "reverts" means precisely) and restarts the
   worker. Leaves `~/.claude-mem/modes/code-embo.json` in place
   (harmless once `CLAUDE_MEM_MODE` no longer points at it) rather than
   deleting it — deleting a file the user didn't create themselves out
   from under a shared machine-wide directory is an unnecessary
   destructive step for zero benefit.
3. **`plugin/commands/improve.md` (rewritten)** — Step 1 changes from
   a `type=`-filtered search (which the PRD confirms is broken) to a
   free-text query, filtered client-side by title/emoji heuristics.
   Step 4 (curation persistence) moves from
   `save_memory(CORRECTION-STATUS)` to a local JSON file (the
   curation-state persistence choice, confirmed by user in tech-design
   Q&A — see Trade-offs).

**Layering**: this is a plugin of markdown-driven commands, not a
compiled app — there is no UI/domain/infra split. The "layers" are:
command markdown (the procedure) → Bash/jq (execution) → claude-mem's
own files (`settings.json`, `modes/*.json`) and process (`worker.pid`)
as the thing being configured.

### Components

**New: `plugin/claude-mem/corrections-lib.sh`** (the testable core)
- **Purpose**: hold the branching logic — settings.json env-block
  merge, the `CLAUDE_MEM_MODES_DIR` conflict guard, enable-record
  read/write, the disable-side removal guard, and the local
  curation-file read/write — as **sourceable shell functions**, so it
  is unit-testable exactly like `fix-hooks.sh`.
- **Location**: `plugin/claude-mem/corrections-lib.sh`
- **Pattern**: directly follows `plugin/hooks/fix-hooks.sh` — a library
  of `corrections_*` functions (`corrections_merge_modes_dir`,
  `corrections_modes_dir_conflict`, `corrections_write_enable_record`,
  `corrections_should_remove_modes_dir`, `corrections_curation_read`,
  `corrections_curation_write`) that the command markdown invokes and
  the test file sources. A `SETTINGS_FILE`/path-override convention
  (like `fix-hooks.sh`'s `SETTINGS_FILES`) lets tests point every
  function at synthetic temp files, never the user's real config.
- **Why this exists**: this repo's `auto-test` convention is
  fixture-based shell tests that `source` the script under test
  (`fix-hooks.test.sh`); logic embedded as prose inside command
  markdown cannot be sourced or asserted against. TDD-first at
  implementation surfaced that the design's `auto-test`-tagged
  requirements (settings merge, conflict guard, idempotency, curation
  persistence) are only real if the logic lives in a sourceable helper.
- **Dependencies**: `jq` CLI (already a hard dependency of this repo's
  hooks); no new external dependency.

**New: `plugin/commands/enable-corrections.md`** (the orchestration)
- **Purpose**: turn on correction capture with zero manual steps.
- **Location**: `plugin/commands/enable-corrections.md`
- **Pattern**: follows `health.md`'s multi-check structure for its
  final verification step; sources and calls `corrections-lib.sh` for
  the file-mutation steps (rather than re-encoding jq inline), the same
  way a command would invoke a helper. Non-testable parts (the consent
  prompt, worker restart, log verification) stay in the markdown.
- **Dependencies**: `corrections-lib.sh`,
  `plugin/claude-mem/code-embo.build.jq`, `jq` CLI, Bash calls kept
  auto-approvable per RULE:AVOID-APPROVAL.

Steps (adopting #29221's sequence, made idempotent — **each step
checks current state before acting**, so a re-run after a partial
failure converges rather than erroring or double-writing; the undo
command's crash-safety, below, is only half the guarantee, this is the
other half):
0. **Disclose the machine-wide effect and get explicit consent.**
   claude-mem runs one shared worker per machine with a single
   `CLAUDE_MEM_MODE`, so this cannot be scoped to one project — turning
   it on adds the `correction` observation type (and the `code-embo`
   observer prompt) to **every** project on this machine. This is a
   claude-mem architecture limitation, not an embo choice, but the
   command must **surface it**, not absorb it silently. Following the
   convention that global mutations are explicit (git's local-vs-
   `--global`), Step 0 prints exactly what becomes machine-wide and why,
   and proceeds only on explicit confirmation. This is the one
   interactive gate in an otherwise no-prompt command.
1. Detect installed claude-mem version and locate its shipped
   `modes/code.json` under
   `~/.claude/plugins/cache/thedotmack/claude-mem/<version>/modes/code.json`.
   **Version gate**: the mechanism patches `code.json`'s internal
   structure and relies on the `CLAUDE_MEM_MODES_DIR` search-order
   override — both are claude-mem internals, not a documented public
   extension API, so they can change across claude-mem releases. The
   mechanism was verified live against **13.11.0**. `enable-corrections`
   records the detected version and, if it differs from the last
   known-good version this design was verified against, **warns loudly
   and continues only on explicit confirmation** (it does not silently
   proceed as if the patch is guaranteed to hold). The verification
   step (5) is the real backstop — but the version warning tells the
   user *why* to watch it. See "the mechanism is unsupported-internals"
   under Implementation Constraints.
2. Run `jq -f plugin/claude-mem/code-embo.build.jq <that path> >
   ~/.claude-mem/modes/code-embo.json` — **always rebuild**, even if
   the file exists, so a stale mode from a prior claude-mem version
   never lingers silently (addresses PRD's "keeps working after
   updates" story).
3. Read `~/.claude/settings.json`. If its `env` block already has
   `CLAUDE_MEM_MODES_DIR` set to a **different** path, stop and report
   a conflict (do not silently overwrite another tool's env var) —
   this is the one failure mode the PRD's acceptance criteria demands
   surfaced clearly ("if it cannot succeed... it says clearly what is
   wrong"). If it is already set to the value we would write, record
   `claude_mem_modes_dir_written=false` (the key pre-existed — disable
   must not remove it). Otherwise write/merge
   `env.CLAUDE_MEM_MODES_DIR=~/.claude-mem/modes` and record
   `claude_mem_modes_dir_written=true` plus the written value in
   `claude_mem_modes_dir_value` (Data Models) — this is what disable
   Step 3 compares against.
4. Read `~/.claude-mem/settings.json`. Record the **current**
   `CLAUDE_MEM_MODE` value (default `"code"` if absent) into the
   enable-record file (Data Models below) before overwriting it —
   this recorded prior value is what `disable-corrections` restores.
   Then set `CLAUDE_MEM_MODE=code-embo`.
5. Stop the worker (`kill $(cat ~/.claude-mem/worker.pid)` — verified
   the pid file exists; the worker is auto-respawned by the next hook
   invocation, matching FINDINGS' "fresh session that spawns the
   worker" note) and confirm via the day's log file that a fresh line
   reads `Mode loaded: code-embo` with **no** preceding `Mode file not
   found ... falling back` line. If the fallback line appears, report
   failure with the exact log path for the user to inspect (same
   failure-transparency requirement as step 3).

**New: `plugin/commands/disable-corrections.md`**
- **Purpose**: fully reverse `enable-corrections`.
- **Location**: `plugin/commands/disable-corrections.md`
- **Pattern**: mirror of `enable-corrections`, reading the enable-record
  file instead of re-deriving values.

Steps:
1. Read the enable-record file (Data Models). If it does not exist,
   report "correction capture was not enabled by this command" and
   stop — do not guess at a prior state.
2. Restore `CLAUDE_MEM_MODE` in `~/.claude-mem/settings.json` to the
   recorded prior value.
3. Remove the `CLAUDE_MEM_MODES_DIR` key from `~/.claude/settings.json`
   `env` block **only if** the enable-record has
   `claude_mem_modes_dir_written=true` AND the key's current value
   still equals the recorded `claude_mem_modes_dir_value` (defends both
   against removing a key enable did not write, and against clobbering
   a value the user or another tool changed in between).
4. Stop the worker; confirm the next log line does NOT show
   `code-embo` as the loaded mode.
5. Delete the enable-record file last, only after 2-4 succeed —
   ensures a failed disable is re-runnable from the same state (crash
   between steps must not lose the record needed to retry).

**Modified: `plugin/commands/improve.md`** (Step 1 spans lines 22-45;
its first search call is lines 24-29, its second lines 33-39; Step 4
spans lines 85-103 — all verified live against the current file):
- **Changes**:
  - Step 1 first search call (lines 24-29): replace
    `search(query="[TYPE: CORRECTION] [STATUS: pending]")` with
    `search(query="correction", type="correction")` attempted first,
    **falling back** to an untyped free-text query
    (`search(query="user corrected OR redirected approach")`) if the
    typed query returns zero results — this directly encodes the PRD's
    documented workaround for the broken `type=` filter without
    silently hiding the underlying claude-mem bug (log which path was
    used, for the upstream bug report evidence trail).
  - Step 1 second search call (lines 33-39, reading `CORRECTION-STATUS`
    observations) and Step 4 (lines 85-103, writing via `save_memory`)
    are **deleted**. Replaced by: read/write a local curation-state
    JSON file (Data Models below).
  - Step 1 gains a **new pre-check**: before querying, check whether
    correction capture is even enabled — read
    `~/.claude-mem/settings.json`'s `CLAUDE_MEM_MODE`. If it is not
    `code-embo` (or whatever mode name is active), output the PRD's
    required message distinguishing "never turned on" from "on, but
    nothing to review" (PRD acceptance criterion, `improve.md`
    currently has no such distinction).
- **Rationale**: `save_memory` does not exist in the worker runtime
  (confirmed dead tool); curation state must live somewhere embo
  controls directly.
- **Risk**: low — this is the only currently-broken command being
  fixed, not a working command being risked.

### Data Models

**Enable-record** (written by `enable-corrections`, read/deleted by
`disable-corrections`) — machine-scoped, not project-scoped, since the
mode change itself is machine-wide (PRD, "Costs we accept"):

`~/.claude-mem/embo-corrections-enable-record.json`
```json
{
  "enabled_at": "<ISO-8601 timestamp>",
  "prior_claude_mem_mode": "code",
  "claude_mem_modes_dir_written": true,
  "claude_mem_modes_dir_value": "~/.claude-mem/modes",
  "claude_mem_version_at_enable": "13.11.0"
}
```
`claude_mem_modes_dir_value` records the exact value
`enable-corrections` wrote into `~/.claude/settings.json`, so
`disable-corrections` Step 3 can compare it against the current value
and refuse to remove a key that something else has since changed
(without this field, Step 3's "only if it still matches" check has
nothing to match against). `claude_mem_modes_dir_written` stays as the
flag for the case where the key was already present before enable ran
(enable did not write it → disable must not remove it).

**Curation state** (read/written by `/embo:improve`) — project-scoped.
It sits under `.claude/`, but note the repo's `.gitignore` currently
ignores only `.claude/rlm_state/` (verified: `.gitignore:29`), **not**
arbitrary `.claude/*.json`. So this file is NOT gitignored by
inheritance — an explicit entry must be added (see Files to
Create/Modify), or the first `/embo:improve` run leaves an untracked
file that could be committed by accident (it may contain user-authored
correction edit text):

`.claude/correction-curation.json`
```json
{
  "curated_ids": [29191, 29205],
  "last_run_at": "<ISO-8601 timestamp>"
}
```
`curated_ids` are claude-mem observation IDs already shown to the user
in a prior `/embo:improve` run (accepted or rejected — both count as
curated, matching the PRD's "either way, don't resurface it"
requirement).

**Write atomically** (temp file + rename — the same
`jq '...' file > tmp && mv tmp file` pattern used for the enable-record
and by `fix-hooks.sh`), so a crash mid-write cannot leave a truncated,
unparseable file. This file is **disposable**: it holds only
bookkeeping, never the source of truth (the corrections themselves live
in claude-mem). If it is ever corrupted or lost, the correct recovery
is to delete it — the only consequence is that already-reviewed
corrections resurface once. `/embo:improve` must treat an unparseable
curation file as "no curation state yet" (re-review), never crash on
it. This disposability is why no stronger store (SQLite, server) is
warranted: there are no concurrent writers and no multi-user
requirement.

### Integration Points

**Connects to** (RLM-confirmed):
- `~/.claude-mem/settings.json` — read/write, 1 key (`CLAUDE_MEM_MODE`)
- `~/.claude/settings.json` — read/write, `env.CLAUDE_MEM_MODES_DIR`
  (this is Claude Code's own settings file, not claude-mem's — the
  automation channel proven in #29221)
- `~/.claude-mem/modes/code-embo.json` — write (regenerated on every
  `enable-corrections` run)
- claude-mem worker process, via `worker.pid` — stop signal only; the
  hook infrastructure respawns it
- `mcp__plugin_claude-mem_mcp-search__search` /
  `get_observations` — read-only, used by rewritten `improve.md`

### Error Handling

Following `health.md`'s convention (collect all results, never
half-fail silently):

| Failure | Detection | User-facing message |
|---|---|---|
| `jq` not installed | command not found | "jq is required and not found on PATH — install it (`brew install jq`) and re-run" |
| `CLAUDE_MEM_MODES_DIR` already set to a different path | step 3 conflict check | "Another tool has configured CLAUDE_MEM_MODES_DIR=<path> — enable-corrections will not overwrite it. Resolve manually." |
| Worker log shows fallback line after restart | step 5 log grep | "Mode did not load — check ~/.claude-mem/logs/claude-mem-<date>.log for 'falling back'. This usually means claude-mem's mode search order changed; report to the embo maintainer with your claude-mem version." |
| `disable-corrections` run with no enable-record | step 1 | "Correction capture was not enabled by this command (no record found) — nothing to undo." |
| `/embo:improve` run while mode is not `code-embo` | pre-check | "Correction capture is not turned on. Run /embo:enable-corrections first." |

### Testing Strategy

No existing automated test harness covers claude-mem integration
(it's an external process/file surface, not embo's own code) — this
matches the project's existing test posture for `fix-hooks.sh`, which
ships `.test.sh` files that test the **script's own logic** (jq
transforms, idempotency) against fixture files, not the live claude-mem
process. Same approach here:
- `code-embo.build.jq` gets a fixture-based test: feed it a minimal
  fake `code.json`, assert the output has 7 types, the `correction`
  entry, and the guidance-text substitutions — pure jq, no live
  claude-mem needed.
- `enable-corrections`/`disable-corrections`'s file-write logic
  (settings.json merge, enable-record read/write) is testable against
  fixture copies of `settings.json` in a temp dir.
- The **worker restart + log verification** step is inherently
  environment-dependent (real process, real claude-mem install) and is
  the one part that must stay `manual-run-claude` (see Verification
  Approach) rather than `auto-test`.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| Turn-on command configures claude-mem with no manual user steps | `manual-run-claude` | integration | Worker log shows `Mode loaded: code-embo` after running `/embo:enable-corrections` on a clean machine state |
| Turn-on command reports clear failure when it cannot succeed | `manual-run-claude` | integration | Simulate `CLAUDE_MEM_MODES_DIR` conflict; command output names the conflict, doesn't claim success |
| Turn-off command fully reverses turn-on | `manual-run-claude` | integration | After enable then disable, `~/.claude-mem/settings.json` `CLAUDE_MEM_MODE` matches its pre-enable value; worker log shows no `code-embo` |
| Restore-to-prior-value rollback is crash-safe (novel pattern — extra scrutiny) | `auto-test` | unit | Fixture test: enable-record present, simulate a crash after Step 2 of disable; re-running disable converges (record still present, restore idempotent) — this logic has no precedent elsewhere in the repo |
| Enable is re-runnable after a partial failure (idempotent) | `auto-test` | unit | Fixture test: pre-set a half-applied state (mode file written, env var not); re-running enable converges without double-writing or erroring |
| Corrections saved during normal work | `observation` | — | A real correction turn produces a `type=correction` row (already proven once: obs 29191 — re-verify after implementation, since this is the acceptance bar, not just the mechanism) |
| Normal (non-correction) observations still categorize correctly | `observation` | — | Session with mixed tool-use + correction turns produces both a normal-typed and a correction-typed observation, matching FINDINGS' existing regression check |
| `/embo:improve` distinguishes "never enabled" vs "nothing to review" | `auto-test` + `manual-run-claude` | unit + integration | Unit test on the pre-check logic with mocked settings.json; manual run against both real states |
| `/embo:improve` curation state persists across runs | `auto-test` | unit | Fixture test: run curation, assert `.claude/correction-curation.json` contains the reviewed IDs; second run excludes them |
| `code-embo.build.jq` output is correct given the current shipped `code.json` | `auto-test` | unit | jq fixture test asserts 7 observation types, correct guidance text substitutions |

## Trade-offs

**Considered Approaches for curation-state persistence:**
1. **Local JSON file** (chosen — user confirmed in tech-design Q&A)
   - Pros: no MCP dependency, works today, matches SEED's original
     fallback idea, trivially testable
   - Cons: project-local file the user could delete/lose, doesn't
     survive a repo clone to a new machine
   - Historical context: this is literally what the SEED proposed
     before FINDINGS discovered the *capture* problem had a claude-mem-
     native solution — the SEED's instinct was right for curation
     state specifically, wrong only for capture itself
2. **Re-review every time** (rejected)
   - Pros: zero state to manage
   - Cons: PRD explicitly calls this "worst UX"; rejected by the PRD
     itself, re-confirmed by user in this design pass
3. **Block on server-beta migration (task 037)** (rejected for now)
   - Pros: uses a "proper" write API when it exists
   - Cons: blocks this fix on an unscheduled migration; task 037 has no
     committed timeline. User chose not to couple these.

**Considered Approaches for command naming:**
1. **Single `/embo:corrections enable|disable` command** (rejected)
   - Pros: doesn't grow the 17-command list
   - Cons: less discoverable; the PRD's plain-language framing already
     treats these as two distinct actions
2. **`/embo:enable-corrections` / `/embo:disable-corrections`**
   (chosen — user confirmed)
   - Pros: matches PRD language exactly, discoverable in command list,
     no subcommand-parsing logic needed inside one markdown file
   - Cons: grows the command count from 17 to 19

**Considered Approaches for file layout:**
1. **`plugin/claude-mem/` subdirectory** (chosen — user confirmed)
   - Pros: keeps the jq helper and its doc together, already the
     location the session staged it at, no extra move needed
   - Cons: introduces a plugin subdirectory not yet mentioned in
     CLAUDE.md's File Structure section (needs a doc update — see
     below)
2. **`plugin/bin/`**: rejected — that directory is reserved for the
   `rlm_repl` PATH-wrapper convention (executable entry points), and
   `code-embo.build.jq` is not invoked as a standalone executable, it's
   a `jq -f` filter argument.
3. **Inline in command markdown**: rejected — the jq program is 37
   lines with its own maintenance note about re-running after
   claude-mem updates; that's better as a versionable standalone file
   than embedded in a command's prose.

## Implementation Constraints

**From existing architecture (RLM):**
- Bash calls in the command markdown must stay in the simple,
  auto-approvable shapes per `RULE:AVOID-APPROVAL` — no `$(...)`
  substitution chains for the settings.json merges; use `jq` in-place
  edits (`jq '...' file > tmp && mv tmp file`) as separate calls,
  matching the pattern in `fix-hooks.sh`.
- No dependencies beyond `jq`, already required elsewhere in the repo.

**From past experience (claude-mem):**
- The mode change is machine-wide, not project-scoped (PRD "Costs we
  accept", re-confirmed live: `~/.claude-mem/settings.json` has no
  per-project scoping mechanism). This is disclosed to the user at
  `enable-corrections` Step 0, not absorbed silently.
- A claude-mem update overwrites `code.json` but not
  `~/.claude-mem/modes/code-embo.json` (outside its managed cache) —
  confirmed by the `CLAUDE_MEM_MODES_DIR` search-order mechanism in
  FINDINGS. Rebuilding the mode file on every `enable-corrections` run
  (not just first-run) is what keeps this correct across updates,
  addressed in Component 1, Step 2 above.

**The mechanism relies on unsupported claude-mem internals** (accepted
risk, mitigated not eliminated):
- Patching `code.json`'s structure and using `CLAUDE_MEM_MODES_DIR` as
  a mode-precedence override are **not a documented public extension
  API** — they are internal behavior observed from claude-mem's source.
  A future claude-mem release can change either and silently revert
  users to stock behavior, or break the worker. Mitigations in this
  design: (1) the version gate at `enable-corrections` Step 1 warns on a
  version other than the verified 13.11.0; (2) Step 5's worker-log
  verification is the hard backstop — it fails loud if the mode did not
  load, rather than assuming success. Neither makes the dependency
  supported; they make its breakage **visible** instead of silent.
- **The jq guidance-substitution depends on a fragile literal string.**
  The transform does `sub("EXACTLY one of these 6 options"; "...7
  options")`. Found live during implementation (subtask 4.3): the
  installed 13.11.0 `code.json` has **8** `observation_types` but its
  `type_guidance` text enumerates only **6** and says "6 options" — the
  shipped file is itself internally inconsistent. The sub() keys off
  that "6" literal, so it fires today, but a claude-mem release that
  renumbers the guidance text (e.g. to "8 options") would make the
  sub() silently no-op, leaving the new `correction` type inert. The
  `code-embo-build.test.sh` guidance-fired assertion catches exactly
  this: it fails loud if the transformed guidance does not contain "7
  options", so a wording change is caught at test time, not in
  production.
- **Upstream action items** (carry into `/embo:tasks` as work items,
  already listed in the PRD): file a claude-mem issue for the broken
  `search(type=...)` custom-type filter, and file a feature request for
  a documented mode-extension API. Track both issue links so the
  free-text `search` workaround and the version gate can be revisited
  when upstream moves. The free-text workaround should carry a code
  comment pointing at the filed issue, so it is revisited on upgrade
  rather than living forever by default.

## Files to Create/Modify

**Create**:
- `plugin/claude-mem/corrections-lib.sh` — sourceable shell library
  holding the testable enable/disable/curation logic (see Components)
- `plugin/claude-mem/corrections-lib.test.sh` — fixture tests for
  `corrections-lib.sh` (merge, conflict guard, enable-record, removal
  guard, curation read/write, idempotency) — follows
  `fix-hooks.test.sh` convention
- `plugin/commands/enable-corrections.md` — turn-on command (sources
  the lib)
- `plugin/commands/disable-corrections.md` — turn-off command (sources
  the lib)
- `plugin/claude-mem/code-embo-build.test.sh` — fixture test for the
  jq transform. Named to match the repo's flat `<name>.test.sh`
  convention (`fix-hooks.test.sh`, `approve-compound.test.sh`, etc.),
  not `code-embo.build.jq.test.sh` (which double-nests extensions and
  breaks a `*.test.sh` glob's one-segment expectation).

**Modify**:
- `plugin/commands/improve.md` (lines 22-45, Step 1) — swap the first
  search call (24-29) to the typed-then-free-text query, delete the
  second search call (33-39, the CORRECTION-STATUS read-back), add the
  enabled/disabled pre-check, and read curation state from the local
  file
- `plugin/commands/improve.md` (lines 85-103, Step 4) — replace both
  `save_memory` calls (lines 90, 99) with an atomic local
  curation-file write
- `.gitignore` — add `.claude/correction-curation.json` (the file is
  not covered by the existing `.claude/rlm_state/` rule)
- `CLAUDE.md` File Structure section — add `plugin/claude-mem/` to the
  documented tree (currently undocumented; this design formalizes its
  existing ad-hoc placement)
- `CLAUDE.md` §Claude-Mem Integration — note that `save_memory` is
  confirmed unavailable in the worker runtime (currently implies it
  might exist)

**Delete**:
- `plugin/claude-mem/correction-capture.md` — untracked manual setup
  guide that conflicts with this design's automated mechanism (see
  Current Architecture). Its required "manual fallback" content is
  folded into `enable-corrections.md` using the settings.json
  mechanism, not the shell-profile `export` this file used. Deleting an
  untracked file loses no git history.

**Already exist, reused as-is**:
- `plugin/claude-mem/code-embo.build.jq` — no changes needed, already
  proven correct

## Dependencies

**External**: none new. `jq` is already a hard dependency of
`plugin/hooks/fix-hooks.sh` and `approve-compound.sh`.

**Internal**:
- `mcp__plugin_claude-mem_mcp-search__search` /
  `get_observations` — existing MCP tools, read-only usage only

## Security Considerations

- `enable-corrections` writes to `~/.claude/settings.json`, a file
  outside the project directory that affects the user's entire Claude
  Code configuration. The conflict-detection step (Component 1, Step 3)
  exists specifically so this command never silently overwrites
  another tool's env var — a real risk given `env` blocks are
  unstructured key-value and multiple plugins could plausibly claim
  the same slot.
- No secrets are involved; all files touched are local configuration,
  no network calls.

## Performance Considerations

Not applicable — this is a one-time, user-initiated setup action, not
a hot path. The worker restart takes however long claude-mem's own
startup takes; no new performance surface is introduced.

## Rollback Plan

`/embo:disable-corrections` **is** the rollback plan — it is a
first-class command, not a manual afterthought, per the PRD's explicit
requirement that turn-off "fully reverses" turn-on. If
`disable-corrections` itself fails partway, the enable-record file
(only deleted as the last step) makes it safely re-runnable.

## References

### Code (RLM):
- `plugin/commands/health.md` — check/report pattern followed by
  `enable-corrections`'s verification step
- `plugin/hooks/fix-hooks.sh` — detect-then-repair pattern, jq usage
  convention
- `plugin/commands/profile.md` — precedent for a command managing
  user-level (not project-level) config
- `plugin/commands/improve.md:90,99` — the dead `save_memory` calls
  being replaced

### History (claude-mem):
- Obs 29191 — the live proof this design's mechanism works
- Obs 29221 — the 5-step sequence this design encodes as
  `enable-corrections`
- Obs 29205 — why this must be a command, not a doc
- Obs 28870 — confirms no write path exists in the worker runtime,
  the root cause this design's curation-file approach fixes

---

**Next Steps**:
1. Review and approve this design.
2. Run `/embo:tasks` for task breakdown.
