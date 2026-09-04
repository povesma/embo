# 064: Live benchmark — embo vs other frameworks — Seed

**Status**: Not started (run /embo:prd to begin).
**Origin**: 2026-09-04 landscape refresh — to demonstrate embo's
capabilities AND find its flaws by running it against competitors on a
real task, not just comparing feature tables.

## Problem

embo's positioning rests on a feature-matrix comparison
(`comparison-data.md`) and design-doc arguments (`docs/WHY.md` cites
METR, SWE-Effi, TDFlow). None of that is a LIVE, run-it-yourself
demonstration. We do not actually know how embo performs against
Superpowers / Spec-Kit / OMC on the same real task — where it wins,
and, more importantly, where it FAILS. A feature table can hide real
flaws that only surface under a live run.

## Goal

Run the SAME real coding task through embo and a set of competitor
frameworks under comparable conditions, and produce a reproducible
scorecard that (a) demonstrates embo's differentiators in action and
(b) surfaces embo's actual flaws for the backlog. Finding flaws is a
first-class goal, not a risk to avoid — dogfooding: embo's own
weaknesses become the next tasks.

## Prior art — VERIFIED, and it is genuinely whitespace

Checked this session via NotebookLM (the 9 tools' live repos) AND web
search. **No cross-framework workflow benchmark exists.** Specifically:

- Existing benchmarks (**SWE-bench**, **Terminal-Bench**) measure a
  *model + harness* on GitHub issues — NOT *framework vs framework*
  workflow overhead, token cost, or output quality. embo's own docs
  cite SWE-bench Lite only as academic evidence (TDFlow 88.8%).
- Tool self-tests are **siloed**: Superpowers' `drill`
  (skill-behavior only), OMC's `geobench` (unrelated GEO/search
  scoring), OMC `vitest` scoring, Pimzino's TS compile test. None runs
  another framework.
- Public "comparisons" are **hand-written editorial rankings**
  (webfuse, ralphwiggum, obviousworks blogs), not reproducible
  harnesses.

So a run-it-yourself framework-vs-framework benchmark is an untapped
opportunity — building one is itself a differentiator, not just an
internal QA exercise.

## Design questions for the PRD

- **Task corpus** — one representative real task, or a small suite?
  Reuse SWE-bench Lite instances (comparable, academic) or embo's own
  historical tasks (realistic, but embo-shaped)?
- **Fairness** — same model, same repo, same starting state, headless
  sandbox per framework. How to normalize each framework's very
  different interaction model (embo's approval gates vs OMC's autopilot
  vs Spec-Kit's delegation)?
- **Metrics** — token spend, wall-clock, correctness (tests pass /
  SWE-bench resolved), human-review burden, and a qualitative "did the
  workflow help or add ceremony?" read.
- **What flaws to watch for in embo** — approval-prompt friction, RLM
  index cost on large repos, docs-first overhead on trivial tasks,
  single-track slowness vs parallel swarms.
- **Automation** — can the harness itself become a shippable embo
  capability (ties to task 063 tracking and the "whitespace" finding)?

## Related

- `tasks/017-.../landscape-verdict-2026-09.md` — the whitespace finding
  (§3) this task acts on.
- `docs/WHY.md` — the academic evidence a live benchmark would
  complement with real embo numbers.
- Task 063 (competitor tracking) — a benchmark harness and a tracking
  harness may share infrastructure.
