# Idea: rework the Bash capture/approve hook

Status: **idea only** — not a committed task, no PRD yet. Captured
2026-07-24 from a session exploration (two clean-context examine passes:
research + internal).

## The problem (as raised by the user)

The `embo-capture.sh` + `approve-compound.sh` system has four
dogfooding pains:

1. **Unclear when/why the rewrite triggers** — `should_wrap` has ~6
   exclusion branches; small output gets no marker, so the rewrite is
   invisible. Opaque from outside.
2. **base64 hides the real command name and args** in the UI and
   transcript — the tool call shows `embo-capture.sh --b64 bGc...`. You
   can't see what you approve; the transcript is unreadable.
3. **Streaming/live output is buffered** for anything not on the
   hardcoded interactive/streaming denylist.
4. **The model gets confused** reasoning about whether a rewrite
   happened; the governing prose (RULE:CAPTURE-OUTPUT) is ~60 lines.

## What the mechanism currently provides (invariants to preserve)

Any rework must preserve ALL of these, not just the headline one:

1. **Context-flood reduction** — large output saved to a file, only a
   preview + marker returned inline.
2. **No re-execution / non-idempotent safety** (user's key point) — the
   full output is on disk, so a wrong filter guess costs a `Read`, not a
   re-run of a possibly state-changing command. This is arguably the
   strongest single reason the mechanism exists, and the research pass
   understated it.
3. **Honest exit codes through filters** — filter-mode preserves the
   upstream's true exit code instead of the filter's (`grep` exit 1 =
   no match masking a real failure).
4. **No lossy silent truncation** — full data always retained, an
   explicit "there is more, here's how" marker always shown. Both passes
   noted embo is AHEAD of naive prior art here; do not simplify it away.

## Candidate approaches considered

- **A. Readable-redirect rewrite instead of base64.**
- **B. Capture after the fact via PostToolUse.**
- **C. Delete the capture wrapper, keep only auto-approve.**
- **D. Invert the streaming denylist into a safe-wrap allowlist.**

## Findings from the two examine passes (research + internal)

**Both passes converged, and both overturned the naive starting ideas
with hard facts:**

- **B is a dead end — platform bug, not a design call.** Claude Code's
  `PostToolUse updatedToolOutput` is confirmed broken/ignored for the
  Bash tool (GitHub #54196, #65403, reproduced independently). Native
  ~30k-char truncation also fires BEFORE any PostToolUse hook runs. B
  would pass isolated tests but silently fail to protect context in
  production — worse than nothing (false confidence). Revisit only if
  the upstream bug closes.
- **base64 was a DELIBERATE decision (task 028) to solve quoting/
  escaping, not readability** (see obs #18436, and 028 tech-design
  "Invocation contract": base64 "avoids ALL shell metacharacter and
  quoting bugs; keeps the rewritten command a single clean token that is
  trivially allow-listed and trivially recognized for the re-entrancy
  guard"). Naive A reintroduces exactly the escaping bug class base64
  eliminated. Do NOT hand-roll a quoting scheme.
- **C contradicts embo's own "Enforce, Don't Ask" principle** — "let
  the model redirect its own big commands" is the prose-dependency the
  repo exists to eliminate (028 PRD rejected manual-redirect for this
  reason). Both passes rejected C as a standalone move. BUT "decouple
  approval from wrap-decision as two structural pieces" (a milder read
  of C) is good hygiene worth keeping.
- **Pure D reverses a considered safety default** — 028 chose a denylist
  precisely because a mis-wrapped interactive command HANGS the session
  (false-positive cost >> false-negative cost). Don't flip the default;
  fold D in as a narrowing layer on top, and just GROW the denylist to
  cover missed streaming tools (problem 3 is a coverage gap, not a
  reason to invert).

**Bigger-picture facts neither starting idea contained:**

- **~78% of context-flood tokens never flow through Bash** (replayed
  Headroom benchmark) — they come from Read/Grep/Glob, which have no
  working rewrite path. So a perfect Bash-capture fix caps out at a
  minority of the total flood surface. NOTE: this does NOT diminish the
  mechanism — it bounds the flood-reduction benefit only; the
  no-re-execution and honest-exit-code benefits are unaffected. (User
  correctly pushed back on any reading of this stat as "capture isn't
  worth it".)
- **Structural gate flaw:** capture is gated on "is it auto-approved,"
  which is the WRONG gate for "will it flood context." A manually-
  approved unusual/large command — exactly when flood is most likely —
  gets ZERO protection. The trigger should key on output-size risk, not
  allowlist membership.
- **The visibility problem is a PRESENTATION problem, not a transport
  problem.** Claude Code shows the executed string verbatim in the
  approval UI (no separate display string). So the only way to make the
  command readable is to make the executed string itself readable —
  inherently in tension with base64. One speculative idea (needs a live
  UI test): an inert readable prefix, e.g.
  `: 'ls -la | grep foo'; embo-capture.sh --b64 <b64>` — the `:` no-op
  renders the original legibly while base64 still carries the payload.
- **Security note:** the wrapper runs unattended via auto-approve; a
  compromised `embo-capture.sh` runs arbitrary commands. Worth a line in
  any future tech-design.
- **The prose (RULE:CAPTURE-OUTPUT / AVOID-APPROVAL) must be updated in
  the SAME change** as any mechanism change (028/030 precedent — both
  shipped the prose update as an in-scope deliverable, not a follow-up).

## Current lean (not decided)

Keep base64 as the execution transport AND the durable-file re-read
property. Fix the actual complaints:
1. Display layer — make the shown command readable (needs live UI test).
2. Add an `EMBO_CAPTURE_DEBUG` stderr trace so "why did/didn't this
   wrap" stops being opaque (cheap, no semantic change).
3. Decouple approval from wrap-decision structurally; reconsider the
   gate (size-risk, not allowlist-membership).
4. Grow the streaming denylist; optionally add D as a narrowing layer.
5. Update the governing prose in the same change.

Reject B (upstream-blocked), reject standalone C (anti-principle),
reject pure D (reverses safety default).

**Separately trackable:** the non-Bash flood (Read/Grep) is the larger
share and has no current mechanism — its own idea/task when it matters.

## Pointers

- Code: `plugin/hooks/approve-compound.sh`, `plugin/hooks/embo-capture.sh`,
  `plugin/hooks/hooks.json`
- Prose: `plugin/commands/start.md` (RULE:CAPTURE-OUTPUT, RULE:AVOID-APPROVAL)
- History: `tasks/027-COMPOUND-CMD-APPROVAL-HOOK/`,
  `tasks/028-REDIRECT-ZEROPROMPT-contradiction/`,
  `tasks/030-FILTER-CAPTURE-pipeline-decomposition/`
- claude-mem: obs #18436 (base64 decision), #18224/#18277 (028 design)
