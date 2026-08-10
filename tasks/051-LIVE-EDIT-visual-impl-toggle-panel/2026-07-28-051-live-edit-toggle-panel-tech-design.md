# 051: Live-Edit Toggle Panel for visual-impl - Technical Design

**Status**: Draft
**PRD**: [2026-07-28-051-live-edit-toggle-panel-prd.md](2026-07-28-051-live-edit-toggle-panel-prd.md)
**Created**: 2026-07-28

## Overview

Add a **Live-Edit Mode** section to `plugin/commands/visual-impl.md`.
It lets the agent inject a floating toggle panel into the live-rendered
page, backed by a fix registry the agent populates as it authors
candidate changes during the session. Each registry entry pairs a
**live-apply patch** (how the browser shows the candidate — a style
rule, a DOM patch, or a swapped handler/script) with a **source
locator** (the file + line/selector in the project's own source the
agent wrote to produce that live effect). The human toggles/compares
via the panel; on lock-in, the agent writes only the ON set back to
each entry's recorded source locator — a lookup against source it
authored moments earlier in the same session, not a search.

There is exactly one target: the project's source code, the same
source the deploy pipeline turns into what's live. This is why FR-5's
"source locator" is one field, not a dispatch table over "kinds of
targets" (CMS/DB/etc.) — a rejected framing during requirements, since
this project has no such multi-target architecture.

## Current Architecture (RLM-verified)

**Verified facts (re-checked this session):**

- `visual-impl.md`'s existing loop is `Parse -> Generate -> Render ->
  Measure -> Correct -> Gate`; Step 6 (Gate) loops back to Step 2 on
  FAIL, capped at 3 iterations — verified via:
  `plugin/commands/visual-impl.md:205-328`, 2026-07-28.
- Browser automation goes through the **Playwright CLI**, never the
  Playwright MCP, specifically because the CLI writes screenshots/DOM
  state to disk and returns paths + element refs instead of streaming
  Base64/accessibility trees into context — verified via:
  `plugin/commands/visual-impl.md:22-27,155-191`, 2026-07-28.
- `visual-qa-reviewer`'s output contract (`verdict`, `numeric`,
  `findings`, `recommended_fixes`, `priority_note`) is unchanged by
  this feature; `recommended_fixes` is a plain ordered string list —
  verified via: `plugin/agents/visual-qa-reviewer.md:104-127`,
  2026-07-28.
- Both files currently self-describe as "EXPERIMENTAL" — verified via:
  `plugin/commands/visual-impl.md:1-14,350-352`,
  `plugin/agents/visual-qa-reviewer.md:1-4`, 2026-07-28. Per the PRD,
  this is promoted to stable as part of this change (no conditional
  "enough runs" language retained).
- No existing live-edit/injection mechanism exists anywhere in the
  codebase — verified via full read of both files, 2026-07-28.

**Relevant components:**

- `plugin/commands/visual-impl.md` — the command file this feature
  extends with a new section; owns the Loop and the Gate.
- `plugin/agents/visual-qa-reviewer.md` — unmodified; its
  `recommended_fixes` list is one of the two population sources for
  the registry (FR-10).

## Past Decisions (Claude-Mem)

Task 040 (`visual-impl`'s original build-out) established two
principles this design must not violate:
- **Separate judge, never self-review** — live-edit changes what a
  human tunes, not who judges conformance; the reviewer agent's
  contract and independence are untouched.
- **Error always stops; only clean absence degrades** — a required
  tool/input that fails halts the run and reports it; this design
  reuses that existing principle for lock-in failures rather than
  inventing new error handling (see Reliability below).

## Proposed Design

### Architecture

Live-Edit Mode ships as one file, `live-edit-panel.js` (alongside the
command), which `visual-impl.md` loads and evals via the Playwright CLI —
the panel is not re-derived from prose. The file is the single source of
truth for the panel and carries its own spec as a header comment so it
stays reproducible; this tech-design section is the authoritative record
of that spec. `visual-impl.md` keeps only the conceptual material (the
trust invariant, the registry data model needed to seed entries, the
live-apply-per-kind table, export/lock-in) and points at the file for
the panel mechanics. (This supersedes an earlier plan to carry the whole
panel as prose inside the command: maintaining it in two places caused
drift.) It has three responsibilities layered on top of the existing
Playwright-CLI-driven render step:

1. **Registry** — an in-page JS array the agent maintains via
   `eval`/injected-script calls through the Playwright CLI. Each entry:
   `{ id, label, kind, apply, sourceLocator }`.
   - `kind`: `style | markup | logic` — decides which apply mechanism
     runs (see Components below). This is the only place a "kind"
     concept exists; it governs the live-preview mechanism, not the
     write-back target (there is one target: source).
   - `apply`: the live-preview patch (CSS rule text for `style`; a DOM
     mutation description for `markup`; a handler/script reference for
     `logic`).
   - `sourceLocator`: `{ file, selector | line }` — captured by the
     agent when it authors the candidate, because it just wrote that
     source to produce the live effect.
2. **Panel** — a `position:fixed` div injected once per page load,
   rendering one toggle row per registry entry, auto-generated (no
   per-entry UI code), plus bulk controls and a drag handle. Rebuilt
   whenever the registry changes (new entry mid-session).
3. **Lock-in** — reads the current ON set from the registry, writes
   each entry's `apply` value to its `sourceLocator` via the agent's
   normal file-editing capability (not through the browser), then
   removes all injected panel/style/script scaffolding from the page.

### Components

**New: Live-Edit Mode section in `visual-impl.md`**

- **Purpose**: everything above — registry lifecycle, panel injection,
  toggle application, lock-in, navigation re-injection.
- **Location**: `plugin/commands/visual-impl.md`, a new top-level
  section after "The Loop" and before "Output" (keeps the file's
  existing Prerequisites/Loop/Output/Notes structure intact; Live-Edit
  is a parallel capability, not a replacement of any existing step —
  per PRD FR-9).
- **Pattern**: same Playwright-CLI-only rule the rest of the file
  already follows (`eval` for injection/toggling, no Playwright MCP).
- **Dependencies**: Playwright CLI (already a hard prerequisite of the
  file); no new tool.
- **Discoverability flag**: a new `tools.visual_impl.live_edit_mention`
  key (boolean, default `true`) in the profile YAML files
  (`plugin/profiles/*.yaml`, matching their existing flat `tools.*`
  shape — e.g. `plugin/profiles/quality.yaml:21-23`). When `false`, the
  command's help/usage text omits the live-edit mention (FR-1 AC1,
  FR-8). No profile currently defines this key, so it defaults to "on"
  everywhere until a user opts out.

**Live-apply mechanisms (per `kind`)**:

| kind | Live-apply mechanism | What toggling does |
|---|---|---|
| `style` | Single injected `<style>` tag, rebuilt from all ON entries' CSS text, each rule scoped under a per-entry body class | Adds/removes the entry's class on `<body>` |
| `markup` | A DOM patch function stored per entry (e.g. swap `outerHTML`/an attribute on a targeted element) | Runs the patch (ON) or its inverse/original-snapshot (OFF) |
| `logic` | A named function or `<script>` block injected once; toggling attaches/detaches it as an event listener, or swaps which of two functions handles an event | Attaches (ON) or detaches (OFF) the handler |

All three share the same registry shape, panel row, export contract,
and lock-in path — only the "what happens when you flip this toggle"
step differs, matching the maintainer's stated design.

For all three kinds, `apply` holds **literal replacement source
text** — not a behavioral description. For `logic`, this means the
full function body/diff the agent would write, captured verbatim when
the candidate is authored, exactly as `style` stores literal CSS text.
Lock-in is always "write this literal text at this location," never
"re-derive code for this described behavior" — the latter would be
re-judgment, which FR-5 forbids for every kind uniformly, `logic`
included.

**Modified: none.** `visual-qa-reviewer.md`'s contract, and the
existing Loop/Gate steps in `visual-impl.md`, are unchanged; Live-Edit
is additive.

### Data Models

Registry entry (in-page JS object, not a file/schema — this is
runtime-only per NFR-2):

```js
{
  id: "f3",                 // stable within a session
  label: "Hero padding",    // shown in the panel row
  kind: "style",            // style | markup | logic — decides apply mechanism
  apply: "padding: 24px",   // CSS text | DOM-patch descriptor | handler ref
  sourceLocator: {
    file: "styles/hero.scss",
    selector: ".hero"        // or a line number for markup/logic
  }
}
```

Export format (FR-4), read by the agent from page state or copied by
the human via clipboard — plain text, unambiguous:

```
ON: f2, f7
OFF: f3, f4
```

### API Design

Not applicable — no new HTTP/CLI surface. The "interface" is the
registry's in-page JS shape (above) plus the Playwright CLI calls
(`eval`, existing) used to inject/toggle/read it. No new binary or
MCP tool.

### Integration Points

**Connects to** (from current-architecture verification):
- `plugin/commands/visual-impl.md`'s existing Playwright-CLI render
  step (Step 3) — Live-Edit starts from an already-rendered page; it
  does not duplicate render logic.
- `visual-qa-reviewer`'s `recommended_fixes` (FR-10) — one of two
  registry-population sources; read as-is (plain strings), the agent
  converts each into a registry entry with its own `kind` and
  `sourceLocator` before the panel is built.

### Reliability / Failure Handling

Reuses the file's existing principle verbatim (`visual-impl.md:353-371`,
"Error always stops; only clean absence degrades") — no new mechanism:

- If a `sourceLocator` no longer resolves at lock-in time (narrow,
  self-inflicted case: the agent or a parallel instruction changed
  that file between authoring the candidate and lock-in), transcription
  halts before writing anything, reports which entry and why, and
  leaves source untouched. Partial writes would violate Success Metric
  2 (transcribed diff matches the ON set exactly).
- If the target page itself is unreachable/unstable, this is outside
  Live-Edit's scope to handle — per the maintainer, an unstable site
  makes the whole tool unusable, not a case to design resilience
  around; the existing Prerequisites step (target URL reachability)
  already covers this.
- An abandoned session (browser closed, no lock-in) needs no cleanup:
  nothing was ever persisted (NFR-2), so there is nothing to roll back.

### Testing Strategy

No existing automated test harness covers `visual-impl.md` (it's a
command-file/agent-prompt contract, verified by live runs, matching
task 049's precedent for `approach-validator.md`). Verification here
follows the same `code-only` / `manual-run-claude` split used in task
049's tasks file.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1: panel injection | `manual-run-claude` | live session | screenshot showing floating panel with toggle rows (discoverability AC verified under FR-8) |
| FR-2: toggle applies live, no reload | `manual-run-claude` | live session | before/after screenshot pair, no navigation event logged |
| FR-3: bulk controls | `manual-run-claude` | live session | screenshot showing All ON/OFF/Invert affecting all rows |
| FR-4: export ON/OFF record | `manual-run-claude` | live session | captured export string matches panel state |
| FR-5: source-locator lock-in | `manual-run-claude` | live session | diff of the actual source file matches the ON set's `apply` values |
| FR-6: scaffolding removed post-lock-in | `manual-run-claude` | live session | page DOM/style after lock-in has no injected panel elements |
| FR-7: re-injection after navigation | `manual-run-claude` | live session | panel present with prior toggle state after a real link click |
| FR-8: mention in static help only | `code-only` | — | grep `visual-impl.md` help/usage text vs. output-after-verdict sections |
| FR-9: usable independent of gate outcome | `code-only` | — | Live-Edit section has no conditional gate-state dependency in its trigger text |
| FR-10: registry population + mid-session add | `manual-run-claude` | live session | a fix added after the panel first renders appears as a new row without reload |
| FR-11: EXPERIMENTAL label removed | `code-only` | — | grep confirms label absent from both files |

Methods used: `code-only`, `manual-run-claude` — no `auto-test` (no
test framework applies to a prompt/markdown contract), no `e2e`/`docker`
(no deployable service here).

## Trade-offs

**Considered approaches for the live-apply mechanism:**

1. **Single generic "kind" dispatch inline in the Live-Edit section
   (chosen)** — a small table (style/markup/logic) directly in
   `visual-impl.md`, no separate file.
   - Pros: matches "no standalone command," keeps the whole capability
     readable in one file, easy to extend with a 4th kind later.
   - Cons: `visual-impl.md` grows longer.
   - Why recommended: the file is already the single place this
     command's whole contract lives; splitting into two files just to
     manage length was rejected earlier in requirements gathering (no
     shared reusable doc — PRD/tech-design question, maintainer chose
     "new section within visual-impl.md").

2. **Locator "kind" dispatch on the write-back side (rejected)** — an
   earlier draft of this design proposed dispatching lock-in writes by
   target kind (CSS file vs. CMS API vs. DB write vs. generator
   config).
   - Pros: none realized — this was solving a multi-target problem the
     project doesn't have.
   - Cons: invents complexity around a nonexistent architecture; this
     project has exactly one target (project source, reached via the
     existing deploy pipeline), and the agent that authored a candidate
     already knows where it wrote it.
   - Why rejected: maintainer clarified the project's actual
     architecture — source code, deployed, is the only artifact that
     ever gets written to. The `kind` field survived only on the
     live-apply side (how the browser previews a candidate), not the
     write-back side.

## Implementation Constraints

**From existing architecture:**
- Must use Playwright CLI's `eval` (or equivalent live-JS-execution
  call), never the Playwright MCP.
- Must not alter `visual-qa-reviewer.md`'s output schema.
- No new runtime dependency (NFR-3) — vanilla JS only, consistent with
  the validated prototype.

**From past experience (claude-mem / task 040):**
- Keep the reviewer agent's independence intact — Live-Edit is a
  human-tuning path, never a path where the authoring agent judges its
  own conformance.

## Files to Create/Modify

**Modify**:
- `plugin/commands/visual-impl.md` — add the "Live-Edit Mode" section
  (registry, panel, apply-per-kind table, lock-in, navigation
  re-injection); update the header/description and the "Notes" section
  to drop "EXPERIMENTAL" (FR-11).
- `plugin/agents/visual-qa-reviewer.md` — update the header/description
  to drop "EXPERIMENTAL" (FR-11 only; no contract change).

**Create**: `plugin/commands/live-edit-panel.js` — the shipped panel
implementation the command loads and evals (single source of truth;
carries its spec as a header comment). No new command or agent.

## Dependencies

**External**: none new — Playwright CLI is an existing hard
prerequisite of `visual-impl.md`.

**Internal**: `visual-qa-reviewer`'s `recommended_fixes` output (read
as plain strings, unchanged contract).

## Security Considerations

Injected JS executes only against a page already reachable and under
active review by the developer running the session (same trust
boundary as the rest of `visual-impl.md`'s Playwright-CLI usage) — no
new external input is introduced. Lock-in writes go through the
agent's normal file-editing path, not an unreviewed automated commit;
the transcribed diff is inspectable before commit (User Story 4 AC),
same as any other agent-authored change.

## Performance Considerations

No reload per toggle (FR-2) is the entire performance goal; single
injected stylesheet + direct DOM/handler patches are O(1) per toggle
regardless of registry size. NFR-1 (glance-scannability) is a UI
concern, not a performance one — addressed via checked-row highlighting
in the panel, not measured here.

## Rollback Plan

This is a documentation-only change (two `.md` files, no runtime code,
no migration, no new dependency). Revert is a plain git revert of the
two file changes; nothing to migrate back.

## References

### Code
- `plugin/commands/visual-impl.md:205-328` — existing Loop/Gate this
  feature sits alongside.
- `plugin/commands/visual-impl.md:353-371` — the error-handling
  principle this design reuses rather than replaces.
- `plugin/agents/visual-qa-reviewer.md:104-127` — `recommended_fixes`
  output shape, one of two registry-population sources.

### History (Claude-Mem)
- Task 040 — original `visual-impl` build-out; "separate judge" and
  "error always stops" principles this design extends.
- Task 049 (`tasks/049-PROOF-TABLE-claim-proof-record/2026-07-27-049-proof-table-tasks.md`)
  — precedent for `code-only` / `manual-run-claude` verification split
  on a prompt/markdown-contract feature (no test framework applies).

---

**Next Steps**:
1. Review and approve design
2. Run `/embo:tasks` for task breakdown
