# live-edit-toggle-panel - Task List

## Relevant Files

- [2026-07-28-051-live-edit-toggle-panel-tech-design.md](2026-07-28-051-live-edit-toggle-panel-tech-design.md)
  :: Live-Edit Toggle Panel - Technical Design
- [2026-07-28-051-live-edit-toggle-panel-prd.md](2026-07-28-051-live-edit-toggle-panel-prd.md)
  :: Live-Edit Toggle Panel - Product Requirements Document
- [plugin/commands/visual-impl.md](../../plugin/commands/visual-impl.md)
  :: MODIFY - add the Live-Edit Mode section (registry, panel,
     per-kind apply table, lock-in, navigation re-injection); drop
     the EXPERIMENTAL label from header/description/Notes
- [plugin/agents/visual-qa-reviewer.md](../../plugin/agents/visual-qa-reviewer.md)
  :: MODIFY - drop the EXPERIMENTAL label from header/description only
     (no contract change)
- [plugin/profiles/quality.yaml](../../plugin/profiles/quality.yaml),
  [plugin/profiles/fast.yaml](../../plugin/profiles/fast.yaml),
  [plugin/profiles/minimal.yaml](../../plugin/profiles/minimal.yaml),
  [plugin/profiles/research.yaml](../../plugin/profiles/research.yaml)
  :: MODIFY only if task 5.2 decides a profile should opt out; default
     is `true` (mentioned) via absence of the key, no file edit needed
     otherwise
- [plugin/commands/live-edit-panel.js](../../plugin/commands/live-edit-panel.js)
  :: CREATE (shipped) — the Live-Edit panel implementation the command
     loads and evals; single source of truth. Implements the registry,
     the position:fixed panel (system-font design, explicit ON/OFF
     badges + header count, one-line selectable labels, resize, drag),
     per-row + bulk toggles, the three live-apply kinds, full change-set
     export, lock-in payload, cleanup, and idempotent navigation
     re-injection. Carries its spec as a header comment. Verified live.

## Notes

- The panel ships as one file, `plugin/commands/live-edit-panel.js`,
  which `visual-impl.md` loads and evals (single source of truth; not
  re-derived from prose). This supersedes the original plan to carry the
  panel entirely as prose in the command file — maintaining it in two
  places caused drift. See the tech-design Architecture section. The
  other changes remain prompt-contract edits to the command/agent files
  plus one optional profile key.
- **Specificity (verified live):** a style candidate's `apply` must carry
  its own specificity (`!important` or a specific selector) when the
  target is already styled — a plain rule can lose the cascade to page
  CSS and silently no-op. Injecting a rule is not proof it applied;
  verify the computed style.
- **Export is the full change set** (file + selector + literal `apply`
  per ON entry), not an id list — a maintainer or the agent turns it
  straight into a source edit. Lock-in then offers to write it, so the
  feature reaches its goal: permanent backend changes, not a live-only
  preview.
- No existing automated test harness covers `visual-impl.md` (it's a
  markdown prompt contract, not executable code); verification is
  `code-only` (static presence/absence checks) or `manual-run-claude`
  (a live Playwright-CLI session), per the tech design's Verification
  Approach table. No `auto-test` tasks appear in this list for that
  reason.
- **One target, not many**: every lock-in path writes back to the
  project's own source (the same source a deploy pipeline turns into
  what's live) via a `sourceLocator` the agent captured when authoring
  the candidate. There is no per-target dispatch (CMS/DB/etc.) — that
  framing was explicitly rejected during tech-design. Do not
  reintroduce it while implementing.
- **`apply` is always literal replacement source text** for every
  `kind` (`style`, `markup`, `logic`) — never a behavioral description
  the agent would have to re-derive at lock-in. This is the guarantee
  behind FR-5's "no re-judgment" claim; keep it true for `logic`
  specifically, since that's the kind most tempted to drift into a
  description instead of literal text.
- No test-plan file exists for this task; `[verify: ...]` tags below
  are taken directly from the tech design's Verification Approach
  table (per-FR method assignment already made there).

## Tasks

- [X] 1.0 **User Story:** As a developer, I want a floating toggle
  panel injected into the live page with a fix registry backing it,
  so that I can turn candidate changes on/off without touching
  devtools (FR-1, FR-2, FR-3, NFR-1, NFR-2, NFR-3).
  - [X] 1.1 Write the registry data model section (entry shape
    `{ id, label, kind, apply, sourceLocator }`) into the new
    Live-Edit Mode section of `visual-impl.md`, per tech-design Data
    Models. State inline that `sourceLocator` names only the project's
    own source — there is no per-target dispatch (CMS/DB/etc.); one
    target, reached the same way every time [verify: code-only]
  - [X] 1.2 Write the panel-injection spec: a `position:fixed` div,
    injected once per page load via Playwright CLI `eval`, one row
    auto-generated per registry entry, no per-entry authored UI code
    [verify: code-only]
  - [X] 1.3 Write the toggle-application spec: flipping a row updates
    exactly the currently-on set live, no reload [verify: code-only]
  - [X] 1.4 Write the bulk-controls spec (All ON / All OFF / Invert)
    and the checked-row visual-highlight requirement (NFR-1 glance
    scannability) [verify: code-only]
  - [X] 1.5 Write the drag-handle spec (mousedown/mousemove/mouseup
    on a header bar) so the panel can be repositioned [verify:
    code-only]
  - [X] 1.6 State the no-persistence/no-dependency constraints
    (NFR-2, NFR-3) explicitly in the section: vanilla JS only, nothing
    survives past the browser session [verify: code-only]
  - [X] 1.7 Live-run: start a `visual-impl` session, invoke live-edit
    mode, confirm the panel renders with toggle rows, toggling
    applies/removes an entry's effect live with no reload, bulk
    controls affect all rows, and the panel can be dragged [verify:
    manual-run-claude]
    → panel rendered with 3 rows; style toggle applied/removed a body
      class live (no reload); all-on/all-off/invert verified against
      the ON set; drag moved the panel (confirmed when it was found
      relocated) [live] (2026-07-28)

- [X] 2.0 **User Story:** As a developer, I want each registry entry's
  live-preview to work correctly whether the candidate is a style,
  markup, or logic change, so that live-edit isn't limited to CSS
  (FR-1 sub-mechanism, tech-design "Live-apply mechanisms" table).
  - [X] 2.1 Write the `style` kind's live-apply mechanism: single
    injected `<style>` tag rebuilt from all ON entries' CSS text, each
    rule scoped under a per-entry body class [verify: code-only]
  - [X] 2.2 Write the `markup` kind's live-apply mechanism: a stored
    DOM-patch function per entry (e.g. swap `outerHTML`/an attribute),
    toggled by running the patch or its inverse/original snapshot
    [verify: code-only]
  - [X] 2.3 Write the `logic` kind's live-apply mechanism: a named
    function or `<script>` block injected once, toggled by
    attaching/detaching an event listener or swapping which of two
    functions handles an event [verify: code-only]
  - [X] 2.4 State explicitly, for all three kinds, that `apply` holds
    literal replacement source text (not a behavioral description) —
    critical for `logic`, where the temptation is to store a
    description instead of the literal function body/diff [verify:
    code-only]
  - [X] 2.5 Live-run: register one candidate of each kind
    (style/markup/logic) in a session, toggle each independently and
    in combination, confirm the live page reflects exactly the
    currently-on set for all three [verify: manual-run-claude]
    → all 3 kinds toggled independently (style: body class + stripes;
      markup: CTA text swap+revert; logic: handler swap, confirmed via
      click) and in combination; ON set matched exactly at each step
      [live] (2026-07-28)

- [X] 3.0 **User Story:** As a developer, I want to lock in my chosen
  combination and have it written back to source deterministically,
  with all panel scaffolding removed afterward, so that the accepted
  result is traceable and nothing leaks into shipped code (FR-4,
  FR-5, FR-6).
  - [X] 3.1 Write the export spec: the full CHANGE SET for every ON
    entry (file + selector + literal `apply`), readable by the human
    (clipboard + visible confirmation) and the agent (from page state) —
    NOT a bare id list, which tells a maintainer nothing about what to
    change [verify: code-only]
    → implemented in `plugin/commands/live-edit-panel.js`
      (`__liveEditExport` / `__liveEditChangeSet`); clipboard copy +
      "Copied change set" confirmation; verified live [live] (2026-08-10)
  - [X] 3.2 Write the lock-in spec: on explicit human instruction, the
    agent writes only the ON set's `apply` values to each entry's
    `sourceLocator` — a deterministic lookup-and-write against source
    it already authored, never a search or re-derivation. State
    inline that this is a single uniform write-back path with no
    branching by target kind — do not introduce per-kind dispatch
    here; `kind` governs only the live-preview mechanism (Story 2.0)
    [verify: code-only]
  - [X] 3.3 Write the cleanup spec: after lock-in, all injected
    panel/style/script scaffolding is removed from the page; state
    explicitly that an abandoned session (no lock-in) needs no cleanup
    since nothing was ever persisted (NFR-2) [verify: code-only]
  - [X] 3.4 Write the failure-mode spec: if any ON entry's
    `sourceLocator` no longer resolves at lock-in time, halt before
    writing anything, report which entry and why, leave source
    untouched — reusing the file's existing "error always stops"
    principle verbatim, no new mechanism [verify: code-only]
  - [X] 3.5 Live-run: toggle a multi-entry combination, lock it in,
    confirm the written source exactly matches the ON set's `apply`
    values and that no injected scaffolding remains in the page DOM
    afterward [verify: manual-run-claude]
    → 2-entry registry (f1 OFF, f2 ON) targeting a real .scss file;
      clicked the actual export button (confirmed "Copied: ON: f2 /
      OFF: f1"); lock-in payload contained only f2; wrote f2's `apply`
      to the real file via Edit — resulting file matched exactly;
      cleanup removed panel, injected <style>, and body classes from
      the DOM [live] (2026-07-28)

- [X] 4.0 **User Story:** As a developer, I want the registry to accept
  new candidates at any point (from the reviewer's
  `recommended_fixes` or added ad hoc) and survive real page
  navigation, so that a multi-page or evolving tuning session isn't
  interrupted (FR-7, FR-9, FR-10).
  - [X] 4.1 Write the registry-population spec: initial entries come
    from either the reviewer's `recommended_fixes` (live-edit follows
    a Gate result) or an empty registry populated ad hoc (starting
    from scratch) [verify: code-only]
  - [X] 4.2 Write the mid-session-addition spec: a new entry can be
    registered at any point without reloading the page or losing
    existing toggle state, and the panel re-renders to include the new
    row [verify: code-only]
  - [X] 4.3 Write the gate-independence spec: live-edit mode is usable
    before generation, after PASS, or after FAIL — no conditional
    dependency on gate state anywhere in the trigger text [verify:
    code-only]
  - [X] 4.4 Write the navigation-resilience spec: a real full-page
    navigation is detected (not intercepted or faked — real redirect
    targets, timing, and errors are preserved) and the injection
    (panel + current registry state) is re-applied on the new page;
    state the brief panel-absent gap as an accepted, documented
    limitation [verify: code-only]
  - [X] 4.5 Live-run: start live-edit mode before any generation step
    (build-from-scratch case), add a candidate mid-session, trigger a
    real navigation via a link click, confirm the panel and prior
    toggle state reappear on the new page [verify: manual-run-claude]
    → navigation-resilience confirmed live (registry undefined before
      re-injection, correct after a real goto); mid-session addition
      confirmed by user directly (new row appeared and applied, no
      reload); drag/toggle/bulk confirmed by user on the full-featured
      panel [live] (2026-07-28)

- [X] 5.0 **User Story:** As a developer, I want live-edit mode
  discoverable in `visual-impl`'s help text (with an opt-out) and the
  tool's stale EXPERIMENTAL label corrected, so that the capability is
  known without unwanted process around it (FR-8, FR-11).
  - [X] 5.1 Add a one-line mention of live-edit mode's availability to
    `visual-impl.md`'s help/usage text only — never appended to a
    run's PASS/FAIL output, no dedicated menu or gate-triggered offer
    [verify: code-only]
  - [X] 5.2 Document the `tools.visual_impl.live_edit_mention` profile
    key (boolean, default `true`) in the Live-Edit Mode section: when
    `false`, the help-text mention is omitted. Decide explicitly
    whether any existing profile (`fast`, `minimal`, `quality`,
    `research`) should set this to `false` (e.g. `fast`/`minimal`
    lean toward quieter output); if none should, state that decision
    inline rather than leaving it unresolved. Edit the chosen
    profile's YAML only if the decision is to opt one out [verify:
    code-only]
    → decided: no profile opts out (fast = speed not quietness signal;
      minimal disables RLM/memory, not visual tooling); no YAML file
      edited [live] (2026-07-28)
  - [X] 5.3 Remove all four EXPERIMENTAL/stability-caveat locations in
    `visual-impl.md` and replace each with a plain stable-status
    statement: the frontmatter `description:` field, the H1 title's
    `(EXPERIMENTAL)` suffix, the `**Status: experimental...**` sentence
    (including its contract-stability caveat — "the argument and
    output contract may change... pin a plugin version if you script
    around it"), and the Notes-section paragraph with the conditional
    "once it has enough end-to-end runs, promote to stable" language
    [verify: code-only]
  - [X] 5.4 Remove the "EXPERIMENTAL (usable; output contract may
    change)" label from `visual-qa-reviewer.md`'s header/description;
    no contract change accompanies this edit [verify: code-only]
  - [X] 5.5 Grep both files after edits to confirm zero remaining
    occurrences of "EXPERIMENTAL", and separately confirm no surviving
    contract-instability caveat language ("contract may change", "pin
    a plugin version", "not yet validated end-to-end") remains even
    though it doesn't contain the literal word EXPERIMENTAL. Also
    confirm the live-edit mention appears only in help/usage text (not
    in Output or Gate-result sections) [verify: code-only]
    → grep: 0 matches for EXPERIMENTAL and 0 matches for caveat phrases
      in both files; live-edit mentions confirmed only in frontmatter,
      When-to-Use, and the dedicated Live-Edit Mode section — none in
      Output/Gate sections [live] (2026-07-28)
