# Release-notes style — what to fix, and how

This doc records the concrete rewriting lessons from polishing the
0.2.5 Live-Edit Mode changelog entry. Consult it before writing or
reviewing a CHANGELOG entry: the failure modes below are ones a
first draft reliably falls into, and each has a rewrite rule.

The CHANGELOG contract is set in `CLAUDE.md` (# CHANGELOG Entries):
describe **what the released version does**, in **behavior** not
mechanism, and every release gets an entry. This doc is the
operational layer on top of that — the recurring drafting mistakes,
and the moves that fix them.

## The rewrite rules, in order

Work through these top-to-bottom on any entry. Each rule is a
question to ask about the current draft.

### 1. Does the entry belong under Added or Fixed?

An entry is `Fixed` only if there is a **shipped predecessor**
whose behavior was wrong or missing and is now correct. First-
release polish of a brand-new feature belongs under `Added` — even
if the polish came from bug-shaped commits along the way. If the
predecessor is the same release, it never shipped, so there is no
fix to record.

Test: "did a released version behave differently before?" — no →
`Added`, yes → `Fixed`.

### 2. Have you named the one thing the feature changes?

Before rewriting, name — in one sentence, to yourself — the single
load-bearing idea the feature adds. Every other line in the entry
must serve it.

If you cannot name that idea, you are not ready to write the
entry: you will churn on wording that is describing scaffolding
(the panel, the toggle, the version banner) instead of the change
itself.

For Live-Edit Mode the idea was: **the fix is chosen visually, in
the running app, before any code changes.** Everything else — the
panel, candidate overlays, lock-in — is a consequence of that idea,
not the idea.

### 3. Are you leading with the load-bearing idea, or with implementation?

Lead with what the user gets, not with the mechanism that
delivers it.

- Bad: "Live overlays on the running page hold candidate edits…"
  (implementation noun first)
- Good: "a WYSIWYG loop for tuning a page against a design…"
  (idea first; overlays are a means to it)

The technology is not important; the UX is important. If the
first clause mentions a data structure, a hook, an overlay, or a
file, rewrite it.

### 4. Have you named where the inputs actually come from?

A feature that takes input from the user, or from Claude, or from
both — say which. "Candidate fixes appear" hides the actor. Being
honest about the initiative direction changes what the entry
means.

Test: for every noun the feature acts on, ask "where does this
come from?" If the entry does not answer, add it.

For Live-Edit Mode both directions matter: **you describe a
change, OR Claude proposes options** — leaving out either half
misrepresents how the feature is used.

### 5. Have you named the actor for each step?

Distinct steps often have distinct actors. Collapsing them into
passive voice ("changes are written") hides who does what and
whether the user can control it.

For Live-Edit Mode:

- **You** describe the change (or accept Claude's proposal).
- **Claude** applies it live on the page.
- **You** accept the result.
- **Claude** writes it back into the source.

The lock-in step is not something the user does with their hands;
naming Claude as the writer answers the reader's implicit "…how do
I do that?".

### 6. Are you flattening a distinct step into a generic verb?

"Written to source" is a plain file-write; the Live-Edit lock-in
step chooses the correct stylesheet rule, component template, or
handler and edits each at its real origin. That is not a plain
write — using the plain verb hides the substance.

Same failure mode: "the tool cleans up" (does what?), "the
command runs the check" (which check?), "you configure it" (how?).

If a step is only interesting because of how it works, at least
gesture at how — not with implementation detail, but with the
distinction that makes it non-trivial.

### 7. Are you using a term from a different context?

Words carry the context they were introduced in. "Gap" for
Live-Edit Mode came from `/embo:visual-impl`'s Figma-verifier
context, where the reference is a design and a "gap" is the diff.
Live-Edit runs against **a design OR your own intent** — no
reference required. Reusing "gap" silently narrows the feature.

Test: for each specialised term in the entry, ask "does this term
mean exactly the same thing here as in the place I know it from?"
If not, replace it or define it.

### 8. Is every word carrying meaning?

Once the meaning is right, cut. Common cutta­bles:

- "the running page" → "the page" (there is only one)
- "either way," → often just delete; the reader has already
  understood the OR from the previous sentence
- "at their real origins (the specific stylesheet rule, the
  component template, the event handler)" → "at their real
  origins" if the examples don't earn their space
- "so no edit-rebuild cycle per attempt" → often can go if
  "no file edit, no rebuild" is already in the entry
- Filler verbs like "iterate on", "work through", "engage with"
  → name the actual action or drop the sentence

Test after cutting: does the entry still deliver the load-bearing
idea (rule 2), the input source (rule 4), and the actors (rule 5)?
If yes, the cut is good.

### 9. When a mechanism became optional, did you say what it still adds?

If a feature previously required a setup step (enable, install,
configure) and now works without it, the entry has to describe
both facts, not just the removed requirement.

- "X now works without Y" alone reads as "Y is unnecessary" and
  the user will skip Y forever.
- Add: "Y is still recommended because it adds Z (which the
  new default doesn't carry)".

The template: `<feature> works out of the box. <how the default
path works.> Running <Y> is still recommended — <what Y adds that
the default lacks>.`

Example (0.2.5 correction capture): the marker-file capture works
without `/embo:enable-corrections`, but enabling it still adds
semantic search across history and cross-session context that the
marker file alone doesn't carry. Both facts belong.

### 10. Have you deleted the euphemisms?

Phrases that sound descriptive but say nothing:

- "try them in the browser" — try how?
- "hand-apply" — meaning what?
- "watching the page redraw" — what does this add?
- "you keep the ones that look right" — as text this is fine, but
  under scrutiny "keep" hides the accept-and-write mechanism

If a phrase would collapse under "how does that work?" from a
reader, either answer the question or delete the phrase.

### 11. In a Fixed entry, name only the specific capability that changed

A Fixed entry that names the whole feature area suggests every part
of it was previously broken. Cut adjacent, correctly-shipped
behavior. Test: for each clause, was this specifically what didn't
work? If not, drop it.

### 12. Say "predecessor was broken" only when the reader would otherwise wonder

The `Fixed` header already tells the reader something was wrong.
Naming the specific broken capability from the previous release is
worth it when the fix corrects a flagship feature the reader may
already have tried and given up on. For routine cleanups, the
header carries the meaning; adding "vX.Y shipped it broken" is
noise.

### 13. No project vocabulary in user-facing entries

Rule 10 removes empty phrases; this one removes internal terms that
carry meaning inside the repo but not outside. Command names,
internal mechanism names, and any word the reader could only learn
from a command file need to be rephrased in ordinary English or
dropped. Test: could a reader who has only seen the README follow
this?

### 14. No showing-off, especially on bug fixes

State what the version does; do not celebrate that it does so. On a
release that fixes a bug that should not have shipped in the first
place, the tone is neutral acknowledgment, not applause. Cut
adjectives that praise the fix ("that actually works", "now really
does X", "the version you've been waiting for"). Also cut hedged
apologies ("finally", "at last") — they draw attention to the earlier
failure. The `Fixed` header carries the meaning; the entry states the
capability plainly.

Test: if the sentence still reads like an announcement of a new
achievement after you remove the version number, cut the celebratory
word. Applies equally to CHANGELOG entries, GitHub Release bodies,
and social/announcement posts.

## The trajectory (Live-Edit Mode 0.2.5)

The entry passed through six drafts. Each draft's fault, and the
rule from above that caught it:

| Draft | Fault | Rule |
|---|---|---|
| 1: "a floating toggle panel injected into the live page lets you turn candidate fixes on/off…" (later moved to Fixed as nav-persistence bullet) | Two-bullet split for one feature; nav-persistence is not a fix, it's part of the feature | 1 (Added vs Fixed) |
| 2: "a floating panel toggles candidate fixes on/off, then locks the chosen ones back into the project's source" | Names the UI affordance, not where candidates come from | 4 (name inputs) |
| 3: "Claude proposes candidate fixes… a floating panel lets you try them in the browser" | "Try them in the browser" is a euphemism for the mechanism | 9 (delete euphemisms) |
| 4: "Claude injects candidate style, markup, or logic fixes into the running page as live overrides you can toggle on and off…" | Implementation-first; too long; still misses that YOU also author changes | 3 (lead with idea), 4 (inputs) |
| 5: "a WYSIWYG loop for fixing a page… Live overlays hold candidate edits — some proposed by Claude, some you author in the panel yourself" | Leads with implementation ("live overlays hold"); "gap" borrowed from Figma context; "no edit-rebuild cycle per attempt" is jargon the reader must decode | 3, 7, 9 |
| 6 (final): "a WYSIWYG loop for tuning a page against a design or your own intent. You describe a change, or Claude proposes options; Claude applies it live on the page — no file edit, no rebuild. When the page looks right, you accept and Claude writes the changes back into the source at their real origins." | — | passes all rules |

## The one-line checklist

Before committing a CHANGELOG entry, ask in order:

1. Added or Fixed — do I have a shipped predecessor?
2. What is the load-bearing idea? Have I said it first?
3. Where do the inputs come from? Have I said who acts on each step?
4. Am I hiding a substantive step behind a generic verb?
5. Am I reusing a term from a context that narrows the meaning?
6. If a setup step became optional, did I say what enabling it still
   adds?
7. Every word carrying its weight — cut what isn't.
8. For a Fixed entry, is each clause specifically what was broken?
9. Am I calling out a predecessor version the reader doesn't need
   named?
10. Would a reader with no project vocabulary understand every phrase?
11. Any showing-off adjectives or hedged apologies — cut them.
