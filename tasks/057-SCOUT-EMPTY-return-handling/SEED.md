# 057-SCOUT-EMPTY: session-scout empty-return handling

Seed for a future `/embo:prd` run. Work MUST proceed on a dedicated
feature branch — never straight to `main`.

## Why now

Task 052 headless testing (2026-08-22 and 2026-08-23) revealed that
when the `embo:session-scout` subagent returned an empty or
unreadable digest, the main model **replaced the delegation with 15+
inline Read/Grep turns** against task files — exactly what the scout
exists to prevent. This defect burns 15+ whole-context resends per
affected run and defeats the purpose of the delegation.

Observed in both runs identically (T8 Agent, then T9-T29 replacement
work) — this is deterministic, not flaky.

## Evidence

- `tmp/052-post5-headless-run.json` — turns 8-25 are the replacement
  work in the first run.
- `tmp/052-post5b-headless-run.json` — turns 8-29 in the second run.
- Both runs called the scout correctly; the scout's return value
  (visible in the JSON) is what the model reacts to.

## Investigation targets

1. **What did the scout actually return?** Inspect the tool_result
   block for T8 in both runs. Was it empty, malformed, or just
   different in shape from what the main model expected?
2. **Where is the "if scout returns empty, do X" logic?** Task 052
   Story 5.1's post-prose-fix start.md added *"if the scout returns
   an empty or unreadable digest, report 'no active tasks' and
   continue — do NOT re-do the scout's work by reading task files
   inline"*. That prose landed AFTER the diagnosis but may itself
   be insufficient (see task 056 for the same failure mode).
3. **Is this a scout bug or a start.md instruction gap?** If the
   scout is producing a valid digest that the main model
   mis-reads, the fix is in the scout. If the scout is truly
   returning nothing usable, the fix is in the scout OR in
   start.md's fallback path.

## Preservation contract

- The scout's positive-path digest format (the compact table used
  by /embo:start's Active Tasks row) must be unchanged.
- The fix must not add a new turn to the positive path (scout
  returns → main model uses it directly, one turn).

## Verification method

`manual-run-claude` — a headless run where the scout is coerced to
return empty (e.g. a repo with no tasks/ folder) must produce a
summary with "Active tasks: none" and NO inline Read/Grep of task
files. On a repo with tasks, the scout's digest must be used
verbatim, unchanged from current behavior.

## Out of scope

- The batching problem (task 056 — separate defect).
- Any change to what the scout is supposed to return in the
  positive path; only the empty/error path is in scope.

## Delivery constraint

Dedicated feature branch. PR merge.
