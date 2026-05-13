# 020-STATUSLINE-MEM-FRESHNESS: Claude-mem Freshness Indicator — Technical Design

**Status**: Draft
**PRD**: [2026-05-14-020-STATUSLINE-MEM-FRESHNESS-prd.md](./2026-05-14-020-STATUSLINE-MEM-FRESHNESS-prd.md)
**Created**: 2026-05-14

---

## Overview

Add one new bash segment to `.claude/statusline.sh` that queries the
local claude-mem worker for the most recent observation timestamp,
computes minutes elapsed, and renders `mem:Xm` / `mem:idle` /
`mem:DOWN` / `mem:NOCURL` with traffic-light coloring. The segment
is purely additive: it does not modify the existing segments
introduced in task 008. Both installers must propagate the updated
statusline.

## Current Architecture (RLM-verified)

Re-verification of PRD facts:

- `.claude/statusline.sh` is 97 lines and structured as: input read
  on line 10, `jq` guard 12–15, segment computations 17–61, ANSI
  color block 63–70, segment assembly 72–94, output 96 — verified
  via: `Read .claude/statusline.sh`, 2026-05-14.
- `~/.claude/statusline.sh` is byte-identical to the repo copy and
  has no `mem:` segment — verified via: `Read ~/.claude/statusline.sh`,
  2026-05-14.
- Claude-mem worker on `127.0.0.1:37777` is live, version 10.6.2 —
  verified via: `curl -s --max-time 1 http://127.0.0.1:37777/api/health`
  returning a JSON object including `status:"ok"`, `version:"10.6.2"`,
  `initialized:true`, `mcpReady:true`, `ai.provider:"claude"`,
  `ai.lastInteraction:null`, plus host-specific fields
  (`uptime`, `pid`, `workerPath`, `platform`), 2026-05-14.
- The observations-listing endpoint exists and accepts `?limit=1` —
  verified via: `curl -s --max-time 1
  'http://127.0.0.1:37777/api/observations?limit=1'` returning
  `{"items":[{"id":<int>,"memory_session_id":"<uuid>","project":
  "<repo>","type":"<type>","title":"<text>","subtitle":"<text>",
  "narrative":"<text>","text":null,"facts":"<json-string>","concepts":
  "<json-string>","files_read":"<json-string>","files_modified":
  "<json-string>","prompt_number":<int>,"created_at":"<iso8601>",
  "created_at_epoch":<int-ms>}],"hasMore":<bool>,"offset":<int>,
  "limit":<int>}`, 2026-05-14.
- The response includes `items[0].created_at_epoch` as **integer
  milliseconds since Unix epoch** — verified via: live response field
  inspection, 2026-05-14. This is materially simpler than parsing
  `created_at` (ISO 8601) and removes the BSD-vs-GNU `date` portability
  concern from the recovered design.
- The existing statusline uses an ANSI-color helper convention where
  colors are assigned to bash variables (`CYAN`, `GREEN`, etc.) and
  applied via `printf "${COLOR}%s${RESET}"` — verified via:
  `.claude/statusline.sh:63-83`, 2026-05-14.
- The existing statusline reads all input fields with `jq` from a
  single buffered `input=$(cat)` value — verified via:
  `.claude/statusline.sh:10` and subsequent `echo "$input" | jq -r`
  invocations, 2026-05-14.

PRD assumptions resolved:

- "[assumption] endpoint and observations-listing endpoint still exist
  at the same address/port" → **resolved**, both confirmed live.
- "[assumption] adding a curl call per refresh is acceptable" →
  **resolved**, loopback healthy response time on the test machine
  is <10 ms; with the chosen 2 s timeout the worst-case statusline
  blocked refresh is bounded by curl's connect+read budget.

## Past Decisions (Claude-Mem)

- **#10350–#10357 (Apr 22, 2026)**: original implementation;
  iterated through `mem:VERSION TIMEm` → `mem:XXXobs sY` →
  `mem:Xm` traffic-light. Final form chosen because freshness is
  the diagnostic the developer actually needs.
- **#10352 (Apr 22, 2026)**: codified a "robust formatter" pattern —
  `curl … || true`, non-empty response check before `jq`, fallback
  defaults for missing/null fields, explicit arithmetic error
  protection (`2>/dev/null || cmem_var=0`). All five guards must be
  preserved.
- **#10353 (Apr 22, 2026)**: edge-case validation matrix (healthy,
  missing fields, malformed JSON, empty response, null uptime,
  arithmetic failure). This becomes the test plan input.
- **#13722 (May 14, 2026)**: the feature was lost. Root cause is in
  the installer, not in the script content. PRD-021 addresses
  prevention separately; this design only restores the segment.

## Proposed Design

### Architecture

A single bash function `cmem_segment` is added to
`.claude/statusline.sh`, called once per refresh inside the segment
assembly block. It returns a fully-rendered colorized segment
string (or empty string if disabled). It owns its own timeouts,
parsing, and error handling so a failure in this segment cannot
poison sibling segments.

Layering inside the script (additive only):

- **Acquisition**: a single `curl` call with explicit `--max-time`.
- **Parsing**: a single `jq -r` extracting `.items[0].created_at_epoch
  // empty`.
- **Classification**: a pure-bash branch over: no curl → `NOCURL`;
  empty curl output → `DOWN`; non-empty but jq returns empty →
  `idle`; numeric value → compute minutes, pick tier.
- **Rendering**: a printf with the resolved color and text.

### Components

**New components**:

1. **`cmem_segment` function** (in `.claude/statusline.sh`)
   - **Purpose**: produce the freshness segment text and color.
   - **Location**: between the existing helper functions and the
     segment-assembly block (i.e. after `short_num()` and after the
     `RESET/CYAN/…` color block, before the `parts=()` array).
   - **Pattern**: mirrors the existing per-segment compute style —
     local-only variables, single `jq` call, fallback defaults.
   - **Dependencies**: `curl`, `jq`, `date +%s` (epoch seconds).

**Modified components**:

1. **`.claude/statusline.sh` segment assembly** (line ~72–83)
   - **Changes**: insert one `parts+=("$(cmem_segment)")` call
     immediately after the `ctx %s%%` segment and before the
     `current_time` segment. Empty return value is filtered by the
     existing join logic (no extra change needed, but verified
     behavior: an empty `part` still gets joined with `" | "`, so
     the function must return either a fully-rendered segment or
     genuinely produce no `parts+=` entry — see *Empty-segment
     handling* below).

2. **`.claude/statusline.sh` header comment** (line 3)
   - **Changes**: extend the "Displays:" line to include `mem`.

3. **`install.sh`** (no logic change; the new statusline.sh content
   is what propagates).
4. **`install.ps1`** (no logic change; same).

### Empty-segment handling

The existing join loop in the script appends `" | "` between every
non-empty `part`, but does not skip empty parts before append. If
`cmem_segment` returned `""`, the result would render two
consecutive separators. To avoid that:

- `cmem_segment` always returns a non-empty string (`mem:DOWN` is
  the explicit empty-state representation).
- Conditional opt-out (if ever needed in v2) would be implemented
  by guarding the `parts+=` call itself, not by returning empty.

### Data Contracts

**Input**: none; `cmem_segment` reads from the worker, not from
Claude Code's statusline JSON.

**Worker response shape** (consumed fields only):

| jq path | type | meaning |
|---|---|---|
| `.items[0].created_at_epoch` | integer (ms) | timestamp of most-recent observation |
| (root) | object | indicates worker reachable |
| `.items` | array (possibly empty) | empty array → `idle` |

All other fields are ignored.

**Output**: a single bash string with embedded ANSI codes,
suitable for inclusion in the `parts=()` array. The string is
self-terminating with `\033[0m` (RESET).

### State Classification

Decision tree (executed top-to-bottom; first match wins):

1. `curl` not available → emit `NOCURL` red.
2. `curl` exit code non-zero OR empty stdout → emit `DOWN` red.
3. Response present but `jq` extraction empty/null → emit `idle`
   yellow.
4. Extraction numeric and ≤ now − ε:
   - elapsed ≤ 10 min → emit `mem:Xm` green
   - 10 min < elapsed ≤ 30 min → emit `mem:Xm` yellow
   - elapsed > 30 min → emit `mem:Xm` red

The thresholds (10, 30) are stored as named bash variables at the
top of `cmem_segment` so a future profile-driven override is a
one-line patch. They are **not** read from `~/.claude/active-profile.yaml`
in v1.

### Threshold Values

Defaults follow the recovered design (#10356): `CMEM_GREEN_MAX=10`,
`CMEM_YELLOW_MAX=30` (minutes). The user requested "tighter, but
check memories"; memory has no tighter value on record, so v1 ships
the recovered defaults. A v2 follow-up could read overrides from
the active profile.

### Timeout

`curl --max-time 2` (per design clarification 2026-05-14). Loopback
healthy response measured at <10 ms; 2 s gives 200× headroom
against transient load while bounding the worst-case
statusline-blocking delay.

### Communication / Sequence

```
statusline.sh refresh
    ├── (existing segments compute, fast & local)
    ├── cmem_segment
    │     ├── command -v curl?  no → return "mem:NOCURL" red
    │     ├── curl --max-time 2 -s loopback/observations?limit=1 || true
    │     ├── if empty → return "mem:DOWN" red
    │     ├── echo "$resp" | jq -r '.items[0].created_at_epoch // empty'
    │     ├── if empty → return "mem:idle" yellow
    │     ├── elapsed_ms = (now_ms - epoch_ms)
    │     ├── elapsed_min = elapsed_ms / 60000
    │     └── classify → return "mem:${N}m" with tier color
    └── join all segments with " | "
```

### Error Handling

Follows the #10352 pattern exactly:

| Failure mode | Handling | Resulting state |
|---|---|---|
| `curl` missing from PATH | early-return | `mem:NOCURL` red |
| Connection refused | `curl … \|\| true` swallows exit | `mem:DOWN` red |
| Timeout | `--max-time` truncates | `mem:DOWN` red |
| Empty response body | `[ -z "$resp" ]` guard | `mem:DOWN` red |
| Malformed JSON | `jq -r … // empty` + numeric test | `mem:DOWN` red |
| Worker up, empty DB | `.items` empty → jq returns empty | `mem:idle` yellow |
| `date` failure | wrapped in `|| now_ms=0` | falls through to DOWN |
| Arithmetic underflow (clock skew, future timestamp) | clamp to 0 before classification | green `mem:0m` |

All five guards from #10352 (curl `|| true`, empty-string check,
`// empty` defaults, arithmetic error protection, fallback values)
must be preserved.

### Testing Strategy

The recovered edge-case matrix from #10353 is the canonical test
input. Tests run as bash unit tests against `cmem_segment`
exercised with mocked `curl` output (a wrapper function override or
`PATH` shim). The matrix is:

| Mocked input | Expected output |
|---|---|
| `command -v curl` returns nothing | `mem:NOCURL` + red |
| curl returns empty | `mem:DOWN` + red |
| curl returns `{}` | `mem:idle` + yellow |
| curl returns `{"items":[]}` | `mem:idle` + yellow |
| curl returns valid items[0] with epoch (now − 5 min) | `mem:5m` + green |
| valid items[0] with epoch (now − 20 min) | `mem:20m` + yellow |
| valid items[0] with epoch (now − 60 min) | `mem:60m` + red |
| curl returns malformed JSON | `mem:DOWN` + red |
| valid epoch in the future (clock skew) | `mem:0m` + green |

Live-integration verification (manual): kill worker, refresh
statusline, observe `mem:DOWN`; restart worker (no new obs yet),
observe `mem:idle`; trigger a new observation, observe
`mem:0m`/`mem:1m`.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1 (segment exists) | `code-only` + `manual-run-user` | unit | `mem:` substring present in rendered statusline |
| FR-2 (three healthy tiers) | `auto-test` | unit | each of green/yellow/red asserted in 3 distinct mocked cases |
| FR-3 (down vs idle distinguished) | `auto-test` | unit | distinct strings asserted for empty-response vs empty-items |
| FR-4 (hard timeout) | `auto-test` | unit | hang-mocked endpoint → segment returns within 2.5 s |
| FR-5 (graceful no-curl) | `auto-test` | unit | `PATH=/empty` shim → `mem:NOCURL` returned, statusline still renders |
| FR-6 (propagated by installers) | `manual-run-user` | integration | post-install `diff ~/.claude/statusline.sh .claude/statusline.sh` returns no differences and both contain `cmem_segment` |
| NFR-1 (performance) | `manual-run-user` | integration | time round-trip of one refresh on warm cache <50 ms |
| NFR-2 (loopback only) | `code-only` | unit | `grep -E '\\bcurl\\b' .claude/statusline.sh` shows only 127.0.0.1 URL |
| NFR-3 (portability) | `manual-run-user` | integration | run on macOS BSD `date` and Linux GNU `date` — both yield consistent output |
| NFR-4 (robustness) | `auto-test` | unit | full #10353 matrix passes |

Method definitions per `/dev:test-plan` canonical list.

## Trade-offs

### Time source: `created_at_epoch` vs ISO 8601

- **Option A — Parse `created_at` (ISO 8601)**: matches recovered
  design exactly. Requires macOS-specific `date -j -u -f` and
  Linux-specific `date -d` code paths. The recovered design hit
  this; the workaround was the source of complexity in #10352.
- **Option B (chosen) — Use `created_at_epoch`**: the field exists
  in the live response in milliseconds. Convert to seconds via
  integer division. Eliminates the portability code path entirely.
  Worth diverging from the recovered design because the recovered
  design predates this field being widely used in callers.

### `cmem_segment` as function vs inline block

- **Option A — Inline computation**: matches the style of every
  other segment in the script. Marginally shorter.
- **Option B (chosen) — Function**: the segment has 4 distinct
  state branches and a non-trivial fallback ladder. Inlining makes
  the parts assembly block unreadable. The recovered design ended
  up as a function (#10357 renaming `cmem_color` etc.) for the
  same reason.

### Empty-segment vs always-emit

- **Option A — Allow `cmem_segment` to return empty**: would
  require adding a skip-empty guard in the join loop. Touches code
  outside the new function.
- **Option B (chosen) — Always emit something**: `mem:DOWN` is the
  explicit empty-state. Keeps the join loop untouched. Lower
  diff surface, lower regression risk.

### Threshold storage: profile vs hard-coded

- **Option A — Read from `~/.claude/active-profile.yaml`**: more
  flexible. Out of v1 scope per PRD.
- **Option B (chosen) — Hard-coded named variables at top of
  function**: zero new dependencies; a v2 patch can swap in a
  profile read without changing structure.

## Implementation Constraints

From RLM (current `.claude/statusline.sh`):

- The script uses `set -euo pipefail`. The new function must not
  trip `-e` on expected-failure paths. `|| true` and `|| default`
  must be used on every potentially-failing command.
- The script reads JSON input via `jq -r '.path // default'`. The
  new function uses an *external* JSON source (curl output), not
  the statusline JSON input — the existing `input=$(cat)` is not
  re-used.
- The `RESET/GREEN/YELLOW/…` color variables defined at line 63–70
  must be used by the new function; introducing new color variables
  is allowed only if a tier is genuinely new (none is).

From past experience (claude-mem):

- #10357: do **not** mix `if/else` color selection with a
  `cmem_color` variable. Pick one. The accepted pattern is a single
  `\033[${cmem_color}m` printf with `cmem_color` assigned earlier.
- #10353: every fallback path must be exercised by a test — silent
  fallthrough is the failure mode that lost the original feature
  the first time around.

## Files to Create / Modify

**Modify**:
- `.claude/statusline.sh` — add `cmem_segment` function, insert one
  `parts+=` line, update header comment. Single hunk, no
  refactor of existing segments.

**Create**:
- `tasks/020-STATUSLINE-MEM-FRESHNESS-indicator/tests/cmem_segment.test.sh`
  (or equivalent under the repo's existing test layout) — bash
  test harness running the #10353 matrix. [assumption, verify in
  tasks: confirm the repo's preferred bash test layout; if there
  is none, place tests under `tests/statusline/` and document the
  invocation in the tasks file.]

**No change**:
- `install.sh`, `install.ps1` — propagation already works; the new
  content is picked up automatically. (PRD-021 will address the
  separate "don't overwrite local edits" concern.)

## Dependencies

**External (runtime)**:
- `curl` — already ubiquitous on macOS/Linux; absence handled
  explicitly (`mem:NOCURL`).
- `jq` — already required by the statusline; absence handled by
  existing guard at the top of the file.
- `date` — POSIX; only `date +%s` (or `+%s%3N` if available) used.
  See *Sub-second handling* below.

**External (test)**:
- `bash` 3.2+ (macOS default) — confirmed available on macOS and
  Linux dev environments.

### Sub-second handling

For an observation captured "just now", `date +%s` minus an epoch in
the same second yields 0 → `mem:0m`. This is acceptable: the
display unit is minutes by design (#10356). If the user wants
sub-minute display (`mem:5s`), it would require either GNU `date
+%s%3N` (not portable to macOS BSD `date`) or `perl -e 'print
time'` (an extra dep). v1 stays minute-granular.

## Security Considerations

- Loopback-only HTTP. No outbound traffic.
- No secrets read, no secrets written.
- `curl` is invoked with `-s` (no progress to stderr) and a
  literal `127.0.0.1:37777` URL — no user-controlled URL
  interpolation, no shell injection surface.

## Performance Considerations

- One additional `curl` + one additional `jq` per statusline
  refresh. Loopback healthy round-trip <10 ms; jq parse of a
  ~1 KB body <5 ms. Total budget ≈ 15 ms.
- Worst case (hung worker): `--max-time 2` caps the contribution
  at 2 s. The statusline becomes briefly laggy, then settles into
  `mem:DOWN` — by design, this is the failure-mode signal.

## Rollback Plan

The change is a localized addition to one bash file. Rollback is a
git revert of the statusline commit and a re-run of `install.sh`
(or `install.ps1`). No data migration, no schema change, no
infrastructure dependency.

## References

### Code (RLM)
- `.claude/statusline.sh` (97 lines) — extension target.
- `install.sh`, `install.ps1` — propagation path (no logic change).

### History (Claude-Mem)
- #10350–#10357 (Apr 22, 2026) — original implementation,
  iteration history, robust formatter pattern, edge-case matrix,
  color-variable refactor.
- #13722 (May 14, 2026) — loss record motivating the recovery.
- PRD-020 (this directory) — requirements.

---

**Next Steps**:
1. Review and approve design.
2. Run `/dev:tasks` for task breakdown.
