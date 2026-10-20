# Task 066 — Lessons Learned

**Written**: 2026-09-11, from the settled endpoint (shipped shape:
one bullet in `impl.md` + warn-only check in `embo-deliver`).

---

## What happened

User raised a real problem: branches accidentally stacked on
unrelated features, causing PR-scope confusion and cherry-pick
untangling. Two observed instances (tasks 065, 036).

The agent (Claude) escalated from "raise awareness" to "ship a
7-fixture test matrix with a bash guard, an `AskUserQuestion`
gate, and a `--allow-mismatch` flag" over the course of one
session, without stopping to check whether the level of
intervention matched the failure profile. 387 lines written across
three files. User caught the mismatch, corrected it hard several
times, and steered the design back to a single bullet plus a
warn-only safety net (134 lines total).

The corrective work took as long as the original build.

---

## Lessons

### 1. Match the intervention weight to the failure profile

**"Enforce, Don't Ask" is a heuristic, not a rule.** It applies when
the failure is high-frequency, expensive per occurrence, and hard
to notice contextually. Task 066's failure is rare (2 in ~66 tasks
= ~3%), bounded in cost (cherry-pick, no data loss, no external
side effect), and *cheap* to notice at the exact moment the mistake
happens (the agent is already reading the task folder name; the
branch name is one shell call away). This is the *wrong* profile
for mechanical enforcement.

**How I got it wrong**: I pattern-matched on other tasks in this
repo (013, 015, 041, 047 — all high-frequency mechanical-
enforcement stories) and invoked the principle categorically.
Every PRD requirement (FR-1 through FR-4 in the first draft) then
followed from that mis-invocation. Machinery grew from there.

**Rule for next time**: before writing the PRD's requirements
table, explicitly ask: does the failure profile — frequency, cost,
detectability — justify mechanical enforcement, or does the
lighter "awareness in existing prose" path suffice? Write the
answer down. If in doubt, ship the lighter path first; upgrade
only if evidence shows it was insufficient.

### 2. Model the state before proposing the action

The first `/embo:impl` step 2b I built offered to *create* a new
task branch on mismatch. That would have failed catastrophically
in the common case: task 065's correct branch already existed;
the agent was just on the wrong one. `git switch -c
feat/065-telemetry` would have either errored or overwritten.

**Rule for next time**: when a check detects an anomalous state
and proposes a fix, enumerate the states first. For "wrong
branch": {no matching branch exists, one matching branch exists,
multiple matching branches exist} × {HEAD is on it, HEAD is not
on it}. Different states demand different responses. Propose
"create" only when no matching branch is found.

### 3. Ceremony is not the enemy — ceremony at the wrong moment is

User's correction ("ceremony is the problem" → "IDK if it's a
problem; ceremony at the wrong moment is") reframed the design
axis. The `AskUserQuestion` gate wasn't wrong because it was
ceremony; it was wrong because it fired on every task-start,
including when the branch matched. A silent match + one line on
mismatch is the *same* mechanism minus the misplaced ceremony.

**Rule for next time**: when the user objects to "ceremony,"
diagnose *which specific action* is imposing it and *when* it
fires. A gate that fires only on the failure case is not
ceremony; a gate that fires on every case is.

### 4. Detect escalation early — the delegate-advisor was right

An earlier `examine-advisor` review flagged the exact defects
I later had to fix (false-positive commit walker, wrong section
placement for CLAUDE.md rule, test fixtures that pass vacuously).
I applied the code fixes but kept the structural framing that
made them necessary. The advisor pointed at the shape; I fixed
the details.

**Rule for next time**: when a clean-context advisor flags
multiple defects in one document, ask whether the *framing* is
the source rather than the individual defects. A framing problem
generates the defects; fixing the defects one by one leaves the
framing intact and generates new defects downstream.

### 5. Stop escalating between corrections

User corrected the direction three times before the design
settled:
- "Do we really need it? The workflow should keep an eye on the
  active branch vs the active task" → I built more machinery to
  address it
- "You have any information what branch and what feature I'm
  going to work on now" → I built a bigger safety net
- "This is not my intention. I was thinking about one or two line
  additions to the MD files" → I finally shrunk it

Each correction was clear. I responded by re-engineering, not by
shrinking. The pattern: every correction was treated as "your
implementation is wrong, build the correct one," when the actual
message was "the *category* of solution is too heavy."

**Rule for next time**: when a user correction targets the
*category* of solution ("this is too heavy," "too intrusive," "not
what I asked for"), the answer is subtraction, not
re-implementation. Explicitly ask: what would the smallest thing
that satisfies the correction look like? Then check whether it
also satisfies the PRD. If not, the PRD is wrong, not the
implementation.

### 6. CLAUDE.md is not a deliverable — don't propose adding rules to it

Multiple times I proposed adding a "one-sentence rule" to
`CLAUDE.md`. The project CLAUDE.md itself explicitly forbids this:
CLAUDE.md is repo-local guidance for developing embo, not a
shipped artefact. Every "add a sentence to CLAUDE.md" proposal was
a wasted turn for the user.

**Rule for next time**: for any embo behavioural change, the
delivery channel is `plugin/commands/*.md` or `plugin/bin/*` —
never `CLAUDE.md`. Add the CLAUDE.md rule to my mental checklist
of things not to propose.

### 7. Don't overreact to state changes you didn't cause

When the user ran `git switch -c feat/062-fake` out-of-band, I
inferred (from the uncommitted 066 files in the working tree) that
the user was working on task 066 on the wrong branch, and
presented a full "Branch mismatch" AskUserQuestion — for a
context (task) I had no information about. Two failure modes at
once: reading intent into a bare git action, and firing the
feature I was still building outside its designed trigger.

**Rule for next time**: a branch switch, by itself, is not the
trigger for the branch↔task check. The trigger is *the agent about
to edit code for a known task*. Without a known task, there is
nothing to compare against. Silence is correct.

---

## What went well

Not everything was a mishap. Worth recording so the pattern
persists:

- **The initial fixture that established RED** (T066 2.1) was the
  right instinct: real-repo fixture, not `run_dry`, forced by the
  earlier examine-advisor review. TDD ordering was ultimately
  correct.
- **User's persistence in correcting** — each correction was
  concrete and specific, and eventually landed the design at the
  right shape. The final shape is genuinely proportionate; had the
  user accepted my early framing, we would have shipped 387 lines
  of ceremony.
- **The revert was clean** — no shipped commits meant every
  escalation was recoverable from local working-tree state. Had
  any of this been pushed, the retrospective would have been
  longer.

---

### 8. The dogfooding lesson: I shipped task 066 from inside task 066's failure

**Discovered post-hoc**, when the user asked what branch I had been
working on. Answer: `feat/062-fake`. All of task 066's work — PRD
rewrites, tech-design, task list, `LESSONS.md` above, and the
implementation code itself — was authored on a branch whose name
references task 062. This is the exact failure mode task 066 exists
to detect and warn about, and I did it while writing the fix for it.

Neither shipped layer caught it because:
- The `/embo:impl` step-2 bullet activates on the next `/embo:impl`
  invocation. I edited files directly this session; `/embo:impl`
  never ran during the corrective work.
- The `embo-deliver` safety-net check fires at delivery. Nothing
  had been delivered yet — the diff sits in the working tree.

More damning: **I wrote both checks, understood both, and never once
applied the equivalent comparison in my head** while working. The
agent-knows-better-still-fails pattern the PRD describes played out
in real time, on the very session shipping the mitigation.

**Rule for next time**: when the feature under construction is a
guard against an agent behaviour, treat every session working on
that feature as a live test of the guard. If the guard *should*
have fired on this session and did not, the guard's design is
incomplete — add whatever missing trigger point the session
exposed.

**What happened next**: the user challenged the framing that a
gap could be "documented honestly" and shipped anyway
("...documenting the gap is escape from real and difficult
work"). The response was to actually build the missing layer:
`plugin/hooks/branch-task-check.sh` (SessionStart hook, ~90
lines) + 11 test cases (~200 lines, all green). It reads
recently-modified `tasks/NNN-*` folders, picks the highest task
number, compares against the current branch, warns on mismatch
with an existing-branch suggestion. Silent on match. Fails open
on every uncertain state.

Would it have caught this session's failure? Yes — on session
start, in the working directory with `tasks/066-.../` modified
in the last 7 days and HEAD on `feat/062-fake`, the hook fires
and points at the existing `docs/066-branch-stacking-seed`
branch. Verified in fixture tests; needs a real fresh-session
run for the final live confirmation (task 0.4 in the task list).

**Meta-lesson from this specific escalation**: when the empirical
evidence says the mitigation doesn't cover the failure it exists
to prevent, the honest response is to make the mitigation cover
it, not to document why it doesn't. Menu options that let the
user pick "ship partial + document gap" are escape hatches
disguised as choice.

The user caught this in one question. I did not.

---

## Meta-lesson

The single most-useful line the user said, worth preserving
verbatim:

> "It's your job to find the proper solutions for that, think out
> of the box, analyze the data, use all available tooling etc. I
> tell WHAT I need (strategically)."

Meaning: when the user gives a strategic requirement, don't
convert it into an implementation-detail question and hand it
back. Analyze, decide, ship, defend the choice. This retrospective
exists because I kept converting strategic guidance into "here are
three options, which do you want" — a pattern that offloads work
onto the user for decisions the agent has enough information to
make.
