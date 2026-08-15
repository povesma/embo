# Changelog

All notable changes to the embo plugin are documented here.

## [0.2.5] - Unreleased

### Added

- `/embo:visual-impl` gains **Live-Edit Mode**: a floating toggle panel
  injected into the live page lets you turn candidate fixes on/off (or
  bulk on/off/invert) without touching devtools, then lock in only the
  chosen ones — written back to the project's own source, never
  auto-committed.
- The Live-Edit panel shows its version in the title (`Embo Live-Edit
  (v.X.Y.Z)`) and warns when it is older than the embo you have
  installed — so a panel you injected before upgrading embo no longer
  drifts out of sync silently; the warning tells you to re-inject.
- **Correction capture now works without enabling claude-mem's
  `correction` observations.** A hook records Claude's one-line
  acknowledgment of each steer (and an unacknowledged rejection note as
  a fallback) to a project-local `.claude/corrections.jsonl`, so
  capture no longer depends on `/embo:enable-corrections`.
- `/embo:improve` now reads that marker file as its primary source and
  the claude-mem observations as secondary, merging and deduplicating
  the two.

### Fixed

- The Live-Edit panel survives a real page navigation — a link you click
  yourself, on a server-rendered page or a client-side single-page app.
  The panel, your toggle state, and any live style re-appear on the new
  page automatically, and the panel restores itself if the app replaces
  the page body. Previously it vanished the moment you navigated away.

## [0.2.4] - 2026-08-08

### Added

- **Behavioral rules stay in view at the point of action.** Each rule
  loaded at session start now carries a short checklist that the agent
  restates as a one-line artifact before the action the rule governs —
  the closing-choice decision, defending a position under questioning,
  keeping a command simple, and handing work to a subagent. The
  reminders are injected on every turn, so a rule is present when it is
  needed rather than only at the top of the session.
- **Delegation is a forced choice at a fixed point.** The agent commits
  to delegate-or-inline on its third file-opening call and states which,
  with a reason, instead of deciding by feel — so bulk exploration is
  handed to a subagent when that is the better move.
- **`/embo:start` costs less context.** Session start no longer repeats
  the recent-work memory that claude-mem already injects, and it reads
  task files through a scout agent instead of pulling every task file
  into the session in full. On `fast`/`minimal` profiles it stays
  briefer still, so starting a session leaves more room for the work.
- **`/embo:prd` asks about the wider goal** the change serves before
  writing, so the document reflects the surrounding context, not just
  the stated feature.
- **`/embo:research:verify` proves each acceptance criterion against a
  source** and returns a per-criterion proof table.

### Fixed

- **`/embo:start` no longer asks to approve reading your profile.** The
  command's profile-load step is pre-authorized, so starting a session
  does not prompt for the `active-profile.yaml` read each time.
- **`/embo:git`'s over-engineering check names what to cut.** The PR
  review step returns a concrete file-and-line cut list rather than
  general advice.
- **`/embo:research:examine` and `/embo:research:verify` report an
  external-source outage** instead of silently continuing with less
  checking when NotebookLM is unavailable, so a partial verification is
  visible as partial.

## [0.2.3] - 2026-07-22

### Added

- **Delegation prompts** — embo now pushes the agent to hand work to a
  subagent where that beats working in the main conversation: bulk
  exploration, an unbiased critique of something written this session,
  an independent proof of a risky approach, several independent tasks
  at once, or a noisy troubleshooting loop. Before bulk exploration the
  agent states a `Delegation:` line (its decision, before the reads),
  and at planning approval gates, during `/embo:impl` discovery, and in
  troubleshooting/delivery loops it offers a subagent through a choice
  prompt. Offers are never auto-run; declining one silences that kind
  for the session. Small targeted lookups and context-dependent work
  are left inline.
- **`/embo:git deliver` cuts a release in one approval** — the deliver
  flow gains a `release` mode: it delivers your change to the base
  branch, then tags `vX.Y.Z` and publishes a GitHub Release, all behind
  the single plan approval. The version manifests and CHANGELOG are
  edited by you beforehand and delivered like any other file; the tool
  writes no source files of its own.

### Fixed

- `/embo:git deliver` commits to the branch named in the plan, not
  whichever branch happens to be checked out. Delivering from `main`
  no longer lands the commit on `main` while pushing a different branch;
  the tool moves to the plan's branch first and refuses to commit
  directly onto a protected branch (`main`/`master`).

## [0.2.2] - 2026-07-20

### Fixed

- `/embo:visual-impl` (experimental) is usable end-to-end: it implements
  a Figma node as frontend code and verifies the built page against the
  design.
- `/embo:improve` reviews your saved corrections reliably in any shell,
  and does not resurface ones you have already reviewed.

## [0.2.1] - 2026-07-17

### Fixed

- Status line no longer reports `mem:DOWN` when claude-mem is running on
  a non-default port. The claude-mem worker port is per-user
  (`CLAUDE_MEM_WORKER_PORT` if set, else `37700 + uid % 100`), but
  `statusline.sh` had hardcoded `37777`. The env var is set in the
  worker's own process and is not reliably inherited by the status line,
  and installs pin it to different values, so the segment now probes
  candidate ports (env override, then the per-user formula, then the
  `37777` fallback) and uses the first that answers with valid JSON.

## [0.2.0] - 2026-07-17

### Added

- `/embo:visual-impl` (**experimental**) — a design-to-code loop that
  implements a Figma node and gates the build against the design with a
  numeric diff plus an independent `visual-qa-reviewer` agent (also
  new). Browser automation uses the **Playwright CLI** (token-efficient,
  scripted); Figma extraction stays on the Figma MCP. The target is any
  reachable URL (local dev server, hosted preview, staging, or sandbox),
  not only localhost. Labeled experimental — argument and output
  contract may change until promoted to stable.
- **Opt-in correction capture** — `/embo:enable-corrections` configures
  claude-mem to record a `correction` observation whenever you steer how
  Claude works, so `/embo:improve` has real data to learn from;
  `/embo:disable-corrections` fully reverses it. Machine-wide and
  reversible. A `RULE:RESTATE-CORRECTION` behavioral rule (injected every
  turn via `behavioral-reminder.sh`) makes Claude restate a correction
  before acting, so conversation-only corrections become captured
  observations instead of being lost.
- `/embo:improve` now finds saved corrections by reading claude-mem's
  relational store directly (the MCP `type=` filter is broken upstream,
  issue #3279 / fix PR #3289) and remembers reviewed items in a local
  curation file so they do not resurface.

## [0.1.5] - 2026-07-10

### Added

- Packaged embo as an installable Claude Code plugin (`plugin/`,
  `/embo:*` commands, marketplace manifest). Install via
  `/plugin marketplace add povesma/embo` + `/plugin install embo@embo`.
- Manual install path: `install.sh`/`uninstall.sh`, plus Windows
  PowerShell parity (`install.ps1`/`uninstall.ps1`).
- Status line: `plugin/bin/statusline-setup` + `/embo:statusline`.
- `/embo:git deliver` — one-approval rapid delivery: stage + commit +
  push + (open PR) + (merge) from a single plan-file approval, run by
  `plugin/bin/embo-deliver`. Now the default delivery path;
  `/embo:git commit`/`pr` remain for multi-commit or human-reviewed
  work.
- Token-efficient task file evidence format, a completeness gate for
  `/embo:start`, and a new `/embo:wrapup` session-end command.

### Fixed

- `embo-deliver` resolves `file:` paths against the repository root,
  regardless of the caller's working directory.
- An already-committed branch delivers cleanly (push + PR) with a
  loud warning, instead of an empty commit or a failure.
- The PR title is the commit message's first line; the full message
  goes to `--body` — keeps `pr`/`pr-merge` under GitHub's 256-character
  title cap for multi-line messages.
- A branch whose upstream doesn't match `origin/<branch>` (e.g. a
  worktree branch auto-tracking `origin/main`) pushes explicitly with
  `-u origin <branch>`.
- The `CLEAR-OPTIONS` closing-choice rule is injected verbatim on
  every prompt, so the choice-kind (exclusive/combinable/ordering)
  stays correct under a compliance challenge.

### Changed

- `/embo:git deliver`'s plan-file Write dialog is the single approval
  for the whole delivery cycle — no separate draft, no extra
  `AskUserQuestion`.
