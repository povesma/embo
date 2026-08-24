# 052-START-SLIM: Slim /embo:start Command - Technical Design

**Status**: Draft
**PRD**: [2026-08-19-052-start-slim-prd.md](2026-08-19-052-start-slim-prd.md)
**Created**: 2026-08-21

## Overview

A prompt-text edit to one shipped file: rewrite the non-rules region of
`plugin/commands/start.md` (pre-change lines 1-45 and 601-874) while
leaving the rules region (lines 46-600) byte-identical. The rewrite
also restructures Steps 1-3 as two explicit parallel batches (FR-9,
scope amendment 2026-08-22): a Turn-1 batch of five independent
discovery calls and a Turn-2 batch of two profile-dependent calls,
so `/embo:start` completes in ≤ 3 assistant turns instead of ~7.
Ships with a patch version bump and a CHANGELOG entry. No code, no
hook changes.

## Current Architecture (RLM-verified)

All claims re-verified against the working tree during design
(2026-08-19 initial, 2026-08-21 re-check; `plugin/` unchanged between
the two — the only intervening merge touched `tasks/` files only):

- `plugin/commands/start.md` = 874 lines — `wc -l`, 2026-08-21.
- Rules region: line 46 (`## Session Behavioral Rules`) through line
  600 (last `<!-- /CHECKLIST -->`; closers at 121, 186, 248, 416, 600)
  = 555 lines; non-rules remainder = 319 lines — `grep -n`, 2026-08-19.
- Hook extraction contract: `plugin/hooks/behavioral-reminder.sh:114`
  awk collects from each line matching `^\[.*checklist` through the
  next `<!-- /CHECKLIST -->`; RULE bodies and the `<!-- CHECKLIST:` 
  comment openers are not read — grep of the awk pattern, 2026-08-19.
- The hook has a test suite: `plugin/hooks/behavioral-reminder.test.sh`
  — exists in tree (claude-mem obs #35693 records its last update).
- Cross-file dependencies: `plugin/commands/impl.md:33-34` references
  the `§Session Behavioral Rules` heading (wrapped across two lines) —
  `grep -n`, 2026-08-19. `install.sh:319-321` mentions the frontmatter
  `allowed-tools` only in a comment — and a stale one (it cites a
  `cat ~/.claude/active-profile.yaml` shape the frontmatter no longer
  carries); there is no functional dependency — Read, 2026-08-21.
- Non-rules region composition (advisor-measured anchors, pre-change):
  frontmatter+intro+Step 0 at 1-45; Steps 1-3, the output template
  (~685-758), "Context Quality Levels", "Important Notes", "Example
  Output" (~804-842), Context7, Docs-First, "Final Instructions" at
  601-874.

## Past Decisions (Claude-Mem)

- Task 047: session rules and their checklists deliberately live in
  `start.md`, extracted by the hook at runtime — the reason FR-8 locks
  that region instead of moving it.
- Task 044 (obs #34725): the delegation checklist was added through the
  same injection mechanism — confirms the extraction contract is the
  only structural dependency the hook has on this file.
- This session (feature 048 closure): headless `claude -p` runs are a
  proven `manual-run-claude` method for verifying shipped command
  behavior — reused here for the live-run metric.

## Proposed Design

### Target layout of the slimmed file

Sections in order; the rules region is untouched, everything else is
rewritten or deleted:

1. **Frontmatter** — unchanged except `allowed-tools` gains
   `Bash(git remote get-url *)` (needed by the deterministic rename
   retry, keeping FR-3's zero-prompt guarantee).
2. **Intro + Step 0 (profile)** — `embo-profile show` stays the single
   per-session profile load; the vague "parse the YAML" is replaced by
   naming `embo-profile get <key>` for any later single-value read.
   Read-depth rule keeps its current semantics (fast/minimal → brief).
3. **Session Behavioral Rules (lines 46-600)** — byte-identical.
4. **Step 1 (parallel discovery, one turn)** — replaces the previous
   Steps 1, 2, and 3 as separate sequential steps with a single
   explicit-batch step (FR-9). The command body directs Claude to
   issue these five calls **in one assistant turn**:
   - `embo-profile show` (Step 0's profile load)
   - `rlm_repl status` (previous Step 1; skip if profile
     `tools.rlm` = false)
   - `git log --oneline -10` (previous Step 3 git)
   - `git diff --stat HEAD` (previous Step 3 git)
   - Read `README.md` at the repo root (previous Step 3 docs).
     If the file does not exist, a Read failure IS the "skip" —
     do NOT shell out to `test -f` or any other existence probe;
     the compound `test -f && echo` shape was observed in the
     smoke test and is exactly what this rule forbids.
   Missing-index handling and CLAUDE.md exclusion are preserved
   from the prior version.
5. **Step 2 (profile-dependent batch, one turn)** — after Step 1's
   results are known, the command body directs Claude to issue
   these two calls **in one assistant turn**:
   - Memory overview `search(query="project overview goals
     architecture", project=<profile-name>, limit=5)`.
   - Session-scout Task with the repo root and resolved depth
     (skip in brief mode; scout returns names + counts only).
   The deterministic rename fallback attaches to the memory
   overview: on **exactly 0 rows**, one retry with the repo name
   from `git remote get-url origin` (basename, `.git` suffix
   stripped) as the `project`. **Failure path**: if the command
   exits non-zero or prints nothing (no remote, no `origin`), skip
   the retry and report the overview as empty — never guess a
   prior name. The retry is a conditional third turn; it does not
   count against the ≤ 3-turn success metric.
7. **Step 3 (output spec — the summary, one turn)** — the mock
   template is replaced by a compact table: `Section | Content
   (one line) | Source step`. Sections: Overview · Repository
   stats · Active tasks · Recent activity · Recommended next
   task · System status. Every row's Source names the step that
   produces it (numbering shifts to Step 1/Step 2 references
   under the FR-9 layout). Headings plain text; status
   indicators permitted only in the System status row. This is
   the "summary turn"; it does not count against the ≤ 3-turn
   metric except as the third turn itself.
8. **Closing guidance (single section)** — merges the content worth
   keeping from "Context Quality Levels", "Important Notes", and
   "Final Instructions": degradation lines (RLM missing → suggest
   init; memory empty → report empty), "do not implement anything
   yet" stated exactly once. The "<30s" directive is deleted.
9. **Context7** and **Docs-First Principle** — kept as-is (unique
   content, not part of the overlap).
10. **Deleted outright**: the full mock template, "Example Output",
    "Context Quality Levels", "Important Notes", "Final Instructions"
    (as separate sections), the "<30s" line, emoji in headings, and
    the pre-rules "When to Use" / "What This Command Does" sections
    (13 lines, redundant with the frontmatter `description` and
    Step 0).

### Data contracts (what must not drift)

| Contract | Consumer | Invariant |
|---|---|---|
| Checklist text: opener `[<RULE> checklist]` line and body through the line before `<!-- /CHECKLIST -->` (the closer terminates but is not itself extracted) | `behavioral-reminder.sh:114` awk | byte-identical |
| `## Session Behavioral Rules` heading string | `impl.md:33-34` prose reference | unchanged |
| Frontmatter `allowed-tools` list | Claude Code permission gate (`install.sh:319-321` mentions it only in a stale comment — no functional dependency) | covers every command shape the body names (adds `git remote get-url *`) |
| Editor guard | hook extraction pattern | no new/edited line outside the CHECKLIST blocks starts with `[` and contains `checklist` |

### Error handling

Degradation only (step 8 above): each missing dependency produces one
report line and the summary continues. No new failure modes are
introduced — the command remains read-only.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1 single output spec | `code-only` | — | — |
| FR-2 slots name their source | `code-only` | — | — |
| FR-3 pre-approved shapes only | `code-only` + `manual-run-claude` | file + live run | body names only frontmatter-covered shapes; run transcript shows no denied/blocked tool call |
| FR-4 docs discovery reduced | `code-only` | — | — |
| FR-5 deterministic fallback | `code-only` | — | 0-results trigger + `git remote get-url origin` source stated |
| FR-6 guidance merged | `code-only` | — | "do not implement" appears once (grep count) |
| FR-7 emoji policy | `code-only` | — | no emoji in headings (grep) |
| FR-8 rules region locked | `auto-test` + `manual-run-claude` | hook + file | auto-test: `behavioral-reminder.test.sh` passes and extraction output diff = 0; manual-run-claude: rules-region byte diff = 0 (a run `git diff` over the region — not automated by the test suite) |
| FR-9 turn count ≤ 3 | `manual-run-claude` | live run | headless `claude -p "/embo:start"` transcript shows ≤ 3 assistant turns containing tool calls (excluding the final summary turn and any conditional rename-retry turn); no `test -f` or other Bash existence-probe call for README |
| NFR-1 size ≥35% | `manual-run-claude` | file | `wc -l` arithmetic on the non-rules region |
| NFR-3 behavior preserved | `manual-run-claude` | live run | headless `claude -p "/embo:start"` with `--allowedTools` set to the frontmatter list: all sections filled, no invented commands |

Live-run caveat: headless mode cannot render approval dialogs; the
zero-prompt claim is approximated by granting exactly the frontmatter
shapes and asserting no tool call falls outside them. A final
interactive smoke test by the user (`manual-run-user`) confirms the
dialog-free experience before release.

## Trade-offs

1. **Relocate rules to a dedicated file** (rejected — user scope
   decision): larger context saving for non-start turns is not needed
   (the hook injects checklists regardless); repointing the hook means
   touching tested infrastructure for no functional gain.
2. **In-place rewrite of the non-rules region** (chosen): smallest
   blast radius; every consumer contract holds by construction.
3. **Delete the rename fallback** (rejected — user decision): renames
   are rare but the retry is cheap once deterministic; cost is one
   narrow allowlist entry.
4. **Full template kept, example deleted** (rejected — user chose the
   compact spec): would keep ~70 lines of mock document that restate
   what the section table says in ~15.

## Implementation Constraints

- Rules region byte-identical (verified by diff, not by intention).
- Editor guard on the `^\[.*checklist` pattern (see contracts table).
- No `tasks/` paths or task numbers in the shipped file (repo rule:
  no internal task references in user-facing files).
- Plain English throughout; no emoji in headings.
- The rewrite must not reintroduce any instruction that requires a
  non-frontmatter command shape.

## Files to Create/Modify

**Modify**:
- `plugin/commands/start.md` — the rewrite (sole functional change)
- `plugin/.claude-plugin/plugin.json` — patch version bump (release
  vehicle; current value read at implementation time)
- `CHANGELOG.md` — entry describing the released behavior (leaner
  session start, no approval prompts during startup)

**Create**:
- `plugin/bin/embo-tokens` — token-count measurement tool (stdlib
  Python, executable). Added mid-task after the user noted that
  lines are a poor proxy for context cost; used to report accurate
  metrics for this task and required by the seeded follow-ups
  (053/054/055) to measure their own before/after.

## Dependencies

**External**: none.
**Internal**: `embo-profile` (`show`/`get`), `rlm_repl`, session-scout
agent, the two exact git commands, `git remote get-url origin` — all
already shipped; only the last needs the frontmatter addition.

## Security Considerations

None — prompt text only; no new tool grants beyond the narrow
read-only `git remote get-url *`.

## Performance Considerations

NFR-1: non-rules region 319 → ≤207 lines (≥35% cut; stretch ≤191,
40%). An independent section-by-section estimate of the target layout
puts the rewritten non-rules region at ~163 lines — comfortably under
both thresholds. Per-session context saving is the deleted-line count
on every `/embo:start` invocation.

## Rollback Plan

`git revert` of the delivery commit restores the previous file
verbatim; the command is stateless. Users on the previous plugin
version are unaffected until they update.

## References

### Code:
- `plugin/commands/start.md:46,600` — rules-region boundaries
- `plugin/hooks/behavioral-reminder.sh:114` — extraction awk
- `plugin/hooks/behavioral-reminder.test.sh` — contract test suite
- `plugin/commands/impl.md:33-34` — heading cross-reference
- `install.sh:319` — frontmatter reference

### History:
- Task 047 — rules-in-start.md placement rationale
- Task 044 (obs #34725) — checklist injection precedent
- Feature 048 closure — headless live-run verification method

---

**Next Steps**:
1. Review and approve design
2. Run `/embo:tasks` for task breakdown
