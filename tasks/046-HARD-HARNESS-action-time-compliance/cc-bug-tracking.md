# 046 — CC bug tracking

Design decisions here are conditioned on open Claude Code bugs. Revisit
when any is fixed.

## #75915 — multiple PreToolUse hooks: updatedInput silently discarded
- Impact: forces M1-hold + M3 to be MERGED into approve-compound.sh
  (one hook) instead of a separate custodian-hold.sh.
- When fixed: a separate hold hook becomes viable; consider splitting
  for cleaner separation of concerns.
- Verify: re-run the FR-9 multi-hook fixture with two separate hooks.

## #19432 — PreToolUse additionalContext silently dropped (closed not-planned)
- Impact: any non-deny JIT context injection must use systemMessage,
  not additionalContext. M3 substitute rides permissionDecisionReason
  (deny reason IS shown), so M3 is unaffected.
- When fixed: a general JIT-reminder mechanism (roadmap M2) could use
  additionalContext directly.

## #19115 — split output schema (permanent, by design)
- PreToolUse: hookSpecificOutput.permissionDecision (nested).
- PostToolUse/Stop: root-level decision/reason.
- Not a bug to track for fix; a constraint to honor. custodian-halt.sh
  MUST use root-level decision:block.
