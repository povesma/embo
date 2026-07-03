# 038: Rapid Deliver — One-Shot Git Delivery - PRD

**Status**: Draft
**Created**: 2026-07-03
**Task**: 038-RAPID-DELIVER-one-shot-git
**Author**: Claude (via embo workflow analysis)

---

## Context

`/embo:git` is the most-used command, and its most-requested operation is
the full delivery cycle: commit + push, sometimes + open PR + merge. Today
each git write (commit, push, PR, merge) is a separate command that stops
for its own Claude Code harness prompt, so the developer approves the same
decision three or four times. We want **one approval for the whole
delivery**, after which it runs to completion untouched.

Rapid delivery becomes the **default delivery path**: one commit of the
needed files, pushed to the branch after one plan approval — used for most
changes regardless of size. The existing multi-commit `commit`/`pr` flow
(splitting, polished messages) stays for the exception: work that needs
human review, or genuinely large/mixed changesets. The distinction is how
the change must be *handled*, not how big it is.

### Current State (observed)

- `/embo:git` runs `git commit`, `git push`, `gh pr create` as separate
  commands, each gated by its own harness prompt — verified via:
  `plugin/commands/git.md:220-228, 327-329`, 2026-07-03.
- Those git write commands are in no allowlist layer, so each prompts every
  time — verified via: `grep "git commit|git push|gh pr"` over the four
  settings files returned no allow rule, 2026-07-03.
- The `approve-compound.sh` hook auto-approves any command whose every
  subcommand matches an allow rule; it has no special handling of git —
  verified via: `plugin/hooks/approve-compound.sh:181-212`, 2026-07-03.
  So "git writes can't be auto-approved" is a *policy* choice (not
  allowlisted), not a mechanical limit: **one allowlisted wrapper command
  can run the whole cycle with no per-command prompt.**
- The plugin already ships bare-command wrappers in `plugin/bin/`
  (`rlm_repl`) that carry a `Bash(<name> *)` allow rule and use no `${...}`
  expansion, so they auto-approve with no prompt — verified via:
  `plugin/bin/rlm_repl:1-31`, 2026-07-03. This is the template.
- Global CLAUDE.md forbids `git add -A` and `git commit -a` — every file
  staged explicitly by name — [project constraint].

### Prior work (claude-mem)

- Task 014 established `/embo:git` and the "harness prompt is the single
  approval point" model. Task 019 removed *duplicate* skill-level gates.
  This feature reintroduces a skill-level gate as the **sole** approval —
  no duplication, because the harness prompt is eliminated by allowlisting.
- Task 032 introduced the `plugin/bin/` wrapper pattern this reuses.

## Problem Statement

**Who**: A developer mid-development, when Claude Code has finished a change
and proposes delivering it.
**What**: One logical decision ("deliver this") costs three or four harness
approvals — for every delivery, not just occasional ones.
**Why**: Repeated approvals for one decision slow the most-used operation
and train click-through. Since single-commit delivery is the common case,
the friction is on the default path.
**When**: End of a development step, where Claude Code already knows the
tree state and target and proposes delivery — not an arbitrary "grab files
and send."

## The Design (agreed with user)

- **The script is dumb.** It executes its arguments only — explicit file
  list, commit message, target branch, mode (direct push | push+PR |
  push+PR+merge). No branch inference, no policy, no decisions.
- **Claude Code is the brain.** It builds the delivery plan from the
  situation and passes explicit arguments.
- **The single approval is Claude Code showing the plan** and the user
  confirming it once.
- **The script is allowlisted** (`Bash(<name> *)`), so the hook
  auto-approves it and no further prompt appears; git writes run as its
  child processes.
- **Hard rule:** never `git add -A` / `add .` / `commit -a`; only files
  shown in the approved plan are committed.

## User Stories

1. **As a** developer with a completed change, **I want** Claude Code to
   show one delivery plan and run it after a single confirmation, **so
   that** I approve delivery once, not per command.

   **Acceptance Criteria**:
   - [ ] One plan confirmation appears before any git write runs.
   - [ ] The plan shows, in plain words: exact files (by name), the full
     commit message verbatim, the target branch, and the mode. When mode
     includes merge, it names the base branch and flags merge as
     irreversible.
   - [ ] On approve, the cycle runs to completion with no further prompt.
   - [ ] On reject, nothing is staged, committed, pushed, or merged.

2. **As a** developer who may have unrelated dirty files, **I want** the
   plan to list every file it will commit, **so that** I can reject a
   commit that would include files not belonging to this change.

   **Acceptance Criteria**:
   - [ ] Only files shown in the approved plan are staged and committed.
   - [ ] The script stages by explicit name only; never `git add -A`,
     `add .`, or `commit -a` (verifiable by inspecting the script).

3. **As a** developer targeting different branches per situation, **I
   want** to deliver by direct push or by opening a PR, chosen per run,
   **so that** I can push to my own branch or route a protected base
   through a PR.

   **Acceptance Criteria**:
   - [ ] Supports target branch + mode (direct push | push+PR |
     push+PR+merge) selected per run.
   - [ ] Mode and branch are chosen by Claude Code and shown in the plan;
     the script itself decides nothing.
   - [ ] Merge happens only when the approved plan explicitly includes it.

4. **As an** embo user, **I want** the whole cycle to run with no
   per-command prompt after I approve the plan, **so that** the plan
   confirmation is the only interaction.

   **Acceptance Criteria**:
   - [ ] The script is invoked as a bare command (no `${...}`/`$(...)`),
     and an allow rule causes the hook to auto-approve it — so the script
     call produces no harness prompt.

## Non-Functional Requirements

- **NFR-1 (Safety)**: No git write occurs before plan approval. The single
  trade-off is: after approval, writes run unattended. Destructive
  operations (force-push, reset, rebase) are out of scope for the script.
- **NFR-2 (No new dependencies)**: `git`, `gh`, and shell only — consistent
  with the plugin's no-dependency rule.
  `[assumption, verify in tech-design]` — `gh`-absent handling to match the
  existing skill's fallback.
- **NFR-3 (Portability)**: Resolves its own path like `rlm_repl`, so it
  works under plugin and manual installs.

## Failure Behaviour

On any mid-cycle failure (push rejected, PR creation fails, merge blocked
by protection/CI), the script stops at the failed step, reports which steps
completed, and exits non-zero. It does not undo completed steps.
`[assumption, verify in tech-design]` — exact failure surfaces to enumerate
in tech-design.

## Out of Scope

- Branch inference or per-branch policy in the script (Claude Code decides).
- Destructive git operations via the rapid path (force-push, reset, rebase,
  branch delete) — remain manual.
- Anything needing mid-run human input (conflicts, interactive rebase) —
  falls back to the full `/embo:git` flow.
- Replacing the existing `/embo:git` multi-group review path — it stays.
- Auto-merge by default — merge only when the plan explicitly includes it.

## Success Metrics

1. **1** approval per full commit → push → (PR) → (merge) cycle (from 3–4).
2. **0** commits containing a file not shown in the approved plan.
3. **0** `git add -A` / `add .` / `commit -a` calls by the script.

## References

- `plugin/commands/git.md:220-228, 327-329` — existing skill; multi-group
  path to preserve.
- `plugin/bin/rlm_repl:1-31` — wrapper template.
- `plugin/hooks/approve-compound.sh:181-212` — allowlist logic the script's
  allow rule must satisfy.
- Tasks 014 (skill), 019 (gate removal), 032 (bin/ wrapper) — claude-mem.

---

**Next Steps**:
1. Review and refine.
2. `/embo:tech-design` — argument contract, failure surfaces, allow-rule
   placement, plan-confirmation flow.
3. `/embo:tasks`.
