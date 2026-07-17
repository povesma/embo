# 040: Ship the Visual-Impl Command + Visual-QA Reviewer to Plugin Users

Combined doc (problem + decisions + scope + tasks). Compact by
agreement: the design already exists in the two prototype files; a
separate PRD/tech-design would restate them. This doc records the
decisions made in the 2026-07-14/15 session and tracks the work to make
the visual design-to-code tooling available to plugin users.

## Problem

The front-end design-to-code verification tooling —
`visual-qa-reviewer` (independent visual-QA judge) and the
`visual-impl` orchestration command — existed only in the maintainer's
repo `.claude/` tree, untracked and unshipped (claude-mem obs 22578,
22579, 28695). A plugin user installing embo did **not** get them:

- `plugin/agents/` shipped only 3 agents (approach-validator,
  examine-advisor, rlm-subcall) — no visual-qa-reviewer.
- No `visual-impl` command existed under `plugin/commands/`.

CLAUDE.md and the command header both describe these as exploratory
prototypes. The goal of this task is to make them usable by end users,
with Figma named as the primary design source.

## Decisions (this session)

1. **Playwright CLI, not Playwright MCP, for browser automation
   (HARD REQUIREMENT — user-stated, non-negotiable).** Capture, live CSS
   reads, and interaction probes MUST run through the `@playwright/cli`
   binary, NEVER the Playwright MCP. Rationale, re-verified 2026-07-17
   against playwright.dev/agent-cli + independent benchmarks: MCP streams
   full accessibility trees and Base64 screenshot bytes into the model
   context (~114k tokens for a typical task); the CLI saves screenshots +
   YAML snapshots to disk (`.playwright-cli/`) and returns file paths +
   element refs (~27k tokens) — a ~4× token reduction, and faster (a
   persistent daemon, no per-call MCP round-trip). This is a documented,
   testable constraint, not an implementation preference — see AC-1.
   (The e2e test agents in task 033 are the self-healing/exploratory
   workload and keep the MCP; out of scope here.)

2. **Figma stays on MCP** — there is no Figma CLI equivalent; design
   extraction (`get_variable_defs`, `get_design_context`, `get_metadata`,
   `get_screenshot`, Code Connect) genuinely needs the MCP.

3. **Figma is the named, prominent design source** (user requirement):
   the most popular design tool, so When-to-Use, arguments, and
   prerequisites call it out specifically.

4. **Conformance-first verification; pixel diff is a caveated fallback.**
   The primary gate is (a) **token/property conformance** — read live
   computed CSS via `playwright-cli eval` and compare numerically to the
   named design tokens/component specs ("live `border-radius: 28px`,
   token defines `16px`") — plus (b) an **independent visual-qa-reviewer**
   7-category audit over the render + the Figma mockup. This is SYSTEM
   MODE (Step 4-SYSTEM), the command's preferred path. Raw pixel diff
   survives ONLY as a weak MOCKUP-mode fallback (no documented design
   system), labelled as such: generous `maxDiffPixelRatio`, masking, and
   the stated caveat that a design export never pixel-matches a render.
   `playwright-cli` is used for capture + `eval` + `resize` only (`eval`
   and `resize` verified present in the installed binary, 2026-07-17).

6. **Target is any reachable URL, not just localhost (design fix).** The
   prototype hardcoded a local dev server. Corrected to `<target-url>`
   spanning local dev server, hosted preview deploy, staging, and
   sandbox — because design work on a large external project usually
   runs against a hosted environment, not a local one. Step 3 checks
   reachability and stops on a dead URL; warns that a hosted preview lags
   the latest push.

7. **`.claude/` dogfood sources are committed (2026-07-15 decision).**
   The repo historically tracks `.claude/` (its dogfood config); these
   two files were untracked only because they were prototypes. Decision:
   commit them to keep the tradition. NOTE: this means two copies of each
   file (`plugin/` = shipped, `.claude/` = dogfood) that must be kept in
   sync manually — a known drift risk (this session hand-synced 4 files).
   The maintainer may later switch to a single source of truth; if so,
   drop the `.claude/` copies and treat `plugin/` as canonical.
   → RESOLVED 2026-07-17: the `.claude/commands/dev/visual-impl.md`
   dogfood copy was deleted; `plugin/` is now the sole source of truth
   for this command. (The `.claude/agents/` reviewer copy, if still
   present, remains a separate sync item.)

8. **Version → 0.2.0; git tag + GitHub Release DEFERRED until verified.**
   Adding a user-facing command + agent is a minor feature bump. But the
   feature has zero end-to-end runs, so cutting a tagged Release now would
   advertise an unrun experimental capability (RULE:ASSUME-BROKEN).
   Decision: bump version + CHANGELOG in this commit; hold the tag and
   GitHub Release until at least one real end-to-end run (task 1.x/2.x)
   passes.

9. **Error always stops; only clean absence degrades (2026-07-15).**
   Challenged: "if a tool is not operational we should stop and fix it,
   never continue; exceptions are real, not automatic." Correct. The
   fix distinguishes a *broken/erroring tool or missing required input*
   (→ STOP + report, no auto-fallback, exception only from the user)
   from an *optional input that is legitimately, cleanly absent* — e.g.
   Code Connect, which most projects never author, or no documented
   token system. Only the latter degrades, and every degraded path is
   stated in the output so the user can object. "Degrade gracefully" as
   originally worded was too loose — it could read as swallow-the-error.

5. **Ship status: EXPERIMENTAL (decided 2026-07-15).** No end-to-end
   runs of the CLI-switched version exist on record (claude-mem search
   confirms only edit observations; the one June anecdote predates the
   CLI switch). Promising "stable" on a never-run version would violate
   RULE:ASSUME-BROKEN. Both files now carry an "experimental — contract
   may change" label instead of "PROTOTYPE". Promotion to stable is a
   later state, earned by real runs. See task 5.0.

## Rejected decisions

- **`toHaveScreenshot` as the first-class diff gate** (was Decision 4).
  Rejected 2026-07-17: `@playwright/cli` (capture binary) is NOT
  `@playwright/test` (the runner that owns `toHaveScreenshot`) — the diff
  step could not run and broke the first live use. Superseded by
  Decision 4 (conformance-first).
- **Raw pixel diff against a Figma export as the gate.** Rejected: a
  browser render never pixel-matches a design canvas (font-smoothing /
  sub-pixel / anti-aliasing noise); kept only as a caveated MOCKUP-mode
  fallback.
- **Playwright MCP for browser automation.** Rejected: token-inefficient
  (~4×) and slower than the CLI — see Decision 1.

## Acceptance criteria

- **AC-1 (no MCP for browser work):** every browser action in the
  command — navigate, screenshot, computed-CSS read, resize, interaction
  probe — invokes the `@playwright/cli` binary. No
  `mcp__...playwright__browser_*` call appears in the browser-automation
  path. (Figma MCP is separate and allowed.)
- **AC-2 (conformance is the primary gate):** in SYSTEM MODE the pass/
  fail verdict is driven by token/component/behavior conformance +
  the visual-qa-reviewer audit, with no pixel-diff threshold. Pixel diff
  appears only under MOCKUP MODE, explicitly labelled a weak fallback.
- **AC-3 (no false tool claims):** the command contains no statement that
  the capture CLI is the `@playwright/test` runner or that it provides
  `toHaveScreenshot`.
- **AC-4 (tool reality):** the `eval` and `resize` subcommands the gate
  relies on exist in the installed `@playwright/cli` binary (verified
  2026-07-17).

## Scope

- Source the two files into the plugin tree, flat namespace.
- Switch all Playwright MCP browser calls to Playwright CLI; keep Figma
  on MCP.
- Add a prerequisites preflight that installs the Playwright CLI if
  absent and verifies it runs.
- Strip private paths and rewrite `/dev:` → `/embo:`.
- Defer: ship-status decision, full graceful-degrade hardening,
  discoverability (CLAUDE.md / README), commit.

## Tasks

- [~] 1.0 **User Story:** As a plugin user, I can invoke
  `/embo:visual-impl` and it uses the Playwright CLI for browser work.
  [4/4 coded; 1.4 verified live; 1.1/1.2/1.3 pending a live end-to-end
  run. Command registration + tool contract corrected 2026-07-17.]
  - [~] 1.1 Switch browser automation from Playwright MCP to CLI in the
    source command (`open`, `eval`, `resize`, `screenshot`). Figma kept
    on MCP. [verify: manual-run-claude]
      → CORRECTED 2026-07-17: the original coding wired the diff to
        `toHaveScreenshot`, which does NOT exist in `@playwright/cli`
        (it is `@playwright/test`-only). Rewrote the gate to
        conformance-first (Decision 4); pixel diff via standalone
        pixelmatch is now a MOCKUP-only fallback. CLI `eval`/`resize`
        verified present in the installed binary. Still pending a live
        end-to-end run.
  - [X] 1.2 Prerequisites preflight: Figma-MCP presence check,
    Playwright-CLI install-if-absent + functional re-check, reachable-
    URL note. [verify: manual-run-claude]
      → DEFECT found + fixed during verification (2026-07-15): the
        shipped preflight installed the WRONG package —
        `npm install -g @playwright/test playwright-cli`. The unscoped
        `playwright-cli` package is DEPRECATED and ships no working
        binary (verified: install succeeded, `playwright-cli` still
        command-not-found). The correct package is **`@playwright/cli`**
        (scoped, official MS maintainers, provides the `playwright-cli`
        binary). Root cause: I took the package name from a Context7
        *library listing* (`/microsoft/playwright-cli`) and shipped it
        without running the install — RULE:RESEARCH-VERIFY /
        RULE:ASSUME-BROKEN miss. Fixed both copies to `@playwright/cli`,
        VERIFIED live: `npm install -g @playwright/cli` →
        `playwright-cli --version` = 0.1.17. Preflight also now probes
        for an existing install (PATH + `npx --no-install`) before
        installing, per user request. This fix NOT yet committed.
      → FOLLOW-UP: extend the probe to more managers (pnpm/yarn/bun/
        brew/local .bin) so a non-npm-global install isn't false-
        negatived into a redundant global install.
  - [~] 1.3 Copy `visual-impl.md` → `plugin/commands/` (→
    `/embo:visual-impl`) and `visual-qa-reviewer.md` →
    `plugin/agents/`. [verify: code-only]
      → done 2026-07-15 (claude-mem obs 28722)
  - [X] 1.4 Rewrite `/dev:visual-impl` → `/embo:visual-impl` (2 refs);
    strip `~/artec/...` origin path from the shipped command.
    [verify: code-only]
      → INCOMPLETE until 2026-07-17: the shipped command lacked YAML
        frontmatter, so it did not register as `/embo:visual-impl` at
        all, and a stale dogfood copy `.claude/commands/dev/
        visual-impl.md` kept surfacing `/dev:visual-impl`. Fixed: added
        frontmatter (registration VERIFIED live — skill list now shows
        `embo:visual-impl`), deleted the stale dev/ copy (git rm).
        Now genuinely done.

- [~] 2.0 **User Story:** As a plugin user, the command fails cleanly
  when its dependencies are absent, and works against any target origin.
  [1/3 coded]
  - [~] 2.1 Target is a **URL of any origin**, not a local server:
    renamed `<target-route>` → `<target-url>`; Arguments, prereq #3, and
    Step 3 now cover local dev server, hosted preview deploy, staging,
    and sandbox. Step 3 checks reachability and stops on a dead URL
    instead of screenshotting nothing; warns that a hosted preview lags
    the latest push. (Design correction, RULE:BEHAVIOUR-FIRST — the
    prototype wrongly hardcoded localhost.) [verify: manual-run-claude]
      → coded 2026-07-15 in both plugin + .claude copies
  - [~] 2.2 Degrade policy specified (decision 9): **error always stops,
    only clean absence degrades**. A tool that errors or a required input
    missing → halt + report, no auto-fallback, no self-granted exception.
    Preflight #1 splits Figma-MCP *required* tools (stop) from *optional*
    Code Connect (proceed, note reduced fidelity). Defined degrade paths:
    Code Connect absent → direct markup; token export absent → MOCKUP
    mode. Every degraded path stated in output. [verify: manual-run-claude]
      → coded 2026-07-15 (both copies synced)
  - [~] 2.3 Clean stop when required Figma-MCP tools are absent:
    preflight #1 says stop with a connect-the-server message if ANY of
    metadata/design-context/variable-defs/screenshot is missing.
    [verify: manual-run-claude]
      → coded 2026-07-15

- [X] 3.0 **User Story:** As a plugin user, I can discover this tooling.
  [2/2]
  - [X] 3.1 CLAUDE.md: documented as shipped-experimental (agent +
    command annotated in the file-structure tree; command count 16→17,
    intro bullet mentions `/embo:visual-impl`). [verify: code-only]
      → done 2026-07-15
  - [X] 3.2 README: added `/embo:visual-impl` row (Design phase, marked
    experimental) to the Available Commands table; also fixed the stale
    "16 commands" count in `.claude-plugin/marketplace.json`.
    [verify: code-only]
      → done 2026-07-15

- [~] 4.0 **User Story:** As the maintainer, the change is committed and
  versioned; the tagged release waits for verification. [1/3 coded]
  - [X] 4.1 Commit moved + edited files (plugin/ copies, .claude/
    sources, CLAUDE.md, README, both manifests, CHANGELOG, this doc).
    [verify: code-only]
      → PR #25 merged to main 2026-07-15 (commit cc91109, 10 files)
  - [X] 4.2 Bump version 0.1.5 → 0.2.0 in `plugin/.claude-plugin/
    plugin.json` + `.claude-plugin/marketplace.json`; add a 0.2.0
    CHANGELOG entry marked unreleased. [verify: code-only]
      → merged in PR #25 (cc91109)
  - [ ] 4.3 Cut the git tag `v0.2.0` + GitHub Release — DEFERRED until a
    verified end-to-end run exists (decision 8). [verify: manual]

- [X] 5.0 **User Story (DECISION GATE):** As the maintainer, I decide
  whether these ship stable or experimental. [1/1]
  - [X] 5.1 Decided EXPERIMENTAL (2026-07-15): no end-to-end run
    evidence for the CLI-switched version. Replaced "PROTOTYPE" with an
    "experimental — contract may change" label in both plugin copies and
    both `.claude/` sources (4 files). Promotion to stable deferred until
    real runs exist. [verify: code-only]
      → verified: grep for "prototype" across all 4 files returns no
        matches (2026-07-15)

## Related

- Task 032 (plugin packaging) — flagged both as untracked prototypes.
- Task 033 (bundle test agents) — the e2e test agents keep Playwright
  MCP (self-healing workload); this task is the CLI counterexample.
- CLAUDE.md "Test Subagents" + `visual-qa-reviewer.md` header.
