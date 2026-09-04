# 063: Continuous competitor tracking — Seed

**Status**: Not started (run /embo:prd to begin).
**Origin**: 2026-09-04 — the comparison table had gone 3 months stale
(snapshot 2026-06-07) and the manual refresh surfaced several material
changes that had silently accumulated.

## Problem

embo's README comparison table and `comparison-data.md` are refreshed
BY HAND. Between refreshes they rot: the 2026-06-07 snapshot missed
BMAD's planning-only refocus, OMC's swarm→Team rename and roster shrink,
Superpowers reaching the official marketplace with built-in memory, and
two significant new entrants (GitHub Spec-Kit at 133k stars; Pimzino).
A stale competitive table misrepresents embo's positioning to
prospective users and to its own maintainers.

## Goal

Make the competitor refresh a repeatable, low-effort operation (ideally
semi-automated) so the table reflects reality within weeks, not months —
reproducing what was done manually this session:
1. Fetch each tracked tool's current repo/README.
2. Re-derive each comparison cell with a live source.
3. Scan for new entrants.
4. Optionally run a NotebookLM synthesis pass for the verdict.

## What this session did manually (the process to automate)

- Three parallel research subagents, each fetching a subset of tools'
  live GitHub repos and re-deriving the 7 comparison dimensions with
  per-cell source URLs.
- A NotebookLM notebook seeded with the live repos, queried for
  positioning / gaps / whitespace with citations.
- Findings written to `comparison-data.md` (dated refresh section) +
  README table + a verdict doc.

## Options to weigh (rank by KISS / maintainability)

1. **A documented /embo:* command or runbook** that dispatches the
   research subagents and NotebookLM pass on demand — human triggers it
   quarterly. Lowest machinery; keeps a human in the loop for judgment
   calls (what counts as a "new entrant", cell rulings).
2. **A scheduled routine** (cron/RemoteTrigger) that runs the fetch +
   diff and opens a PR/issue when a tracked repo's relevant surface
   changed. More automation; risk of noise and of mis-scoring cells
   without human judgment.
3. **Diff-only alerting** — track each competitor repo's README hash /
   release feed; alert on change, human does the re-scoring. Cheapest
   signal, no auto-scoring.

## Open questions for the PRD

- Cadence: on-demand, quarterly, or change-triggered?
- Which signal detects a meaningful change vs. cosmetic churn (release
  tags? README diff? star-count thresholds for new entrants)?
- Where do new-entrant candidates come from (curated search queries,
  awesome-lists, marketplace listings)?
- How much can be auto-scored vs. must stay human-judged (the cell
  rulings are judgment-heavy — "partial" vs "yes" is not mechanical)?

## Related

- `tasks/017-.../comparison-data.md` — the sourced data file to keep
  fresh (see its dated "Refresh" sections for the format).
- `tasks/017-.../landscape-verdict-2026-09.md` — the verdict output.
- The `loop` / `schedule` skills and `RemoteTrigger`/`CronCreate` tools
  are candidate automation substrates.
