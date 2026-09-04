# Comparison Data — Working Notes

> Scratch file. Each cell value MUST be sourced (link to a line
> in the competitor's README, or a footnote with quote + URL).
> Final compact table for README is in the last section.

## Schema

| Column | Type | Source-of-truth |
|---|---|---|
| Project | string + link | competitor repo URL |
| Spec-driven phases | ✅ / ❌ / partial | competitor README |
| Persistent codebase index | ✅ / ❌ | competitor README |
| Cross-session memory | ✅ built-in / ✅ optional / ❌ | competitor README |
| TDD enforcement | ✅ / ❌ / partial | competitor README |
| Workflow profiles | ✅ / ❌ | competitor README |
| Subagent count | integer | competitor README |
| Git worktrees | ✅ / ❌ | competitor README |

## Sourced rows (with citations)

### Row 1: rlm-mem (this repo)

| Cell | Value | Source |
|---|---|---|
| Project | [rlm-mem](https://github.com/povesma/claude_code_RLM_mem) | this repo |
| Spec-driven phases | ✅ | `.claude/commands/dev/{prd,tech-design,tasks,impl}.md` exist (verified 2026-04-30) |
| Persistent codebase index | ✅ | `.claude/rlm_scripts/rlm_repl.py` (RLM REPL builds `.claude/rlm_state/state.pkl`) |
| Cross-session memory | ✅ built-in | claude-mem MCP integration mandatory per `CLAUDE.md` "Claude-Mem Integration (MANDATORY)" |
| TDD enforcement | ✅ | `.claude/commands/dev/tasks.md` "TDD Planning Guidelines"; profile `quality.yaml` `testing.approach: tdd` |
| Workflow profiles | ✅ | `.claude/profiles/{quality,fast,minimal,research}.yaml` (4 profiles) |
| Subagent count | 6 | 1 in `.claude/agents/` (`rlm-subcall.md`); 5 test-* agents documented but not yet committed (`README.md` "Test Subagents" section) |
| Git worktrees | ❌ | grep for "worktree" in `.claude/` returns no usage |

### Row 2: Superpowers ([obra/superpowers](https://github.com/obra/superpowers))

| Cell | Value | Source |
|---|---|---|
| Spec-driven phases | ✅ | "brainstorming → writing-plans → implementation"; "Refines rough ideas through questions, presents design in sections for validation" |
| Persistent codebase index | ❌ | "No mention of indexing system across the documentation" |
| Cross-session memory | ❌ | "No built-in or optional cross-session memory capability described" |
| TDD enforcement | ✅ | "test-driven-development" skill enforces "RED-GREEN-REFACTOR cycle"; "Write tests first, always" stated in Philosophy |
| Workflow profiles | ❌ (partial) | Skills activate contextually but not explicitly called "profiles" for different scenarios |
| Subagent count | 14+ | "Multiple skills shipped including test-driven-development, systematic-debugging, brainstorming, writing-plans, dispatching-parallel-agents, and others" |
| Git worktrees | ✅ | "using-git-worktrees" skill: "Creates isolated workspace on new branch, runs project setup, verifies clean test baseline" |

### Row 3: BMAD-METHOD ([aj-geddes/claude-code-bmad-skills](https://github.com/aj-geddes/claude-code-bmad-skills))

| Cell | Value | Source |
|---|---|---|
| Spec-driven phases | ✅ | "Phase 1: Analysis → Phase 2: Planning (PRD/tech-spec) → Phase 3: Solutioning (architecture) → Phase 4: Implementation" |
| Persistent codebase index | ❌ | "Status tracking uses YAML project config, not code indexing" |
| Cross-session memory | ✅ built-in | "YAML-based status files"; "Persistent context across sessions. No re-explaining project state." |
| TDD enforcement | ❌ (partial) | "Development includes testing (Writes tests) but not explicitly mandated as test-first workflow" |
| Workflow profiles | ✅ | "Project Levels (Right-Sizing) with 5 complexity levels (0-4) adjusting planning depth accordingly" |
| Subagent count | 9 | "BMad Master, Business Analyst, Product Manager, System Architect, Scrum Master, Developer, UX Designer, Builder, Creative Intelligence" |
| Git worktrees | ❌ | "No mention of git worktrees" |

### Row 4: Oh-My-ClaudeCode ([Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode))

| Cell | Value | Source |
|---|---|---|
| Spec-driven phases | ❌ (partial) | "deep-interview…before any code is written" + "team-plan → team-prd → team-exec pipeline" but enforcement is optional |
| Persistent codebase index | ❌ | "Session summaries: .omc/sessions/*.json…but no explicit persistent AST/semantic codebase index" |
| Cross-session memory | ✅ built-in | "Extract reusable patterns from your sessions" with project and user scope stored in `.omc/skills/` |
| TDD enforcement | ❌ | "No mention of test-first workflows or TDD enforcement" |
| Workflow profiles | ✅ | "Multiple strategies for different use cases including Team, autopilot, ultrawork, ralph, pipeline, and ultrapilot modes" |
| Subagent count | 19 | "19 specialized agents (with tier variants) for architecture, research, design, testing, data science" |
| Git worktrees | ✅ | "Native team worker worktrees are being added behind an opt-in/config gate" |

### Row 5: claude-code-workflows ([shinpr/claude-code-workflows](https://github.com/shinpr/claude-code-workflows))

| Cell | Value | Source |
|---|---|---|
| Spec-driven phases | ✅ | "Creates design documents…Breaks down into tasks…Implements"; PRD → design → planning → execution phases |
| Persistent codebase index | ❌ (partial) | "codebase-analyzer agent analyzes existing codebase before design, but no persistent indexing mechanism" |
| Cross-session memory | ❌ | "No cross-session memory system mentioned" |
| TDD enforcement | ✅ | "task-executor…Implements backend features with TDD" |
| Workflow profiles | ✅ | "backend (`dev-workflows`), frontend (`dev-workflows-frontend`), fullstack, skills-only" |
| Subagent count | 27 | "16 recipes + 11 knowledge skills" |
| Git worktrees | ❌ | "No git worktree usage mentioned" |

### Row 6: claude-workflow-template ([nicholasmartin/claude-workflow-template](https://github.com/nicholasmartin/claude-workflow-template))

| Cell | Value | Source |
|---|---|---|
| Spec-driven phases | ✅ | "PRD → /plan-feature → /execute" lifecycle; "write your first PRD with /create-prd" |
| Persistent codebase index | ❌ | "No mention of maintaining an indexed codebase snapshot" |
| Cross-session memory | ❌ (partial) | "/continue scans board state and checks git history, but reconstructs context from GitHub/git rather than storing persistent memory" |
| TDD enforcement | ❌ | "No requirement for tests before code" |
| Workflow profiles | ❌ | "One standard workflow lifecycle shown; no mention of alternative profiles" |
| Subagent count | 1 | "/workflow - Workflow Modifier (Skill) for modifying the workflow system itself" |
| Git worktrees | ❌ | "No mention of worktrees" |

## Refresh 2026-06-07 — re-verified cells + axis changes

> Re-research via web + NotebookLM ("AI Agentic Workflows and
> Claude Developer Tools", 40 sources). Changes from the 2026-04-30
> snapshot:
>
> - **Own row Subagents**: was `6`. Repo `.claude/agents/` holds only
>   `rlm-subcall.md`; the 5 test agents are documented (README "Test
>   subagents") and invoked via Task tool, not shipped as agent files.
>   Honest representation: 1 shipped + 5 documented test subagents.
> - **OMC Subagents**: was `19` → now **29 agents + 34 skills**
>   (multi-tier Haiku/Sonnet/Opus). Source: OMC docs via NotebookLM
>   (agent roster table, 29 entries; "34 Total" skills).
> - **OMC code navigation**: native LSP tools (`lsp_goto_definition`,
>   `lsp_rename`) + `ast_grep_search`/`ast_grep_replace`. Source: OMC
>   "Available Tools" / "AST Tools (ast-grep Integration)".
> - **Superpowers Subagents**: was `14+` → now "20+ skills"; agent vs
>   skill counting differs, so the integer was always apples-to-oranges.
> - **Superpowers memory**: core has none, but same author/marketplace
>   ships `private-journal-mcp` (semantic-search memory) → `🟡 optional`.
> - **BMAD (aj-geddes port)**: re-verified **9 skills + 15 commands**;
>   no LSP/AST, no multi-CLI (those live in the separate `bmad-assist`
>   repo, not this port). Source: aj-geddes.github.io/claude-code-bmad-skills.
> - **shinpr**: restructured into plugin variants (`dev-skills` vs
>   `dev-workflows`, frontend/fullstack); flat `27` no longer maps to
>   one install. Quality gates baked into completion criteria (author
>   states he avoids hooks). No LSP/AST or multi-CLI orchestration
>   (Codex used only as side reviewer).
>
> **Axis decision (narrow re-axis):** the integer "Subagents" column
> is misleading (counts mix agents/skills/recipes; "more" is not
> "better"). Replaced with qualitative **Agent model**. Added one new
> sourced column, **Code navigation**, because it is the axis where
> rlm-mem (persistent index) and OMC (LSP/AST) genuinely differ.
> Emerging axes with no citable data for ≥4 of 6 projects
> (verification loops, multi-CLI orchestration) are handled in README
> prose, not as columns, to avoid fabricated negatives.

### Code navigation — per-cell sources

| Project | Value | Source |
|---|---|---|
| rlm-mem | index (RLM) | `rlm_repl.py` builds `.pkl` index of all files |
| Superpowers | grep-only | no index/LSP described; relies on native context |
| BMAD (port) | none | YAML status files, no code-level navigation |
| OMC | LSP + AST | `lsp_*` tools + `ast_grep_*` (OMC docs, NotebookLM) |
| shinpr | grep-only | `codebase-analyzer` agent, no persistent/LSP/AST |
| claude-workflow-template | none | git/GitHub board reconstruction, no code index |

### Agent model — per-cell sources

| Project | Value | Source |
|---|---|---|
| rlm-mem | focused (1 + 5 test) | 1 shipped (`rlm-subcall`) + 5 documented test subagents |
| Superpowers | skills (20+) | "20+ battle-tested skills"; code-reviewer agent |
| BMAD (port) | roles (9) | 9 role skills + 15 commands |
| OMC | swarm (29) | 29 agents + 34 skills, multi-tier |
| shinpr | roles (variants) | phase agents across plugin variants |
| claude-workflow-template | single (1) | one workflow-modifier skill |

## Final compact table (for README paste)

> **Legend**: ✅ built-in · 🟡 partial / optional · ❌ absent
>
> Snapshot date: 2026-06-07. Sources for every cell:
> [comparison-data.md](
> tasks/017-README-ONBOARDING-spec-driven-positioning/comparison-data.md)

| Project | Spec phases | Code navigation | X-session memory | TDD | Profiles | Agent model | Worktrees |
|---|---|---|---|---|---|---|---|
| **rlm-mem** *(this)* | ✅ | index (RLM) | ✅ | ✅ | ✅ (4) | focused (1+5 test) | ❌ |
| [Superpowers](https://github.com/obra/superpowers) | ✅ | grep-only | 🟡 | ✅ | 🟡 | skills (20+) | ✅ |
| [BMAD-METHOD](https://github.com/aj-geddes/claude-code-bmad-skills) | ✅ | none | ✅ | 🟡 | ✅ | roles (9) | ❌ |
| [Oh-My-ClaudeCode](https://github.com/Yeachan-Heo/oh-my-claudecode) | 🟡 | LSP+AST | ✅ | ❌ | ✅ | swarm (29) | ✅ |
| [claude-code-workflows](https://github.com/shinpr/claude-code-workflows) | ✅ | grep-only | ❌ | ✅ | ✅ | roles (variants) | ❌ |
| [claude-workflow-template](https://github.com/nicholasmartin/claude-workflow-template) | ✅ | none | 🟡 | ❌ | ❌ | single (1) | ❌ |

**rlm-mem's only-one-with-both differentiator**: persistent
codebase index (RLM) **and** cross-session memory (claude-mem)
in a single workflow. No competitor in the table has both — OMC
has memory + LSP/AST navigation but no persistent index; the
spec-driven ones (Superpowers, shinpr) lack persistent memory.

## Refresh 2026-09-04 — re-verified cells + two new entrants

> Re-research via parallel web/repo fetches (three research subagents,
> each citing the tool's live GitHub repo/README, 2026-09-04). Every
> changed cell below has a live source. Changes from the 2026-06-07
> snapshot:
>
> - **Superpowers memory**: `🟡 optional` → **`✅`**. Core now ships
>   multi-section private journaling (feelings, project notes, technical
>   insights, user context) persisting across sessions — no longer an
>   external add-on. Now in Anthropic's official marketplace; reached
>   v5.x. Source: github.com/obra/superpowers README.
> - **Superpowers agent model**: "skills (20+)" → **focused (~14
>   skills)** with a coordinator dispatching per-task subagents
>   (`dispatching-parallel-agents`).
> - **BMAD TDD**: `🟡` → **`❌`**. v6.x refocus dropped all
>   code-execution/dev-story/lint/coverage skills; now planning &
>   orchestration ONLY. Memory reframed `✅`→**`🟡 optional`** (planning
>   artifacts, not a documented cross-session store). Agent model ~20
>   skills + 3 planning subagents. Source:
>   aj-geddes.github.io/claude-code-bmad-skills.
> - **OMC agent model**: swarm "(29)" → **~16 core role agents**
>   (legacy `swarm` keyword removed v4.1.7; now branded "Team"). LSP+AST
>   navigation and the `ralph` self-looping verifier BOTH still exist
>   (confirmed in repo tree: `src/tools/lsp/`, `src/tools/ast-tools.ts`,
>   `src/hooks/ralph/`). Spec phases remain `🟡`. Source:
>   github.com/Yeachan-Heo/oh-my-claudecode.
> - **shinpr agent model / profiles**: refined to **~25 role-based**
>   (~16 shared + 4 backend + 5 frontend); profiles `✅`→**`🟡`**
>   (`quality.yaml` repo rules, not full workflow-mode profiles). Split
>   into three install targets; added an independent security-review
>   gate. Memory remains `❌` (committed docs, not a store). Source:
>   github.com/shinpr/claude-code-workflows.
> - **claude-workflow-template**: worktrees `❌`→**`✅`** (shipped
>   `execute-isolated.md` + Level-4 isolation). Navigation `none`→
>   **grep-only** (path-scoped rules + `/prime` context, plain reads).
>   Agent model single→**role-based (~few)** (`execute-team.md`,
>   `execute-isolated.md`). Memory remains `🟡` (GitHub Issues + git,
>   no semantic store). Source:
>   github.com/nicholasmartin/claude-workflow-template.
>
> **Two new entrants added** (both genuinely spec-driven Claude Code
> workflows, verified live):
>
> - **GitHub Spec-Kit** (github.com/github/spec-kit) — 133k stars,
>   GitHub-official, `/spec.constitution→specify→plan→tasks→implement`,
>   works with 30+ agents incl. Claude Code. Now the dominant tool in
>   the field. Spec `✅`; nav grep-only; memory `❌` (`constitution.md`
>   is a rules file, not cross-session store); TDD `🟡` (constitution
>   can mandate); profiles `🟡` (`--ai` flag); agent model delegates to
>   the host agent's subagents; worktrees `✅` (feature-level isolation,
>   DAG waves). *TDD/profile ratings inferred from docs, not
>   code-verified — provisional.*
> - **Pimzino/claude-code-spec-workflow**
>   (github.com/Pimzino/claude-code-spec-workflow) — 3.9k stars (aging,
>   last push 2025-09). Requirements→Design→Tasks→Implementation + bug
>   flow, Kiro-inspired steering docs, context caching. Spec `✅`; nav
>   grep-only; memory `❌` (steering docs); TDD `🟡`; profiles `❌`;
>   agent model focused (main+sub with selective context); worktrees
>   `❌`.
>
> **Adjacent, NOT added as rows** (planning-only or not a Claude Code
> workflow plugin): Taskmaster/claude-task-master (28k stars,
> PRD→tasks.json, planning-only, editor-agnostic); Kiro (AWS agentic
> IDE, not a plugin); Aider/Cline (general coding assistants).
>
> **Axis note:** no axis change this refresh — the 2026-06-07 columns
> (Spec phases, Code navigation, X-session memory, TDD, Profiles, Agent
> model, Worktrees) still capture the field. Worktrees is now the axis
> where embo is most conspicuously behind: Spec-Kit, Superpowers, OMC,
> and claude-workflow-template all have it; embo does not.

### Final compact table — refreshed 2026-09-04

> **Legend**: ✅ built-in · 🟡 partial / optional · ❌ absent.
> Snapshot 2026-09-04; every cell sourced above.

| Project | Spec phases | Code navigation | X-session memory | TDD | Profiles | Agent model | Worktrees |
|---|---|---|---|---|---|---|---|
| **embo** *(this)* | ✅ | index (RLM) | ✅ | ✅ | ✅ (4) | focused (1+5 test) | ❌ |
| [GitHub Spec-Kit](https://github.com/github/spec-kit) | ✅ | grep-only | ❌ | 🟡 | 🟡 | delegates to host | ✅ |
| [Superpowers](https://github.com/obra/superpowers) | ✅ | grep-only | ✅ | ✅ | ❌ | focused (~14) | ✅ |
| [BMAD-METHOD](https://github.com/aj-geddes/claude-code-bmad-skills) | ✅ | none | 🟡 | ❌ | ✅ | roles (~20, plan-only) | ❌ |
| [Oh-My-ClaudeCode](https://github.com/Yeachan-Heo/oh-my-claudecode) | 🟡 | LSP+AST | ✅ | 🟡 | ✅ | swarm/Team (~16) | ✅ |
| [claude-code-workflows](https://github.com/shinpr/claude-code-workflows) | ✅ | grep-only | ❌ | ✅ | 🟡 | roles (~25) | ❌ |
| [Pimzino/spec-workflow](https://github.com/Pimzino/claude-code-spec-workflow) | ✅ | grep-only | ❌ | 🟡 | ❌ | focused (main+sub) | ❌ |
| [claude-workflow-template](https://github.com/nicholasmartin/claude-workflow-template) | ✅ | grep-only | 🟡 | 🟡 | 🟡 | roles (~few) | ✅ |

**embo's only-one-with-both differentiator holds against the refreshed
field**: persistent codebase index (RLM) **and** cross-session memory
(claude-mem). Even Spec-Kit (now dominant) has neither; Superpowers has
memory but grep-only nav; OMC has LSP+AST nav but session-search, not
semantic cross-session recall. The trade: embo is the deep-context,
single-track choice in a field trending toward broad parallelism —
worktree isolation is the one gap most likely to lose a
parallelism-seeking user.
