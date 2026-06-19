# 032: Package embo as a Claude Code Plugin — PRD

**Status**: Draft
**Created**: 2026-06-17
**JIRA**: N/A (internal task 032)
**Author**: Claude (via dev workflow analysis)

---

## Context

embo is distributed today as files the user copies into `~/.claude/`
(`cp .claude/rlm_scripts/...`, `cp .claude/agents/...`,
`cp -r .claude/commands/dev ...`). Claude Code now has a first-class
plugin system (manifest + marketplace + `/plugin install`) that bundles
commands, agents, hooks, and MCP config and installs them in one step
with versioning. Packaging embo as a plugin replaces the manual copy
flow with a single `/plugin install` while keeping provenance and
update control.

### Current State (observed)

- 15 command files under `.claude/commands/dev/` (flat plus a
  `research/` subdir: `examine.md`, `verify.md`) — verified via: `find
  .claude/commands -name '*.md'`, 2026-06-17. All leaf filenames are
  unique, so flattening to a single namespace has no collisions.
- 4 agents in `.claude/agents/`: `rlm-subcall`, `examine-advisor`,
  `approach-validator`, `visual-qa-reviewer` — verified via: `ls
  .claude/agents/`, 2026-06-17.
- The 5 test subagents (`test-backend`, `test-review`,
  `test-e2e-planner`, `test-e2e-generator`, `test-e2e-healer`) are
  documented in `CLAUDE.md` but are NOT present in this repo's
  `.claude/agents/` — verified via: `ls .claude/agents/`, 2026-06-17.
  They currently exist only in the user's `~/.claude/agents/`.
- 11 files reference home-rooted paths (`~/.claude/...` or
  `/.claude/rlm_scripts`): 10 command files plus
  `.claude/hooks/approve-compound.sh` — verified via: `grep -rl
  '~/.claude\|/.claude/rlm_scripts' .claude/commands .claude/hooks`,
  2026-06-17.
- Hooks present: `approve-compound.sh`, `embo-capture.sh`,
  `behavioral-reminder.sh`, `context-guard.sh` (each with a `.test.sh`)
  — verified via: `ls .claude/hooks/`, 2026-06-17.
- RLM REPL writes per-repo state to the project's `.claude/rlm_state/`
  and is invoked from the user's CWD — verified via: `CLAUDE.md`
  architecture section + `rlm_repl.py status` output showing
  `State file: .claude/rlm_state/state.pkl`, 2026-06-17.
- claude-mem is consumed as MCP tools and is declared MANDATORY —
  verified via: `CLAUDE.md` "Claude-Mem Integration (MANDATORY)",
  2026-06-17.

### Plugin system facts (verified against live Anthropic docs, 2026-06-17)

Source: `code.claude.com/docs/en/plugins.md`,
`plugins-reference.md`, `plugin-marketplaces.md`,
`discover-plugins.md`.

- Manifest is `.claude-plugin/plugin.json`; `name` is the only required
  field. `.claude-plugin/` holds ONLY the manifest — `commands/`,
  `agents/`, `hooks/`, etc. live at the plugin root.
- Commands are namespaced as `/<plugin-name>:<command>`.
- Hook command strings reference bundled scripts via
  `${CLAUDE_PLUGIN_ROOT}`; scripts must be executable.
- Persistent per-plugin data dir is `${CLAUDE_PLUGIN_DATA}`.
- Marketplace file is `.claude-plugin/marketplace.json`; each entry
  needs `name` + `source` (e.g. `{type: github, repo: "owner/repo"}`).
- Users install with `/plugin marketplace add <repo>` then
  `/plugin install <name>@<marketplace>`.
- Plugins **cannot** override the main statusline (only
  `subagentStatusLine`) and **cannot** force user permissions.
- `plugin.json` has NO `dependencies` field (corrected in
  tech-design, 2026-06-18); cross-plugin requirements are not declared
  in the manifest.

### Past Similar Features (from claude-mem)

No prior plugin-packaging PRD exists in project memory; the closest
lineage is the install-flow documentation in tasks 011 (command
rename/flatten) and 017 (README onboarding), which already grappled
with command naming and the cp-install instructions.

## Problem Statement

**Who**: New and existing embo users, and the maintainer.
**What**: Installing embo means manually copying multiple files/dirs
into `~/.claude/`, with no versioning, no update path, and easy drift
between the repo and what's installed.
**Why**: High onboarding friction, silent version skew, and no clean
upgrade story. The plugin system solves all three but embo's current
layout and its reliance on user-level statusline + permissions don't
map one-to-one onto it.
**When**: Every install and every update.

## Goals

### Primary Goal

Make embo installable and updatable as a Claude Code plugin via
`/plugin install embo@embo` from a public GitHub marketplace, while
keeping the existing manual (cp) install working as a standalone
fallback.

### Secondary Goals

- Flatten the command namespace to `/embo:*` (decision below).
- Bundle the test subagents so `/embo:impl`'s testing works out of box.
- Preserve embo's ability to develop itself (self-dogfooding) after the
  repo is restructured to plugin layout.
- Document, honestly, the two things a plugin cannot do for the user
  (statusline install, permission allowlist) as manual steps.

## User Stories

### Epic

As an embo user, I want to install and update embo as a Claude Code
plugin, so that onboarding is one command and upgrades are versioned.

### User Stories

1. **As a** new user
   **I want** to add a marketplace and install embo in two commands
   **So that** I get all commands, agents, and hooks without manual
   copying.

   **Acceptance Criteria**:
   - [ ] `/plugin marketplace add povesma/embo` registers the
     marketplace from `.claude-plugin/marketplace.json`.
   - [ ] `/plugin install embo@embo` installs all commands, agents, and
     hooks.
   - [ ] After install, embo commands appear as `/embo:start`,
     `/embo:impl`, etc.
   - [ ] `claude plugin validate` passes on the repo (strict).

2. **As a** plugin user running a command
   **I want** hooks and the RLM script to resolve their own bundled
   paths
   **So that** capture/approve and RLM analysis work without
   home-rooted paths.

   **Acceptance Criteria**:
   - [ ] Hook command strings use `${CLAUDE_PLUGIN_ROOT}` and the
     wrapper produces the `[embo-capture]` marker in a plugin install.
   - [ ] Commands invoke the RLM script via `${CLAUDE_PLUGIN_ROOT}`;
     RLM state still writes to the project's `.claude/rlm_state/`.
   - [ ] No command or hook references `~/.claude/...` after migration.

3. **As a** plugin user
   **I want** the test subagents available
   **So that** `/embo:impl`'s test steps run without extra setup.

   **Acceptance Criteria**:
   - [ ] The 5 test subagents are present in the repo's `agents/` and
     ship with the plugin.
   - [ ] `/embo:impl` references them by name and they resolve.

4. **As an** existing user on the cp-install
   **I want** the manual install to keep working
   **So that** I'm not stranded mid-upgrade.

   **Acceptance Criteria**:
   - [ ] README documents BOTH the plugin install and the manual
     (standalone) install, each complete on its own.
   - [ ] The manual steps install the same component set the plugin
     does (per the Documentation Rule in CLAUDE.md).

5. **As the** maintainer
   **I want** embo to still develop itself after restructuring
   **So that** dogfooding (using embo's own commands/hooks while
   working in this repo) survives the move out of `.claude/`.

   **Acceptance Criteria**:
   - [ ] Working in the embo repo, the embo commands/hooks are active
     (via project-local config pointing at the new plugin-root layout,
     or equivalent).
   - [ ] The mechanism is documented so a contributor can reproduce it.

## Requirements

### Functional Requirements

1. **FR-1 — Plugin manifest**: Add `.claude-plugin/plugin.json` naming
   the plugin `embo`, with version, description, author, repository,
   license. NOTE: `plugin.json` has no `dependencies` field (verified
   in tech-design); the MANDATORY claude-mem relationship is enforced
   by a runtime check in the commands, not the manifest.
   - **Priority**: High
   - **Rationale**: Required for the plugin to load at all.
   - **Dependencies**: none.

2. **FR-2 — Marketplace file**: Add `.claude-plugin/marketplace.json`
   with one entry for embo sourced from this GitHub repo.
   - **Priority**: High
   - **Rationale**: Enables `/plugin marketplace add povesma/embo`.

3. **FR-3 — Repo restructure to plugin layout**: Move `commands/`,
   `agents/`, `hooks/`, `rlm_scripts/`, `profiles/`, `statusline.sh`
   from `.claude/` to the plugin root, per the plugin spec (only the
   manifest lives under `.claude-plugin/`).
   - **Priority**: High
   - **Rationale**: Plugin spec requires component dirs at root.
   - **Dependencies**: FR-9 (dogfooding must survive the move).

4. **FR-4 — Flatten command namespace to `/embo:*`**: Collapse the
   `dev:` and `research:` grouping segments; all 15 commands become
   `/embo:<leaf>` (`/embo:start`, `/embo:impl`, `/embo:examine`,
   `/embo:verify`, …). Rewrite every cross-reference inside command
   bodies, agents, and docs.
   - **Priority**: High
   - **Rationale**: Decision below; leaf names verified collision-free.
   - **Dependencies**: FR-3.

5. **FR-5 — Hook + script path rewrite**: Replace all home-rooted
   path references with `${CLAUDE_PLUGIN_ROOT}`-relative paths in hook
   configs and in commands that shell out to the RLM script. Scope
   includes the 11 grep-counted command/hook files PLUS the inter-hook
   reference at `.claude/hooks/approve-compound.sh:219`
   (`EMBO_CAPTURE_CMD` default), which is not in the 11 and is the most
   functionally critical path. Fix: default `EMBO_CAPTURE_CMD` to
   `${CLAUDE_PLUGIN_ROOT}/hooks/embo-capture.sh`, keeping the
   `~/.claude/...` value as a secondary fallback for manual installs —
   verified via: `grep -n embo-capture
   .claude/hooks/approve-compound.sh`, 2026-06-17.
   - **Priority**: High
   - **Rationale**: Home paths don't exist for plugin installs; the
     inter-hook reference fails capture silently if missed.
   - **Dependencies**: FR-3.

5b. **FR-5b — Hook registration migration**: The active hooks
   (`context-guard.sh`, `behavioral-reminder.sh`, `approve-compound.sh`)
   are currently REGISTERED as PreToolUse/etc. entries in the user-level
   `~/.claude/settings.json` with hard-coded `bash ~/.claude/hooks/...`
   commands — separate from rewriting paths inside the scripts (FR-5).
   The plugin must declare these registrations in its own
   `hooks/hooks.json`, AND the migration must include a one-time manual
   step for existing users to REMOVE the old `~/.claude/settings.json`
   entries, or hooks fire twice (old registration + plugin) or break.
   `embo-capture.sh` is a helper invoked by `approve-compound.sh`, NOT a
   registered event handler — it ships in `hooks/` but must not be
   declared as a hook, or it fires twice.
   - **Priority**: High (Critical)
   - **Rationale**: Without this, the `[embo-capture]` marker contract
     (a "cannot change" constraint) breaks on plugin install.
   - **Dependencies**: FR-3.

6. **FR-6 — RLM state stays project-local**: The RLM script ships in
   the plugin; its per-repo index/state continues to write to the
   project's `.claude/rlm_state/` (not `${CLAUDE_PLUGIN_DATA}`), so each
   repo keeps its own index.
   - **Priority**: High
   - **Rationale**: Per-repo indexing is the existing, correct behavior.

6b. **FR-6b — Profile read-path in plugin install**: `/embo:start` and
   `/embo:profile` read/write `~/.claude/active-profile.yaml` and
   `~/.claude/profiles/` (home-rooted). The PRD must state where
   profiles live for a plugin install: keep them user-managed under
   `~/.claude/` (documented as outside plugin scope), or relocate to
   `${CLAUDE_PLUGIN_DATA}/` and have commands check both. Leaving the
   path home-rooted without a decision fails the NFR path-hygiene
   metric. Default decision (override in tech-design): **keep profiles
   user-managed under `~/.claude/`**, documented as a user-owned config
   the plugin reads but does not install — verified via: `grep -n
   active-profile .claude/commands/dev/start.md`, 2026-06-17.
   - **Priority**: High (Critical)
   - **Rationale**: Load-bearing path wrongly treated as settled; both
     install paths must know where profiles live.
   - **Dependencies**: FR-3, FR-4.

7. **FR-7 — Bundle test subagents**: Source the 5 test subagents into
   the repo's `agents/` so they ship with the plugin.
   - **Priority**: Medium
   - **Rationale**: `/embo:impl` testing breaks for plugin users
     without them. [assumption: the canonical text of these agents is
     recoverable from `~/.claude/agents/` or upstream; verify in
     tech-design]

8. **FR-8 — Permissions: document + graceful degrade**: The
   capture/approve hooks must function without allowlist entries (more
   approval prompts, no failure); the README documents the exact
   allowlist entries a user adds for zero-prompt operation. The plugin
   does not write user permissions.
   - **Priority**: High
   - **Rationale**: Plugins cannot force permissions; honesty about the
     limit beats silent breakage.

9. **FR-9 — Preserve self-dogfooding**: Provide a documented mechanism
   (e.g. project-local `.claude/settings.json` referencing the new
   plugin-root layout, or equivalent) so that working in the embo repo
   keeps embo's own commands and hooks active after FR-3.
   - **Priority**: High
   - **Rationale**: The repo develops itself; losing that slows all
     future embo work. [assumption: exact mechanism chosen in
     tech-design]

10. **FR-10 — Dual install docs**: README and TROUBLESHOOTING document
    both the plugin install and a complete standalone (manual) install,
    each sufficient on its own.
    - **Priority**: High
    - **Rationale**: User decision to keep both; CLAUDE.md Documentation
      Rule requires manual equivalents for any automation.

11. **FR-11 — Statusline manual step**: Since plugins can't set the
    main statusline, the README instructs users to copy `statusline.sh`
    (and wire it) manually; the file still ships in the plugin.
    - **Priority**: Medium
    - **Rationale**: Plugin spec constraint, verified.

### Non-Functional Requirements

1. **NFR-1 — Compatibility**: `claude plugin validate --strict` passes;
   plugin loads on Claude Code v2.1.128+ (the `/plugin` command
   floor).
2. **NFR-2 — No behavior regression**: Every command's documented
   behavior is unchanged except its invocation name.
3. **NFR-3 — Zero secrets in repo**: No user-specific paths, tokens, or
   private data introduced by the restructure (Sanitization pass).

### Technical Constraints

- Must integrate with: claude-mem (MANDATORY, enforced by runtime
  check — NOT a manifest dependency; MCP tools unchanged), the existing
  capture/approve hook contract.
- Should follow patterns: plugin spec dir layout
  (`${CLAUDE_PLUGIN_ROOT}`, `.claude-plugin/`).
- Cannot change: per-repo RLM state location; claude-mem MANDATORY
  posture; the `[embo-capture]` marker contract.
- Cannot do: ship a main statusline, or force user permissions.

## Out of Scope

- Submitting embo to the Anthropic community directory (separate
  follow-up after the GitHub marketplace works).
- Migrating claude-mem tooling from the worker runtime to server-beta
  (already tracked separately in CLAUDE.md).
- Any new command features or behavior changes beyond renaming.
- Building 030-HOOK-HEALTH's statusline indicator (separate task; this
  PRD only relocates `statusline.sh`).

## Success Metrics

1. Install path: `/plugin marketplace add povesma/embo` +
   `/plugin install embo@embo` yields a working embo — target: 2
   commands, 0 manual file copies (statusline + permissions excepted
   and documented).
2. Validation: `claude plugin validate --strict` — target: 0 errors.
3. Path hygiene: home-rooted path references in commands/hooks —
   target: 0.
4. Parity: manual install installs the same component set as the plugin
   — target: 100% of commands/agents/hooks.

## References

### From Codebase (RLM / direct inspection)

- Commands: `.claude/commands/dev/**` (15 files, leaf names unique).
- Agents: `.claude/agents/` (4 present; 5 test agents to be sourced).
- Hooks: `.claude/hooks/` (`approve-compound.sh`, `embo-capture.sh`,
  `behavioral-reminder.sh`, `context-guard.sh`).
- Home-path references: 11 files (grep result, 2026-06-17).
- RLM state: project-local `.claude/rlm_state/state.pkl`.

### From History (Claude-Mem)

- Command naming/flatten lineage: task 011.
- Onboarding/install docs lineage: task 017.
- Recent hook work that the path rewrite must not break: tasks 029,
  030 (capture/approve, pipeline decomposition).

## Decisions (made during requirements gathering, 2026-06-17)

- **Namespace**: flatten to `/embo:*` (drop `dev:`/`research:`
  grouping). Leaf names verified collision-free.
- **Distribution**: public GitHub marketplace on `povesma/embo`;
  community-directory submission deferred.
- **Permissions**: document + graceful degrade (FR-8).
- **RLM**: script in plugin, state project-local (FR-6).
- **Test agents**: bundle in the plugin (FR-7).
- **Transition**: restructure repo to plugin layout AND keep the
  standalone manual install working (FR-3, FR-10).
- **claude-mem dependency**: claude-mem is a trusted plugin the user
  installs separately. CORRECTION (2026-06-18): `plugin.json` has no
  `dependencies` field, so there is no manifest declaration; the
  MANDATORY relationship is enforced by a runtime check in commands
  (graceful-degrade). FR-1 updated accordingly.

### Examine pass (internal, 2026-06-17)

An internal `examine-advisor` pass against the codebase found three
Critical gaps the first draft treated as settled; all three are now
addressed:
- Hook REGISTRATION lives in user `~/.claude/settings.json`, not just
  in script paths → **FR-5b** added.
- `approve-compound.sh:219` inter-hook path is outside the 11 counted
  files → folded into **FR-5** scope.
- Profile read-path was unaddressed → **FR-6b** added.

Confirmed sound by the pass: flatten to `/embo:*`, public GitHub
marketplace, dual install, RLM script-in-plugin/state-project-local,
and that FR-7/FR-8/FR-9 are the right deferred assumptions.

---

**Next Steps**:
1. Review and refine this PRD.
2. Run `/dev:tech-design` to resolve the open assumptions: exact
   self-dogfooding mechanism (FR-9), source of canonical test-agent
   text (FR-7), and the precise allowlist entries to document (FR-8).
3. Run `/dev:tasks` to break down into tasks.
