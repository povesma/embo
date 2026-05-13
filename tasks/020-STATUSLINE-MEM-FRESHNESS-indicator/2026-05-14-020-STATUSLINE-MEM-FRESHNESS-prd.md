# 020-STATUSLINE-MEM-FRESHNESS: Claude-mem Freshness Indicator in Statusline — PRD

**Status**: Draft
**Created**: 2026-05-14
**Author**: Claude (via dev workflow analysis)

---

## Context

A claude-mem freshness indicator was added to the live statusline on
2026-04-22 — verified via: claude-mem observations #10350–#10357,
2026-04-22. It displayed `mem:Xm` with traffic-light coloring based
on minutes since the last recorded observation, plus `mem:idle` /
`mem:DOWN` states for degraded service. The feature has since been
**lost from both the live `~/.claude/statusline.sh` and the repo
copy** — verified via: `diff ~/.claude/statusline.sh
./.claude/statusline.sh` returns identical 97-line files with no
`mem:` segment, 2026-05-14.

The probable cause of the loss is the installer overwriting the live
file with the repo copy on each run — verified via: `install.sh`
lines 70–73 unconditionally `cp $REPO_DIR/.claude/statusline.sh
$TARGET/statusline.sh`, 2026-05-14. Prevention of such silent
overwrites is **out of scope** for this PRD; it is addressed in
PRD-021 (config-change audit trail).

### Current State (observed)

- The repo ships a statusline at `.claude/statusline.sh` with
  segments `cwd | git branch | model | USED/TOTAL $cost | ctx % | time`
  — verified via: `Read .claude/statusline.sh`, 2026-05-14.
- The live statusline at `~/.claude/statusline.sh` is byte-identical
  to the repo copy and has no `mem:` segment — verified via:
  `Read ~/.claude/statusline.sh`, 2026-05-14.
- A claude-mem worker is expected to expose a local HTTP endpoint
  with observation timestamp data — verified via: observation #10350
  ("Health endpoint http://127.0.0.1:37777/api/health … running for
  24+ days"), 2026-04-22. [assumption, verify in tech-design that
  this endpoint and an observations-listing endpoint still exist at
  the same address/port in the current claude-mem version.]
- The previously-shipped feature relied on `curl` and `jq`; `jq` is
  already a documented dependency of the statusline — verified via:
  `.claude/statusline.sh` line 12 guard, 2026-05-14. `curl` is
  ubiquitous on macOS and Linux. [assumption, verify in tech-design
  that adding a curl call per refresh is acceptable for refresh
  cadence.]

### Past Similar Features (from claude-mem)

The recovery target is the design captured in observations
#10354–#10357 (Apr 22, 2026):
- `mem:VERSION TIMEm` (worker uptime) — replaced by…
- `mem:XXXobs sY` (DB stats) — replaced by…
- `mem:Xm` with traffic-light freshness (final design)
- `mem:idle` (yellow) when worker is up but DB has no observations
- `mem:DOWN` (red) when endpoint unreachable or response unparsable
- Color tiers: green ≤10 min, yellow 11–30 min, red >30 min

Task 008-STATUSLINE shipped the original tilde-abbreviation and
`USED/TOTAL` token display — verified via:
`tasks/008-STATUSLINE-config-and-improvements/`, 2026-05-14. This
PRD extends 008 with a new segment; it does not modify 008's
existing segments.

## Problem Statement

**Who**: developers using the RLM-Mem installation with claude-mem
enabled.

**What**: there is no live signal in the statusline indicating
whether the claude-mem service is actively capturing observations.
When the worker silently stops, crashes, or fails to record, the
developer continues working under the false assumption that memory
is being saved. This loss is only discovered later, often after
session compaction has already destroyed unsaved context.

**Why**: claude-mem is mandatory for the dev workflow — verified
via: `CLAUDE.md` ("Claude-Mem (MANDATORY)"), 2026-05-14. Silent
failure of a mandatory subsystem is a high-impact, low-visibility
failure mode.

**When**: any session where the worker is not healthy, where the DB
is misconfigured, or where observation recording stalls (for any
reason) without crashing the worker outright.

## Goals

### Primary Goal

The statusline shows, at all times, a fresh visual indication of
whether claude-mem is actively recording observations, with no
configuration required by the user beyond installing the statusline.

### Secondary Goals

- Degraded states (worker down, DB empty) are visually distinct
  from healthy states; the developer can tell the difference at a
  glance without reading text.
- The statusline keeps refreshing promptly even when the worker is
  unreachable — i.e. no statusline call ever hangs.
- The indicator is portable across macOS and Linux without
  additional dependencies beyond what the statusline already
  requires (`jq`).

## User Stories

### Epic

As a developer using claude-mem, I want a live freshness signal in
my statusline, so that I am alerted to memory recording problems
before they cost me work.

### User Stories

1. **As a** developer in an active coding session
   **I want** my statusline to show how recently claude-mem captured
   an observation
   **So that** I know my work is being recorded as I go.

   **Acceptance Criteria**:
   - [ ] When the worker is healthy and observations are being
     recorded, the statusline includes a segment displaying minutes
     since the most recent observation.
   - [ ] The segment is rendered in a "fresh / acceptable / stale"
     three-tier color scheme; the fresh and stale tiers are
     visually unambiguous to a non-colorblind reader.
   - [ ] The threshold boundaries are documented in the tech-design
     and configurable enough to be tightened without code changes
     in future revisions. Default thresholds for v1: green ≤10 min,
     yellow 11–30 min, red >30 min. [assumption, verify in
     tech-design — user requested "tighter, but check with
     memories"; memory only records the 10/30 values, so this PRD
     adopts them as v1 and leaves tightening as a follow-up tuning
     decision.]

2. **As a** developer whose claude-mem worker has stopped
   **I want** the statusline to make that obvious
   **So that** I notice and restart it before more work is lost.

   **Acceptance Criteria**:
   - [ ] When the freshness endpoint is unreachable, parse-failing,
     or times out, the statusline shows an explicit "down" state in
     the failure color tier.
   - [ ] The "down" state never blocks or delays statusline
     refresh; the freshness check has a hard timeout.

3. **As a** developer whose claude-mem worker is healthy but the
   observation DB is empty
   **I want** the statusline to distinguish that from "down"
   **So that** I can tell the difference between a broken service
   and a brand-new install.

   **Acceptance Criteria**:
   - [ ] When the worker responds successfully but reports no
     observations, the statusline shows an explicit "idle" state in
     the intermediate-warning color tier (distinct from both
     "healthy" and "down").

4. **As a** new RLM-Mem installer
   **I want** the freshness indicator to be present out of the box
   **So that** I don't have to discover and configure it myself.

   **Acceptance Criteria**:
   - [ ] After running `install.sh` / `install.ps1`, the live
     statusline includes the freshness segment with no additional
     manual step.
   - [ ] If `curl` or the worker endpoint is not available at
     install time, install does not fail; the statusline degrades
     gracefully (showing the "down" tier at runtime).

## Requirements

### Functional Requirements

1. **FR-1**: The statusline MUST include a new segment dedicated to
   claude-mem freshness.
   - **Priority**: High
   - **Rationale**: The whole point of the feature.
   - **Dependencies**: Must coexist with existing 008-STATUSLINE
     segments without crowding them out at typical terminal widths.

2. **FR-2**: The freshness segment MUST distinguish three operating
   states by both text and color: fresh, acceptable, stale.
   - **Priority**: High
   - **Rationale**: Color alone is insufficient (accessibility);
     text alone is insufficient (skim-ability).

3. **FR-3**: The freshness segment MUST distinguish two degraded
   states by text: a "service unreachable" state and a "service up
   but no observations recorded" state.
   - **Priority**: High
   - **Rationale**: These states have different remediation paths
     (restart worker vs. wait for first observation / check DB).

4. **FR-4**: The freshness query MUST have a hard timeout small
   enough that a non-responsive worker does not visibly delay
   statusline refresh.
   - **Priority**: High
   - **Rationale**: Statusline runs frequently; any latency is
     felt across the whole IDE.
   - **Dependencies**: Tech-design must pick a concrete value; the
     recovered design used 1 s.

5. **FR-5**: The freshness segment MUST degrade gracefully when
   prerequisites are missing — e.g. no `curl`, no network stack —
   without breaking the rest of the statusline.
   - **Priority**: High
   - **Rationale**: Statusline is a critical-path UI element; a
     broken statusline is worse than a missing segment.

6. **FR-6**: The freshness segment MUST be shipped in the repo
   `.claude/statusline.sh` and propagated by both `install.sh` and
   `install.ps1` to `~/.claude/statusline.sh`.
   - **Priority**: High
   - **Rationale**: The repo→home sync is the canonical
     distribution path; without it the feature regresses each
     install run.

### Non-Functional Requirements

1. **NFR-1**: Performance — the per-refresh overhead added by the
   freshness check must not exceed the configured timeout
   (FR-4), and on the happy path must be unnoticeable to the user.
2. **NFR-2**: Privacy — the freshness check must only contact a
   loopback (`127.0.0.1`) endpoint; no remote network call is made
   from the statusline.
3. **NFR-3**: Portability — the script must run on macOS (BSD
   userland) and Linux (GNU userland) without modification.
4. **NFR-4**: Robustness — empty responses, malformed JSON, missing
   fields, and arithmetic edge cases (e.g. zero observations) must
   all degrade to a defined state and never crash the script.

### Technical Constraints

- Must integrate with: the existing `.claude/statusline.sh`
  framework (single-pass `jq`, ANSI color helpers, segment
  concatenation).
- Should follow patterns: same input-passing convention as existing
  segments; same degradation pattern as the `jq`-not-found early
  exit at the top of the script.
- Cannot change: existing 008-STATUSLINE segments. The freshness
  segment is additive.
- Cannot assume: the structure or path of the claude-mem HTTP API
  is stable. The tech-design must confirm the endpoint(s) used.
  [assumption, verify in tech-design]

## Out of Scope

- Preventing the live statusline from being overwritten on
  subsequent installer runs — covered separately in PRD-021
  (config-change audit trail).
- Configurable thresholds via `active-profile.yaml` — possible
  follow-up; v1 uses fixed defaults.
- Alerting / notifications beyond the visual indicator (no Slack
  pings, no terminal bell, no log file).
- Tracking statistics beyond "time since last observation" (e.g.
  observation rate, DB size, session count). Memory shows these
  were tried earlier (#10355) and rejected in favor of freshness.
- Cross-machine / remote-worker support. Loopback only.
- Migrating users who have already customized their local
  statusline.sh away from the repo version.

## Success Metrics

1. **Effective detection**: when a developer's claude-mem worker
   stops mid-session, the statusline reflects the degraded state
   within one statusline refresh cycle after the timeout window
   elapses.
2. **No false positives during healthy operation**: in a session
   that is actively producing observations, the segment never
   spends a refresh cycle in the "stale" or "down" tier.
3. **No statusline regression**: with the new segment present, the
   statusline refresh latency on the happy path is
   indistinguishable from current behavior to a human user.
4. **Out-of-box availability**: a fresh install of this repo on a
   clean machine produces a statusline that includes the freshness
   segment after `install.sh` (or `install.ps1`) completes.

## References

### From Codebase (RLM)

- `.claude/statusline.sh` — file to extend (97 lines, current
  segments listed in Current State).
- `install.sh` lines 70–73 — statusline copy step (no preservation
  of local edits; see PRD-021).
- `install.ps1` lines 165–175 — Windows equivalent statusline
  copy step.
- `tasks/008-STATUSLINE-config-and-improvements/` — prior
  statusline work; this PRD is additive to it.

### From History (Claude-Mem)

- #10350 (2026-04-22) — worker health endpoint exists at
  `127.0.0.1:37777/api/health`.
- #10352 (2026-04-22) — robust health check formatter pattern (curl
  with timeout, `|| true`, non-empty check before `jq`, default
  fallbacks).
- #10353 (2026-04-22) — edge case validation: healthy, missing
  fields, malformed JSON, empty response, null uptime, arithmetic
  failure.
- #10354 (2026-04-22) — first integration: `mem:VERSION TIMEm` /
  `mem:DOWN` (later superseded).
- #10355 (2026-04-22) — second iteration: switched to DB stats
  `mem:XXXobs sY` (later superseded).
- #10356 (2026-04-22) — **final design** the user wants restored:
  `mem:Xm` with traffic-light colors and `mem:idle` / `mem:DOWN`
  fallback states.
- #10357 (2026-04-22) — minor refactor that consolidated color
  selection into a `cmem_color` variable.
- #13722 (2026-05-14) — record that this feature was lost.

---

**Next Steps**:
1. Review and refine this PRD.
2. Run `/dev:tech-design` to design the new statusline segment and
   confirm the endpoint, timeout value, and threshold choice
   against the live worker.
3. Run `/dev:tasks` to break down into tasks.
