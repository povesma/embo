# 054: Profile storage model redesign

**Status**: Not started (seed).
**Origin**: surfaced 2026-08-16 during task 053 (profile-access-via-script).
Deferred from 053 to keep that task minimal.
**Priority**: medium — real durability + correctness gaps, no user-facing
breakage today.

## Problems (verified 2026-08-16)

1. **Shipped presets do not survive a plugin update.** Presets live in
   `plugin/profiles/*.yaml`; a plugin update overwrites the directory.
   Any user edit to a shipped preset is lost on update. Only
   `~/.claude/profiles/` and `~/.claude/active-profile.yaml` (user space)
   survive.
2. **"Active" is a stale COPY, not a pointer.** `/embo:profile use <name>`
   copies the preset to `~/.claude/active-profile.yaml`. Nothing links the
   copy back to its source preset, so editing the preset afterwards does
   not affect the active profile, and there is no reliable "which preset
   is active" answer beyond the copied `name:` field.
3. **No supported way to edit a NAMED (non-active) profile.**
   `/embo:git style` and any field edit only touch the active copy. The
   `embo-profile` wrapper owns whole-profile reads/writes (`show`/`get`/
   `set`/`reset`/`list`) but has no single-field setter. `git.md` Step 3
   currently does a direct `yq -i` edit of the active copy as a stopgap.

## Questions to resolve in the design pass

- **Preset tier vs user tier.** Should shipped presets be read-only
  templates (never edited in place), with all user edits landing in
  `~/.claude/profiles/`? How does a user "fork" a preset?
- **Active as pointer vs copy.** Store the active profile as a NAME
  (+ optional overrides) rather than a full copy, so editing the named
  profile takes effect and "which is active" is unambiguous. Trade-off:
  a pointer needs the referenced file to exist; a copy is self-contained.
- **Field edits.** Add `embo-profile set-field <profile> <path> <value>`
  (yq-based, atomic) so `/embo:git style` and similar edit a named
  profile through the wrapper, not a raw file write. Which profile does
  `/embo:git style` target — the active one, by name?
- **One file vs file-per-profile.** Current model is file-per-profile
  (presets) + one `active-profile.yaml`. Keep, or consolidate?
- **Update durability.** Guarantee that user profiles and the active
  selection survive `/plugin marketplace update`.

## Related

- `plugin/bin/embo-profile` (053) — wrapper that would gain `set-field`.
- `plugin/commands/profile.md` — the manager (`use`/`list`/`off`).
- `plugin/commands/git.md` Step 3 (`style` mode) — the stopgap direct edit.
- `plugin/profiles/*.yaml` — shipped presets + `default.yaml`.
- Task 053 — profile access via script (the minimal change this defers from).
