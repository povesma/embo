# 011-RENAME: Command Prefix Rename and Structure Flatten - Technical Design

**Status**: Draft
**PRD**: [2026-03-21-011-RENAME-prd.md](2026-03-21-011-RENAME-prd.md)
**Created**: 2026-03-21

---

## Overview

Pure filesystem restructure + string replacement. No logic changes.
Three operations: (1) move files, (2) replace strings, (3) update
install.sh. The deprecated `dev` tree at user scope must be archived
into the repo before the new `dev/` directory is created.

---

## Scope of Changes

### Files to move (within repo)

```
FROM: .claude/commands/rlm-mem/discover/init.md
TO:   .claude/commands/dev/init.md

FROM: .claude/commands/rlm-mem/discover/start.md
TO:   .claude/commands/dev/start.md

FROM: .claude/commands/rlm-mem/discover/health.md
TO:   .claude/commands/dev/health.md

FROM: .claude/commands/rlm-mem/plan/prd.md
TO:   .claude/commands/dev/prd.md

FROM: .claude/commands/rlm-mem/plan/tech-design.md
TO:   .claude/commands/dev/tech-design.md

FROM: .claude/commands/rlm-mem/plan/tasks.md
TO:   .claude/commands/dev/tasks.md

FROM: .claude/commands/rlm-mem/plan/check.md
TO:   .claude/commands/dev/check.md

FROM: .claude/commands/rlm-mem/develop/impl.md
TO:   .claude/commands/dev/impl.md

FROM: .claude/commands/rlm-mem/support/improve.md
TO:   .claude/commands/dev/improve.md
```

The `rlm-mem/` directory tree is deleted after migration.

### Files to archive (from user scope into repo)

The existing deprecated `dev` command tree at `~/.claude/commands/dev/`
must be captured into `.claude/commands-archive/dev/` in the repo
before the new `dev/` is written. This prevents loss and avoids
confusion.

```
~/.claude/commands/dev/* → .claude/commands-archive/dev/
```

The `dev-archive/` directory is committed to the repo but excluded
from `install.sh` sync — it is reference material only.

### String replacements (across all moved files + docs)

| Pattern | Replacement | Scope |
|---------|-------------|-------|
| `/rlm-mem:discover:start` | `/dev:start` | command files |
| `/rlm-mem:discover:init` | `/dev:init` | command files |
| `/rlm-mem:discover:health` | `/dev:health` | command files |
| `/rlm-mem:plan:prd` | `/dev:prd` | command files |
| `/rlm-mem:plan:tech-design` | `/dev:tech-design` | command files |
| `/rlm-mem:plan:tasks` | `/dev:tasks` | command files |
| `/rlm-mem:plan:check` | `/dev:check` | command files |
| `/rlm-mem:develop:impl` | `/dev:impl` | command files |
| `/rlm-mem:develop:save` | `/dev:save` | command files |
| `/rlm-mem:support:improve` | `/dev:improve` | command files |
| `/rlm-mem:` (any remaining) | `/dev:` | command files |
| All of the above | same | README.md |
| All of the above | same | CLAUDE.md |

A final grep for `/rlm-mem:` across the entire repo confirms zero
misses before the task is closed.

### install.sh changes

Two line changes:

```bash
# BEFORE:
mkdir -p "$TARGET/commands/rlm-mem"
cp -r "$REPO_DIR/.claude/commands/rlm-mem/"* "$TARGET/commands/rlm-mem/"
echo "  commands/rlm-mem: synced"

# AFTER:
mkdir -p "$TARGET/commands/dev"
cp -r "$REPO_DIR/.claude/commands/dev/"* "$TARGET/commands/dev/"
echo "  commands/dev: synced"
```

The `dev-archive/` directory must NOT be included in the copy.
Since `install.sh` only copies `commands/dev/`, the archive is
automatically excluded.

Also update the final line:
```bash
# BEFORE:
echo "Done. Run /rlm-mem:discover:start to begin a session."

# AFTER:
echo "Done. Run /dev:start to begin a session."
```

---

## Operation Order

Order matters — archive before create to avoid overwriting.

```
1. Copy ~/.claude/commands/dev/* into .claude/commands-archive/dev/
2. mkdir .claude/commands/dev/
3. git mv each rlm-mem file to dev/ (preserves git history)
4. git rm -r .claude/commands/rlm-mem/
5. Replace all strings in moved files
6. Update README.md
7. Update CLAUDE.md
8. Update install.sh
9. grep -r "/rlm-mem:" . — must return zero results
10. git add + commit
```

Using `git mv` (not `cp`+`rm`) preserves file history in git log,
making it easy to trace when a command's content changed.

---

## CLAUDE.md / README.md File Tree

### CLAUDE.md — updated file structure section

```
.claude/
├── agents/         (unchanged)
├── commands/
│   ├── dev/        # 10 command definitions
│   │   ├── init.md, start.md, health.md    # discovery
│   │   ├── prd.md, tech-design.md,         # planning
│   │   │   tasks.md, check.md
│   │   ├── impl.md                          # development
│   │   └── improve.md                       # support
│   └── dev-archive/  # deprecated dev tree (reference only)
├── hooks/          (unchanged)
├── rlm_scripts/    (unchanged)
└── statusline.sh   (unchanged)
```

### README — Available Commands section

Phase grouping in the command list (Discovery / Planning / Development /
Support) is kept as **prose headers**, not encoded in the command path.
This preserves the conceptual organization for users reading docs
without imposing it on the command namespace.

```markdown
### Discovery
- `/dev:init`    - Initialize RLM + claude-mem
- `/dev:start`   - Start session with full context
- `/dev:health`  - Verify all system dependencies

### Planning
- `/dev:prd`          - Generate PRD with codebase awareness
- `/dev:tech-design`  - Design with pattern discovery
- `/dev:tasks`        - Task breakdown with complexity analysis
- `/dev:check`        - Verify task completion status

### Development
- `/dev:impl`    - Implement following patterns
- `/dev:save`    - Wrap up session, save to claude-mem

### Support
- `/dev:improve` - Review corrections and generate improvement proposal
```

---

## Command Tree Disambiguation

After install, `~/.claude/commands/` will contain:

```
~/.claude/commands/
├── dev/        ← new (this package)
├── coding/     ← separate package, unchanged
├── rlm/        ← separate package, unchanged
└── rlm-mem/    ← OLD, must be manually removed post-install
```

The old `rlm-mem/` at user scope is NOT automatically removed by
`install.sh` — that would be destructive. A post-install note in
README guides users to remove it manually:

```bash
rm -rf ~/.claude/commands/rlm-mem
```

---

## Trade-offs

### `git mv` vs `cp` + `rm`
`git mv` chosen — preserves history per file. `cp`+`rm` would show
all files as new in `git log`, losing blame/history continuity.

### Delete `rlm-mem/` subdir names vs keep as comments
The phase names (`discover/`, `plan/`, etc.) were useful internal
organization. After flattening, the organization is preserved as
section comments in README only — not in filesystem. A future
`_README.md` inside `dev/` could document the grouping if needed.

### Archive at user scope vs skip
Archiving `~/.claude/commands/dev/` into the repo ensures the old
content isn't lost and is visible to contributors. Skipping archive
risks losing context on why the old `dev` commands were deprecated.

---

**Next Steps:**
1. Review and approve this design
2. Run `/dev:tasks` to generate implementation task list
