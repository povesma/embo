# proof-table-claim-proof-record - Task List

## Relevant Files

- [2026-07-27-049-proof-table-tech-design.md](2026-07-27-049-proof-table-tech-design.md)
  :: Proof Table - Technical Design
- [2026-07-26-049-proof-table-prd.md](2026-07-26-049-proof-table-prd.md)
  :: Proof Table - Product Requirements Document
- [plugin/agents/approach-validator.md](../../plugin/agents/approach-validator.md)
  :: MODIFY - Output section (summary table with C1/C2 IDs + 8-field
     proof-table blocks); new Hedge-check Process step; 0-10 confidence
     with 4 data-availability bands + ≤5 forcing function
- [plugin/.claude-plugin/plugin.json](../../plugin/.claude-plugin/plugin.json)
  :: MAYBE MODIFY - patch bump IF agent files are version-cache-keyed
     (assumption to resolve in 3.3)

## Notes

- Entirely a prompt-contract edit to one agent file, plus a possible
  version bump. No code, no new file, no hook, no main-loop checklist.
- All three stories edit the SAME file; implement as one coherent change.
- The methodology field is the load-bearing constraint: it MUST be a
  reproducible command another party can re-run, not a prose description
  of what the agent did. A non-reproducible method counts as absent and
  lowers confidence.
- Subagents cannot run Stop/PostToolUse hooks, so the Hedge-check
  artifact is contract-forced, not hook-measured (accepted).
- `code-only` = verified by reading the shipped agent file for presence
  and internal consistency. `manual-run-claude` = a live
  `/embo:research:verify` run whose output shows the runtime behavior.

## Tasks

- [ ] 1.0 **User Story:** As an embo user, I want each load-bearing claim
  shown as a proof-table record with a reproducible methodology, so I can
  re-run the check and trust the conclusion (FR-1, FR-2). [4/0]
  - [X] 1.1 Replace the single verdict table in the Output section
    (`approach-validator.md:133`) with a summary table whose first column
    is a claim ID (`C1`, `C2`, … in appearance order), then Claim,
    Verdict, Confidence [verify: code-only]
  - [X] 1.2 Add one proof-table block per claim below the summary, headed
    by its ID (`### C1 — <label>`), with the 8 fields: env, domain,
    assumption, methodology NN, evidence, critical assessment
    (differential), conclusion, confidence [verify: code-only]
  - [X] 1.3 State the reproducibility constraint on the methodology field:
    it MUST be a re-runnable command, not prose; a non-reproducible
    method counts as absent and lowers confidence. Keep the existing
    "Then advise" block after the proof-table blocks [verify: code-only]
  - [~] 1.4 Live-run `/embo:research:verify` on a small claim; confirm
    the output shows the summary table (with C-IDs) and at least one
    8-field block whose methodology is an actual re-runnable command
    [verify: manual-run-claude]
    → pending fresh-session run at 0.2.4 after `marketplace update`
      refreshes the cache (2026-07-27)

- [ ] 2.0 **User Story:** As an embo user, I want the agent to catch its
  own hedged claims and resolve them, so no guess is emitted as a fact
  (FR-3). [3/0]
  - [X] 2.1 Add the Hedge-check Process step (after current step 5): a
    revision pass over the drafted-but-not-yet-emitted proof table;
    per hedged load-bearing claim emit
    `Hedge-check: <ID> — <proven | unproven | needs-methodology>`, then
    resolve each (prove / state unproven with confidence / name the
    settling method) [verify: code-only]
  - [X] 2.2 Add the fixed hedge-word list (should be, presumably,
    precisely, likely, typically, I believe, probably, seems, appears,
    ought to, in all likelihood, my sense is) plus the "and similar
    epistemic softeners" generalization clause; reference the existing
    load-bearing-claim definition (Process step 1) [verify: code-only]
  - [~] 2.3 Live-run `/embo:research:verify` on a claim the agent would
    naturally hedge; confirm a `Hedge-check:` line appears with a
    resolution and the claim is not emitted as a bare fact
    [verify: manual-run-claude]
    → pending fresh-session run at 0.2.4 after `marketplace update`
      refreshes the cache (2026-07-27)

- [ ] 3.0 **User Story:** As an embo user, I want confidence scored on
  data-availability bands that force further investigation when low, so
  the number means something (FR-4). [4/0]
  - [X] 3.1 Add the 0-10 confidence definition with 4 bands (9-10
    reproduced authoritative data; 6-8 strong indirect / single
    authoritative source; 3-5 partial or one unreliable source; 0-2 no
    usable data / mostly inference), stating explicitly that the ≤5
    threshold covers bands 0-2 and 3-5 [verify: code-only]
  - [X] 3.2 Add the forcing function: when confidence ≤5, the block MUST
    name the methodology that would raise it (and why unavailable this
    run) OR prove with evidence that none exists without more
    access/research [verify: code-only]
  - [X] 3.3 Resolve the version-cache assumption: check whether agent
    files load from the version-keyed cache (inspect
    `~/.claude/plugins/cache/embo/embo/<version>/agents/`); if so, patch-
    bump `plugin/.claude-plugin/plugin.json`; else note no bump needed
    [verify: code-only]
    → RESOLVED: agent files ARE cache-keyed
      (`.../0.2.4/agents/approach-validator.md` exists). No new bump
      needed — version stays 0.2.4 (unreleased); a fresh cache copy for
      live tests comes from re-running `marketplace update`, which
      re-copies the working tree into the 0.2.4 cache dir [live]
      (2026-07-27)
  - [~] 3.4 Live-run `/embo:research:verify` producing a low-confidence
    (≤5) claim; confirm the block names the raising methodology or proves
    none is available [verify: manual-run-claude]
    → pending fresh-session run at 0.2.4 after `marketplace update`
      refreshes the cache (2026-07-27)
