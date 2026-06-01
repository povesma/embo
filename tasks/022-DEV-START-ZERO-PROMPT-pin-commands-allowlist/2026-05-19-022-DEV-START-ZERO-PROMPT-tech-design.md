# 022-DEV-START-ZERO-PROMPT: Eliminate Permission Prompts During `/dev:start` — Technical Design

**Status**: Draft
**PRD**: [2026-05-18-022-DEV-START-ZERO-PROMPT-prd.md](./2026-05-18-022-DEV-START-ZERO-PROMPT-prd.md)
**Created**: 2026-05-19

---

## Overview

Two coordinated edits eliminate harness permission prompts during
`/dev:start`:

1. **Pin** filesystem-touching command shapes in
   `.claude/commands/dev/start.md` by replacing prose
   instructions with fenced bash blocks plus a verbatim-copy
   directive, or with explicit "use the Glob tool, not Bash"
   directives for the doc/task discovery steps.
2. **Allow** the pinned command shapes in
   `~/.claude/settings.json` via a small number of exact-line
   allow rules, propagated to new installs through the existing
   `RLM_PERMS` / `$rlmPerms` blocks in both installers.

The change is additive (no removals from the allowlist, no
removals from the skill's behaviour), narrow (no broader access
than the skill needs), and reversible (each new rule deletable
without ripple).

## Current Architecture (RLM-verified)

Re-verification of every PRD claim, 2026-05-19:

- `start.md` lines 21–26 contain the Step 0 prose ("Read
  `~/.claude/active-profile.yaml` if it exists") — verified via:
  `Read .claude/commands/dev/start.md` lines 21–26, 2026-05-19.
- `start.md` lines 90–92 contain the Step 3 prose ("Docs: Glob
  …", "Tasks: Glob …", "Git: …") — verified via:
  same `Read`, 2026-05-19.
- `start.md` lines 58–67 already pin the RLM status command in a
  fenced bash block; Step 2 (lines 75–86) already pins the MCP
  search calls — verified via: same `Read`, 2026-05-19.
- The user-level allow list in `~/.claude/settings.json` contains
  the rules introduced by commit `ebd833a` plus subsequent
  additions; the existing rules cover `Bash(git log:*)`,
  `Bash(git diff:*)`, `Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)`,
  `Bash(find:*)`, `Bash(grep:*)`, `Bash(head:*)`, `Bash(git status:*)`,
  `Bash(basename:*)`, `Bash(git rev-parse:*)` — verified via:
  `jq -r '.permissions.allow[]' ~/.claude/settings.json | grep Bash`,
  2026-05-19.
- The `permissions.deny` list contains `Read(~/.ssh/*)`,
  `Read(~/.aws/*)`, `Read(~/.gnupg/*)`, `Read(~/.env*)`,
  `Read(~/.netrc)`, `Read(~/.config/gcloud/*)`,
  `Read(~/.kube/config)` — verified via: same `jq` query
  against `.permissions.deny`, 2026-05-19.
  **Important**: every deny rule is on the `Read` tool, not on
  `Bash`. A `Bash(...)` allow rule cannot conflict with these
  deny rules; only a `Read(...)` allow rule could.
- Both installers contain a working permission-injection block:
  `install.sh:132-142` (`RLM_PERMS=( ... )` with 9 entries) and
  `install.ps1:253-263` (`$rlmPerms = @( ... )` with the same
  9 entries) — verified via: `grep -n -A 12 'RLM_PERMS=' install.sh`
  and `grep -n -A 12 'rlmPerms = @' install.ps1`, 2026-05-19.
  Both have idempotent dedup logic.
- The `Bash(<token>:*)` matcher pattern performs prefix matching
  on the command's first tokens — verified via: `git log --oneline -10`
  executing without a permission prompt against the `Bash(git log:*)`
  allow rule during this session, 2026-05-19.

PRD assumptions resolved:

- **A1** ("pinning text in the skill reliably causes the model to
  copy verbatim") — not provable by code inspection alone; this
  is a model-behavior claim. Tech-design treats it as a
  **design requirement on the skill text**: the fenced block
  must contain an explicit "run this exact command — do not
  paraphrase" directive inline, so a future model has the same
  signal as the current one. Empirical proof comes from the
  PRD's 5-run cold-start success metric.
- **A2** ("chosen narrow rules do not collide with the existing
  `permissions.deny`") — **resolved**: deny rules are
  `Read(...)` only; new allow rules are `Bash(...)` only; no
  intersection possible at the tool-namespace level.
- **A3** ("Claude Code's `Bash(<verbatim line>)` matcher
  semantics behave as expected") — **resolved**: existing
  `Bash(<verbatim line>)` rules in the user's settings (e.g.
  `Bash(mkdir -p .claude/commands/dev)`) match exact lines; the
  `:*` suffix enables prefix matching. We use the exact-line
  form for the Step 0 idiom because no argument variation is
  desired or tolerated.

## Past Decisions (Claude-Mem)

- `#12291` (May 7, 2026) — precedent for narrowing
  `Bash(python3:*)` → `Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)`.
  Same narrow-over-broad discipline applies here.
- `#12299` (May 7) — installer permission-injection pattern; this
  design reuses the same `RLM_PERMS` array rather than introducing
  a new injection mechanism.
- `#12269` / `#12272` (May 6–7) — single-gate confirmation
  principle. The harness permission prompt is the only safety
  gate; pre-approving narrow shapes removes friction without
  weakening safety.

## Proposed Design

### Architecture

Two layers, both file-edits to existing files; no new code, no
new components, no new infrastructure.

**Layer 1 — Skill text (`.claude/commands/dev/start.md`)**:
the source of truth for what `/dev:start` does. Becomes
authoritative on which bash shapes the skill emits.

**Layer 2 — Allowlist (`~/.claude/settings.json` and the
installers)**: declarative permission rules. Each new rule maps
1:1 to a Layer 1 pinned shape.

The 1:1 mapping is what makes the design auditable (PRD FR-5).

### Components

**Modified components**:

1. **`.claude/commands/dev/start.md`** (lines 21–26, 90–92)
   - **Changes**: replace three prose blocks with one fenced
     bash block plus two "use the Glob tool, not Bash"
     directives. Each fenced block carries an inline directive
     "run this exact command — do not paraphrase, do not rewrite
     this shape."
   - **Rationale**: addresses PRD FR-1. The skill text becomes
     the single point of control for the shape the model emits.
   - **Risk**: low; the change preserves the skill's behaviour
     (still reads the profile, still discovers docs/tasks, still
     runs git inspection) and only constrains the command shapes
     used to do those things.

2. **`~/.claude/settings.json`** (`permissions.allow`)
   - **Changes**: add one new exact-line `Bash(...)` rule for
     the Step 0 profile-load shape. The existing `Bash(git log:*)`
     and `Bash(git diff:*)` rules already cover Step 3's git
     pair; no new git rule is added.
   - **Rationale**: addresses PRD FR-2.
   - **Risk**: low; the new rule grants no broader access than
     reading one file under `~/.claude/` and emitting a literal
     fallback string.

3. **`install.sh`** (line 132 — `RLM_PERMS` array)
   - **Changes**: append one entry to the array.
   - **Rationale**: addresses PRD FR-3.
   - **Risk**: low; existing idempotent injection handles
     duplicates.

4. **`install.ps1`** (line 253 — `$rlmPerms` array)
   - **Changes**: append the same entry to the array.
   - **Rationale**: addresses PRD FR-3 on Windows.
   - **Risk**: low; same dedup logic as install.sh.

### Data Contracts

**Skill ↔ harness** (Layer 1):

The skill text constrains the model to produce Bash invocations
matching a small whitelist of shapes. The shapes are listed in
**Pinned Shapes** below.

**Harness ↔ user** (Layer 2):

The `permissions.allow` array entries match shapes from Pinned
Shapes via the matcher semantics confirmed in
"Current Architecture" — exact-line for invariant shapes,
`<token>:*` for shapes that take varying arguments.

### Pinned Shapes (canonical)

The skill produces exactly these shapes at exactly these sites.
Any deviation is a skill-text regression, not an allowlist
problem.

| Site | Pinned shape | Match rule | Notes |
|---|---|---|---|
| Step 0 profile load | `cat ~/.claude/active-profile.yaml 2>/dev/null \|\| echo "NO_PROFILE"` | `Bash(cat ~/.claude/active-profile.yaml 2>/dev/null \|\| echo "NO_PROFILE")` — exact line, new | Reads exactly one file at a stable absolute path. Sentinel output `NO_PROFILE` is the explicit miss indicator. No other path can be substituted into this rule. |
| Step 1 RLM status | `python3 ~/.claude/rlm_scripts/rlm_repl.py status` | `Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)` — already exists | No change. |
| Step 2 claude-mem search | MCP tool calls | `mcp__plugin_claude-mem_mcp-search__search`, `mcp__plugin_claude-mem_mcp-search__get_observations` — already exist | No change. |
| Step 3 docs discovery | **Glob tool** with patterns `**/README*.md`, `**/CLAUDE*.md`, read-only | **No Bash rule needed** — Glob is a Claude Code tool, not Bash | Skill text adds a "use Glob, not Bash" directive. |
| Step 3 tasks discovery | **Glob tool** with `tasks/**/*-tasks.md`, post-filter `/archive/`, read-only | **No Bash rule needed** | Same. |
| Step 3 git log | `git log --oneline -10` | `Bash(git log:*)` — already exists | No change. |
| Step 3 git diff | `git diff --stat HEAD` | `Bash(git diff:*)` — already exists | No change. |

**Net new allowlist entries**: **one** —
`Bash(cat ~/.claude/active-profile.yaml 2>/dev/null || echo "NO_PROFILE")`.

This single new entry is what the user-level settings update and
the two installer arrays need to inject.

### Skill-Text Edits (precise)

**Edit 1 — Step 0 (replace lines 21–26)**:

Replace:
```
### Step 0: Load Profile

Read `~/.claude/active-profile.yaml` if it exists. If not present,
use defaults: rlm=true, memory_backend=claude-mem, docs_first=strict.
Note the active profile name in the session summary output.
```

With:
```
### Step 0: Load Profile

Run this exact command — do not paraphrase, do not rewrite the
shape. The skill's pre-approved permission entry matches this
line literally:

```bash
cat ~/.claude/active-profile.yaml 2>/dev/null || echo "NO_PROFILE"
```

If the output is the literal string `NO_PROFILE`, use defaults:
rlm=true, memory_backend=claude-mem, docs_first=strict. Otherwise
parse the YAML for profile fields. Note the active profile name
(or "default") in the session summary output.
```

**Edit 2 — Step 3 docs/tasks discovery (replace lines 90–91)**:

Replace:
```
- Docs: Glob `**/README*.md`, `**/CLAUDE*.md` — read top-level only
- Tasks: Glob `tasks/**/*-tasks.md` (exclude `/archive/`) — read active task files
```

With:
```
- Docs: use the **Glob tool** (not Bash, not `find`) with pattern
  `**/README*.md`, then again with `**/CLAUDE*.md`. Read the
  matched files at the project root only.
- Tasks: use the **Glob tool** (not Bash, not `find`) with pattern
  `tasks/**/*-tasks.md`. Discard matches whose path contains
  `/archive/`. Read the surviving active task files.
```

**Edit 3 — Step 3 git pair (replace line 92)**:

Replace:
```
- Git: `git log --oneline -10` and `git diff --stat HEAD`
```

With:
```
- Git: run these two commands exactly as shown. Do not change
  flags, count, or `HEAD` reference; they are pre-approved at
  these exact prefixes.

```bash
git log --oneline -10
git diff --stat HEAD
```
```

### Allowlist Entries (precise)

The single new entry, formatted for the existing array literal
syntax:

In `install.sh` (`RLM_PERMS` array, append after the last entry,
preserving the existing single-quoted string form):

```
    'Bash(cat ~/.claude/active-profile.yaml 2>/dev/null || echo "NO_PROFILE")'
```

In `install.ps1` (`$rlmPerms` array, append after the last entry,
preserving PowerShell's single-quoted string form — the embedded
double quotes are literal):

```
    'Bash(cat ~/.claude/active-profile.yaml 2>/dev/null || echo "NO_PROFILE")'
```

In `~/.claude/settings.json` (`permissions.allow`, append as a
JSON string with the embedded double quotes escaped):

```json
"Bash(cat ~/.claude/active-profile.yaml 2>/dev/null || echo \"NO_PROFILE\")"
```

### Integration Points

- **Skill text** ↔ **harness command matcher**: pre-existing,
  no new wiring. The fenced bash block makes the model emit the
  exact line; the harness sees it through its existing
  permission-check pipeline.
- **Installer** ↔ **`~/.claude/settings.json`**: pre-existing,
  no new wiring. The `RLM_PERMS` / `$rlmPerms` blocks already
  parse JSON, append missing entries, and write back atomically
  via temp-file rename.
- **Glob tool** ↔ **read access**: Glob is a Claude Code tool
  with its own permission model independent of Bash. The Glob
  tool reads filenames only (not contents) and does not require
  the same allow rules as Bash. Reading the discovered files
  uses the `Read` tool, which respects the existing
  `permissions.deny` block.

### Privacy / Secret-Exposure Boundary

Per user-stated constraint: "make sure that all kinds of
scanning in any way do not read or access the files where the
secrets of private data can be potentially stored."

The design upholds this by **positive scoping**: the skill only
ever reads from these paths:

- `~/.claude/active-profile.yaml` — explicit, single file,
  user's own profile config.
- Repo-root `README*.md` and `CLAUDE*.md` — version-controlled,
  project-public, single directory level.
- Repo-relative `tasks/**/*-tasks.md` (excluding `/archive/`) —
  version-controlled, project-public.
- Repo-root git history via `git log` and `git diff` — operates
  on tracked content only.

The skill never reads `~/.ssh/*`, `~/.aws/*`, `~/.gnupg/*`,
`~/.env*`, `~/.netrc`, `~/.config/gcloud/*`, `~/.kube/config`,
shell histories, browser profiles, keychains, or any of the
classes listed in the user's global `permissions.deny`. The
deny list remains the safety net for accidental reads (e.g. if
the model deviates from the pinned shapes and falls back to
broader Bash patterns covered by `Bash(find:*)`, the existing
deny rules still block secret-bearing paths from the `Read` tool
that would be needed to consume found contents).

The single new allow rule cannot be exploited to read other
files: the exact-line match makes `cat ~/.ssh/id_rsa 2>/dev/null
|| echo "NO_PROFILE"` not match the rule because the path
literal differs.

### Error Handling

Three failure modes considered:

1. **Profile file missing** — the `2>/dev/null || echo
   "NO_PROFILE"` idiom emits exactly `NO_PROFILE` and exits
   zero. The skill parses this sentinel and falls back to
   defaults. No prompt, no error to surface.
2. **Claude-mem worker down** — the existing MCP search calls
   fail at the MCP layer; the skill already documents
   degradation paths ("Context Quality Levels" in start.md).
   Unchanged.
3. **Glob tool unavailable** — extremely unlikely (Glob is a
   built-in Claude Code tool); skill text directs the model
   explicitly to use Glob, but if the tool is genuinely absent,
   the fallback is to skip the discovery step rather than fall
   back to Bash. Documented as a one-line note in the skill text.

### Testing Strategy

Manual end-to-end verification per PRD Success Metric 1:

1. Apply the three skill-text edits and the one allowlist entry
   to a clean checkout / clean settings.json.
2. Restart Claude Code to load the new permissions.
3. Run `/dev:start` in a fresh session; observe zero prompts.
4. Repeat the run-and-observe cycle four more times in separate
   fresh sessions for the 5-run cold-start standard.
5. Run a control command outside the allowlist (e.g.
   `cat ~/.zshrc`) and observe that the harness still prompts.

Installer idempotency verification per PRD Success Metric 2:

1. Run `bash install.sh` on a machine that already has the new
   rule installed; observe "permissions: all rules already
   present — skipping" or equivalent (the existing dedup logic
   reports per-rule additions).
2. Diff `jq -r '.permissions.allow[]' ~/.claude/settings.json
   | sort` before and after the second installer run; expect
   empty diff.

### Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|---|---|---|---|
| FR-1 (pinned skill text) | `code-only` | unit | Diff of `start.md` showing the three pinned blocks at the documented sites |
| FR-2 (allowlist covers shapes) | `manual-run-claude` | integration | A run of `/dev:start` in a fresh session produces zero harness prompts and the transcript shows the exact pinned shapes |
| FR-3 (installer injects rule) | `manual-run-user` | integration | Running `bash install.sh` on a fresh `~/.claude/settings.json` produces a settings file whose `permissions.allow` contains the new rule |
| FR-4 (output parity) | `manual-run-user` | integration | Session summary produced by `/dev:start` after the change contains the same field classes as before (profile noted, RLM stats, claude-mem history, git context, recommended task) |
| FR-5 (auditable mapping) | `code-only` | unit | The Pinned Shapes table in this tech-design (and a brief comment in `start.md`) provides the 1:1 mapping; a reviewer can locate any rule's matching skill line in <30 s |
| NFR-1 (no performance regression) | `manual-run-user` | integration | Subjective: skill completes in <30 s with no visible lag introduced by the new check |
| NFR-2 (privacy / narrow scope) | `code-only` + `manual-run-user` | unit + integration | The new rule is exact-line for one specific path; control test (`cat ~/.zshrc`) still prompts |
| NFR-3 (portability) | `manual-run-user` | integration | Same new rule appears in `install.ps1`'s `$rlmPerms`; running install.ps1 on Windows adds it to that machine's settings.json |
| NFR-4 (idempotency) | `manual-run-user` | integration | Running the installer twice produces empty diff on the second run |
| NFR-5 (reversibility) | `code-only` | unit | The change is contained to 3 edits in start.md + 1 entry in each of two installer arrays + 1 entry in user settings.json |

Methods per `/dev:test-plan` canonical list.

## Trade-offs

### Skill-text pinning vs. broader allowlist

- **Option A — Broader allowlist (rejected)**: `Bash(cat:*)`,
  `Bash(test:*)`, `Bash([ -f:*)`. Would absorb all paraphrase
  variants without touching the skill text. **Rejected**: would
  also grant read access to any file on the system, violating
  PRD NFR-2 and the user's explicit "don't access files where
  secrets may live" constraint. The deny list cannot shadow a
  Bash allow because deny rules are on the `Read` tool.
- **Option B — Skill-text pinning (chosen)**: forces one
  canonical shape per step. Narrow allow rules suffice. **Chosen**:
  preserves audit narrowness; small skill-text patch; reversible.

### Use Glob tool vs. pin a `find` command for docs/tasks

- **Option A — Pin `find` commands (rejected)**: e.g.
  `find . -maxdepth 2 -name 'README*.md' -o -name 'CLAUDE*.md'`.
  Already covered by `Bash(find:*)`, so no new rule. But
  introduces three more sites where the model could paraphrase
  (`find . -maxdepth 1 -iname …`, `find . -type f -name …`,
  etc.) and each would need its own rule.
- **Option B — Glob tool directive (chosen)**: Glob is a
  first-class Claude Code tool, does not consume Bash
  permissions at all, and its built-in matching is exactly what
  the skill wants. **Chosen**: removes three potential
  paraphrase sites from the Bash surface entirely.

### Sentinel-output vs. exit-code-only profile-miss

- **Option A — Exit-code only**: `cat ... 2>/dev/null || true`.
  No marker in output. **Rejected**: forces the model to
  inspect `$?` (which it cannot directly observe in tool output
  in the same turn) and adds an inference step.
- **Option B — `NO_PROFILE` sentinel (chosen)**: the output
  itself tells the model whether the file existed. Stable,
  cheap, unambiguous. **Chosen**.

## Implementation Constraints

From existing architecture (RLM):

- The `RLM_PERMS` array in `install.sh` uses single-quoted bash
  strings; the new entry must use the same form, escaping nothing
  inside the quotes.
- The `$rlmPerms` array in `install.ps1` uses single-quoted
  PowerShell strings (literal `'`...`'`), so the embedded
  double quotes around `NO_PROFILE` are literal characters; no
  escaping needed.
- Both installers write to settings.json via temp-file rename
  (`/tmp/_rlm_settings.tmp` → `~/.claude/settings.json`); this is
  atomic at the filesystem level.

From past experience (claude-mem):

- Per `#12291`: never use `Bash(<token>:*)` when the entire
  command's identity is known. The profile-load idiom is fully
  known, so it gets an exact-line rule, not a `:*` prefix rule.
- Per `#12299` / `#12272`: do not add new permission injection
  mechanisms when `RLM_PERMS` exists. Extend, don't replace.

## Files to Create / Modify

**Modify**:
- `.claude/commands/dev/start.md` — three edits (Step 0
  profile-load, Step 3 docs/tasks directive, Step 3 git pair).
  Net size change: small; existing line count remains close.
- `install.sh` — append one entry to `RLM_PERMS` array (line
  132–142). No logic change.
- `install.ps1` — append one entry to `$rlmPerms` array (line
  253–263). No logic change.
- `~/.claude/settings.json` — append one entry to
  `permissions.allow`. This is the user's local-effect change;
  re-running `install.sh` after the rule is added performs the
  same write idempotently.

**Create**: none.

## Dependencies

**External**: none added. The skill already requires `jq`,
`curl`, `git`, `python3`, and the claude-mem MCP server; this
change introduces no new runtime dependencies. The `cat` and
`echo` builtins are POSIX-required on every supported platform.

**Internal**: the existing `RLM_PERMS` / `$rlmPerms` injection
mechanism in both installers.

## Security Considerations

The single load-bearing safety property: the **new allow rule's
scope is one specific absolute path under `~/.claude/`**, and
the matcher's exact-line semantics make substitution impossible.
Specifically, none of these alternative invocations would match
the new rule:

- `cat ~/.ssh/id_rsa 2>/dev/null || echo "NO_PROFILE"` — different path
- `cat ~/.claude/active-profile.yaml` — missing redirect / OR
- `cat ~/.claude/active-profile.yaml; echo "NO_PROFILE"` — semicolon
- `cat ~/.claude/active-profile.yaml 2>/dev/null || echo NO_PROFILE` — missing quotes

All would still trigger a harness prompt under the existing
matcher.

The existing `permissions.deny` block continues to protect
secret-bearing paths from the `Read` tool. No `Bash(...)` rule
in this design (or any in the existing allowlist) opens a path
to those files via shell, because none of the Bash rules permit
`cat`, `head`, or `tail` on arbitrary paths — all are scoped to
specific commands or paths.

The Glob tool directives in Step 3 are bounded by their
patterns (`**/README*.md`, `**/CLAUDE*.md`, `tasks/**/*-tasks.md`)
and the project root; Glob does not return file contents, only
filenames, and reading those filenames via the `Read` tool is
itself subject to the `permissions.deny` rules (none of which
intersect with the patterns above).

## Performance Considerations

The new permission rule eliminates 1–3 harness prompt round-trips
per `/dev:start` invocation. Each prompt currently introduces a
few hundred milliseconds to several seconds of wait time
depending on user response speed. The expected change is a
strict reduction in session-start latency, not an increase.

The pinned commands themselves are unchanged from what the
skill already runs in some invocations; performance properties
are inherited from the existing fastpath.

## Rollback Plan

Rollback steps, ordered by reversibility:

1. **Revert skill text**: `git revert <commit>` on the
   `start.md` edits. The skill returns to prose instructions;
   prompts may resume.
2. **Remove allow rule from user settings**: `jq 'del(.permissions.allow[]
   | select(. == "<exact rule>"))' ~/.claude/settings.json > tmp &&
   mv tmp ~/.claude/settings.json`.
3. **Revert installer arrays**: `git revert` the install.sh and
   install.ps1 changes.

Each step is independent. There is no schema migration, no
external dependency, and no permanent state change.

## References

### Code (RLM)
- `.claude/commands/dev/start.md` — modification target.
- `install.sh:132-142` — `RLM_PERMS` injection block.
- `install.ps1:253-263` — `$rlmPerms` injection block.
- `~/.claude/settings.json` — `permissions.allow` + `permissions.deny`.

### History (Claude-Mem)
- `#13888` — `/dev:start` command-surface inventory (research).
- `#13889` — strategy plan (superseded by this design).
- `#12291` — narrow-allow-rule precedent.
- `#12299` — installer permission-injection pattern.
- `#12269` / `#12272` — single-gate confirmation rationale.

---

**Next Steps**:
1. Review and approve design.
2. Run `/dev:tasks` for task breakdown — expected ~6 leaf tasks
   in 3 stories (skill edits, installer arrays + user settings,
   verification).

---

## Addendum — 2026-05-19 (resolution)

### Harness gate model (corrected)

| Gate | Trigger | Resolution |
|---|---|---|
| Static-analyzability | `for`/`while`/`if`/`$(…)`/backticks/pipe-into-loop | Not allowlistable; avoid in skill text. |
| Command-shape | Bash command not matched by allowlist | `Bash(...)` rule, in user settings OR skill frontmatter. |
| Filesystem-access | Read of a path outside session's project root | `Read(~/...)` rule (home-relative form per docs), in user settings OR skill frontmatter. |

Stories 1–5 closed Gate 2 via global user settings. Gates 1 and 3
were closed by **moving permissions into the skill's frontmatter**
rather than adding more global rules.

### The fix

Per Claude Code permissions docs
(`code.claude.com/docs/en/skills` → "Pre-approve tools for a
skill"):

> `allowed-tools` — Tools Claude can use without asking permission
> when this skill is active.

Add YAML frontmatter at the top of `.claude/commands/dev/start.md`:

```yaml
---
description: Start a coding session with comprehensive context from RLM code analysis and claude-mem historical knowledge. Use at the beginning of each coding session.
allowed-tools: Bash(cat ~/.claude/active-profile.yaml *) Read(~/.claude/active-profile.yaml) Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py *) Bash(git log *) Bash(git diff *)
---
```

`Read(~/.claude/active-profile.yaml)` is the canonical home-relative
form per docs (`Read(/...)` is project-relative, `Read(//...)` is
filesystem-absolute, `Read(~/...)` is home-relative). The rule
clears Gate 3 for exactly the one file Step 0 reads.

### Step 3 negative directive (also adopted)

Insert at the top of Step 3 in `start.md`, before the "Docs:" bullet:

```
**Do not** use Bash loops (`for`, `while`), `find`, or `$(...)`
substitution for the discovery steps below. The harness refuses
to auto-approve those constructs. Use the **Glob tool** as
directed; if Glob is unavailable, skip the step.
```

### Why frontmatter, not global rules

- **Narrow by construction**: pre-approval is scoped to this
  skill's activation; reading the same file from another skill
  or from prose still prompts.
- **No installer logic for permissions**: shipping the skill ships
  the permissions. Fresh installs work immediately, no merging
  into user settings.json needed.
- **Reviewable in one file**: a reader of `start.md` sees both
  the command shape and its pre-approval together.

The installer entries (`Bash(cat …)`, `Read(…)`) added during
diagnosis are removed; the frontmatter supersedes them.

### Verification

| Requirement | Method | Evidence |
|---|---|---|
| FR-6 | `manual-run-user` | Fresh session: `/dev:start` Step 0 runs with no Read-gate prompt. **Confirmed** 2026-05-19. |
| FR-7 | `code-only` | `install.sh` / `install.ps1` no longer add the profile-load entries to `RLM_PERMS` / `$rlmPerms`. |
| FR-8 | `code-only` | `start.md` Step 3 contains the negative directive block before the Docs: bullet. |
