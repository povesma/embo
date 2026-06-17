---
description: >
  Manually-invoked check that a chosen approach will satisfy its
  acceptance criteria before implementation, by proving each
  load-bearing claim against an independent source rather than the
  agent's own confidence. Invoke with /dev:research:verify. The agent
  proactively suggests it (per the RESEARCH-VERIFY rule) for any
  non-trivial task; it does not auto-run.
---

# Verify a Chosen Approach Against Its Acceptance Criteria

Prove a chosen approach will reach the expected result and satisfy each
acceptance criterion **before** implementation — rather than trusting
the authoring agent's confidence. This command is a thin spawner: it
gathers the input and hands off to the `approach-validator` agent, which
does the work in its own clean context and returns a verdict.

## When to Use

- A chosen spec is **risky, complex, or hard to reverse**, or confidence
  is below average.
- NOT for trivial, easily-reverted changes — that is waste.
- For mere doubt about a tool/API, just check **Context7 MCP** directly.
  For cross-checking a whole document or weighing options, use
  `dev:research:examine` instead.

## Process

1. **Gather input:** the chosen approach (a spec/tech-design **path** or
   **inline** text) and its acceptance criteria. If no criteria can be
   found or inferred, ask the user — verification needs something to
   prove against.
2. **Spawn the `approach-validator` agent** (Agent tool) with the
   approach + criteria. It runs the verification discipline in its own
   context: proves each claim against an independent source (Context7,
   the live system, the real artifacts, NotebookLM for prior art),
   exercises un-proven paths once, and stays report-only.
3. **Relay its verdict** to the user unchanged — the per-criterion
   table (proven / unproven / contradicted), the claim list, the
   constructive advice (alternatives if unconfirmed, evidence if
   proven), and the bottom line. Do **not** edit the target or start
   implementing.

The discipline's full narrative reference (for humans) is
`docs/VERIFICATION-DISCIPLINE.md`; the operational form lives in the
`approach-validator` agent, so this command does not restate it.
