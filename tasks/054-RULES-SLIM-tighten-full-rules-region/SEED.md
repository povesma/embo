# 054-RULES-SLIM: Tighten the full rules region of start.md

Seed for a future `/embo:prd` run. Work MUST proceed on a dedicated
feature branch — never straight to `main`. Runs AFTER 053, or in
parallel on its own branch, but never merged back onto shared work
without an examine-advisor review pass.

## Why now

The rules region of `plugin/commands/start.md` (lines 31-585 as of
2026-08-22, 555 lines, ≈6,593 tokens by chars/4) is loaded once per
`/embo:start` invocation. Task 052 deliberately locked it byte-identical
because the slim-down was scoped as "no rule authoring" — that scope
constraint expires at the boundary of this task, which explicitly IS
"tighten the rules-region prose without changing enforcement."

## Measurement (baseline, 2026-08-22, embo-tokens)

| File | chars | words | lines | ~tok(chars/4) | ~tok(words*4/3) |
|---|---:|---:|---:|---:|---:|
| Rules region (RULE bodies + CHECKLIST blocks) | 26,372 | 4,185 | 555 | **6,593** | 5,580 |

Goal: ~6,593 → ~5,300 tokens (≈20% cut) with no behavioral change.

## Scope

Rewrite every RULE body in the rules region for terseness:
- collapse duplicated failure descriptions ("this is the failure
  this catches" reappears in most rules — pick one canonical form)
- move repeat definitions to a shared preamble
- delete restatements that only paraphrase the preceding paragraph
- keep every list, every example, every specific-forbidden-phrase

Task 053 must be delivered first (or clearly separated) so the
CHECKLIST tightening it does is not accidentally re-broadened here.

## Preservation contract (must-not-change)

- Every CHECKLIST block byte-identical to its 053 output.
- Every RULE name unchanged (`impl.md:33-34` cross-reference intact,
  and any other file that references a rule name by string).
- Every specific behavioral clause: the exact forbidden phrases,
  the exact required emit shapes, the exact continuation-menu
  wording where a rule cites it.
- `plugin/hooks/behavioral-reminder.test.sh` still passes.

## Verification method

Independent review is load-bearing here. Required:
- Full `/embo:research:examine` pass on the diff before merge.
- `manual-run-claude` live run of `/embo:start` and one further
  command under the tightened rules, confirming no behavioral drift.
- `manual-run-user` acceptance in a real session.

## Out of scope

- CHECKLIST wording (task 053).
- Other command files (task 055).
- Adding, removing, or renaming rules.

## Delivery constraint (from user, 2026-08-22)

Dedicated feature branch. PR merge. This task's changes MUST NOT land
on top of a still-open 053 branch — sequence them or rebase carefully.
