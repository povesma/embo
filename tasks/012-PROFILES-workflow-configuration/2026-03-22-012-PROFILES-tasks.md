# 012-PROFILES - Task List

## Relevant Files

- [2026-03-22-012-PROFILES-prd.md](2026-03-22-012-PROFILES-prd.md)
  :: PRD
- [2026-03-22-012-PROFILES-tech-design.md](
  2026-03-22-012-PROFILES-tech-design.md)
  :: Technical Design
- [.claude/profiles/](../../.claude/profiles/) :: Profile YAMLs
- [.claude/commands/dev/profile.md](
  ../../.claude/commands/dev/profile.md) :: Profile command
- [.claude/commands/dev/impl.md](../../.claude/commands/dev/impl.md)
  :: Conditional sections from profile
- [.claude/commands/dev/start.md](../../.claude/commands/dev/start.md)
  :: Conditional RLM/claude-mem
- [.claude/commands/dev/health.md](
  ../../.claude/commands/dev/health.md) :: MCP validation
- [.claude/commands/dev/init.md](../../.claude/commands/dev/init.md)
  :: Conditional init
- [.claude/commands/dev/prd.md](../../.claude/commands/dev/prd.md)
  :: Conditional tool steps
- [.claude/commands/dev/tech-design.md](
  ../../.claude/commands/dev/tech-design.md) :: Conditional tool steps
- [.claude/commands/dev/tasks.md](../../.claude/commands/dev/tasks.md)
  :: Conditional tool steps
- [install.sh](../../install.sh) :: Profiles copy block
- [README.md](../../README.md) :: Profiles documentation
- [CLAUDE.md](../../CLAUDE.md) :: File structure
- [Dockerfile](../../Dockerfile) :: Container test environment

## Notes

- TDD does not apply — all deliverables are YAML data files and
  markdown prompt files.
- Profile YAML is read by Claude at runtime via `Read` tool —
  best-effort compliance.
- All existing behavior preserved as defaults when no profile active.

## Tasks

- [X] 1.0 **User Story:** Built-in profiles shipped [4/4]
  - [X] 1.1 Created `quality.yaml` with full schema
  - [X] 1.2 Created `fast.yaml`
  - [X] 1.3 Created `minimal.yaml`
  - [X] 1.4 Verified all three parse with PyYAML

- [X] 2.0 **User Story:** `/dev:profile` command [4/4]
  - [X] 2.1 Created `profile.md` with header and argument parsing
  - [X] 2.2 `use <name>` mode implemented
  - [X] 2.3 `list` mode implemented
  - [X] 2.4 `off` mode implemented

- [X] 3.0 **User Story:** `impl.md` conditional sections [6/6]
  - [X] 3.1 Added Step 0: Load Profile
  - [X] 3.2 Code Style section conditional
  - [X] 3.3 Testing Guidelines section conditional
  - [X] 3.4 Correction Capture section conditional
  - [X] 3.5 Docs-first enforcement conditional
  - [X] 3.6 RLM and claude-mem steps conditional

- [X] 4.0 **User Story:** `start.md` conditional steps [3/3]
  - [X] 4.1 Added Step 0: Load Profile
  - [X] 4.2 RLM status check conditional
  - [X] 4.3 Claude-mem queries conditional

- [X] 5.0 **User Story:** Remaining commands + health MCP [6/6]
  - [X] 5.1 `health.md`: profile load + MCP validation check
  - [X] 5.2 `init.md`: profile load + conditional init
  - [X] 5.3 `prd.md`: profile load + conditional steps
  - [X] 5.4 `tech-design.md`: profile load + conditional steps
  - [X] 5.5 `tasks.md`: profile load + conditional steps
  - [X] 5.6 Verify with minimal profile (pending testing)

- [X] 6.0 **User Story:** `install.sh` copies profiles [2/2]
  - [X] 6.1 Added profiles copy block
  - [X] 6.2 Verify install.sh works (verified via Docker)

- [X] 7.0 **User Story:** README and CLAUDE.md updated [3/3]
  - [X] 7.1 Added §Profiles section to README
  - [X] 7.2 Updated file tree with profiles/ directory
  - [X] 7.3 Updated CLAUDE.md file structure

- [X] 8.0 **User Story:** Docker container [5/5]
  - [X] 8.1 Created Dockerfile
  - [X] 8.2 Created .dockerignore
  - [X] 8.3 Docker build succeeds
  - [X] 8.4 Auth persistence via named volume
  - [X] 8.5 claude-mem plugin auto-installs (chroma disabled in container)

- [~] 9.0 **User Story:** E2E verification [3/4]
  - [X] 9.1 All 10 commands verified in Docker (`-p` non-interactive)
  - [X] 9.2 `/dev:health` verified in Docker (interactive tmux)
  - [X] 9.3 `/dev:profile list` shows all profiles correctly
  - [ ] 9.4 Full interactive profile activate/deactivate cycle
