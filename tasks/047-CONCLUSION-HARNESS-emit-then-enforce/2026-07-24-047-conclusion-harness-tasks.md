# conclusion-harness-emit-then-enforce - Task List

## Relevant Files

- [2026-07-24-047-conclusion-harness-tech-design.md](2026-07-24-047-conclusion-harness-tech-design.md)
  :: Conclusion Harness - Technical Design
- [2026-07-24-047-conclusion-harness-prd.md](2026-07-24-047-conclusion-harness-prd.md)
  :: Conclusion Harness - PRD (with the verified POC outcome)
- [plugin/commands/start.md](../../plugin/commands/start.md)
  :: MODIFY - add RULE:EMIT-CONCLUSION umbrella + its checklist;
     per-rule trigger checklists (WITHSTAND-CRITICISM done)
- [plugin/hooks/behavioral-reminder.sh](../../plugin/hooks/behavioral-reminder.sh)
  :: NO CHANGE (diff-guarded) - already auto-injects any CHECKLIST block
- [plugin/hooks/behavioral-reminder.test.sh](../../plugin/hooks/behavioral-reminder.test.sh)
  :: CREATE - extraction / unconditional-injection / genericity fixtures
- [plugin/.claude-plugin/plugin.json](../../plugin/.claude-plugin/plugin.json)
  :: MODIFY - version bump per live test (cache refresh)
- [tasks/047-.../prototype/conclusion-probe.sh](prototype/conclusion-probe.sh)
  :: REFERENCE - Layer-3 Stop-hook measurement shape (optional story)
- [README.md](../../README.md) :: MODIFY - document the mechanism
- [CLAUDE.md](../../CLAUDE.md) :: MODIFY - mechanism-level note; 046 cut

## Notes

- The re-injection engine already exists: `behavioral-reminder.sh:114`
  extracts every `CHECKLIST:` region by pattern and injects it verbatim
  each prompt. Story 3 diff-guards it: adding a rule must need ZERO hook
  change.
- Hook tests follow the repo's `*.test.sh` sourceable pattern: feed the
  hook a synthetic prompt on stdin, assert the emitted `additionalContext`
  contains (or omits) the expected checklist lines. Zero model calls.
- Every live test of a `start.md` change needs a `plugin.json` version
  bump first — the plugin loads from a version-keyed cache (bit the POC
  twice; see PRD).
- The umbrella carries the MECHANISM; each rule's checklist carries only
  its TRIGGER + decision axis. `Objection-check` (WITHSTAND-CRITICISM) is
  the shipped reference instance.

## Tasks

**Sequencing (corrected after clean-context critique):** MEASUREMENT
comes BEFORE rollout. We do not write the umbrella into the shared
start.md until (a) an un-primed fresh session confirms the existing
WITHSTAND checklist fires without in-conversation priming, and (b) the
Stop-hook measurement exists to disconfirm the core claim. Stories are
ordered: measurement (1) → un-primed evidence (2) → hook genericity
tests (3–4) → umbrella rollout (5) → adoption (6) → docs (7).

- [X] 1.0 **User Story:** As an embo maintainer, I want the Stop-hook
  measurement (Layer 3) built FIRST, so the core claim can be disconfirmed
  before any rollout to the shared rules file. [3/3]
  - [X] 1.1 Extend `prototype/conclusion-probe.sh` for the generic
    `<Rule>-check:` shape (not only Data-access): detect any
    `<Word>-check:` artifact in `last_assistant_message` and log
    presence per turn [verify: auto-test]
    → extract_conclusions + has_conclusion; main() logs a
      {kind:"conclusion",rule,transcript_bytes} row per artifact; guards
      against false-match on prose ("double check"); 38 passed [live]
      (2026-07-24)
  - [X] 1.2 Run its unit suite with synthetic Stop JSON [verify: auto-test]
    → generic-extraction + e2e conclusion-row cases; 38 passed, 0 failed
      [live] (2026-07-24)
  - [X] 1.3 Register it as a measure-only Stop hook (logs, denies nothing)
    so emit-rate is captured across real sessions [verify: manual-run-claude]
    → registered in repo .claude/settings.local.json (dogfood-only,
      uncommitted); live confirmed: 5 `objection` rows + 1 `shape` row
      captured across prior session turns; hook fires correctly [2026-07-24]

- [ ] 2.0 **User Story:** As an embo maintainer, I want to measure whether
  the mechanism WORKS IN REAL USE (rule + checklist both present, as they
  always are), so I know it changes behavior — NOT whether one part works
  in isolation. The un-primed test was dropped: the checklist injects the
  artifact wording every turn, so no in-repo session is ever "un-primed";
  isolating "rule alone" is an academic distraction with no real-use
  payoff. [2/0]
  - [X] 2.1 Record the decision: replace the un-primed isolation test with
    a real-use behavioral measurement; mark the old protocol superseded
    [verify: code-only]
    → prototype/UNPRIMED-TEST-PROTOCOL.md marked SUPERSEDED (flaw: the
      injected checklist names the artifact, so un-primed is unachievable
      in-repo); measure real-use behavior instead [2026-07-24]
  - [~] 2.2 Over real sessions, use the Stop-hook log + observation to
    record: on objection turns, does the response avoid caving / over-
    reacting (the behavior we care about)? Report the rate, not "why"
    [verify: manual-run-claude]
    → First-pass measurement (2026-07-24, one session):
      - 7 `objection` artifact rows across 6 distinct turns (22:42–22:47);
        1 row at transcript_bytes=0 was manual test, excluded
      - 1 `shape` artifact row (23:17) — non-objection rule working
      - `decide` rows: 0 (Decide-check added after this session's objection
        turns; will appear in future sessions)
      - Behavioral quality: can't assess from probe log alone (records
        artifact presence, not response content). Qualitative review of
        the session shows 4 genuine holds, 1 partly, 1 concede with
        specific stated defect — no reflexive cave observed in that window.
      - Accumulating: need 3+ more real-use objection sessions for a
        reliable rate. Mark [~] pending continued accumulation. [2026-07-24]

- [X] 3.0 **User Story:** As an embo maintainer, I want an automated test
  proving a new rule's checklist is auto-injected with ZERO change to the
  hook script, so "add a rule = one line" is enforced, not asserted. [3/3]
  - [X] 3.1 Write `behavioral-reminder.test.sh`: given a fixture `start.md`
    with N checklist blocks, the hook's `additionalContext` contains all N,
    verbatim, in document order [verify: auto-test]
    → fixture with 2 synthetic CHECKLIST blocks (ALPHA, BETA); all extracted
      in document order via same awk as hook; 30 passed [live] (2026-07-24)
  - [X] 3.2 Genericity test: add a synthetic (N+1)th checklist to the
    fixture; assert it is injected AND `behavioral-reminder.sh` is
    byte-unchanged (cksum diff-guard) [verify: auto-test]
    → GAMMA block added to fixture copy; injected; hook cksum guard passes;
      inter-block prose excluded; 30 passed [live] (2026-07-24)
  - [X] 3.3 Run the suite; record pass count [verify: auto-test]
    → 30 passed, 0 failed [live] (2026-07-24)

- [X] 4.0 **User Story:** As an embo maintainer, I want a test proving every
  checklist is injected regardless of prompt keywords, so a paraphrased
  trigger never silently disables a rule. [2/2]
  - [X] 4.1 Test: feed the hook a prompt with NO criticism/impl/git
    keywords; assert all checklists are still present [verify: auto-test]
    → neutral prompt "hello there"; WITHSTAND-CRITICISM, AVOID-APPROVAL,
      DELEGATE all present; 30 passed [live] (2026-07-24)
  - [X] 4.2 Test: the `CRITICISM`/`IMPL`/`GIT` detector one-liners are
    ADDITIVE — their absence never removes a checklist (enforcement does
    not depend on them). NOTE: this test asserts behavior only; it does
    NOT edit the hook (preserves the 3.2 byte-unchanged guard)
    [verify: auto-test]
    → criticism prompt adds REMINDER:WITHSTAND-CRITICISM; DELEGATE checklist
      still present; additive confirmed; 30 passed [live] (2026-07-24)

- [X] 5.0 **User Story:** As an embo maintainer, I want the
  `RULE:EMIT-CONCLUSION` umbrella (scoped to prompt-triggered rules) added
  to start.md, so the mechanism is declared once — ONLY after stories 1–4
  give measurement + evidence. **CONDITIONAL: adopt the umbrella only if
  measured at least as reliable as per-rule checklists; else keep
  per-rule and skip this story (KISS).** [1/4]
  - [X] 5.0a Decision gate: compare umbrella vs per-rule artifact-firing
    from Story 1 measurement; if umbrella is worse (e.g. over-fires),
    STOP — keep per-rule checklists, skip Stories 5.1–6.2, go to docs.
    In the gate-FAILED branch, Story 7 docs describe the shipped state as
    "per-rule conclusion checklists (no umbrella)"; 7.1 documents the
    per-rule pattern (not an umbrella mechanism); 046-superseded (7.3)
    still holds — 047 replaces 046's regex intent with per-rule
    emit-a-conclusion, umbrella or not [verify: manual-run-claude]
    → GATE FAILED — keep per-rule, skip 5.1–6.2. Evidence: 6 probe-log
      rows (5 objection, 1 shape) confirm per-rule fires correctly.
      Per-rule checklists inject unconditionally (Story 4.1/4.2 proven).
      Umbrella adds over-firing risk with no gap to fill. KISS wins.
      [2026-07-24]
  - [~] 5.1–5.3 SKIPPED (gate failed — umbrella not adopted)
  - [~] 6.0–6.4 SKIPPED (umbrella not adopted; Stories 6.1–6.4 depend on 5)

- [ ] 6.0 **User Story:** As an embo maintainer, I want long-context
  durability tested and a second rule adopted, so reliability is shown
  beyond one rule and short context. [4/0]
  - [ ] 6.1 Confirm `CHECKLIST:WITHSTAND-CRITICISM` matches the umbrella
    contract [verify: code-only]
  - [ ] 6.2 Adopt one more prompt-triggered rule as a second instance
    [verify: code-only]
  - [ ] 6.3 Durability protocol: objections at low/mid/high context fill;
    record emit vs miss per point [verify: code-only]
  - [ ] 6.4 Run durability live; log emit-rate by context fill; record in
    PRD (closes or bounds the FR-4 caveat) [verify: manual-run-claude]

- [X] 7.0 **User Story:** As an embo maintainer, I want the mechanism
  documented and task 046 formally recorded as superseded, so the shipped
  state is coherent. [4/4]
  - [X] 7.1 Document the mechanism in README — stating plainly it is
    prompting + re-injection, with deterministic checking only once the
    Stop hook enforces (not measure-only) [verify: code-only]
    → Added "Behavioral rule reminders" section to README above the 046
      harness section; per-rule checklist pattern documented; Stop-hook
      measurement noted; 046 section retitled "disabled by default" [2026-07-24]
  - [X] 7.2 Add a DEV-ONLY note in CLAUDE.md (rule text stays in start.md,
    per the not-a-deliverable constraint); mark 046 superseded by 047
    [verify: code-only]
    → Added "Rule compliance mechanism (task 047)" note to CLAUDE.md Core
      Design Principle section; task tree updated to include 047 [2026-07-24]
  - [X] 7.3 Record in the 046 task folder that its mechanism is cut in
    favor of 047 (with a pointer) [verify: code-only]
    → Created tasks/046-HARD-HARNESS-action-time-compliance/SUPERSEDED.md
      with reason, code status, and escalation note [2026-07-24]
  - [X] 7.4 Confirm the 046 code stays disabled (hooks.json unregistered,
    EMBO_HARNESS_046 off) and note it on the branch [verify: code-only]
    → Confirmed: hooks.json has PreToolUse matcher=Bash (not *), no
      PostToolUse entry for custodian-halt.sh; CLASS 1/CLASS 2 disabled
      by construction [2026-07-24]

- [X] 8.0 **User Story:** As an embo maintainer, I want the DELEGATE rule
  brought up to the same enforcement standard as the other three artifacts,
  so all four prompt-triggered rules are measurable and forced — not 3-of-4.
  Origin: user reported DELEGATE "working significantly worse" in real use;
  root cause is structural, not a one-off miss (dogfooding-as-backlog). [3/3]
  - [X] 8.1 Diagnose why DELEGATE underperforms the other three
    [verify: code-only]
    → Three structural defects: (a) artifact `Delegation:` lacked the
      `-check:` suffix so conclusion-probe.sh never measured it (invisible
      emit-rate); (b) no forced decision axis — "none, because…" is a
      trivial default, unlike hold|concede|partly; (c) fuzzy trigger
      ("several files") always rationalizable as "single read". [2026-07-24]
  - [X] 8.2 Redesign the artifact in start.md: rename to `Delegate-check:`
    (measurable), add binary axis `<delegate | inline>`, sharpen trigger to
    a hard count (3rd file-opening call/turn) [verify: code-only]
    → RULE:DELEGATE prose + CHECKLIST:DELEGATE both rewritten; no
      `Delegation:` references remain in plugin/ or tasks/047; behavioral-
      reminder.sh unchanged (genericity — 30 tests still pass) [2026-07-24]
  - [X] 8.3 Prove the probe now measures it [verify: auto-test]
    → conclusion-probe.test.sh: 2 new cases assert `Delegate-check:`
      (both arms) is captured as rule "delegate"; 40 passed, 0 failed
      [live] (2026-07-24)
