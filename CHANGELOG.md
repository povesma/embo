# Changelog

All notable changes to the embo plugin are documented here.

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
