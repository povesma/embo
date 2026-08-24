# 053-CHECKLIST-SLIM: Tighten the 5 hook-extracted CHECKLIST blocks

Seed for a future `/embo:prd` run. Work MUST proceed on a dedicated
feature branch — never straight to `main`.

## Why now

The 5 CHECKLIST blocks in `plugin/commands/start.md` are extracted by
`plugin/hooks/behavioral-reminder.sh` (awk at line 114) and injected
**on every user prompt**, session-long, across every install of the
plugin. That makes them the highest-leverage prose in the entire
codebase per token spent.

## Measurement (baseline, 2026-08-22, embo-tokens)

| File | chars | words | lines | ~tok(chars/4) | ~tok(words*4/3) |
|---|---:|---:|---:|---:|---:|
| Extraction output (5 blocks together) | 3,374 | 532 | 51 | **843** | 710 |

Injected per user prompt, not per session. If a session takes 40 user
prompts, that is ~33k tokens loaded from these blocks alone.

## Scope

Rewrite each of the 5 CHECKLIST blocks — `WITHSTAND-CRITICISM`,
`CLOSING-CHOICE`, `RESTATE-CORRECTION`, `AVOID-APPROVAL`, `DELEGATE`
— to preserve the enforcement contract exactly while shortening the
prose. Rough goal: ~843 → ~590 tokens (≈30%). No RULE body edits;
that is task 054's scope.

## Preservation contract (must-not-change)

- Every `[<RULE> checklist]` opener line still begins at column 0
  with `[` and contains "checklist" (so the awk still matches).
- Every `<!-- /CHECKLIST -->` closer still terminates its block.
- Each block still names: the trigger, the required emit line and its
  exact format, and the specific failure it prevents. Meaning holds;
  words tighten.
- `plugin/hooks/behavioral-reminder.test.sh` must still pass (30/30).

## Verification method

`auto-test` (behavioral-reminder.test.sh) + `manual-run-claude`
(diff extracted output before/after — the format is unchanged, only
wording; the diff will not be zero, so evidence is the per-block
token delta) + `manual-run-user` (one live session driven under the
tightened blocks to confirm behavior is still enforced).

## Out of scope

- Any RULE body outside the CHECKLIST tags (that is task 054).
- Any other command file (that is task 055's audit output).
- Adding, removing, or renaming rules.

## Delivery constraint (from user, 2026-08-22)

All work on a dedicated feature branch. No direct commits to `main`;
delivery via PR merge (`/embo:git deliver` with `pr-merge` or
`release` mode).
