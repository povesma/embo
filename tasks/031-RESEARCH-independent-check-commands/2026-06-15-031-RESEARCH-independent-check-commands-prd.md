# 031: Independent-Check Research Commands (`dev:research:*`) — PRD

**Status**: Draft · **Created**: 2026-06-15 · **Sequence**: 031

---

## Problem

Decisions and specs get accepted on the *authoring agent's own
confidence* — which carries its biases and hallucinations forward
unchecked. Two moments need an independent check in a clean context:

1. **Choosing a direction** — proofread a PRD/tech-design or weigh
   options, *before* committing.
2. **Trusting a chosen spec** — confirm a selected approach will
   actually satisfy its acceptance criteria, *before* implementing.

The user already does both by hand with copy-pasted prompts. This
session proved the cost of skipping the check: a claim ("subagents
can't call MCP tools") was asserted from reasoning and was **wrong** —
a one-call probe overturned it.

## Solution (scope)

Ship, under a shared `dev:research:*` namespace:

- **`dev:research:examine`** — spawns two parallel clean-context
  critics (NotebookLM-MCP research critic + generic architecture
  critic), each told to *find flaws*; main agent reconciles into one
  **report-only** verdict. For deciding a direction.
- **`dev:research:verify`** — applies `VERIFICATION-DISCIPLINE.md` to a
  chosen spec: is each acceptance criterion proven, unproven, or
  contradicted? For trusting a spec before building.
- **Vendor `VERIFICATION-DISCIPLINE.md`** into the repo (location TBD in
  tech-design); improve it where useful.
- **2–3 reusable critic prompts** (adversarial-critic, verify-claim)
  factored so both commands and the rules can reference them.
- **One behavioral rule** in `start.md` (remindable, like
  AVOID-APPROVAL): `RESEARCH-VERIFY` — don't accept your own confidence
  as evidence. Trigger when **either** the cost of being wrong is
  above average **or** your confidence is low. Escalate by weight:
  - **Slightest doubt, any tool/API/approach** — especially
    **not-widely-used** ones — check **Context7 MCP** for current docs
    rather than relying on memory. This is the cheap, always-on check.
  - **Above-average cost or a real decision/spec** — run
    `dev:research:examine` (choose a direction) or
    `dev:research:verify` (prove a spec).

  Add the rule to the `behavioral-reminder.sh` BASELINE. (The
  reset-don't-patch principle stays inside
  `VERIFICATION-DISCIPLINE.md` section G — it is implementation-loop
  discipline, not part of this task's checking commands.)

## Verified facts (load-bearing)

- Flat commands in `.claude/commands/dev/`; skill names derive as
  `dev:<name>`; a nested `research/` subdir yields `dev:research:<name>`
  — verified via: `ls .claude/commands/dev/`, 2026-06-15.
- A `general-purpose` subagent (`Tools: *`) **can** call NotebookLM MCP
  (`notebook_list` → `status: success`); a `claude-code-guide` subagent
  **cannot** (no MCP in its tool list) — verified via: capability probe
  + two failed delegations, 2026-06-15.
- Subagents run non-interactively, cannot prompt mid-run — so any
  user confirmation (e.g. approving a digest) happens in the **main
  agent** before spawning — [assumption, verify in tech-design].
- NotebookLM auth expires (~20 min); `refresh_auth` may say `expired`
  while direct MCP calls still succeed — verified via: observed
  `refresh_auth=expired` + `notebook_list=success`, 2026-06-15.

## Requirements

- **FR-1** `examine`: two parallel background critics → reconciled,
  severity-ranked, **report-only** output (never edits the target).
- **FR-2** `verify`: per-acceptance-criterion verdict (proven /
  unproven / contradicted); each claim sourced or tagged assumption.
- **FR-3** Graceful degradation: if NotebookLM/MCP/auth is unavailable,
  the generic critic still runs and the report flags the missing
  external check — no hard fail.
- **FR-4** Privacy (outbound to NotebookLM): two hard rules — **no
  secrets**, **no user-identity** (external IPs, public hostnames, local
  paths, account markers). Internal IPs and non-identifying technical
  detail are fine; over-redaction that starves the research is
  discouraged. Send a purpose-built **digest**, not raw docs. Ask the
  user when sensitivity is unclear.
- **FR-5** `RESEARCH-VERIFY` rule + reusable critic prompts shipped;
  rule wired into BASELINE.

## Out of scope (v1)

Auto-applying fixes (report-only) · wiring `verify` into `/dev:impl` ·
a hook that auto-detects "review/verify this" (possible v2) ·
claude-mem server-beta migration.

## Success metrics (all demonstrated live)

1. `examine` runs two parallel critics → one reconciled report.
2. NotebookLM-unavailable: useful report from generic critic, gap
   flagged.
3. Privacy: a digest containing a secret + external hostname is
   masked/blocked before any outbound call.

## Open for tech-design

Vendored-doc path · dedicated MCP agent vs. `general-purpose` ·
`examine` argument shape (doc path vs. described options) · how the main
agent collects + reconciles two background results · NotebookLM auth
pre-check + fallback flow · exact rule wording + prompt files.

Minor tweaks to apply when vendoring `VERIFICATION-DISCIPLINE.md`
(low-hanging, additive only): (a) a top scope line — when the discipline
applies (risky / complex / expensive-to-reverse), so it isn't invoked
for trivial changes; (b) a section-A clause for "no independent source
exists" — mark the claim unproven, don't let reasoning fill the gap;
(c) clarify section G with the patch-vs-reset contrast (patch = fix the
current error on the same approach; reset = discard and re-derive from
verified facts, possibly a different approach).

## References

- Prior art: `test-review` (adversarial reviewer), `dev:improve`
  (review-and-propose), AVOID-APPROVAL (remindable rule pattern).
- claude-mem #21114 "Multi-Agent Critical Review and Verification
  Workflow"; #20881/#20681 (this session's subagent-tooling research).
- `VERIFICATION-DISCIPLINE.md` (to be vendored).

**Next**: `/dev:tech-design` for 031.
