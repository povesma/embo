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

1. **Playwright CLI, not Playwright MCP, for browser automation.**
   Verified against Microsoft's own docs via Context7
   (`/microsoft/playwright-cli`): the CLI is "designed for modern coding
   agents, token-efficient… avoids loading large tool schemas and
   accessibility trees into the model context." The MCP is for
   "exploratory automation, self-healing tests, long-running autonomous
   workflows where maintaining continuous browser context matters more
   than token cost." `visual-impl` runs a scripted navigate → screenshot
   → resize → diff sequence — the CLI's exact target workload — so the
   CLI is strictly better here. (The e2e test agents in task 033 are the
   "self-healing/exploratory" workload and would keep the MCP; out of
   scope here.)

2. **Figma stays on MCP** — there is no Figma CLI equivalent; design
   extraction (`get_variable_defs`, `get_design_context`, `get_metadata`,
   `get_screenshot`, Code Connect) genuinely needs the MCP.

3. **Figma is the named, prominent design source** (user requirement):
   the most popular design tool, so When-to-Use, arguments, and
   prerequisites call it out specifically.

4. **The CLI switch also closed a real gap** — the numeric-diff step was
   under-specified ("prefer toHaveScreenshot… otherwise looks-same"). The
   CLI *is* the `@playwright/test` runner, so `toHaveScreenshot({
   maxDiffPixelRatio })` (auto `-actual`/`-expected`/`-diff` images)
   becomes the first-class diff method.

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

8. **Version → 0.2.0; git tag + GitHub Release DEFERRED until verified.**
   Adding a user-facing command + agent is a minor feature bump. But the
   feature has zero end-to-end runs, so cutting a tagged Release now would
   advertise an unrun experimental capability (RULE:ASSUME-BROKEN).
   Decision: bump version + CHANGELOG in this commit; hold the tag and
   GitHub Release until at least one real end-to-end run (task 1.x/2.x)
   passes.

5. **Ship status: EXPERIMENTAL (decided 2026-07-15).** No end-to-end
   runs of the CLI-switched version exist on record (claude-mem search
   confirms only edit observations; the one June anecdote predates the
   CLI switch). Promising "stable" on a never-run version would violate
   RULE:ASSUME-BROKEN. Both files now carry an "experimental — contract
   may change" label instead of "PROTOTYPE". Promotion to stable is a
   later state, earned by real runs. See task 5.0.

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
  [4/4 coded, pending verification]
  - [~] 1.1 Switch browser automation from Playwright MCP to CLI in the
    source command (`open`, `eval`, `resize`, `screenshot`;
    `toHaveScreenshot` diff). Figma kept on MCP. [verify: manual-run-claude]
  - [~] 1.2 Add prerequisites preflight: Figma-MCP presence check,
    `playwright-cli --version || npm install -g …` install-if-absent +
    functional re-check, dev-server note. [verify: manual-run-claude]
  - [~] 1.3 Copy `visual-impl.md` → `plugin/commands/` (→
    `/embo:visual-impl`) and `visual-qa-reviewer.md` →
    `plugin/agents/`. [verify: code-only]
      → done 2026-07-15 (claude-mem obs 28722)
  - [~] 1.4 Rewrite `/dev:visual-impl` → `/embo:visual-impl` (2 refs);
    strip `~/artec/...` origin path from the shipped command.
    [verify: code-only]

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
  - [ ] 2.2 Graceful-degrade when Code Connect / token export is
    unavailable (already noted in command Notes — verify it actually
    degrades, not just documented). [verify: manual-run-claude]
  - [ ] 2.3 Clean stop when the Figma MCP is absent (preflight #1 says
    stop — verify it actually does, with a clear message).
    [verify: manual-run-claude]

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
  - [~] 4.1 Commit moved + edited files (plugin/ copies, .claude/
    sources, CLAUDE.md, README, both manifests, CHANGELOG, this doc).
    [verify: code-only]
  - [~] 4.2 Bump version 0.1.5 → 0.2.0 in `plugin/.claude-plugin/
    plugin.json` + `.claude-plugin/marketplace.json`; add a 0.2.0
    CHANGELOG entry marked unreleased. [verify: code-only]
      → coded 2026-07-15
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
