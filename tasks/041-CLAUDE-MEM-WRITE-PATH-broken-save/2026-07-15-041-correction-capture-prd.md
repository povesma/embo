# 041 — Capture user corrections so `/embo:improve` works — PRD

**Status**: Draft. **Created**: 2026-07-15.

**Background for the reader**: embo ships a command called
`/embo:improve`. Its job is to look at the corrections a user gave
Claude over time — moments where the user told Claude to work
differently ("check the documentation first", "don't over-complicate
this", "use jq instead of python") — find the ones that keep repeating,
and write them up as a proposal the user can send to embo's maintainer
to improve the workflow. `/embo:improve` has never actually worked,
because nothing was ever saving those corrections anywhere it could read
them. This document proposes the feature that fixes that.

**How corrections get saved (the key fact)**: embo relies on a separate
tool called claude-mem. claude-mem runs a background program that reads
each Claude Code session and writes short notes ("observations") about
what happened — bug fixes, new features, discoveries, and so on. It
decides the note's category on its own. Out of the box, claude-mem has
no category for "the user corrected Claude", so corrections are never
saved as their own kind of note. This session proved that claude-mem
**can** be configured to add a "correction" category, and that it then
saves corrections correctly. This feature packages that configuration so
any embo user can turn it on.

**Why let claude-mem's background program record corrections, instead of
having Claude record its own?** Because the Claude doing the actual work
is focused on the task and tends to miss or skip logging its own
mistakes. A separate program watching the whole conversation catches
them more reliably. (Verified by studying claude-mem's code and by
research into similar systems.)

**This replaces earlier plans** in the SEED file and in task 009's PRD,
which both assumed corrections had to be written to a local file because
claude-mem "had no way to save them." That turned out to be wrong —
claude-mem's background program can save them once it has a "correction"
category. Full technical detail and live evidence:
`FINDINGS-correction-capture.md` in this folder.

---

## What we are building

Two new embo commands (exact names to be decided in tech-design; call
them the **turn-on command** and the **turn-off command** here), plus a
rewrite of the existing `/embo:improve` command.

- **Turn-on command**: the user runs it once. It configures claude-mem
  to start saving corrections. No manual editing of files by the user.
- **Turn-off command**: the user runs it to stop saving corrections and
  put claude-mem back exactly as it was.
- **`/embo:improve` (rewritten)**: reads the saved corrections and helps
  the user turn them into an improvement proposal.

Turning correction-saving on is **optional and off by default**. It is
never switched on automatically when embo is installed — the user must
run the turn-on command themselves. This matters because the change
affects claude-mem for **every** project on the user's machine, not just
the current one (see "Costs we accept" below).

---

## Goals

- After the user runs the turn-on command, corrections they give Claude
  are saved automatically, with no further effort.
- `/embo:improve` finds those corrections and produces a useful proposal.
- The turn-off command fully undoes everything the turn-on command did.
- Normal claude-mem note-taking (all its other categories) keeps working
  the same whether correction-saving is on or off.
- If the user runs `/embo:improve` when correction-saving was never
  turned on, the command says so clearly and tells them how to turn it
  on — it does not just say "nothing found".

## Non-goals

- Turning correction-saving on automatically at install time. It is
  always a deliberate choice by the user.
- Catching every possible correction. A correction is caught when the
  user says it as a normal chat message to Claude; corrections tucked
  inside a message that is mostly about something else may be missed
  (explained under "Known limitations").
- Repairing a bug in claude-mem's own search (explained under "Known
  limitations"). We work around it instead.

---

## The main story: `/embo:improve`

This is the point of the whole feature. Everything else exists to feed
it.

**Who**: a developer who has been using embo and, over several
sessions, has corrected Claude a number of times.

**What they do**: they run `/embo:improve`.

**What they see**: the command gathers the corrections that were saved,
groups the similar ones together (for example, three different times the
user said some version of "verify against the real docs before you
guess"), and shows each group with:
- how many times that kind of correction came up,
- a couple of real examples in the user's own words,
- a suggestion for which embo file or rule could change to prevent that
  correction from being needed again.

**What they can do with each group**: accept it (include in the
proposal), edit the wording, or reject it (drop it — it was a one-off,
not a pattern).

**What they get out**: a tidy write-up they can copy into a GitHub issue
or send to embo's maintainer, saying "here is where the workflow keeps
tripping me up, and here is what might fix it."

**If nothing was saved**: the command must tell the user *why*. There
are two cases and they must be distinguished:
1. Correction-saving was never turned on → the command says exactly that
   and tells the user to run the turn-on command.
2. Correction-saving is on but genuinely nothing has been corrected yet
   → the command says "no corrections to review" plainly.

**Not-a-correction cases** (must NOT be saved or shown): the user
changing what they want built ("let's do feature B instead"), a design
choice ("make that field optional"), or reordering work ("skip task 3").
These are normal project decisions, not corrections of how Claude works.

---

## The supporting stories

### Turn it on (one command, no manual steps)

The user runs the turn-on command and correction-saving is active
afterwards, without editing any files by hand.

Acceptance criteria:
- The command configures claude-mem to add the "correction" category
  and start saving corrections (the exact steps it performs are in
  FINDINGS — building a config file, setting two settings, restarting
  claude-mem's background program).
- It performs all steps itself; the user types nothing beyond running
  the command.
- It confirms success by checking that claude-mem actually loaded the
  new configuration, and reports what it changed.
- If it cannot succeed (for example claude-mem is set up in a way this
  does not support, or a required tool is missing), it says clearly what
  is wrong instead of pretending it worked.

### Turn it off (one command, full undo)

The user runs the turn-off command and claude-mem is back to how it was.

Acceptance criteria:
- Every change the turn-on command made is reversed.
- claude-mem returns to its normal categories and behaviour.
- Corrections already saved are left in place (turning it off does not
  delete past corrections).

### Corrections get saved during normal work

With correction-saving on, when the user tells Claude to work
differently, that gets recorded as a correction.

Acceptance criteria:
- When the user gives a correction as a normal chat message, a
  correction record is saved, tied to the current project, with a clear
  title and summary of what the user wanted changed.
- If the same message both corrects Claude and involves normal work,
  both get recorded — the correction is not lost inside the record of
  the work.
- Normal (non-correction) work is still categorised correctly. Turning
  correction-saving on must not damage claude-mem's other note-taking.

### `/embo:improve` notices when saving is off (detect + point to fix)

Acceptance criteria:
- `/embo:improve` can tell the difference between "correction-saving was
  never turned on" and "it is on but there is nothing to review".
- In the never-turned-on case, it tells the user to run the turn-on
  command.
- (Deeper breakage — for example claude-mem updated and quietly reverted
  the configuration — is out of scope for this first version; it will
  show up as "nothing to review". A fuller health check can come later.)

### It keeps working after claude-mem updates

Acceptance criteria:
- The configuration is stored in a location claude-mem's updates do not
  overwrite (design intent — this is reasoned from the code but has NOT
  yet been observed across a real update; it must be tested when
  claude-mem next updates — see FINDINGS).
- After a claude-mem update, there is a way (documented or automatic) to
  rebuild the configuration so it matches the updated claude-mem.

---

## Costs we accept (the main design decision)

Turning correction-saving on changes claude-mem across the user's whole
machine, not just the current project — because claude-mem uses one
shared background program for everything. It also edits one Claude Code
setting. We accept this because:
- it only happens when the user deliberately runs the turn-on command,
  and
- the turn-off command fully reverses it.

We also accept that this feature depends on internal details of
claude-mem that its future updates could change. The feature must
document that risk and provide the rebuild step above.

Alternative considered and rejected: building embo's own correction-
saving from scratch (a separate watcher program). Rejected because it
would duplicate what claude-mem already does, and this session proved
configuring claude-mem works.

---

## Known limitations (must be stated in the command's help text)

- **A correction is caught when the user says it as its own chat
  message.** A correction buried inside a message that is mostly about
  something else may not be recorded. (This is because claude-mem's
  background program only receives the user's message text at the start
  of each turn.)
- **claude-mem's search has a bug**: asking it for notes "of category
  correction" returns nothing, even though the corrections are saved.
  `/embo:improve` works around this by searching the note text instead
  and then keeping the ones that are corrections. (This is claude-mem's
  bug, not embo's; version 13.11.0.) **We must make sure this bug is
  reported to the claude-mem project** — check whether an issue already
  exists in their GitHub, and open one if not, so the search filter can
  eventually be fixed and we can drop this workaround.
- **While on, it affects every project** on the machine, and it relies
  on claude-mem internals that updates could change.

---

## Open questions for tech-design

- How `/embo:improve` remembers which corrections it already showed the
  user, so they do not come back every time. (claude-mem has no way for
  a command to write a note directly, so this likely needs a small local
  file. This was the original problem in the SEED.)
- Where the two new commands and the config-building helper live inside
  the plugin.
- The exact, reliable way a command restarts claude-mem's background
  program.
- Whether turning it on should also make corrections show up in the
  session-start summary, or stay out of it.

## Upstream action item

- **Report the claude-mem search-filter bug** (asking for notes of a
  custom category like "correction" returns nothing, though the notes
  are saved; version 13.11.0). Search the claude-mem GitHub for an
  existing issue; if none, open one with a minimal reproduction. Track
  the issue link here so the `/embo:improve` workaround can be removed
  once upstream fixes it.

## Next steps

1. Review and approve this PRD.
2. `/embo:tech-design` — answer the open questions above.
3. `/embo:tasks`, then `/embo:impl`.
