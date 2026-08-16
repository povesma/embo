# 056: README updates for embo-profile + yq dependency

**Status**: Not started (seed).
**Origin**: surfaced 2026-08-16 during the /embo:wrapup audit at the
end of task 053 (profile-access-via-script). Task 053 shipped the
`embo-profile` wrapper and made `yq` a hard dependency, but the README
was not updated.
**Priority**: low — user-facing docs improvement; no functional gap.

## Problem

The README does not mention:
1. `embo-profile` (the new bin wrapper), its subcommands
   (`show`/`get`/`set`/`reset`/`list`), or its purpose.
2. The `Bash(embo-profile *)` allow rule users add to keep profile
   access prompt-free (parallel to the existing `Bash(rlm_repl *)` and
   `Bash(embo-corrections *)` guidance).
3. The `yq` dependency (now hard-required by the profile system;
   `/embo:health` Check 2 validates it).
4. The canonical `default.yaml` (single source of profile defaults;
   commands no longer hardcode field defaults).

## Scope

- Add a "Profile" section (or extend an existing section) to README
  describing `embo-profile` alongside the profile presets.
- Document the `Bash(embo-profile *)` allow rule with the same shape
  as `rlm_repl` / `embo-corrections`.
- Add `yq` to the plugin's prerequisites (with install commands per
  platform).
- Mention `default.yaml` as the canonical default source.
- (Optional) A short "Extending profiles" note pointing at
  `plugin/profiles/*.yaml` and the search order.

## Related

- `plugin/bin/embo-profile` (task 053) — the wrapper.
- `plugin/profiles/default.yaml` (task 053) — canonical defaults.
- `plugin/commands/health.md` Check 2 (task 053 wrap-up) — yq
  validation.
- Task 053 doc — full context on why profile access was changed.
- Task 054 — future storage redesign (README may need another pass
  after that lands).
