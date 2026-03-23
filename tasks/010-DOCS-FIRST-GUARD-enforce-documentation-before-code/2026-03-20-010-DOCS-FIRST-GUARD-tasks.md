# 010-DOCS-FIRST-GUARD - Task List

## Relevant Files

- [tasks/010-DOCS-FIRST-GUARD-enforce-documentation-before-code/
  2026-03-20-010-DOCS-FIRST-GUARD-prd.md](
  2026-03-20-010-DOCS-FIRST-GUARD-prd.md)
  :: Product Requirements Document
- [tasks/010-DOCS-FIRST-GUARD-enforce-documentation-before-code/
  2026-03-20-010-DOCS-FIRST-GUARD-tech-design.md](
  2026-03-20-010-DOCS-FIRST-GUARD-tech-design.md)
  :: Technical Design Document
- [.claude/commands/rlm-mem/develop/impl.md](
  ../../.claude/commands/rlm-mem/develop/impl.md)
  :: Modified — prompt-based docs-first + docs-after enforcement
- [.claude/commands/rlm-mem/discover/start.md](
  ../../.claude/commands/rlm-mem/discover/start.md)
  :: Modified — semantic Docs-First Principle
- [README.md](../../README.md)
  :: Modified — hook section revised, install steps updated
- [CLAUDE.md](../../CLAUDE.md)
  :: Modified — file structure updated

## Notes

- **V1 (hook-based) was attempted and abandoned.** The PreToolUse
  hook broke Shift+Tab "Allow all edits" and could not reason about
  semantic context. See PRD for full rationale.
- **V2 (prompt-based) is complete.** Enforcement lives in command
  prompts. Claude uses semantic judgment before editing code files.
- The hook file (`.claude/hooks/docs-first-guard.sh`) remains in
  the repo as a historical reference — NOT installed, NOT registered.

## V1 Tasks (hook-based — abandoned)

- [X] 1.0 ~~PreToolUse hook script~~ **ABANDONED** — hook breaks
  Shift+Tab permission mode [5/5]
  - [X] 1.1–1.5 (implemented, tested — incompatible with Claude
    Code permission modes)

- [X] 2.0 ~~Marker file management~~ **ABANDONED** — filesystem
  flag can't reason about semantic context [2/2]
  - [X] 2.1–2.2 (implemented and reverted)

- [X] 3.0 ~~Prompt hardening with hook references~~ **SUPERSEDED**
  by V2 [3/3]
  - [X] 3.1–3.3 (hook references removed, semantic text in place)

- [X] 4.0 ~~install.sh hook registration~~ **REVERTED** [3/3]

- [X] 5.0 ~~README hook documentation~~ **REVISED** [2/2]

- [X] 6.0 ~~E2E Gherkin scenarios~~ **CANCELLED** — hook-based
  scenarios no longer applicable

## V2 Tasks (prompt-based enforcement)

- [X] 7.0 **Revert V1 hook artifacts** [5/5]
  - [X] 7.1 Removed Step 0 (touch marker) and Step 9 (rm marker)
    from `impl.md`
  - [X] 7.2 Removed hook reference from `impl.md` Scope Verification
  - [X] 7.3 Removed hook reference from `start.md` Docs-First section
  - [X] 7.4 Removed hook registration block from `install.sh`
  - [X] 7.5 Removed hook copy steps from README (macOS + Windows)

- [X] 8.0 **Prompt-based enforcement in command files** [3/3]
  - [X] 8.1 Rewrote Docs-First Principle in `start.md`: semantic
    cases (research/POC, minor changes, undocumented code)
  - [X] 8.2 Updated Scope Verification in `impl.md`: removed hook
    reference, added docs-after rule (immediate sync after changes)
  - [X] 8.3 Verified: no hook/marker references remain in command
    files, install.sh, README, or CLAUDE.md

- [X] 9.0 **README and CLAUDE.md updated** [4/4]
  - [X] 9.1 Replaced docs-first-guard section with prompt-based note
  - [X] 9.2 Removed `docs-first-guard.sh` from file tree
  - [X] 9.3 Removed hook copy steps from macOS and Windows install
  - [X] 9.4 Removed `docs-first-guard.sh` from CLAUDE.md

- [X] 10.0 **Installation artifacts cleaned up** [2/2]
  - [X] 10.1 Removed hook registration block from `install.sh`
  - [X] 10.2 Removed hook copy line from `install.sh`
