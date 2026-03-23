# Repository Documentation Sync & Update

Synchronize and update repository documentation for initialized Project AI repositories. This command refreshes repository understanding by examining current implementation state, updating architecture documentation, and maintaining repository overview accuracy.

## Process

### Phase 1: Repository Initialization Check
1. **Verify Project AI Structure:** Check if `ai-docs/` directory and core files exist
   - **If NOT INITIALIZED:** Stop and inform user: "Repository is not initialized with Project AI structure. Please run `/prj-setup` command first to set up the repository structure and perform initial analysis."
   - **If INITIALIZED:** Continue with synchronization process

### Phase 2: Current State Assessment  
1. **Examine Implementation State:** Review all `ai-docs/` files and UPDATE them to reflect ACTUAL current implementation:
   - `ai-docs/README.md` - Update with currently implemented features, working technology stack, tested setup instructions
   - `ai-docs/ARCHITECTURE.md` - Update with current system components, implemented architecture, working integrations (reference tech design docs if they exist)
   - `ai-docs/API.md` - Update with currently available external API endpoints and interfaces, tested examples
   - `ai-docs/DEVELOPMENT.md` - Update with current development practices, tools in use, coding standards applied
   - `ai-docs/SCHEMA.md` - Update with existing external database schemas and repository entities, applied migrations
   - `ai-docs/USAGE.md` - Update with current working functionality, tested usage examples
   - Additional files: Update only if corresponding functionality exists
2. **Update Context Files:** Update `CLAUDE.md` and `AGENTS.md` to reflect current repository implementation state
3. **Check Tech Design Documents:** Review any existing technical design documents in `/tasks` directory and incorporate implemented designs into architecture documentation
4. **Verify Documentation Accuracy:** Test described processes and verify all documented features actually work
5. **Analyze Codebase Changes:** Scan codebase for new dependencies, architecture changes, and implementation updates

### Phase 3: Documentation Refresh - Current Implementation Focus
1. **Update Technology Stack:** Scan `package.json`, `go.mod`, `build.sbt`, `requirements.txt`, `pyproject.toml`, `Pipfile`, dependencies and refresh `ai-docs/README.md` with ONLY currently used technologies
   - For other languages: scan relevant dependency files (e.g., `Cargo.toml`, `composer.json`, `Gemfile`, `pom.xml`, etc.)
2. **Sync Architecture Documentation:** Update `ai-docs/ARCHITECTURE.md` with implemented components and working integrations only
3. **Refresh API Documentation:** Update `ai-docs/API.md` with tested external API endpoints - remove documentation for non-working external interfaces
4. **Update Development Practices:** Sync `ai-docs/DEVELOPMENT.md` with actual coding patterns in use and tools currently configured
5. **Validate Feature Accuracy:** Remove or mark as "planned" any features not yet implemented in the codebase
6. **Test Documentation:** Verify setup instructions work, API examples function, and architecture diagrams reflect reality

### Phase 4: Repository Status Tracking - Implementation Reality Check
1. **Review Active Tasks:** Examine `/tasks` directory for ongoing work:
   - Find repository overview file (`*-overview.md`)
   - Review PRD files (`*-prd.md`) and their completion status vs actual implementation
   - Review technical design files (`*-tech-design.md`) and verify implemented architecture matches designs
   - Check task files (`*-tasks.md`) and verify claimed completion against codebase reality
2. **Update Repository Overview:** Sync repository goals, features, and ACTUAL completion status based on working code
3. **Sync Feature Status:** Update feature implementation status to reflect what's actually working in the codebase
4. **Mark Incomplete Features:** Clearly separate implemented features from planned/partial features
5. **Update AGENTS.md Context:** Refresh AI context to reflect current implementation state, not aspirational features

## Documentation Update Requirements

### ai-docs/ Files Synchronization
Ensure the following files are current with implementation:

#### README.md Structure
```markdown
# Project Name

## Overview
[Current project purpose and scope]

## Key Features  
- [Implemented Feature 1]
- [Implemented Feature 2]
- [In Progress Feature 3]

## Technology Stack
[Current dependencies, frameworks, and tools - MUST BE CURRENT]

## Architecture
See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed system design.

## Quick Start
[Current setup and usage instructions]
```

#### Repository Overview Tracking
- **Location:** `/tasks/[repository-name]-overview.md`
- **Purpose:** Track feature completion and repository status  
- **Format:** The repository overview _must_ follow this structure:
```markdown
# [repository-name] - Repository Overview

## Goal
[Repository's goal and short description]

## Technical Stack
- [item 1]
- [item 2]
```

## Create or Update List of PRDs and Tech Designs
- Add or update list of PRDs and technical designs in the repository overview file for each document found.
- **Format:** The repository overview _must_ follow this structure:
```markdown
## [One line description of PRD/Tech Design]
- [JIRA-ID-feature-name/prd-file-name](JIRA-ID-feature-name/prd-file-name)
- [JIRA-ID-feature-name/tech-design-file-name](JIRA-ID-feature-name/tech-design-file-name)
- [Status]
- [Key Feature Implemented 1]
- [Key Feature Implemented 2]
```

## Example of Repository Overview File
```markdown
# Mineswpr - Repository Overview

## Goal
Build mobile-first Minesweeper game.

## Technical Stack
- Next.js + TypeScript + Tailwind CSS
- Custom hooks for state management and responsive design
- Comprehensive test suite with Jest + React Testing Library
- Cross-browser compatibility (Chrome, Firefox, Safari, Edge)

## Phase 1 Summary: Core Minesweeper Implementation
- [GAME-001-minesweeper-v1/2025-06-08-GAME-001-minesweeper-v1-prd.md](GAME-001-minesweeper-v1/2025-06-08-GAME-001-minesweeper-v1-prd.md)
- Status: ✅ 100% Complete - All 35 tasks completed across 5 major areas (setup, game logic, UI components, state management, responsive design)
- Responsive grid generation - Adapts to screen size at game start
- Core game mechanics - Mine placement (15% density), adjacent counting, cascade reveals
- Touch-optimized controls - Left-click/tap to reveal, right-click/long-press to flag
- Modern UI - Clean design with Tailwind CSS, 44px+ touch targets
- Complete game flow - Win/lose detection, reset functionality
```
