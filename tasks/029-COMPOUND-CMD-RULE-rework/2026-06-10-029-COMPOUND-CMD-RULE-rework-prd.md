# 029: Compound-Command Rule Rework + Compound Capture — PRD

**Status**: Draft · **Created**: 2026-06-10
**Task ID**: 029-COMPOUND-CMD-RULE-rework

---

## Context

Three goals conflict when running Bash commands:

1. **Zero permission prompts** — prompts interrupt and slow development.
2. **Full output + true exit code** — the model must reach both.
3. **Minimum call count** — one-command-per-call multiplies round trips
   and per-output LLM processing.

The old mitigation for (1) — the global-CLAUDE.md rule "one allow-listed
command per Bash call, no `;`/`&&`, no redirects" — predates the 027/028
hooks and now hurts (3) without being needed for (1).

### Current State (observed 2026-06-10)

| Fact | Source |
|------|--------|
| Compounds are already auto-approved: hook splits on `&&` `\|\|` `;` `\|`, normalizes each segment, allows iff all match allow-rules, deny wins | `approve-compound.sh:160-191` |
| Hook falls through to the prompt on `$(...)`, backticks, `<(...)`, heredocs | `approve-compound.sh:12-18` |
| `should_wrap` refuses compounds → chained/piped output gets **no capture** and can flood inline | `approve-compound.sh:227-247` |
| Wrapper runs payload via `bash -c`, tees full output, passes exit code through — already compound-capable | `embo-capture.sh:39-55` |
| Shipped REDIRECT-CMD-OUTPUT rule still says "run one plain command, once" | `start.md` RULE:REDIRECT-CMD-OUTPUT |
| `~/.claude/CLAUDE.md` holds the stale rule plus other ad hoc rules | user confirmation, this session |
| Hook + wrapper allow-rule installed in user env | claude-mem #18450, 2026-06-09 |

**Lineage**: 027 solved prompts for compounds (#18163, #18326); 028
solved capture for simple commands (#18420, #18437). 029 aligns the
prose with the hooks and closes the compound-capture gap.

## Problem Statement

Prose rules still mandate one-command-per-call, so agents either split
work into many slow Bash calls or violate the rule and hit prompts.
Compounds that do run are exempt from capture and flood the context.
Both costs are avoidable with the hooks already installed.

## Goal

One consistent policy across hooks and prose: compounds of allowlisted
segments run with zero prompts, get full-output capture with the true
exit code, and the rules the model reads say exactly that.

Secondary: shrink `~/.claude/CLAUDE.md` to genuinely personal rules;
ship reusable ones in `dev:start`. Keep exit-code-integrity discipline.

## User Stories

1. **Chain without prompts** — As a developer, I chain commands with
   `&&`/`|` in one Bash call, in fewer round trips, prompt-free.
   - [ ] start.md rule permits compounds of allowlisted segments;
     one-command-per-call mandate removed
   - [ ] Rule keeps: no `$(...)`/backticks/heredocs (hook bails),
     no masking a checked command's exit code behind a filter
   - [ ] Live test: allowlisted compound runs with 0 prompts

2. **Compound output captured** — As a developer, a large compound
   output gives me preview + marker + true exit code, not a flood.
   - [ ] Chains (`&&` `||` `;`) and pipelines (`|`) are wrapped; full
     combined output in the per-call log
   - [ ] Marker exit code = what bash reports for that compound
     (no semantics change, no `pipefail` injection)
   - [ ] Opt-outs preserved: interactive head, explicit redirect,
     unsafe construct, re-entrancy
   - [ ] Both `.test.sh` suites extended and passing

3. **Global CLAUDE.md triage** — As the file's owner, I get a per-rule
   verdict table (keep / move-to-dev:start / remove, one-line reason).
   - [ ] Table covers every rule; user approves before any edit
   - [ ] Approved edits applied to `~/.claude/CLAUDE.md` and
     `start.md` in this task (decision 2026-06-10: propose + apply)

4. **Install docs** — As an end user, I can set up the hook pair and
   allow-rule, manually if needed.
   - [ ] Docs cover hook registration, wrapper allow-rule, and what
     is / is not auto-approved; manual steps alongside scripted ones
   - [ ] Docs state the *user's own* allowlist decides what runs
     prompt-free; embo ships no allowlist beyond the wrapper rule

## Requirements

| # | Requirement | Priority |
|---|------------|----------|
| FR-1 | Rewrite shipped compound-command guidance (REDIRECT-CMD-OUTPUT + any one-command-per-call language) to match hook behavior | High |
| FR-2 | Remove the compound exclusion from `should_wrap`; keep all other opt-outs, checked per-segment where applicable | High |
| FR-3 | Triage `~/.claude/CLAUDE.md` rules; approval gate; apply | Medium |
| FR-5 | Strip leading `env` wrapper (flags + assignments) in allowlist normalization, so `env VAR=x cmd` matches `cmd`'s rule (live case 2026-06-10) | High |
| FR-6 | Add allow-listable-invocation design rule to dev:impl: generated scripts/launchers take parameters via flags, config file, or self-loaded env file — never required prepended assignments/`env`. Defense in depth if the hook is absent or broken | Medium |
| FR-4 | Install docs for hook pair + allow-rule, with manual steps | Medium |

**NFRs**: never auto-approve a command with an unmatched segment;
deny-wins ordering unchanged; fail open to the prompt, never to silent
approval. Wrapped exit codes equal unwrapped execution. Every change
lands with test cases; live verification scenario per 028's template.

**Constraints**: pure Bash + jq, stateless, fail-open (hook
convention). `~/.claude/CLAUDE.md` is personal — edits applied
in-place, recorded in the task file, not committed here. Shipped rules
live in `.claude/commands/dev/`.

## Follow-ups (recorded, not in 029)

- **030 candidate — hook-health statusline indicator**: hook touches a
  heartbeat file per invocation; statusline segment shows capture
  health (registration + wrapper presence + heartbeat freshness).
  Rationale: the hook pair is becoming core infrastructure; breakage
  must be visible, not discovered via missing markers. (User request
  2026-06-10; lineage: tasks 008, 020.)

## Out of Scope

- Shipping or growing user allowlists — the end user decides what runs
  without prompting
- LLM-judge enforcement of the rules (task 026)
- Changing shell semantics inside the wrapper (e.g. `pipefail`)
- Auto-approving `$(...)`/backtick/heredoc commands — unparseable,
  keep falling through to the prompt

## Success Metrics

1. Allowlisted compound → 0 prompts (live test)
2. Compound with >10-line output → marker with correct counts and the
   bash-reported exit code, including a failing-segment case (live test)
3. No one-command-per-call language left in shipped rules or the
   post-triage global CLAUDE.md
4. Every global-CLAUDE.md rule has a recorded verdict; file afterwards
   contains only "keep" rules

## References

**Code**: `approve-compound.sh` (exclusion to remove: 241-243),
`embo-capture.sh`, both `.test.sh` suites, `start.md`
(RULE:REDIRECT-CMD-OUTPUT), README/install docs.
**Memory**: #18420, #18437, #18450 (028); #18163, #18326 (027).

---

**Next**: review → `/dev:tech-design` → `/dev:tasks`
