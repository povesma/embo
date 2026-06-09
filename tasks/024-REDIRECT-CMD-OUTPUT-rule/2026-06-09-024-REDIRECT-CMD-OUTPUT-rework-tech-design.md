# 024-REDIRECT-CMD-OUTPUT — Rework Tech Design

Supersedes the redirect-remedy portion of the original Task 024 tasks
file and the diagnose/extract redirect split added by Task 028. Written
2026-06-09 after the original premise was proven partly obsolete.

## Why this rework

The original rule prescribed: "for large output, redirect to an
in-project `tmp/` file and read it." Task 028 elaborated that into a
diagnose-vs-extract redirect split. Both rest on a premise that is now
false:

> Premise (obsolete): the agent must manually redirect a command's
> output to a file to keep the full record when output is large.

This premise caused repeated, avoidable permission prompts: a manual
redirect (`> tmp/x`) is shell syntax the static permission engine
cannot analyze, so it prompts unless a hook rewrites it. The rule's own
mechanism fought the zero-prompt goal.

## Proven mechanism (the basis for the rework)

Verified empirically on 2026-06-09 in this repo session:

1. **The harness auto-persists oversized tool output.** When a tool's
   output exceeds the inline limit, the harness writes the **full**
   output to a file and returns a fixed-size preview plus the path.
   Observed message shape:

   > `Output too large (NNN KB). Full output saved to:`
   > `/Users/<user>/.claude/projects/<sanitized-cwd>/<session-id>/tool-results/<id>.txt`
   > `Preview (first 2KB): …`

   **Measured this session** (do not over-specify beyond these):
   - Trigger: a 2KB preview was emitted for outputs of **11.2KB** and
     **263.8KB**. The exact threshold is not pinned — only that outputs
     at/above ~11KB persist. Treat the threshold as "an indeterminate
     size limit; react to the message, do not predict it."
   - Preview size: **first 2KB** of the output, in both observed cases.
   - Path: under `~/.claude/projects/<sanitized-cwd>/<session-id>/
     tool-results/<id>.txt`. The `<id>` is opaque (e.g. `b2n65m71t`) or
     a descriptive hook name.

2. **The persisted file is readable with no re-run.** Two access paths,
   each verified 2026-06-09:
   - **Read tool / Grep tool — always free.** Reading
     `…/tool-results/b2n65m71t.txt` with the Read tool succeeded with no
     prompt and no Bash. (It refused only when asked for 143k tokens at
     once; with `offset`/`limit` it serves any slice. Grep searches it
     the same way.) This is the preferred path.
   - **Bash on the file — follows the normal allow-list.** `grep -c ""`
     against that persisted path ran with no prompt because `Bash(grep:*)`
     is allow-listed; the off-workspace location did **not** trip the
     filesystem sandbox for a read. So `grep`/`head`/`tail` (allow-listed)
     work on the file; a non-listed reader like `wc` would prompt just as
     it would anywhere. The path being outside the workspace is not a
     blocker for reads — the allow-list is the only gate.

3. **No re-run is required.** The full output is on disk from the
   **first** run. Recovering truncated output never means running the
   command again — which is what makes this safe for slow or
   non-idempotent commands.

### Consequence

The "redirect large output to `tmp/`" instruction solves a problem the
harness already solves — for free, after the fact, with no re-run and
no prompt. It should be **removed**, not patched.

## What stays vs. what goes

**Stays (still valid):**
- The exit-code integrity lesson: do not pipe a command **whose success
  you are checking** into `| tail` / `| head` / `; wc`. A pipeline
  reports the filter's exit code, not the command's, so a failure reads
  as a pass. (Piping is fine when output is known and you are not
  checking the exit code, e.g. `git log --oneline | head -5`.)
- Read the command's native exit code; never append `; echo $?`.
- When a command fails, read the lines that explain why.
- Never conclude success from a clean truncated tail.

**Goes (obsolete):**
- "For large output, redirect to a `tmp/` file" as the remedy for size.
- The Task 028 diagnose-vs-extract redirect split **as a size remedy**.
  (The diagnose/extract distinction survives only for the narrow
  artifact case below.)
- The `.gitignore`-the-scratch-dir dance presented as a routine step for
  reading output.

## New rule shape (for stage b)

1. **Default: run one plain command, once.** Output and exit code come
   back inline/natively. No redirect, chain, pipe, or `$(...)` — each is
   unanalyzable shell that prompts and buys nothing.
2. **Oversized output:** the harness already saved it to
   `…/tool-results/<id>.txt`. Read that file (offset/limit) or Grep it.
   No prediction, no second run, no manual redirect.
3. **Manual redirect is justified by exactly one thing — producing a
   reusable artifact** (feed another command; read repeatedly). Not "in
   case it is large." When you do redirect, keep the hook-approved
   shape: **one allow-listed command + one redirect to `tmp/`** — no
   chaining, no pipe, no `$(...)`. The `approve-compound.sh` hook strips
   the redirect, confirms the bare head is allow-listed, and approves
   silently. `tmp/` must be in `.gitignore` (captured output may hold
   secrets); never the absolute `/tmp` (off-workspace write prompts).
   - diagnose (keep stderr): `cmd > tmp/out.log 2>&1`
   - extract a value (stdout only): `cmd > tmp/value.yaml`

## Cross-task reconciliation

- **Task 028** (REDIRECT-ZEROPROMPT): its redirect split is reframed,
  not deleted — it now applies only to the artifact case, not to size.
  The hook work from 028 (strip redirects, strip reflexive tail) is
  unaffected and remains the mechanism that keeps the artifact redirect
  prompt-free.
- **behavioral-reminder.sh**: the `REDIRECT-CMD-OUTPUT` baseline token
  stays; only the rule body in `start.md` changes.

## Out of scope

- Changing the harness behavior (it is upstream Claude Code).
- The `approve-compound.sh` hook logic (already correct; verified 61
  tests passing 2026-06-09).
