# Changelog

All notable changes to the embo plugin are documented here.

## [Unreleased]

### Added

- `/embo:wrapup` enforces session idempotency: at session end the docs
  tree (PRD / tech-design / tasks) must reflect everything decided,
  discovered, or completed — wrapup flags docs-first violations,
  unmarked task progress, decisions or findings with no doc home,
  unresolvable doc references, and corrections not yet workflow rules,
  and proposes each doc update for confirmation.
- FOLD-FIRST session rule (with enforcement checklist), built on the
  replay principle — replaying the docs tree from scratch must rebuild
  the current product: a change to an existing feature amends the docs
  that cover it; a separate new doc is justified only when no
  amendment passes the replay test.

### Fixed

- `/embo:init` completes on repositories with arbitrarily large
  `tasks/` trees: it catalogues task docs by name instead of reading
  every file into the context window; task content is read later, per
  selected task, by the workflow commands.
- Session startup cost no longer grows with the task archive: the
  session-scout agent scans newest-first and stops when older files
  can no longer change the resumption recommendation.

## [0.2.8] - 2026-08-24

### Changed

- `/embo:start` runs faster and no longer stalls on permission
  dialogs.

### Added

- `embo-tokens` — measures the token cost of a prompt file.
- `embo-plugin-info` — reports the plugin's install state in one call.

## [0.2.7] - 2026-08-18

### Fixed

- **Live-Edit stays in one browser window.** Follow-up edits for the
  same task land in the same panel, not in a new browser that opens on
  the side.
- **Live-Edit never touches your backend without you asking.** Once
  the panel is up, files, database rows, CMS entries, and API payloads
  stay untouched until you say to save the change.
- Panel header shows the correct plugin version.
- **`/embo:git deliver release` on a reused feature branch works.**
  A follow-up release from a branch whose earlier PR was already
  merged now creates a new PR for the new commit, instead of
  silently skipping and tagging a stale commit.

## [0.2.6] - 2026-08-18

### Fixed

- **Live-Edit Mode is usable.** 0.2.5 shipped it broken. In
  `/embo:visual-impl` you now see the browser and the panel appears
  on the page.

## [0.2.5] - 2026-08-16

### Added

- `/embo:visual-impl` gains **Live-Edit Mode** — a WYSIWYG loop for
  tuning a page against a design or your own intent. You describe a
  change, or Claude proposes options; Claude applies it live on the
  page — no file edit, no rebuild. When the page looks right, you
  accept and Claude writes the changes back into the source at their
  real origins.
- **Profile access no longer prompts.** A new `embo-profile` command
  reads the active profile (or the shipped `default.yaml` fallback), so
  workflows can be pre-approved with one narrow `Bash(embo-profile *)`
  allow rule instead of whitelisting all of `~/.claude`. Requires `yq`.
- **Correction capture works out of the box.** When you steer how
  Claude works, Claude restates the correction as a one-line
  acknowledgment and a hook records it to a project-local
  `.claude/corrections.jsonl`. `/embo:improve` reads that file as its
  primary source. Running `/embo:enable-corrections` is still
  recommended — claude-mem's `correction` observations add semantic
  search across the history and cross-session context that the marker
  file alone doesn't carry; `/embo:improve` merges and deduplicates
  the two sources when both are present.
- **`/embo:health` checks for `yq`.** The profile system hard-requires
  it, so a `yq`-less environment now fails loudly at health-check time
  instead of on the first profile read.

### Fixed

- **`/embo:research:examine` and `/embo:research:verify` actually run
  their external check.** They pointed at the retired NotebookLM MCP
  name; the live server is `gemini-notebook-mcp`. Every run silently
  skipped the external prior-art pass and degraded to reasoning-only. A
  skipped external check now leads with a loud failure instead of being
  buried under a confident verdict.

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
