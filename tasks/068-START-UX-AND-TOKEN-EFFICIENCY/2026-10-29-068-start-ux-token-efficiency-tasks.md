# 068: /embo:start UX fixes and token efficiency — Task List

## Decisions Taken (unattended mode)

This task list was generated with `EMBO_DOCTREE_UNATTENDED` set. The
mandatory clarifying-question step was skipped and every scope question
was decided from the PRD, tech-design, and repository evidence.

| # | Question | Decision | Evidence |
|---|---|---|---|
| D-1 | Should FR-1/FR-2 (scout ordering) and FR-3 (start.md tightening) be one story or two? | Two separate stories: one is a correctness fix (ordering/CHECKLIST), the other is a prose edit (tightening). They have different verification methods and different risk profiles. | PRD §Story 1 vs §Story 2; tech-design §FR-1/FR-2 vs §FR-3. |
| D-2 | Which files need a before/after token measurement step? | All files in FR-3 and FR-4 scope: `start.md`, `prd.md`, `impl.md`, `tech-design.md`, `tasks.md`, `session-scout.md`, `examine-advisor.md`, `approach-validator.md`. | Tech-design §D-5 baselines; PRD §NFR-2. |
| D-3 | Should agent tightening (session-scout, examine-advisor, approach-validator) be one story or three? | One story covering all three agents: same strategy, same verification method, same risk. Grouping avoids story-count inflation for low-risk prose edits. | Tech-design §FR-4; baseline tokens: session-scout 848, examine-advisor 1,283, approach-validator 2,711 — only approach-validator is large enough to treat alone but all share the same tightening recipe. |
| D-4 | Does the subsequent-run fast path (FR-5) require a separate baseline measurement? | No separate measurement task: FR-5 adds prose to `start.md`; it is covered under the start.md before/after measurement in Story 2. | Tech-design §FR-5: FR-5 changes are inline in `start.md` only. |
| D-5 | Which verify method for the CHECKLIST extraction test? | `manual-run-claude` (awk dry-run) — not `auto-test` because there is no automated test harness for the awk extraction in the repo. | Tech-design §Testing Strategy: "verify via `awk` dry-run on the edited `start.md`"; no test runner in `behavioral-reminder.sh` test block. |
| D-6 | FR-1 root cause and fix approach (SUPERSEDED — see D-9) | The `Agent` tool returns a spawn confirmation immediately; the scout digest arrives later as a `<teammate-message>` notification. Fix attempted: rewrite the trigger to require `<teammate-message teammate_id="session-scout">` presence, enforced by a CHECKLIST block. | Diagnosed 2026-10-29 from `start.md` lines 658–707 structure. **This fix was implemented, live-tested, and failed — see D-9.** |
| D-9 | Why the D-6 fix failed, and what the root cause actually is | A live `/embo:start` run produced two summaries and two menus. The command DID wait for the scout (that part worked), but `<teammate-message>` is the envelope for several events — a mid-flight message, a completion report, an idle notification — so the condition was satisfied by the first, not by the agent finishing. The single-menu guard said "this turn"; the later delivery arrives as a NEW turn, so it never applied. **Real root cause, from the docs: "subagents Claude spawns from the main conversation already start in the background by default", and background results "arrive as a completion notification in a later turn".** The double menu is default behaviour, not a prose-fixable bug. | Live run in another project, 2026-10-29 (transcript provided by the user). Docs: code.claude.com/docs/en/sub-agents, /docs/en/agent-teams. The `<teammate-message>` tag, the `idle_notification` shape and the "Teammate @X finished" line are **all undocumented**; the documented completion signal is the agent ID. |
| D-10 | Is there a plugin-available way to make the scout block? | **Not one that is documented.** `background` is a real frontmatter boolean, but it only FORCES background ("set to `true` to keep this subagent in the background even when Claude asks to wait for it"); `background: false` is not documented as blocking. No per-call foreground parameter is documented (`model` and `effort` are the only documented per-call overrides). `CLAUDE_CODE_FORK_SUBAGENT=0` is documented as making Claude wait, but it is a session environment variable a plugin cannot set. | Research pass 2026-10-29 against code.claude.com/docs/en/sub-agents. Sources fetched via WebFetch (small-model summarisation) — quotes to be confirmed against the live page before shipping any fix built on them. |
| D-7 | FR-5 completion marker — why not `\| System status \|`? | That string appears at `start.md` line 703 inside the command file, so it is always present in context on every invocation, causing the fast path to fire on the first run. Correct marker: `<!-- embo-start: complete -->`, written only by the completed summary step's output. | Examiner review finding H1, 2026-10-29. |
| D-8 | Should `session-scout.md` be tightened? | No — explicitly excluded. FR-1 depends on its digest quality; only 848 tokens; marginal savings don't justify the risk. | Examiner review finding M6, 2026-10-29. |

---

## Relevant Files

- [tasks/068-START-UX-AND-TOKEN-EFFICIENCY/2026-10-29-068-start-ux-token-efficiency-prd.md](2026-10-29-068-start-ux-token-efficiency-prd.md)
  :: 068 — Product Requirements Document
- [tasks/068-START-UX-AND-TOKEN-EFFICIENCY/2026-10-29-068-start-ux-token-efficiency-tech-design.md](2026-10-29-068-start-ux-token-efficiency-tech-design.md)
  :: 068 — Technical Design
- [plugin/commands/start.md](../../../plugin/commands/start.md)
  :: Primary target: FR-5 marker
  check, and prose tightening (FR-3). Lines 36–618 are the rules region;
  lines 619–740 are the workflow region.
- [plugin/commands/prd.md](../../../plugin/commands/prd.md)
  :: Token tightening target (FR-4): 4,113 tok baseline; target ≥ 15%
  reduction.
- [plugin/commands/impl.md](../../../plugin/commands/impl.md)
  :: Token tightening target (FR-4): 4,470 tok baseline; target ≥ 15%
  reduction.
- [plugin/commands/tech-design.md](../../../plugin/commands/tech-design.md)
  :: Token tightening target (FR-4): 2,800 tok baseline; target ≥ 15%
  reduction.
- [plugin/commands/tasks.md](../../../plugin/commands/tasks.md)
  :: Token tightening target (FR-4): 2,612 tok baseline; target ≥ 15%
  reduction.
- [plugin/agents/session-scout.md](../../../plugin/agents/session-scout.md)
  :: Agent tightening target (FR-4): 848 tok baseline; tighten if ≥ 15%
  achievable without removing behavioral constraints.
- [plugin/agents/examine-advisor.md](../../../plugin/agents/examine-advisor.md)
  :: Agent tightening target (FR-4): 1,283 tok baseline; same rule.
- [plugin/agents/approach-validator.md](../../../plugin/agents/approach-validator.md)
  :: Agent tightening target (FR-4): 2,711 tok baseline; same rule.
- [plugin/hooks/behavioral-reminder.sh](../../../plugin/hooks/behavioral-reminder.sh)
  :: Load-bearing: awk extractor at lines 110–115 reads all CHECKLIST
  blocks from `start.md`. Six blocks exist; Story 2 must not break
  them. No changes to this file expected; read-only reference.

---

## Notes

- No test plan file found in the task directory. Verify tags below are
  inferred from task nature per the embo:test-plan taxonomy.
- Token baseline figures are from tech-design §D-5 (fresh `embo-tokens`
  run, 2026-10-29): start.md 8,866, prd.md 4,113, impl.md 4,470,
  tech-design.md 2,800, tasks.md 2,612, session-scout.md 848,
  examine-advisor.md 1,283, approach-validator.md 2,711.
- The `behavioral-reminder.sh` awk anchor fires on lines starting with
  `[` containing `checklist` — any new CHECKLIST block must include a
  `[<NAME> checklist]` line as its first content line (see tech-design
  §Current Architecture, CHECKLIST extraction section).
- **Never abbreviate the governing sentence in any CHECKLIST block.** The
  hook re-injects these verbatim; they are behavioral enforcement, not
  documentation.
- **Measurement tool**: `embo-tokens <file>` is the canonical token
  counter for before/after comparisons. No substitute.

## TDD Planning Guidelines

These changes are all prose edits to `.md` files — TDD in the classical
sense (write failing test, make it pass) does not apply. Verification
is:
- `code-only`: read before/after diff and confirm no governing constraint
  was removed.
- `manual-run-claude`: run the affected command in a live session and
  confirm the behavior matches the acceptance criteria.

No test files are expected to be created alongside these edits.

---

## Tasks

- [ ] 1.0 **User Story:** As an embo user, I want `/embo:start` to show
  the next-action menu exactly once — after the scout agent returns —
  so that I am not confused by a second menu appearing after I dismissed
  the first. [3/0] **BLOCKED — see D-9/D-10.**

  **Status 2026-10-29:** the CHECKLIST approach (former 1.2–1.4b) was
  implemented (ea62d9c), live-tested, and FAILED. It was reverted in
  847a6a5. The failing run and the root cause are recorded in D-9; the
  absence of a documented plugin-available fix is recorded in D-10.
  No further implementation until 1.1 settles which mechanism works.

  - [X] 1.1 Record `embo-tokens plugin/commands/start.md` baseline before
    any edit to `start.md`. [verify: code-only]
    → 8,866 tokens, matching tech-design §D-5; no drift [live] (2026-10-29)
  - [X] 1.5 Run `/embo:start` in a live session; confirm exactly one
    `AskUserQuestion` drawn from the scout's digest.
    [verify: manual-run-claude]
    → FAILED: two summaries and two menus; the second menu came out as
    prose (a/b/c) rather than AskUserQuestion, also violating
    CLEAR-OPTIONS. The scout wait itself worked. [live] (2026-10-29)
  - [ ] 1.6 Settle which mechanism can make the scout block, by live
    test — the only remaining candidate is `background: false` in
    `plugin/agents/session-scout.md` frontmatter, which is NOT
    documented as blocking (D-10). Set it, run `/embo:start`, and
    observe whether the Agent call returns the digest as its tool
    result with no later notification. If it does not block, FR-1 has
    no plugin-available fix and 1.0 closes as blocked.
    **Requires the installed plugin to point at this worktree.**
    [verify: manual-run-claude]
  - [ ] 1.7 Confirm the D-10 doc quotes against the live
    code.claude.com/docs/en/sub-agents page. The research reaching
    them used WebFetch, which summarises with a small model; two
    fixes have now failed on second-hand claims about undocumented
    behaviour. [verify: manual-run-claude]

- [ ] 2.0 **User Story:** As an embo user, I want the `start.md` rules
  region to be as short as possible while remaining behaviorally
  equivalent, so that each session start spends fewer tokens on rules
  the hook already injects as checklists. [6/0]
  - [ ] 2.1 Record `embo-tokens plugin/commands/start.md` before tightening
    (or use baseline from 1.1). Target: rules region (lines 36–618) down
    from ~7,000 tokens to ≤ 5,250 (≥ 25% reduction). [verify: code-only]
  - [ ] 2.2 Tighten the rules region (lines 36–618) of `start.md`:
    remove verbose examples that illustrate a rule already stated
    clearly; cut preamble sentences that recap context before stating the
    rule; merge redundant sub-bullets within a rule block. Leave every
    governing sentence and every CHECKLIST block intact and unedited.
    [verify: code-only]
  - [X] 2.3 Re-run `behavioral-reminder.sh` awk extractor after tightening
    and confirm all pre-existing CHECKLIST blocks are still fully present
    in output. [verify: manual-run-claude]
    → all 6 blocks extract intact after tightening and after the 847a6a5
    revert [live] (2026-10-29)
  - [X] 2.3b Grep-count `<!-- RULE:` markers in `start.md` before and
    after the rules-region tightening. [verify: code-only]
    → 14 before, 14 after [live] (2026-10-29)
  - [ ] 2.4 Add the subsequent-run fast path (FR-5) at the very start of
    the `start.md` workflow section (before Step 0 / Batch A): if the
    marker `<!-- embo-start: complete -->` is already present in the
    session context (written at the end of a prior full run's summary
    output), run only `git log --oneline -10` and `git diff --stat HEAD`,
    emit a short delta note, then show the `AskUserQuestion`. Skip Batch A
    and Batch B entirely.
    Before implementing: run `grep -rn 'embo-start: complete' plugin/`
    and `grep -rn 'embo-start: complete' ~/.claude/` to confirm the
    marker string appears nowhere in existing files. If found, choose a
    different unique string before proceeding.
    Also add the marker line `<!-- embo-start: complete -->` to the end of
    the Summary section output template (after the AskUserQuestion close).
    [verify: code-only]
  - [X] 2.5 Record `embo-tokens plugin/commands/start.md` after all
    Story 2 edits. Confirm whole-file total ≤ 6,700 tokens.
    [verify: code-only]
    → 8,866 → 6,209 tokens (30%), target ≤ 6,700 met [live] (2026-10-29)
  - [ ] 2.5b Re-run the FR-1 live test after all Story 2 edits.
    **Blocked on 1.6** — there is no FR-1 mechanism to regression-test
    until one is found. The Story 2 edits themselves are verified by
    2.3 (extractor) and 2.3b (RULE markers).
    [verify: manual-run-claude]
  - [ ] 2.6 Run `/embo:start` a second time in the same session (after a
    first complete run) and confirm the fast path fires: only two git
    commands run, a delta note is emitted, full Batch A/B is skipped.
    [verify: manual-run-claude]

- [X] 3.0 **User Story:** As an embo user, I want the per-invocation token
  cost of each command file to be as low as possible without losing
  meaning, so that more of my context window is available for code
  analysis and planning. [11/11]
  - [X] 3.1 Record baselines for all four command files before any edits.
    [verify: code-only]
    → prd 4,113; impl 4,470; tech-design 2,800; tasks 2,612 — all match
    tech-design §D-5, no drift [live] (2026-10-29)
  - [X] 3.2 Tighten `plugin/commands/prd.md`. Target ≤ 3,496.
    [verify: code-only]
    → 4,113 → 3,165 (23.0%) [live] (2026-10-29)
  - [X] 3.3 Verify `prd.md` diff: governing instructions still present.
    [verify: code-only]
    → 5 governing-constraint markers retained; cuts were the duplicated
    Example Output block, the Important Notes rationale, and the Final
    Instructions list that restated the Process steps [live] (2026-10-29)
  - [X] 3.4 Tighten `plugin/commands/impl.md`. Target ≤ 3,800.
    [verify: code-only]
    → 4,470 → 3,925 (12.2%) — **target missed, deliberately**. What
    remains is the evidence-gate table, verify-type definitions, marker
    semantics and profile conditionals; cutting any removes a behavioral
    constraint, which NFR-1 forbids [live] (2026-10-29)
  - [X] 3.5 Verify `impl.md` diff: governing instructions still present.
    [verify: code-only]
    → 19 governing-constraint markers retained [live] (2026-10-29)
  - [X] 3.6 Tighten `plugin/commands/tech-design.md`. Target ≤ 2,380.
    [verify: code-only]
    → 2,800 → 2,254 (19.5%) [live] (2026-10-29)
  - [X] 3.7 Verify `tech-design.md` diff: no governing constraint removed.
    [verify: code-only]
    → 4 markers retained; every output-template section header kept, since
    the headers are the output contract [live] (2026-10-29)
  - [X] 3.8 Tighten `plugin/commands/tasks.md`. Target ≤ 2,220.
    [verify: code-only]
    → 2,612 → 2,142 (18.0%) [live] (2026-10-29)
  - [X] 3.9 Verify `tasks.md` diff: no governing constraint removed.
    [verify: code-only]
    → 12 markers retained [live] (2026-10-29)
  - [X] 3.10 Record post-edit token counts for all four files.
    [verify: code-only]
    → prd 23.0%, tech-design 19.5%, tasks 18.0% all met; impl 12.2% under
    target per 3.4. Four files: 13,995 → 11,486 tokens [live] (2026-10-29)
  - [X] 3.11 Fix `rlm_repl exec` heredoc examples. Found while tightening:
    prd.md, impl.md, tech-design.md and tasks.md all documented
    `rlm_repl exec` invoked with a heredoc, which it does not support.
    [verify: code-only]
    → all four corrected to `rlm_repl exec -c "$(cat tmp/rlm-probe.py)"`
    [live] (2026-10-29)

- [ ] 4.0 **User Story:** As an embo user, I want the agent files that
  load at each command invocation to be as concise as possible, so that
  the agents themselves spend less of their context budget on preamble.
  [8/0]
  - [ ] 4.1 Record baselines for all three agent files:
    `embo-tokens plugin/agents/session-scout.md`,
    `embo-tokens plugin/agents/examine-advisor.md`,
    `embo-tokens plugin/agents/approach-validator.md`.
    Baselines: 848, 1,283, 2,711 (re-measure to confirm). [verify: code-only]
  - [ ] 4.2 **Skip `plugin/agents/session-scout.md`** — explicitly out of
    scope for tightening. FR-1 depends on the scout's digest quality; the
    file is only 848 tokens (below the ≥ 15% target threshold in
    meaningful absolute terms — 127 tokens); and any edit to it risks the
    FR-1 fix without proportionate benefit. Record this decision here.
    [verify: code-only — no edit needed; mark done after recording]
  - [ ] 4.4 Review `plugin/agents/examine-advisor.md` for tightening
    (target ≤ 1,091 tokens for ≥ 15% reduction). Same skip rule applies.
    [verify: code-only]
  - [ ] 4.5 Verify examine-advisor.md diff: no governing constraint
    removed. [verify: code-only]
  - [ ] 4.6 Review `plugin/agents/approach-validator.md` for tightening
    (target ≤ 2,304 tokens for ≥ 15% reduction). Same skip rule applies.
    [verify: code-only]
  - [ ] 4.7 Verify approach-validator.md diff: no governing constraint
    removed. [verify: code-only]
  - [ ] 4.8 Record post-edit token counts for all three agents. Confirm
    any tightened file meets its ≥ 15% target; note skipped files and
    reason. [verify: code-only]

- [ ] 5.0 **User Story:** As an embo maintainer, I want zero approval
  dialogs when running `/embo:start` headless after these edits, so that
  CI and unattended runs are not broken by the changes. [2/0]
  - [ ] 5.1 Run headless `/embo:start` (NFR-3): `claude -p "/embo:start"`
    and confirm the run completes with no Bash approval dialogs.
    Compare behavior before and after the edits in Story 1 and Story 2.
    [verify: manual-run-claude]
  - [ ] 5.2 Confirm `embo-tokens` output for all edited files is recorded
    in a note (or committed alongside the PR description) so the before/
    after comparison is traceable. [verify: code-only]

