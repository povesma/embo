---
description: >
  Independently examines a decision (competing options) or a conceptual
  document (PRD, tech-design, etc.) you are unsure about, by running the
  examine-advisor agent as two parallel passes — research (prior art via
  NotebookLM) and internal (codebase / consistency) — then reconciles
  them into one report plus a recommendation. Invoke with
  /embo:research:examine. Report-only; never edits the target.
---

# Examine a Decision or Document, Independently

Get an independent read on a direction you're unsure about — which
option to pick, or what's weak in a draft document — from two parallel
clean-context passes, reconciled into one recommendation. This command
is a thin spawner: the judgment lives in the `examine-advisor` agent.

## When to Use

- You are offered options (exclusive or not) and cannot confidently
  decide — the choice is finely balanced, or too technical.
- You have a conceptual document (PRD, tech-design, proposal) and want
  its inconsistencies found and improvements suggested.
- For a single quick fact, use Context7 directly; to verify a chosen
  spec against acceptance criteria, use `dev:research:verify`.

## Process

1. **Identify the target.** If the argument resolves to a readable file,
   treat it as a document; otherwise treat the argument (and any
   following prose) as the options/decision to weigh.

2. **Build the digest + surrounding context.** Produce a purpose-shaped
   **digest** of the target (not a raw paste) AND assemble the
   **surrounding-context block** the agent requires — the goal the
   direction serves, its constraints, what has been tried or ruled out,
   and why you're unsure. The agent runs blind and cannot ask; thin
   context yields a weak read.

   **Sanitize the digest before it leaves the machine** (the research
   pass sends it to NotebookLM): hard-block secrets (passwords, tokens,
   keys) and user-identity (external IPs, public hostnames, local paths,
   account markers). Internal IPs and non-identifying technical detail
   are fine. Ask the user when a value's sensitivity is unclear.

3. **Get user go-ahead** on the digest + context block before any
   outbound call (a subagent cannot prompt mid-run).

3a. **Verify the NotebookLM MCP server is connected — a precondition for
   the research pass.** A subagent spawned while `gemini-notebook-mcp` is
   disconnected receives NONE of its `mcp__gemini-notebook-mcp__*` tools (the
   tools do not exist in the session at that moment), so the research
   pass silently degrades to reasoning-only. Do NOT let that happen
   silently, and do NOT work around it by running the query from the
   main context — that hides the failure.
   - Check reachability first (e.g. attempt a cheap
     `mcp__gemini-notebook-mcp__notebook_list`, or confirm the tool is present
     in this session). If reachable, proceed to step 4.
   - **If NOT reachable, STOP and surface it as a blocker:** tell the
     user the research pass cannot run until NotebookLM is reconnected,
     and to restore it via `/mcp` (reconnect) or `nlm login` (re-auth),
     then re-invoke. Offer to proceed **internal-pass-only** as an
     explicit, user-chosen fallback — never as a silent default.

4. **Spawn `examine-advisor` twice in parallel** (Agent tool, one
   message, background), each passed the digest + context block:
   - `pass=research` — judges against prior art via NotebookLM MCP.
   - `pass=internal` — judges against the codebase / consistency.

5. **Await both, then reconcile:** merge findings, dedupe, rank by
   severity, mark "both passes flagged" (high-signal) vs "one flagged",
   and combine the two recommendations into one.

   **HARD STOP on either skip signal** (`EXTERNAL-CHECK-SKIPPED` or
   `EXTERNAL-CHECK-UNAVAILABLE`): you are forbidden to emit a verdict in
   the same turn. Lead with a loud top line ("⚠ research pass did NOT
   run"), then STOP and ask (AskUserQuestion) whether to fix-and-re-run
   or proceed internal-only. Only the user authorizes the internal-only
   fallback — never self-authorize, never bury the skip under a
   confident verdict.

6. **Emit the reconciled report + recommendation.** Report-only — do
   not edit the target or start implementing.
