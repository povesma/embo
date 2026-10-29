---
description: >
  Generate a technical design from an approved PRD, verifying inherited
  facts against the codebase (RLM) and past decisions (claude-mem).
  Produces components, contracts, trade-offs, and a verification table.
---

# Generate Technical Design with embo Hybrid Analysis

Create a technical design informed by past architectural decisions
(claude-mem) and current code patterns (RLM). Run it after the PRD is
approved and before breaking down into tasks.

## Process

### Step 0: Load Profile

Use the profile already loaded this session (from `/embo:start`). If
it is not in context, run `embo-profile show`. Skip RLM discovery
(Step 2-3) if `tools.rlm` is `false`. (claude-mem is always on.)

### Step 1: Load Context

**Read PRD**:
- From file: `tasks/{jira-id}-{feature}/...-prd.md`
- Or search claude-mem for recent PRD

**Search past tech designs** (claude-mem):
```
mcp__plugin_claude-mem_mcp-search__search(
  query="{feature_keywords} architecture design patterns technical",
  type="TECH-DESIGN",
  limit=5
)
```

### Step 1.5: Verify Inherited PRD Facts

Treat every factual claim in the PRD's "Current State (observed)"
section and any concrete identifier that leaked into Requirements
(config keys, column names, routes, counts, version numbers) as an
**input to verify**, not a truth to build on.

For each claim:
- If it carries `— verified via: ...`, re-run the named source
  (read the file, run the command, query RLM) and confirm it still
  holds. Stale verification is worse than none.
- If it carries `[assumption, verify in tech-design]`, resolve it
  now via RLM / file read / command — or flag it as a blocker.
- If a concrete identifier appears in the PRD, independently
  confirm it against code before reusing it. Do not copy
  identifiers verbatim without a code-level check.

Record each resolved claim in the tech-design's "Current
Architecture (RLM-verified)" section with its own source citation
(file:line, command, date). A PRD fact that fails verification
invalidates the dependent requirement — stop and loop back to
`/embo:prd` rather than designing against a false premise.

### Step 2: RLM Architecture Discovery

Write the probe to `tmp/rlm-probe.py`, then run
`rlm_repl exec -c "$(cat tmp/rlm-probe.py)"`. The `-c` flag is required;
heredocs are not supported.

```python
# tmp/rlm-probe.py — find architecture-relevant files
arch_files = []
patterns = ['handler', 'service', 'controller', 'manager', 'repository', 'model']
for pattern in patterns:
    matches = [
        path for path, meta in repo_index['files'].items()
        if pattern in path.lower() and not meta['is_binary']
    ]
    arch_files.extend(matches[:5])
print('\n'.join(set(arch_files)[:30]))
```

**Analyze patterns with rlm-subcall**:
- Query: "Extract architectural patterns: layering, dependency injection, error handling, data flow, module structure"
- Files: Top 10 most representative architecture files
- Collect: Design patterns, conventions, anti-patterns

### Step 3: Identify Integration Points

From the PRD requirements and the Step 2 findings, list where new code
connects: files that will be modified, files that will be created, and
external dependencies that will be used. Use the same probe form as
Step 2 when the answer needs a codebase query.

### Step 4: Learn from History

**Query past decisions** (claude-mem):
```
mcp__plugin_claude-mem_mcp-search__search(
  query="why we chose {relevant_tech} architecture decision trade-offs",
  limit=5
)
```

Extract:
- Past architectural decisions and rationale
- Trade-offs made and lessons learned
- Patterns that worked well
- Patterns that caused problems

### Step 5: Ask Technical Clarifying Questions (MANDATORY)

**🚨 BEFORE writing the technical design, you MUST ask clarifying
questions using the AskUserQuestion tool.** Adapt to the feature; common
areas: architecture pattern, technology stack, integration points, data
storage, performance constraints, external dependencies, error handling,
state management.

**Architecture trade-offs** (informed by the Step 2–3 RLM findings):
which of the patterns found should this follow; extend an existing
component or build new; reuse or diverge from a past design.

Always include an **"All clear, proceed"** option; if selected, skip to
Step 6. Incorporate the answers into the design — do NOT leave answered
questions in an "Open Questions" section.

### Step 5b: Content Quality Rules

Every section must answer: "what would a developer not know without
this?" If a section reads like a user manual, remove it or move it.

**DO include:** component boundaries and responsibilities; data
contracts between components; communication patterns; reliability and
failure handling; performance feasibility estimates; rejected
alternatives with reasons.

**DO NOT include:** setup guides, workflow steps, CLI usage, sample
output, installation instructions, user-facing documentation (all →
README); algorithm parameter values and thresholds (→ code).

### Step 6: Synthesize Technical Design

Create design document:

```markdown
# {JIRA-ID}: {Feature Name} - Technical Design

**Status**: Draft
**PRD**: [{JIRA-ID}-prd.md](link)
**Created**: {date}

## Overview

{High-level technical approach}

## Current Architecture (RLM Analysis)

Discovered patterns, and the relevant components with their file
locations — each with its source citation (file:line, command, date).

## Past Decisions (Claude-Mem)

Relevant historical decisions and why each matters for this feature.

## Proposed Design

### Architecture

{Detailed design following discovered patterns, stated per layer:
UI, application, domain, infrastructure.}

### Components

**New Components** — for each: purpose, location, the existing pattern
it follows, and its dependencies.

**Modified Components** — for each (with `file:line`): the changes, the
rationale, and the risk.

### Data Models

{New or modified data structures}

### API Design

{New endpoints, methods, or interfaces}

### Integration Points

What this connects to, and via which interface (from RLM analysis).

### Error Handling

{Following discovered patterns from codebase}

### Testing Strategy

{Based on existing test patterns}

### Verification Approach

Maps each functional requirement to its verification method and
expected evidence. This section is the primary input to `/embo:test-plan`.

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1: {description} | `auto-test` | unit | pytest: N passed |
| FR-2: {description} | `manual-run-claude` | integration | output shows X |
| FR-3: {description} | `code-only` | — | — |

Methods: `code-only` \| `auto-test` \| `manual-run-claude` \|
`manual-run-user` \| `docker` \| `e2e` \| `observation`
(canonical definitions in `/embo:test-plan`)

## Trade-offs

Each considered approach with its pros, cons, and historical context
from claude-mem. Mark the recommended one and state why.

## Implementation Constraints

Constraints from the existing architecture (RLM) and lessons from past
experience (claude-mem).

## Files to Create/Modify

**Create**: path and purpose. **Modify**: `path:line` and the changes.

## Dependencies

**External**: library, version, why. **Internal**: module and how it is
used.

## Security Considerations

{Security requirements and mitigations}

## Performance Considerations

{Performance requirements and optimizations}

## Rollback Plan

{How to revert if issues arise}

## References

Code (RLM): the files and the pattern or example each provides.
History (claude-mem): past designs and what to learn from them.

---

**Next Steps**:
1. Review and approve design
2. Run `/embo:tasks` for task breakdown
```

### Step 6.5: Sanitization Pass (MANDATORY)

Apply the same sanitization rule as `/embo:prd` Step 5.6: scan for private data, defer to CLAUDE.md "Documentation Sanitization" if defined,
otherwise mask with `<descriptor>` placeholders or RFC 5737/2606 examples. Drafts may carry private values; sanitize before
`Status: Complete`. Orthogonal to Step 1.5 (which verifies inherited PRD facts are true): 6.5 verifies they are shareable.

### Step 7: Save to File

```
tasks/{jira-id}-{feature}/{date}-{jira-id}-{feature}-tech-design.md
```

After writing, **Read the file back** — the PostToolUse hook captures it
as a claude-mem observation automatically. No explicit save call needed.

## Context7

When referencing any library, framework, or external API — use the Context7 MCP to look up current documentation rather than guessing. Call `mcp__context7__resolve-library-id` then `mcp__context7__get-library-docs`. Never invent API signatures or assume version-specific behaviour.

## Final Instructions

- Step 5 (technical clarifying questions via AskUserQuestion) is
  **mandatory**.
- Before approval, apply RULE:DELEGATE trigger 2: offer a clean-context
  `examine-advisor` critique of the design (marker `[delegate:trigger-2]`).
- Suggest `/embo:tasks` as the next step.
