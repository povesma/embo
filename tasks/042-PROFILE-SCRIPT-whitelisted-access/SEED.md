# 042: Move profile access to a whitelisted script

**Status**: Not started (seed). **Origin**: user request, 2026-08-05
session — the inline profile read triggered an approval prompt during
`/embo:git deliver`.
**Priority**: medium — every command's Step 0 pays an approval prompt.

## Problem

Every command's Step 0 runs an inline
`cat ~/.claude/active-profile.yaml 2>/dev/null || echo "NO_PROFILE"`.
This shape:

- is not reliably allowlisted, so it can stop for an approval dialog
  at the start of nearly every command;
- duplicates default-handling ("if NO_PROFILE use defaults") across
  every command file;
- leaves YAML field extraction to the model, per command, with no
  single source of truth for defaults.

## Proposal

A `profile` executable in `plugin/bin/` (shipped, on PATH after plugin
install — same pattern as `rlm_repl` and `embo-deliver`), allowlisted
as `Bash(profile *)`. Subcommands, minimum:

- `profile get <field>` — value of a field (e.g. `git.commit_style`),
  falling back to the documented default when the file or field is
  absent;
- `profile list` — all effective fields (defaults merged in);
- `profile name` — active profile name, or `default`.

Command files then replace the inline cat + parse with one bare
`profile get ...` call.

## Scope (validate in PRD/design)

- Subcommand set and output format (plain value vs YAML/JSON).
- Where defaults live: the script is the single owner; command files
  stop restating them.
- Which permission rule ships and where it is documented (README
  opt-in like `embo-deliver`, or hook-level auto-approval).
- Migration: update every command's Step 0; `/embo:git` Step 0 too.
- Manual-steps rule: document the equivalent manual read for users
  without the script (CLAUDE.md Documentation Rules).

## Related

- Task 012 (PROFILES) — introduced `active-profile.yaml`.
- Task 022 (DEV-START-ZERO-PROMPT) — the pin-commands-allowlist
  effort this continues.
- `plugin/bin/rlm_repl`, `plugin/bin/embo-deliver` — the established
  bare-command-on-PATH pattern.
