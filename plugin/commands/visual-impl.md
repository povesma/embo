---
description: >
  EXPERIMENTAL design-to-code loop: implement a Figma node as frontend
  code and verify it against the design by token/property conformance and
  an independent visual-qa-reviewer agent (pixel diff is a weak,
  mockup-only fallback). Drives the Figma MCP (design source) and the
  Playwright CLI for capture + live CSS reads. Argument and output
  contract may still change.
---

# Visual Design Implementation (EXPERIMENTAL)

**Status: experimental — usable, but the argument and output contract
may change.** Not yet validated end-to-end enough to promise stability;
pin a plugin version if you script around it. This command
orchestrates a design-to-code loop that implements a Figma node and
verifies it against the design by **conformance** (token / component /
behavior) and an independent review agent. It drives the **Figma MCP**
(design source) and the **Playwright CLI** (render / capture / live CSS
reads / interaction probes), plus the `visual-qa-reviewer` agent.

Browser automation uses the **Playwright CLI** for capture, not the
Playwright MCP: the CLI keeps screenshots and DOM state on disk instead
of streaming Base64 image bytes and full accessibility trees into the
LLM context, so a multi-step run does not exhaust the context window.
Figma stays on MCP (no CLI equivalent).

Core thesis: **do not gate on a raw pixel diff against the Figma frame.**
A browser render never pixel-matches a design canvas (OS font-smoothing,
sub-pixel and anti-aliasing differences produce large false-positive
noise), and a self-generated screenshot baseline just ratifies whatever
the author built. Instead: (1) extract a machine-readable spec (tokens /
component defs), (2) render live, (3) verify by **property/token
conformance** — read the live computed CSS and compare it numerically to
the named design values ("live `border-radius: 28px`, token defines
`16px`") — and (4) a review step SEPARATE from authoring: an independent
visual-qa-reviewer runs a 7-category audit over the render + the Figma
mockup. The same model that writes the code cannot be trusted to judge
it. Pixel diff is retained only as a weak MOCKUP-mode fallback, heavily
caveated (see Step 4).

## When to Use

- A designer hands you a Figma frame as ground truth and you must
  implement it to the pixel in HTML/CSS/JS.
- You want the build gated against the design, not against the author's
  own opinion of the build.

## Arguments

```
/embo:visual-impl <figma-node-url> <target-url>
```

- `<figma-node-url>` — a node-specific Figma URL (must contain
  `node-id`). The command extracts `fileKey` and `nodeId` from it.
- `<target-url>` — the URL where the built page under review is served.
  This can be **any reachable origin**, not just localhost:
  - a local dev server (`http://localhost:3000/pricing`),
  - a hosted preview deploy (`https://pr-42.myapp.vercel.app/pricing`),
  - a staging / review-app / sandbox environment.
  The render → screenshot → diff loop only needs the URL to respond; it
  does not care where it is hosted. **Caveat for hosted targets:** the
  code you author must be *deployed* to that URL before the render
  reflects it — unlike a local server, a preview deploy lags behind your
  edits. Verify the target shows your latest change before trusting the
  diff.

If the URL has no `node-id`, stop and ask for a node-specific URL —
the Figma tools require it.

## Step 0: Is there a documented design system? (decides the whole mode)

Before doing anything else, establish whether you are working against a
**documented design system** or a **single mockup**. This changes the
baseline, the generation method, and the verification gate.

A "documented design system" is a three-layer source:

```
Tokens      → color / type / spacing primitives (e.g. an "Artec Foundation"
              file, design-tokens export, Tailwind/CSS-var theme)
Components  → per-component specs: Button, Breadcrumbs, Modal, Accordion,
              Data table … each with variants, states, measurements
Templates   → how components compose into a page (a "Patterns"/templates file)
```

**Detect it, in this order — first hit wins:**

1. **User-provided** — the user named a Foundation/design-system file, a
   templates/patterns file, or a tokens export. Use those node URLs.
2. **In-repo** — look for a design-tokens source or component library:
   `tokens.json`, `design-tokens.*`, a Tailwind theme with custom
   tokens, a Storybook setup, or **Code Connect** mappings
   (`*.figma.tsx` / `get_code_connect_map`). Use the Glob tool, not
   Bash loops.
3. **In Figma** — the linked file references a published library
   (`get_variable_defs` returns named token roles like
   `Themes/Button/button-primary`, not raw hex). That naming means a
   system exists even if you were not handed it.

**Then branch:**

- **System found → SYSTEM MODE.** Build a `design-contract` (Step 0a),
  generate by *assembling documented components* constrained to tokens,
  and verify by **conformance** (Step 4-SYSTEM), not pixel diff. This is
  the preferred, higher-fidelity path.
- **No system, single mockup → MOCKUP MODE.** Fall back to the
  baseline-image pixel-diff loop described in the original steps below.
  State explicitly in your output that you ran in mockup mode and why
  (no documented system found), since its guarantees are weaker.

If you are unsure which mode applies, **ask the user** whether a
documented design system exists and where — do not silently assume a
single mockup is the whole spec. (A single node can be one frame of a
multi-frame review board; treating it as the spec produced a meaningless
result in early testing.)

### Step 0a: Build the design-contract (SYSTEM MODE only)

Extract the system **once** into a cached, machine-readable contract so
every later run (and every page) reads the cache, not Figma live —
otherwise the tool is too slow to use.

- Tokens: `get_variable_defs` on the Foundation/token node → full
  color / type ramp / spacing scale, by named role.
- Components: `get_design_context` (and `get_metadata`) on each
  component node the page uses (Button, Breadcrumbs, etc.) → variants,
  states, measurements, and the **defined** radius/padding/states.
- Templates: `get_metadata` on the templates node → the canonical block
  order and which components a page of this type must contain.
- Code Connect: `get_code_connect_map` → which Figma components map to
  real code components (so generation can place real components).

Write this to `tmp/design-contract.json` (or a project-chosen path).
Refresh only when the design system changes — not every run.

## Prerequisites — check first, install if missing

Run this preflight before Step 0. If any check fails, stop and resolve
it (or report the blocker); do not proceed on a broken tool.

**1. Figma MCP** — the design source; not installable from here.
- **Required tools** — `get_metadata`, `get_design_context`,
  `get_variable_defs`, `get_screenshot`. If ANY of these is absent,
  **stop** and tell the user to connect the Figma MCP server, then
  re-run. The loop cannot produce a design baseline without them.
- **Optional enhancement** — Code Connect (`get_code_connect_map`).
  When present, generation assembles from the project's real code
  components (higher fidelity). When absent, do **not** stop: proceed
  and generate markup directly, and state in the output that Code
  Connect was unavailable so fidelity is reduced (no real-component
  mapping).

**2. Playwright CLI (`@playwright/cli`)** — the browser-automation tool
for capture, live CSS reads (`eval`), and viewport probes (`resize`).
Browser work goes through this CLI, **never the Playwright MCP**: the
MCP streams accessibility trees and screenshot bytes into the model
context (~4× the tokens, and slower), while the CLI writes them to disk
and returns file paths + element refs. This is a hard requirement.

The `playwright-cli` binary is provided by the **`@playwright/cli`**
package (scoped, official Microsoft). Do NOT use the unscoped
`playwright-cli` npm package — it is deprecated and ships no working
binary. Note this CLI is **not** the `@playwright/test` runner; it does
not provide `toHaveScreenshot` (see Step 4).

First check whether it is already present (avoid a redundant global
install):

```bash
playwright-cli --version
```

If that prints a version, you are done. If not-found, check a
project-local install before installing globally:

```bash
npx --no-install playwright-cli --version
```

Only if BOTH report not-found, install it, then verify:

```bash
npm install -g @playwright/cli
playwright-cli --version
```

The final `--version` must print a version. If it still fails, report
the error and stop — the render/measure steps cannot run without it.
Installing browsers may also be needed once: `npx playwright install`.

**3. A reachable target URL** — some origin serving the current build
of the code under review. This may be a local dev server OR a hosted
preview / staging / sandbox environment. Confirm `<target-url>`
responds before rendering (Step 3). Only start a server yourself if the
target is local and startable; for a hosted URL, verify reachability —
never try to start it.

Storybook + addon-mcp and Uiprobe-style property audit are NOT required
— they are later extensions. The core loop is Figma spec → live render →
**conformance check (token/component/behavior)** → separate reviewer →
gate. Pixel diff is a MOCKUP-mode fallback only, not the core gate.

## The Loop: Parse → Generate → Render → Measure → Correct → Gate

### 1. Parse (build the spec — do NOT work from the image alone)

- **SYSTEM MODE:** read the cached `design-contract.json` from Step 0a.
  The contract IS the spec — tokens, component defs, and the template's
  required block order. Do not re-pull from Figma if the cache is fresh.
- **MOCKUP MODE:** `get_metadata` on the node for structure;
  `get_design_context` for reference code + screenshot;
  `get_variable_defs` for whatever tokens the node exposes. Map tokens
  to the project's CSS vars / Tailwind so generation is constrained to
  design-system values, not guessed hex/px.
- In both modes, use **Code Connect** mappings to assemble from the
  project's real components instead of reinventing markup.

### 2. Generate (author under hard constraints)

Author the implementation. Apply these generation constraints (from
PSD2Code — they made generation deterministic, model-independent):

- Integer coordinates for absolute positioning; no fractional px.
- Element sizing derived from actual asset sizes, not parsed-JSON sizes.
- Emit text only for nodes whose type is text.
- Plan z-index explicitly; no overlap or out-of-bounds placement.
- Constrain to the exported tokens; never hardcode a value a token
  covers.

### 3. Render

- Ensure `<target-url>` is reachable.
  - **Local, startable** → if the server is down and you know the start
    command, start it and report the command you used.
  - **Hosted (preview / staging / sandbox)** → do NOT try to start
    anything. Confirm the URL responds; if the target deploys from your
    branch, confirm it reflects your latest push (a preview lags your
    edits — rendering a stale deploy makes the diff meaningless).
  - If the URL does not respond, stop and report it — do not screenshot
    a dead page.
- `playwright-cli open <target-url>` (or `goto` on an open browser).

### 4-SYSTEM. Verify by conformance (SYSTEM MODE — preferred)

When a documented design system exists, pixel diff is the WRONG gate: a
design system is applied across many pages, so the page will never match
any single mockup pixel-for-pixel. Verify **conformance to the contract**
instead, in three checks — all measured, each traceable to a named
token / component / template entry:

- **a. Token conformance** — read live CSS via `playwright-cli eval`
  (computed styles of headings, body, buttons, surfaces). Every
  color/size/space must resolve to a defined token. Report deviations as
  "live `border-radius: 28px`, Button component defines `Npx`".
- **b. Component conformance** — for each component on the page
  (Button, Breadcrumbs, Accordion, Modal, Data table…), compare the
  live element against its contract spec: variant, states, padding,
  defined radius. Catch missing states (no hover/focus) and off-spec
  values.
- **c. Behavior conformance** — probe the interactions the system
  specifies, live, **at each target breakpoint** (resize via
  `playwright-cli resize <w> <h>`): sticky-on-scroll,
  anchor-scroll-to-section,
  accordion expand/collapse, modal focus, dropdown open. A scroll/click
  probe PROVES behavior; a screenshot cannot. (Early testing caught a
  tab bar that was `position: static` instead of the specified sticky —
  only a real scroll probe revealed it.)
- **d. Composition conformance** — compare the live block sequence
  against the template's required block order; flag missing or
  reordered sections (e.g. a tab bar missing two of its four tabs).

Then go to step 5 (separate reviewer) with these findings. There is no
pixel threshold in system mode; the gate is "zero high-severity
conformance violations" plus the reviewer's verdict.

### 4. Measure (MOCKUP MODE — weak fallback, no documented design system)

Use this ONLY when Step 0 found no documented design system. A raw pixel
diff against a Figma export is unreliable — a browser render never
pixel-matches a design canvas (OS font-smoothing, sub-pixel and
anti-aliasing differences produce large false-positive noise), so treat
its result as a hint for the reviewer, not a hard gate.

- Baseline: `get_screenshot` on the Figma node (Figma MCP) → save path.
- Live: `playwright-cli screenshot <path>` (full page or the matching
  frame) → save path.
- Numeric diff: run a standalone pixel comparison (e.g. `pixelmatch`,
  the library Playwright itself uses, or `looks-same`) between the two
  saved PNGs → mismatch ratio + a diff image. Do **not** use
  `toHaveScreenshot` / `toMatchSnapshot`: those live only in the
  `@playwright/test` runner (a different product from `@playwright/cli`),
  and they compare against a self-generated baseline, not an external
  design export. Set a **generous** threshold and mask volatile / text
  regions, since exact-match is not expected.
- Also capture per-element computed CSS with `playwright-cli eval` and
  hand it to the reviewer — property comparison catches what a noisy
  pixel diff cannot (font-weight, spacing, radius).

### 5. Correct (spawn the SEPARATE judge)

Spawn the `visual-qa-reviewer` agent via the Agent tool. It runs in a
clean context and did not author the code. Pass it:

- `figma_baseline` (path), `live_render` (path)
- `conformance_findings` (SYSTEM MODE) — the token / component /
  behavior / composition deviations from Step 4-SYSTEM; or
  `numeric_verdict` (MOCKUP MODE) — pixel mismatch ratio + diff-image
  path, flagged as a weak signal
- `design_spec` / `live_properties` (computed CSS) if available

It returns measured findings + a PASS/FAIL verdict + ordered fixes.
**Do not self-review in this command** — that defeats the purpose.

### 6. Gate

- If `verdict: FAIL` (SYSTEM MODE: any high-severity conformance
  violation; MOCKUP MODE: reviewer FAIL, pixel mismatch as supporting
  evidence): apply the reviewer's ordered fixes, then loop back to
  step 2. Cap at 3 iterations; if still failing, stop and report the
  remaining findings for human judgement.
- If `verdict: PASS`: report done, with the conformance summary (or the
  pixel value in mockup mode) and the screenshot paths.

**Merge is never approved on the model's opinion alone — it requires
zero high-severity conformance violations plus the independent
reviewer's PASS.**

## Critical distinction (do not conflate)

| Question | Tool class |
|---|---|
| "Match the **design**?" | Design QA — Figma frame baseline (this command) |
| "**Changed** between builds?" | Visual regression — Percy/Chromatic/Backstop |

This command answers "match the design". It is NOT a regression tool;
the baseline is the Figma frame, not a prior build.

## Output

Report: iterations run, the conformance result (SYSTEM MODE:
token/component/behavior/composition violations, if any) or the pixel
mismatch value vs threshold (MOCKUP MODE), the reviewer's remaining
findings (if any), and the saved baseline/live screenshot paths so the
result can be re-checked without re-running.

## Notes

- This is experimental. Once it has enough end-to-end runs to trust its
  guarantees, promote it to stable (freeze the arg/output contract) and
  drop the experimental note.
- **Error always stops; only clean absence degrades.** A tool that
  ERRORS, or a required input that is missing, halts the run — report it
  and stop, never fall back to a lesser path to paper over a broken
  tool. Do not grant yourself an exception; a real exception comes from
  the user, explicitly, not automatically. Degradation below applies
  ONLY to an OPTIONAL input that is legitimately, non-erroneously absent
  (the project simply never authored it). Every degraded path is stated
  in the output so the user can object.
  - **Code Connect absent** (project never set it up — the common case)
    → generate markup directly instead of assembling real components
    (preflight #1); note it in the output.
  - **Token export absent** (no documented design system found in
    Step 0) → run MOCKUP mode: baseline-image pixel diff instead of
    SYSTEM-mode conformance. State that mockup mode ran and why.
  - In every degraded run, the core loop still completes (baseline →
    render → diff → review → gate); the output names what was reduced.
    But if a *required* tool (Figma-MCP required set, Playwright CLI,
    the target URL) fails or errors mid-run, stop — do not degrade.
