# Profile System Research Report

*Generated via NotebookLM from 10 sources (Cursor, Windsurf, Cline,
Claude Code, Aider, GitHub Copilot, Kiro docs)*

## Key Findings for Our Profile System

### 1. Industry standard: Markdown + YAML frontmatter

Every major tool uses **Markdown files** for behavioral rules, with
**YAML frontmatter** for metadata (paths, triggers, activation modes).
JSON/YAML used only for hard client-side settings.

### 2. Path-scoped activation is the pattern

Claude Code, Windsurf, Copilot, Cline all support **glob-based rule
scoping** — rules only load when the LLM touches matching files.
This is the mechanism for per-task/per-component config.

### 3. Layered precedence is standard

| Tool | Precedence (highest → lowest) |
|------|-------------------------------|
| Copilot | Personal > Repository > Organization |
| Claude Code | Project > User (managed policy overrides all) |
| Windsurf | System merges; workspace + global deduplicated |

### 4. Config loads as context, not system prompt

Claude Code: CLAUDE.md delivered as **user message after system prompt**.
Windsurf: `always_on` = full content every message; `model_decision` =
description only, full on demand. Aider: read-only + prompt caching.

**Key constraint**: >200 lines reduces adherence significantly.

### 5. Enforcement is best-effort — use hooks for hard rules

No tool guarantees LLM compliance with config instructions. Hard
enforcement requires **client-side settings** (permissions.deny) or
**hooks** (PostToolUse quality gates). Behavioral guidance via prompts
is soft by nature.

### 6. Known failure modes

- Context window pressure (long configs → ignored)
- Vague instructions ("write good code" = useless)
- Conflicting rules → LLM picks arbitrarily

### 7. Per-task config exists

- **Windsurf**: `manual` trigger — rule only loads when @mentioned
- **Claude Code**: Skills only load when invoked
- **Kiro**: Per-feature `tasks.md` spec files
- **Copilot**: Path-specific `.instructions.md` files

### 8. Best practices

- Keep instructions specific & verifiable
- Use markdown formatting (headers, bullets)
- Scope rules by path (glob patterns)
- Use ignore files to reduce context bloat
- Don't duplicate what the model already knows

### Anti-patterns

- Generic rules ("write good code") waste tokens
- Monolithic config files (>200 lines) decrease adherence
- Using prompt configs for hard security enforcement
