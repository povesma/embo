# 014: Git Commit & PR Texts — Technical Design

**Status**: Draft
**PRD**: [2026-03-29-014-git-commit-pr-texts-prd.md](
  2026-03-29-014-git-commit-pr-texts-prd.md)
**Created**: 2026-03-29

---

## Overview

All changes are to `.md` command prompt files and `.yaml` profile files.
No scripts, no binaries. The implementation is prompt engineering:
one new command and a schema extension to four profile files.

The command reads `git` output (diff, log, status) and uses it as
context for message generation. It never reads the full codebase —
git's own diff output is the context source.

---

## Current Architecture

This repo ships prompt files installed to `~/.claude/`. The relevant
existing structure:

```
.claude/
├── commands/dev/           # 11 flat .md command files
│   ├── profile.md          # Reads ~/.claude/active-profile.yaml
│   ├── impl.md             # Reads profile for code_style, testing, workflow
│   └── start.md            # Reads profile for all session defaults
└── profiles/
    ├── quality.yaml         # Full workflow profile
    ├── fast.yaml            # Speed profile
    ├── minimal.yaml         # Bare-bones profile
    └── research.yaml        # Research profile
```

**Profile consumption pattern** (established by `impl.md`, `start.md`):
1. `cat ~/.claude/active-profile.yaml` at session start
2. Extract named fields (`rules.code_style.line_length`, etc.)
3. Fall back to hardcoded defaults if field absent or file missing

**Profile schema** (current, all four files share this structure):
```yaml
name: <string>
description: <string>
rules:
  code_style: { line_length, comments, naming_convention }
  testing: { approach, scope, subagents }
  workflow: { docs_first, correction_capture, scope_drift }
tools:
  rlm: <bool>
  memory_backend: <string>
mcps:
  required: [...]
  optional: [...]
```

---

## Proposed Design

### 1. Profile Schema Extension

Add a `git` block to all four profile files. This block is optional —
absent means fall back to defaults.

```yaml
git:
  commit_style: conventional   # conventional | imperative | tim-pope | custom
  custom_style:                # only used when commit_style: custom
    name: "My Style"
    subject_template: "{verb} {what}"
    body_guidance: "Explain the business reason. Reference ticket."
```

**Default values** (when `git` block absent):

| Field | Default |
|-------|---------|
| `commit_style` | `conventional` |
| `custom_style` | n/a |

**Values per profile** (initial):

| Profile | `commit_style` |
|---------|----------------|
| quality | `conventional` |
| fast | `conventional` |
| minimal | `conventional` |
| research | `conventional` |

All start at `conventional`. Users override in their copy.

---

### 2. Style Taxonomy

Three built-in styles. Their definitions live inside `git.md` as
reference text Claude reads when generating messages.

#### `conventional`

Follows [Conventional Commits 1.0](https://www.conventionalcommits.org/).

```
<type>(<scope>): <subject>          ← ≤72 chars, imperative, no period
                                    ← blank line
<body>                              ← why, not what; wrap at 72 chars
                                    ← blank line (if footer present)
<footer>                            ← Breaking-change or issue refs
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`,
`ci`, `build`, `revert`.

Scope: the subsystem changed (e.g. `auth`, `api`, `profiles`). Omit
if the change is cross-cutting.

Body rules (from PRD input):
- Explain *why*, not *what* (the diff shows what)
- Bullet lists acceptable when each adds context the diff doesn't

#### `imperative`

```
<Verb> <what>                       ← ≤50 chars, imperative, no period
                                    ← blank line
<body>                              ← motivation, context, trade-offs
```

No type prefix. Same body rules as `conventional`.

#### `tim-pope`

Same subject format as `imperative` (≤50 chars). Body wrapped at 72
chars. No structural difference from `imperative` beyond line-wrap
discipline. Reference: https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html

#### `custom`

Claude reads `git.custom_style.subject_template` and
`git.custom_style.body_guidance` from the active profile and uses them
as the generation template. If the block is missing, warn and fall back
to `conventional`.

---

### 3. `/dev:git` Command Structure

**File**: `.claude/commands/dev/git.md`

**Subcommands** (determined from args):

| Invocation | Mode |
|------------|------|
| `/dev:git` | interactive menu: commit / pr / style |
| `/dev:git commit` | `commit` |
| `/dev:git pr` | `pr` |
| `/dev:git style` | `style` — list styles, switch active |

#### Commit mode flow

```
read ~/.claude/active-profile.yaml → extract git.commit_style (default: conventional)
       │
       ▼
git diff --staged --stat
       │
       ├─ nothing staged ──► git status → show unstaged files
       │                   → ask user which to stage (or all)
       │                   → git add <selection>
       │                   → re-read git diff --staged
       │
       ▼
git diff --staged           ← full diff for context
git log --oneline -10       ← recent history for scope/type inference
       │
       ▼
generate commit message per active style
       │
       ▼
present message to user
       │
       ├─ accept ──► git commit -m "$(cat <<'EOF' ... EOF)"
       ├─ edit   ──► user edits inline → git commit with edited message
       └─ reject ──► stop, no commit
```

#### PR mode flow

```
read ~/.claude/active-profile.yaml → extract git.commit_style
       │
       ▼
ask: "Base branch? [main]:"         ← always ask (per user decision)
       │
       ▼
git log <base>..HEAD --oneline      ← commit list
git diff <base>...HEAD --stat       ← files changed
git diff <base>...HEAD              ← full diff (may be large — use --stat
                                       first; read full diff only if <500 lines)
       │
       ▼
generate PR description:
  ## Summary
  <prose: what changed and why, drawn from commits + diff>

  ## Test plan
  - [ ] <specific thing to verify, drawn from actual changes>
  - [ ] ...
       │
       ▼
present to user
       │
       ├─ accept + gh available ──► gh pr create --title "..." --body "..."
       ├─ accept + no gh ──────────► print body, instruct user to paste
       ├─ edit ──────────────────────► user edits → same branching
       └─ reject ──────────────────► stop
```

---

### 4. `style` subcommand flow

```
/dev:git style invoked
      │
      ▼
read ~/.claude/active-profile.yaml → current git.commit_style (default: conventional)
      │
      ▼
display all three built-in styles with one-line subject examples:
  * conventional (active)    feat(scope): subject
    imperative               Add feature
    tim-pope                 Add feature  (72-char body wrap)
      │
      ▼
ask: "Switch to style? (enter name or press Enter to keep current)"
      │
      ├─ Enter / no change ──► "Style unchanged: conventional"
      └─ valid style name ──► write git.commit_style: <name>
                              to ~/.claude/active-profile.yaml
                              → "Style updated: conventional → imperative"
```

**Write mechanism**: read active profile YAML, update the
`git.commit_style` field, write back. If no `git:` block exists,
add one. If no active profile, inform user to activate one first
(`/dev:profile use <name>`).

---

### 5. `profile.md` Extension

Add git style to the `use <name>` confirmation output:

```
✅ Profile activated: quality

Full workflow — docs-first, TDD, RLM + claude-mem

Key settings:
- Code style: 120 chars, comments: minimal
- Testing: tdd, subagents: test-backend, test-review
- Workflow: docs-first: strict, corrections: on
- Tools: RLM: on, memory: claude-mem
- Git: commit style: conventional          ← NEW LINE
- Required MCPs: context7
```

---

## Data Contracts

### Profile `git` block schema

```yaml
git:
  commit_style: conventional | imperative | tim-pope | custom
  custom_style:           # optional; required only when commit_style: custom
    name: string
    subject_template: string   # e.g. "{verb} {what} in {scope}"
    body_guidance: string      # free text prompt guidance for body generation
```

### Commit message contract (conventional)

```
type(scope): subject\n\nbody\n\nfooter
```

- `type`: one of the 10 standard types
- `scope`: optional, lowercase, no spaces
- `subject`: imperative, ≤72 chars total line, no trailing period
- `body`: separated by blank line, explains why; 72-char wrap
- `footer`: optional; `BREAKING CHANGE:` or `Closes #N`

### PR description contract

```markdown
## Summary

<1-3 paragraph prose>

## Test plan

- [ ] <specific check>
- [ ] <specific check>
```

---

## Sequence: Staged Changes Check

```
/dev:git invoked
      │
      ▼
git diff --staged --stat
      │
      ├─ has output ──────────────────────────► proceed to generation
      │
      └─ empty ──► git status --short
                       │
                       ├─ nothing at all ──► "Nothing to commit. Exiting."
                       │
                       └─ unstaged changes exist ──► show list
                                  │
                                  ▼
                          ask: stage all? stage selected? cancel?
                                  │
                                  ├─ all ──► git add -A → proceed
                                  ├─ selected ──► git add <files> → proceed
                                  └─ cancel ──► stop
```

---

## Trade-offs

### Single `/dev:git` command vs separate `/dev:commit` and `/dev:pr`

**Chosen**: single `/dev:git` with subcommands

**Rejected**: two separate commands (`/dev:commit`, `/dev:pr`)

**Rationale**: The PRD specified `/dev:git`. Fewer top-level commands
reduces the surface area to learn. Both subcommands share profile
loading and style taxonomy logic — conceptually one feature.

### Style templates in `git.md` vs external files

**Chosen**: style definitions embedded in `git.md`

**Rejected**: separate `~/.claude/git-styles/conventional.md` files

**Rationale**: Consistent with how all other commands work — everything
the command needs is inside the `.md` file. No extra install steps, no
extra files to copy. PRD explicitly states "style taxonomy lives inside
`git.md` itself."

### PR diff size handling

**Chosen**: read `--stat` first; read full diff only if <500 lines

**Rejected**: always read full diff / always use stat only

**Rationale**: Full diffs on large PRs exceed practical context limits.
`--stat` gives enough signal for the Summary. Full diff is read only
when small enough to add meaningful detail without overwhelming context.

### Base branch: always ask vs auto-detect

**Chosen**: always ask with default suggestion

**Rejected**: auto-detect from `git merge-base`

**Rationale**: User explicitly chose this. Auto-detection is fragile on
repos with unusual base branch names or multiple active branches. The
prompt adds <5 seconds and prevents wrong-base PR descriptions.

---

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1: `/dev:git` command exists with commit + pr subcommands | `code-only` | — | — |
| FR-2: reads `git diff --staged` before generating | `manual-run-claude` | integration | Claude shows diff stat before message |
| FR-3: presents message for review, does not auto-commit | `manual-run-user` | integration | user confirms no commit without approval |
| FR-4: reads `git.commit_style` from active profile | `manual-run-claude` | integration | switching profile changes generated style |
| FR-5: three built-in styles produce correct subject formats | `manual-run-claude` | integration | conventional shows `type(scope):`, imperative shows bare verb |
| FR-6: custom style via profile block | `code-only` | — | — (v1 deferred) |
| Profile `git` block added to all four profiles | `code-only` | — | — |
| `profile.md` shows git style in activation output | `manual-run-claude` | integration | `/dev:profile use quality` output includes git line |
| FR-7: natural language triggers `/dev:git` via skill | `manual-run-user` | integration | "commit my changes" auto-invokes the command |

---

## Files to Create/Modify

**Create**:
- `.claude/commands/dev/git.md` — new command (~150 lines)

**Modify**:
- `.claude/profiles/quality.yaml` — add `git:` block
- `.claude/profiles/fast.yaml` — add `git:` block
- `.claude/profiles/minimal.yaml` — add `git:` block
- `.claude/profiles/research.yaml` — add `git:` block
- `.claude/commands/dev/profile.md` — add git style line to
  activation output template
- `install.sh` — already copies `commands/dev/*` wildcard and
  `profiles/*`; no change needed
- `README.md` — add `/dev:git` row to Available Commands table

---

**Next Steps**:
1. Review and approve this design
2. Run `/dev:test-plan` to map stories to verification methods
3. Run `/dev:tasks` to break into implementation tasks
