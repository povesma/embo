# 035: Plugin update awareness for embo users — Seed

**Status**: Not started (run /embo:prd to begin).
**Origin**: surfaced during the statusline work, 2026-06-21.

## Problem

embo is a **third-party** marketplace, so plugin auto-update is **off by
default** (verified: `code.claude.com/docs/en/discover-plugins.md` —
"Third-party and local development marketplaces have auto-update disabled
by default"). Claude Code gives no notification that a newer version
exists. So a user installs embo once and never gets fixes/features unless
they manually enable auto-update or run `/plugin update`. Most won't.

## Constraints (verified, shape the design)

- `/plugin update` keys on `plugin.json`'s `version`; an unchanged string
  reports "already at the latest" — every shippable change must bump it.
- Hooks cannot modify settings or show banners; no `onInstall` hook.
- A purely local check (installed cache version) can't detect an
  *upstream* release — the cache only changes after an update happens.
- Detecting an upstream release needs a network call, which must NOT run
  on the status-line render path (latency/offline/API-spam). Safe shape:
  a fail-silent, TTL-cached background check (e.g. a SessionStart hook
  writing a cache file the render reads).

## Options to weigh (rank by KISS / maintainability)

1. **Docs only** — tell users to enable auto-update for the embo
   marketplace once (the `/plugin` UI toggle), which then gives native
   updates + the reload notice. May be enough on its own.
2. **Cached upstream check** — a TTL'd, fail-silent SessionStart check
   compares installed vs latest GitHub version, writes a cache file; a
   status-line segment or one-line notice reads it and hints
   "embo X.Y.Z available — /plugin update". Capable, but adds a network
   dependency to a third-party plugin.

## Related

`plugin/hooks/statusline-refresh.sh` is a working precedent for the
"compare bundled vs installed, act on difference" pattern and a candidate
home for a cached version check.
