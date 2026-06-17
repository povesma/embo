# Verification Discipline — A Failure-and-Success Pattern

A project-agnostic account of why a "simple, textbook" task failed
repeatedly, and the process that finally made it succeed. Written for
any agent or engineer doing infrastructure or code work where a change
is expensive to get wrong. The specifics of the task are irrelevant;
the failure modes and the working process are the point.

**When to apply this.** This discipline has a cost; spend it where
being wrong is expensive. Apply it when a change is risky, complex, or
hard to reverse, or when your confidence is below average. Skip it for
trivial, easily-reverted changes — running the full process on a typo
fix is waste.

## The shape of the failure

The task was a standard, well-trodden pattern — the kind where "this
should just work" feels obviously true. That feeling was the trap.

The work failed several times in a row. Each failure had the same
structure:

1. Build a solution.
2. Declare it "verified" — based on own reasoning, recalled knowledge,
   and a local sanity check (a dry-run, a parse, a "looks right").
3. Run it.
4. Fail on one detail that was *assumed*, not *checked*.
5. Fix that one detail.
6. Declare "now it's verified" — and run again.
7. Fail on a *different* assumed detail.

The detail that broke it was different every time (an auth mechanism,
a path convention, a flag that no longer existed, a resource-lifecycle
default). The constant was not the bug. **The constant was the agent's
own confidence standing in for verification.**

## What definitely caused the failures

These are the specific anti-patterns. Any one of them is enough to
produce the loop above.

### 1. Self-issued "verified"
Treating one's own reasoning, memory, or training as sufficient proof.
"I verified it" meant "I thought about it and it seems right." That is
not verification — it is a hypothesis wearing the costume of a
conclusion. Every time this phrase was used before a run, a failure
followed.

### 2. Verifying once, then changing the design, then running
A review was done, it found a flaw, the flaw was fixed — and the fixed
design was run **without re-reviewing it**. The fix itself was never
verified. A change invalidates the prior verification; the new artifact
is unproven until checked again.

### 3. Local checks mistaken for proof
Schema dry-runs, YAML parsing, and "it applied cleanly" prove the
*shape* is acceptable. They do not prove the thing *works*. A
client-side validation passed while a server-side strict check would
have rejected the same input. Passing a cheap check created false
confidence that skipped the real one.

### 4. Reasoning by analogy across un-exercised paths
"Component A works, and B is structurally similar, so B works." Three
near-identical units — one was proven by execution, the other two were
assumed safe because they "looked the same." Similar is not same. An
un-exercised path is unverified, however much it resembles a proven one.

### 5. A biased reviewer treated as independent
The same review source had been fed earlier, incorrect premises. It
faithfully echoed those mistakes back as advice (recommending a flag
that did not exist, recommending the very approach that had already
failed). A reviewer carrying your prior errors is not an independent
check — it is your own bias with a second voice.

### 6. Abandoning the rule under pressure
When close to "done," the temptation was to patch the running system in
place and hand-test, instead of following the slower correct path
(reset to a clean state, change the source of truth, redeploy). Patching
to make the immediate error disappear is how the loop sustains itself:
it optimizes for "this error gone now," not "this works for the right
reason."

### 7. "Finally clean" as a terminal thought
The belief "this must be done now" actively suppresses scrutiny. The
moment the goal is to *finish verifying*, verification stops being
honest — it starts looking for permission to stop.

## The process that produced success

The same task succeeded once these were enforced. None of them are
clever; they are discipline.

### A. An independent source is the authority, not you
Proof comes from something outside your own judgment:
- **Authoritative current docs** for the exact tool/version in use
  (not memory, not "I recall the API is...").
- **The live system's own report** — query the running system for what
  it actually supports, owns, or returns. The installed version is the
  truth, even when it contradicts the docs or the reviewer.
- **The real artifacts** — read the actual files/configs the change
  depends on, rather than assuming their structure.
- **A fresh agent in a clean context** — spawn a subagent with no
  share of your prior reasoning, give it the design neutrally, and ask
  it adversarially to find what is wrong (see D). Its lack of your
  context is exactly what makes it independent; treat its findings as
  evidence to weigh, not as your own thought echoed back.
When the independent source and your belief disagree, the source wins,
or you dig until you have first-hand evidence.

When **no** independent source exists — a genuinely novel approach,
nothing to query, no prior art — do not let your own reasoning quietly
fill the gap. Mark the claim explicitly as unproven and treat it as a
risk to retire by exercising it (see E), not as a fact. An unprovable
claim is a known unknown; a claim proven only by your confidence is a
hidden one, and hidden unknowns are what the failure loop feeds on.

### B. Verify the version/instance you actually run against
Generic documentation describes a tool in general; you run a *specific
version* in a *specific environment*. Confirm load-bearing facts against
the installed instance. A field, flag, or default can differ between
versions, and the running system is the only authority on which one you
have.

### C. The verify loop has a back-edge
```
create -> verify (independent) -> any flaw? -> fix -> GO BACK TO verify
                                  -> no flaw, twice over? -> only THEN run
```
The critical, most-skipped step is the arrow back to verify after a fix.
A design is not ready when the review *first* returns clean; it is ready
when a review of *the current, unchanged artifact* returns clean. Every
edit resets that clock.

### D. Use a clean, unbiased reviewer
When a review source has been contaminated with earlier wrong premises,
discard it and start a fresh one with no prior context. State the design
neutrally and ask it to **find what is wrong**, adversarially — not to
confirm. A review that only confirms is worthless; a review instructed
to assume failure and hunt for the cause is where real defects surface.

### E. Distinguish "reviewed sound" from "executed green"
Review can certify a design against known principles. It cannot certify
that a never-run path actually runs in your environment. Identify the
exact components that review *cannot* prove, and exercise *only those*
once — not a nervous full rehearsal, but a targeted execution of the
genuinely un-exercised piece. Everything else is proven; this is the
residual.

### F. Reject wrong criticism with evidence — do not just absorb it
Independent review is not infallible. When a reviewer asserts something
the live system contradicts, do not cave to it *and* do not ignore it:
go get first-hand evidence (query the system, read the source) and let
that settle it. Defer to evidence, not to whoever spoke last — including
the reviewer, and including your own prior conviction.

### G. When it fails, reset — do not patch
A failed attempt on a "simple" thing is a signal that the *approach* may
be wrong, not that one more fix is needed. Resetting to a clean state and
re-deriving from verified facts is cheaper than an open-ended patch loop,
because each patch rests on the same unverified foundation that produced
the failure. Patching treats the symptom; resetting forces you back to
the source of truth.

To be concrete about the two: **patching** is making the current error
disappear with one more local fix while keeping the same approach —
each fix assumes the approach is sound and just had a small bug.
**Resetting** is discarding the broken attempt, returning to a clean
state, and re-deriving the solution from facts you have actually
verified — which often surfaces that the approach itself was wrong.
Repeated failure on a "simple" thing is the signal to reset, not to
patch again.

### H. Never let "done" be a feeling
"Done" is a state with evidence behind it, not a sense of being close.
If you cannot point to the independent proof for each load-bearing claim,
you are not done — you are hopeful. Treat the urge to declare victory as
a prompt to find the one thing still unproven.

## The one-line version

Your own confidence is not evidence. Make an independent source prove
each load-bearing fact against the exact thing you run, re-verify after
every change, exercise the paths review can't certify, and treat a
failure as "wrong approach, reset" rather than "one more patch." The
discipline is the deliverable; the working artifact is just its
byproduct.
