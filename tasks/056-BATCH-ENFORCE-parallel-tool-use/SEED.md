# 056-BATCH-ENFORCE: Real enforcement for parallel tool_use

Seed for a future `/embo:prd` run. Work MUST proceed on a dedicated
feature branch — never straight to `main`.

## Why now

Task 052 FR-9 documented `/embo:start` as two parallel batches (A: 5
independent discovery calls; B: 2 profile-dependent calls) with the
wording *"emit these as parallel `tool_use` blocks in the same
assistant response"*. Two headless test runs (2026-08-22 and
2026-08-23) confirmed the model ignores this directive: 11 and 10
turns respectively, when the data-dependency graph supports 3.

This is the exact failure the embo `## Core Design Principle — Enforce,
Don't Ask` warns about: **prose-level enforcement is unreliable and
must be converted into a deterministic mechanism**. FR-9 was
downgraded to best-effort in 052 pending this task.

## Evidence

- `tmp/052-post5-headless-run.json` — first run, 11 turns.
- `tmp/052-post5b-headless-run.json` — second run after prose
  strengthening ("parallel tool_use blocks in the same response",
  Batch A / Batch B rename), 10 turns.
- Both runs: Batch A serialized as 5 single-tool turns (T2-T6).

## Candidate mechanisms (for the tech-design pass to choose from)

1. **Stop-hook that inspects the transcript** and either warns the
   user or self-corrects when it detects a serial-single-tool pattern
   during `/embo:start`. Cheap to build, mirrors the pattern used by
   `behavioral-reminder.sh` and the correction-capture hooks.
2. **Bash wrapper (`embo-start-discovery`)** that runs the 5 Batch A
   calls in one shell invocation and returns a structured JSON blob.
   The command body then makes a single Bash call. Removes 4 turns
   deterministically, but binds Bash and Read into one shape (the
   README read would need to move into the wrapper).
3. **`tool_choice: any` with a required set** — a Claude API feature
   where the caller can force the model to emit specific tools in a
   specific response. Requires infrastructure changes if the CLI
   exposes it.
4. **A dedicated `/embo:start-fast` variant** that ships as a script
   instead of a prompt, so the batching is done by code, not by prose.

## Preservation contract

- The 6 output sections of `/embo:start` must still be produced.
- The rules region in start.md stays byte-identical (locked by task
  052 FR-8; still applies).
- Whatever mechanism ships must degrade gracefully on missing
  dependencies (RLM off, memory empty, no git remote, no README).

## Verification method

`manual-run-claude` — headless `claude -p "/embo:start"` with
`--allowedTools` set to the frontmatter list; transcript shows ≤ 3
assistant turns containing tool calls. The mechanism, whatever it is,
must produce this measurably.

## Out of scope

- Any other command's turn count (task 055's audit output ranks the
  next targets).
- The scout empty-return defect (task 057).

## Delivery constraint

Dedicated feature branch. PR merge (`/embo:git deliver` with
`pr-merge` or `release`).
