# 014: Git Commit & PR Texts — PRD

**Status**: Draft
**Created**: 2026-03-29
**TaskID**: 014-git-commit-pr-texts
**Author**: Claude (via dev workflow analysis)

---

## Context

Git commit messages and PR descriptions are the primary communication
channel between a developer and their team (and future self). Low-quality
messages ("fix stuff", "WIP") destroy institutional knowledge. High-quality
messages explain *why* the change was made, not just *what* changed.

This feature introduces a `/dev:git` command that generates commit messages
and PR descriptions following a configurable style. It integrates into the
existing workflow profile system so teams can standardise their style without
per-project configuration overhead.

### Current State (from codebase analysis)

- No git-related command exists in `.claude/commands/dev/`
- Workflow profiles (`quality.yaml`, `fast.yaml`, `minimal.yaml`,
  `research.yaml`) currently cover code style, testing, and workflow
  rules — but have no `git` section
- The `rlm:git:commit` command exists in the legacy `rlm` skill tree
  but is not part of the `dev:*` workflow

### Gaps

- No `/dev:git` command
- Profiles have no `git.commit_style` or `git.pr_template` fields
- No PR description generation in any current command

---

## Problem Statement

**Who**: Developers using the RLM-Mem workflow across projects

**What**: No standardised, context-aware way to write commit messages or PR
descriptions — each commit is hand-written, inconsistent, and often omits
motivation and context

**Why**: Poor commit messages make code review harder, git blame useless,
and changelogs meaningless

**When**: Every time code is committed or a PR is opened

---

## Goals

### Primary Goal

Introduce a `/dev:git` command that generates high-quality, context-aware
commit messages and PR descriptions, following a configurable style defined
in the workflow profile.

### Secondary Goals

- Make Conventional Commits the default (machine-parseable, changelog-ready)
- Allow users to select or define a different style via their profile
- Keep the command fast — it should work from `git diff` output, not require
  full codebase indexing
- PR descriptions generated from diff analysis + commit history, not a
  fixed template

---

## User Stories

### Story 1 — Commit message generation

**As a** developer who has staged changes,
**I want** `/dev:git` to read the diff and generate a Conventional Commits
message,
**So that** I get a high-quality commit message without writing it from
scratch.

**Acceptance Criteria**:
- [ ] Running `/dev:git` reads `git diff --staged` and `git log --oneline -10`
- [ ] Output is a commit message following the active profile's
  `git.commit_style` (default: conventional)
- [ ] Subject line: `type(scope): description` ≤72 chars, imperative mood,
  no period
- [ ] Body: explains *why* the change was made; does not restate the diff
- [ ] Claude presents the message for review before running `git commit`
- [ ] User can accept, edit, or reject

### Story 2 — PR description generation

**As a** developer opening a pull request,
**I want** `/dev:git pr` to generate a PR description from the branch's
commits and diff,
**So that** reviewers immediately understand the motivation and scope of
the change.

**Acceptance Criteria**:
- [ ] Running `/dev:git pr` reads `git log main..HEAD` and
  `git diff main...HEAD`
- [ ] Output has two sections: **Summary** (what and why) and **Test plan**
  (bulleted checklist of what to verify)
- [ ] Summary is written in plain prose, not bullet soup
- [ ] Test plan bullets are specific to the actual changes, not generic
- [ ] Claude presents for review before creating the PR via `gh pr create`
- [ ] User can accept, edit, or reject

### Story 3 — Style configuration via profiles

**As a** developer or team lead,
**I want** to set `git.commit_style` in my workflow profile,
**So that** every commit in this project follows our agreed convention
without per-session setup.

**Acceptance Criteria**:
- [ ] All four profiles (`quality`, `fast`, `minimal`, `research`) gain a
  `git` section with `commit_style` and `pr_template` fields
- [ ] Supported `commit_style` values: `conventional`, `imperative`,
  `tim-pope`
- [ ] `/dev:git` reads the active profile's `git.commit_style`; falls back
  to `conventional` if absent
- [ ] `/dev:profile` lists the active git style in its output

### Story 4 — Custom style definition (future-proofing)

**As a** developer with a project-specific convention,
**I want** to define a custom commit style with a name, subject template,
and body guidance,
**So that** the workflow respects our convention without hardcoding it.

**Acceptance Criteria**:
- [ ] Profile supports a `git.custom_style` block with fields: `name`,
  `subject_template`, `body_guidance`
- [ ] When `commit_style: custom`, Claude uses `custom_style` as the prompt
  template for generation
- [ ] If `custom_style` is missing when `commit_style: custom`, Claude warns
  and falls back to `conventional`

### Story 5 — Natural language invocation

**As a** developer doing routine git work,
**I want** to say "commit my changes" or "create a PR" in natural language
and have Claude auto-invoke `/dev:git`,
**So that** I don't need to remember the slash command for common operations.

**Acceptance Criteria**:
- [ ] Claude auto-invokes `/dev:git` when user says "commit", "push",
  "create a PR", "write a commit message", or similar phrases
- [ ] Implemented as a skill with YAML frontmatter trigger description
- [ ] Installed alongside the command file by `install.sh`

---

## Functional Requirements

1. **FR-1**: `/dev:git` subcommands — `commit` (default) and `pr`
   - **Priority**: High
   - **Rationale**: Single entry point keeps the command surface small

2. **FR-2**: Diff-first analysis — always read staged diff before generating
   - **Priority**: High
   - **Rationale**: Message must be grounded in what actually changed

3. **FR-3**: Review-before-execute — never commit or create PR without
   showing the generated text first
   - **Priority**: High
   - **Rationale**: Safety; user remains in control

4. **FR-4**: Profile-driven style — read `git.commit_style` from active
   profile; default `conventional`
   - **Priority**: High
   - **Rationale**: Consistent with how other workflow settings work

5. **FR-5**: Three built-in styles: `conventional`, `imperative`, `tim-pope`
   - **Priority**: Medium
   - **Rationale**: Covers the most common conventions

6. **FR-6**: Custom style via profile block (Story 4)
   - **Priority**: Low — future iteration
   - **Rationale**: Power users need escape hatch; not needed for v1

---

## Non-Functional Requirements

1. **NFR-1 Speed**: Command should produce output in <10s; no RLM indexing
   required — works from `git` output alone
2. **NFR-2 Safety**: Never runs `git commit` or `gh pr create` without
   explicit user approval in the current turn
3. **NFR-3 Portability**: Works without `gh` CLI — degrades gracefully
   (prints PR description to paste manually)

---

## Technical Constraints

- Must integrate with existing profile system (`.claude/profiles/*.yaml`)
- Command file goes in `.claude/commands/dev/git.md` — flat structure,
  consistent with all other `dev:*` commands
- No new dependencies — uses `git` CLI and optionally `gh` CLI
- Style taxonomy and prompt templates live inside `git.md` itself
  (no external config files)

---

## Out of Scope

- Branch naming conventions (separate feature if needed)
- Git tagging or release management
- Automated commit on every file save
- Integration with JIRA or issue trackers (beyond referencing IDs if present)
- Changelog generation (follows naturally from Conventional Commits but
  is a separate feature)

---

## Success Metrics

1. **Adoption**: `/dev:git` used in ≥50% of commits in projects using
   the workflow
2. **Quality**: Generated commit subjects consistently ≤72 chars, imperative,
   typed (spot-check)
3. **Safety**: Zero cases of unintended `git commit` without user approval

---

## References

### From Codebase

- `.claude/profiles/quality.yaml` — profile schema to extend with `git`
  section
- `.claude/commands/dev/` — flat command structure to follow
- `.claude/commands/dev/profile.md` — how profile values are read and
  displayed (pattern to follow for reading `git.commit_style`)

### From Input

- Conventional Commits spec: imperative subject, optional body explaining
  *why*, bullet lists for context the diff doesn't provide
- Three styles documented in user input: imperative-plain, Conventional
  Commits, Tim Pope

---

**Next Steps**:
1. Review and refine this PRD
2. Run `/dev:tech-design` to design the command structure and style templates
3. Run `/dev:tasks` to break into implementation tasks
