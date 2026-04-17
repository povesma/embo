# Initialize RLM-Mem Hybrid System

Bootstrap both RLM file indexing and claude-mem semantic memory for a project. This is the foundation for quality-first development workflow.

## When to Use

- **First time** working on a project with dev commands
- **Migrating** from `dev/*` or `coding/*` workflows
- **Re-indexing** after major repository changes
- **New team member** onboarding

## What This Command Does

1. **RLM Indexing**: Builds file index for code analysis
   - Indexes all files (respecting `.gitignore`)
   - Detects languages, file types, binary files
   - Creates persistent state for fast lookups

2. **Claude-Mem Bootstrap**: Indexes project knowledge
   - Scans existing documentation
   - Indexes PRDs, designs, task lists, reviews
   - Creates searchable semantic memory

3. **Cross-Linking**: Connects both systems
   - Saves RLM index summary to claude-mem
   - Tags observations with project metadata
   - Enables hybrid queries

## Process

### Step 0: Load Profile

Read `~/.claude/active-profile.yaml` if it exists. If not present,
use defaults: rlm=true, memory_backend=claude-mem. Skip RLM init
steps below if `tools.rlm` is `false`. Skip claude-mem bootstrap
if `tools.memory_backend` is `none`.

### Step 1: Verify Prerequisites

Check that both systems are available (skip checks for disabled tools):
```bash
# Check RLM
python3 ~/.claude/rlm_scripts/rlm_repl.py --help

# Check claude-mem (via search tool availability)
# MCP tools should be accessible
```

### Step 2: Determine Project Name

```bash
# From git
project_name=$(basename $(git rev-parse --show-toplevel 2>/dev/null) || basename $(pwd))

# Ask user to confirm
```

**Ask user**: "Project name detected as `<project_name>`. Use this? (yes/no/custom)"

### Step 3: Initialize RLM

```bash
python3 ~/.claude/rlm_scripts/rlm_repl.py init-repo .
```

This will:
- Auto-discover any `.rlmignore` (cwd → ancestors → repo root)
- Discover all files (git-aware)
- Detect languages (50+ types)
- Identify binary files
- Calculate metadata
- Store in `.claude/rlm_state/state.pkl`

If the repo has a large vendor tree (e.g. `html/`, `node_modules/`)
and no `.rlmignore` exists, suggest one before running — or pass
`--exclude 'html/**'` for a one-off run. Other flags:
`--include` (allowlist), `--exclude-from FILE`, `--no-rlmignore`.

**Capture output**:
- Total files indexed
- Repository size
- Primary languages
- Per-pattern filter counts (only shown when filters were applied)
- State file location

### Step 4: Bootstrap Claude-Mem

**4a. Scan for existing documentation**:
```bash
# Find key documentation files
- CLAUDE.md (project instructions)
- README.md (project overview)
- /tasks/ directory (PRDs, designs, tasks, reviews)
- Package files (package.json, go.mod, etc.)
```

**4b. Index project overview**:

If README.md or CLAUDE.md exist:
```
mcp__plugin_claude-mem_mcp-search__save_memory(
  text=f"""[TYPE: PROJECT-OVERVIEW]
[PROJECT: {project_name}]
[SOURCE: README.md, CLAUDE.md]

# Project Overview

{readme_content}

{claude_md_content}

## RLM Index Summary
- Total files: {rlm_total_files}
- Repository size: {rlm_size_mb} MB
- Primary languages: {rlm_top_languages}
- Indexed at: {timestamp}
""",
  title=f"{project_name} - Project Overview",
  project=project_name
)
```

**4c. Index RLM analysis as baseline**:

```
mcp__plugin_claude-mem_mcp-search__save_memory(
  text=f"""[TYPE: CODEBASE-ANALYSIS]
[PROJECT: {project_name}]
[ANALYZER: RLM]
[SOURCE: Initial indexing]

# Codebase Analysis - Initial Snapshot

## Repository Statistics
- **Total files**: {total_files}
- **Repository size**: {size_mb} MB
- **Languages detected**: {num_languages}

## Language Distribution
{language_breakdown}

## File Categories
- Source code files: {source_count}
- Test files: {test_count}
- Configuration files: {config_count}
- Documentation files: {doc_count}
- Binary files: {binary_count}

## Key Directories
{directory_structure}

This baseline analysis was performed by RLM indexing at {timestamp}.
""",
  title=f"{project_name} - Initial Codebase Analysis",
  project=project_name
)
```

**4d. Index existing tasks directory** (if exists):

For each file in `/tasks/` (prd, tech-design, tasks, review files):
Read the file — the PostToolUse hook captures it as a claude-mem
observation automatically. No explicit save call needed.

**4e. Index configuration files**:

If package.json, go.mod, Makefile, or similar exist:
Read the file — the PostToolUse hook captures it automatically.

### Step 5: Verify Integration

```bash
# Check RLM status
python3 ~/.claude/rlm_scripts/rlm_repl.py status

# Check claude-mem observations
mcp__plugin_claude-mem_mcp-search__search(
  query="project overview codebase analysis",
  project=project_name,
  limit=5
)
```

### Step 6: Generate Summary Report

```markdown
# ✅ RLM-Mem Initialization Complete

**Project**: {project_name}

## RLM Indexing
- ✅ **Files indexed**: {total_files:,}
- ✅ **Repository size**: {size_mb:.1f} MB
- ✅ **Primary languages**:
  • {lang1}: {count1} files ({pct1:.1f}%)
  • {lang2}: {count2} files ({pct2:.1f}%)
  • {lang3}: {count3} files ({pct3:.1f}%)
- ✅ **State saved**: .claude/rlm_state/state.pkl

Include any filter summary lines from the `init-repo` stdout
verbatim, if present.

## Claude-Mem Bootstrap
- ✅ **Project overview**: Indexed
- ✅ **Codebase analysis**: Indexed
- ✅ **PRDs**: {prd_count} indexed
- ✅ **Tech designs**: {design_count} indexed
- ✅ **Task lists**: {tasks_count} indexed
- ✅ **Reviews**: {review_count} indexed
- ✅ **Configuration**: Indexed
- ✅ **Total observations**: {total_obs}

## Integration Status
- ✅ RLM ↔ Claude-Mem: Connected
- ✅ Cross-references: Created
- ✅ Project tagged: "{project_name}"

## Next Steps

**Start your first session**:
```
/dev:start
```

**Or create a new feature**:
```
/dev:prd
```

**Or search existing work**:
```
Search: "authentication" or "database schema" or "API design"
(Claude-mem will find it)
```

## Notes
- **One-time operation**: Only run this on first setup
- **Idempotent**: Safe to re-run if needed (will update observations)
- **Fast**: Indexing took ~{duration}s
- **Automatic from now on**: Future work auto-captured by hooks
```

## Important Notes

1. **Selective Indexing**:
   - Only index documentation and metadata
   - DO NOT index entire source code files into claude-mem
   - RLM handles code analysis on-demand

2. **Git Ignore**:
   - Ensure `.claude/rlm_state/` is in `.gitignore`
   - Check if already present, add if missing

3. **Confirmation**:
   - Show user what will be indexed
   - Wait for explicit "go" before proceeding
   - Allow user to skip sections

4. **Error Handling**:
   - If RLM init fails: report error, suggest fixes
   - If claude-mem unavailable: warn but continue with RLM only
   - If no documentation found: that's OK, index RLM baseline only

## Output Example

```
# ✅ RLM-Mem Initialization Complete

**Project**: app-astudio

## RLM Indexing
- ✅ **Files indexed**: 3,940
- ✅ **Repository size**: 157.1 MB
- ✅ **Primary languages**:
  • C/C++: 1254 files (31.8%)
  • C++: 876 files (22.2%)
  • TypeScript: 35 files (0.9%)
- ✅ **State saved**: .claude/rlm_state/state.pkl

## Claude-Mem Bootstrap
- ✅ **Project overview**: Indexed
- ✅ **Codebase analysis**: Indexed
- ✅ **PRDs**: 12 indexed
- ✅ **Tech designs**: 8 indexed
- ✅ **Task lists**: 15 indexed
- ✅ **Reviews**: 5 indexed
- ✅ **Configuration**: Indexed
- ✅ **Total observations**: 42

## Integration Status
- ✅ RLM ↔ Claude-Mem: Connected
- ✅ Cross-references: Created
- ✅ Project tagged: "app-astudio"

## Next Steps
/dev:start
```

## Final Instructions

1. Verify both RLM and claude-mem prerequisites
2. Ask user to confirm project name
3. Initialize RLM (always)
4. Bootstrap claude-mem (if available)
5. Cross-link systems
6. Report comprehensive summary
7. DO NOT start implementing anything
8. DO NOT read entire source code files
9. Suggest `/dev:start` as next step
