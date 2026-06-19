# 032: Package embo as a Claude Code Plugin — Technical Design

**Status**: Draft
**PRD**: [2026-06-17-032-PLUGIN-PACKAGING-prd.md](./2026-06-17-032-PLUGIN-PACKAGING-prd.md)
**Created**: 2026-06-18
**Branch**: `feature/032-plugin-packaging`

## Overview

Repackage embo as a Claude Code plugin distributed from a public
GitHub marketplace (`povesma/embo`), while keeping the manual (cp)
install working. The work is mostly mechanical relocation + path
rewriting, with one genuine engineering problem: the capture/approve
hook can become **registered more than once** on a machine (old manual
install + plugin, or + repo dogfood), and Claude Code's behavior when
two PreToolUse hooks return conflicting command rewrites is
**undocumented**. The design prevents double-registration with a
required migration/doctor script (`fix-hooks.sh`) rather than trying to
survive it.

## Current Architecture (RLM-verified)

All claims re-verified on this branch, 2026-06-18.

- **Commands**: 15 files under `.claude/commands/dev/` — `check`, `git`,
  `health`, `impl`, `improve`, `init`, `prd`, `profile`, `start`,
  `tasks`, `tech-design`, `test-plan`, `visual-impl`, plus
  `research/examine` and `research/verify`. Leaf names all unique —
  verified via: `find .claude/commands -name '*.md'`, 2026-06-18.
- **Agents in repo**: `rlm-subcall`, `examine-advisor`,
  `approach-validator`, `visual-qa-reviewer` — verified via: `ls
  .claude/agents/`, 2026-06-18.
- **Test agents (FR-7 source RESOLVED)**: all 5 (`test-backend`,
  `test-review`, `test-e2e-planner`, `test-e2e-generator`,
  `test-e2e-healer`) exist in `~/.claude/agents/` — verified via: `ls
  ~/.claude/agents/`, 2026-06-18. They are the canonical source to copy
  into the repo's `agents/`.
- **Hooks (scripts)**: `approve-compound.sh`, `embo-capture.sh`,
  `behavioral-reminder.sh`, `context-guard.sh` (+ `.test.sh` each) in
  `.claude/hooks/` — verified via: `ls .claude/hooks/`, 2026-06-18.
- **Hook REGISTRATION today**: NOT in the repo. `.claude/settings.json`
  does not exist; `.claude/settings.local.json` holds only
  `permissions` entries (no `hooks` block) — verified via: `ls -la
  .claude/settings.*` + `grep hooks .claude/settings.local.json`,
  2026-06-18. The active hooks fire solely from the maintainer's
  user-level `~/.claude/settings.json`; repo scripts are EDITED here but
  EXECUTED from `~/.claude/`.
- **Inter-hook path**: `approve-compound.sh:219` defaults
  `EMBO_CAPTURE_CMD` to `~/.claude/hooks/embo-capture.sh` (already
  overridable via env) — verified via: `grep -n embo-capture
  .claude/hooks/approve-compound.sh`, 2026-06-18.
- **Re-entrancy guard**: `approve-compound.sh` lines 261, 332, 424 skip
  any command already containing the `embo-capture.sh ` token — verified
  via: file read, 2026-06-18.
- **Profile paths**: command files read BOTH `~/.claude/profiles/`
  (user) and `.claude/profiles/` (project), and the active pointer is
  `~/.claude/active-profile.yaml` — verified via: `grep -n
  active-profile\|profiles/ .claude/commands/dev/{start,profile}.md`,
  2026-06-18.
- **RLM state**: project-local `.claude/rlm_state/state.pkl` — verified
  via: `rlm_repl.py status`, 2026-06-17.

## Verified External Facts (Claude Code plugin system)

Source: `code.claude.com/docs/en/{plugins,plugins-reference,hooks,settings}.md`,
verified via claude-code-guide agent, 2026-06-17/18.

- Manifest: `.claude-plugin/plugin.json`; `.claude-plugin/` holds ONLY
  the manifest; components (`commands/`, `agents/`, `hooks/`, `.mcp.json`,
  `settings.json`) live at the plugin ROOT.
- Path vars: `${CLAUDE_PLUGIN_ROOT}` (install dir), `${CLAUDE_PLUGIN_DATA}`
  (persistent per-plugin data), `${CLAUDE_PROJECT_DIR}` (repo root; works
  in project `.claude/settings.json` hook commands too).
- Marketplace: `.claude-plugin/marketplace.json`; entry needs `name` +
  `source` (`{type:github, repo:"povesma/embo"}`).
- Install: `/plugin marketplace add povesma/embo` then
  `/plugin install embo@embo`.
- Hook precedence (highest→lowest): managed → plugin → project →
  local → user. Hooks are **additive/merged**, not last-wins.
  Deduplication applies ONLY to **byte-identical** command strings.
- Plugins CANNOT set the main statusline (only `subagentStatusLine`)
  and CANNOT force user permissions.
- **`plugin.json` has NO `dependencies` field.** Verified against the
  authoritative on-disk Anthropic references: the manifest-reference
  complete field list AND the advanced-plugin enterprise example (the
  fullest manifest Anthropic ships) both enumerate every field —
  name, version, description, author, homepage, repository, license,
  keywords, commands, agents, hooks, mcpServers — and neither includes
  `dependencies`. An earlier claim that plugins declare `dependencies`
  was WRONG and is retracted. claude-mem (a trusted plugin the user
  installs separately) is therefore NOT expressed as a manifest
  dependency; the MANDATORY relationship is enforced at RUNTIME — embo
  commands already fail with a clear error if the claude-mem MCP tools
  are absent (graceful-degrade, same pattern as permissions). Verified
  via on-disk plugin-dev references, 2026-06-18.
- **Command prefix is mandatory and non-configurable.** A plugin's
  commands are ALWAYS invoked as `/<plugin-name>:<command>`; there is no
  unprefixed mode. The prefix is taken from the `name` field in
  `plugin.json` — the SOLE authority (marketplace entry name and
  directory name do not affect it; if they differ, the manifest wins).
  Naming the plugin `embo` therefore forces `/embo:*` — not a choice.
  (Built-in bundled skills like `/code-review` carry no prefix; those
  are NOT plugins and are not a counter-example.) Verified via
  claude-code-guide vs docs, 2026-06-18.
- **Command subdirectories DO create typeable colon-namespaces —
  VERIFIED LIVE 2026-06-19.** `commands/research/examine.md` registers
  as **`/embo:research:examine`** (a typeable invocation, not just a
  `/help` label). Confirmed by installing the plugin with the subdir
  restored and reading the registered skill list: both research
  commands appeared as `embo:research:examine` / `embo:research:verify`,
  and `claude plugin validate --strict` accepted the subdir.
  **Decision: KEEP `commands/research/{examine,verify}.md`** — the
  `research:` grouping is preserved (user preference + it has real
  meaning). This OVERTURNS two earlier wrong positions, both now
  retracted: (1) the docs-agent's "nested is NOT discovered (loader
  error)" claim, and (2) the fallback "flatten because nested is
  unverified." The live install is the authority. History note:
  flattened in story 6, restored after the live test in this session.
  Resolved via: live plugin reinstall + skill-list inspection,
  2026-06-18.

### Critical gap (verified, load-bearing)

**Two parallel PreToolUse hooks that each return a DIFFERENT
`updatedInput.command` for the same call → resolution is UNDOCUMENTED.**
Confirmed via claude-code-guide (docs specify only byte-identical
dedup; say nothing about conflicting rewrites, sequential vs parallel
application, or which command runs). Empirical simulation against the
real hook (`final_command` called twice with different
`EMBO_CAPTURE_CMD`):

- Both registrations independently wrap the ORIGINAL command → two
  rewrites differing only in wrapper path (same base64 payload).
- IF Claude applies hooks sequentially, the re-entrancy guard catches
  the second wrap (`final_command(A_OUT) == A_OUT`, no double-wrap).
- IF Claude applies them independently/parallel, the guard never sees
  the first rewrite → two conflicting `updatedInput` with undefined
  outcome.

**Design consequence**: we do not know, and cannot promise, what
happens. Therefore double-registration is **prevented**, not tolerated.
The re-entrancy guard is retained as defense-in-depth only.

## Proposed Design

### Component layout (FR-3: move into a `plugin/` subdir)

**Decision (2026-06-18, during impl 1.2): the plugin lives in a
`plugin/` SUBDIR, not at the repo root.** Every Anthropic marketplace
example nests each plugin under its own subdir
(`source:"./plugins/<name>"`, manifest at
`<subdir>/.claude-plugin/plugin.json`); NO example uses `source:"."`
for a root-level plugin. Mirroring the proven layout avoids gambling on
undocumented root-plugin behavior. The repo is a single-plugin
marketplace, so one subdir named `plugin/` (cleaner than
`plugins/embo/` for a single plugin).

```
povesma/embo/  (marketplace repo)
├── .claude-plugin/
│   └── marketplace.json     # one entry, source: "./plugin"
├── plugin/                  # THE PLUGIN ROOT (${CLAUDE_PLUGIN_ROOT})
│   ├── .claude-plugin/
│   │   └── plugin.json      # name:"embo" (NO deps field; see facts)
│   ├── commands/            # 12 flat .md + research/ subdir.
│   │   └── research/        # examine.md, verify.md →
│   │                        # /embo:research:examine, :verify
│   │                        # (nested namespace VERIFIED live)
│   ├── agents/              # 4 existing (5 test agents deferred → 033)
│   ├── hooks/
│   │   ├── hooks.json       # registers the 3 event handlers (FR-5b)
│   │   ├── approve-compound.sh
│   │   ├── embo-capture.sh  # helper, NOT registered
│   │   ├── behavioral-reminder.sh
│   │   ├── context-guard.sh
│   │   ├── fix-hooks.sh     # NEW: doctor/migration (FR-5b)
│   │   └── *.test.sh
│   ├── rlm_scripts/rlm_repl.py
│   ├── profiles/*.yaml
│   └── statusline.sh        # ships, manual install (FR-11)
├── .claude/
│   └── settings.local.json  # repo's own permissions (dogfood, unchanged)
├── tasks/                   # task docs (NOT part of the plugin)
└── README.md, TROUBLESHOOTING.md, CLAUDE.md
```

`.claude/commands`, `.claude/agents`, `.claude/hooks`,
`.claude/rlm_scripts`, `.claude/profiles`, `.claude/statusline.sh` are
moved into `plugin/`; `git mv` preserves history. NOTE: `${CLAUDE_PLUGIN_ROOT}`
resolves to the installed `plugin/` dir, so all hook/RLM path rewrites
(FR-5) point at `${CLAUDE_PLUGIN_ROOT}/hooks/...` etc. — the subdir
nesting does not change those references (the var already abstracts the
root).

### FR-4: namespace → `/embo:*`, with `research/` subdir KEPT

**The `research/` subdir is RETAINED — verified live (see fact above).**
Nested command dirs create typeable colon-namespaces, so
`commands/research/{examine,verify}.md` give **`/embo:research:examine`**
and **`/embo:research:verify`**, preserving the `research:` grouping
(user preference, 2026-06-19). All other commands are flat at
`commands/*.md`.

- `commands/research/examine.md` → `/embo:research:examine`;
  `commands/research/verify.md` → `/embo:research:verify`. Every other
  command is `commands/<name>.md` → `/embo:<name>`.
- The `/embo:` prefix itself is forced by the plugin `name` (verified
  above) — unavoidable. The `research:` segment comes from the subdir.
- Every internal cross-reference `/dev:<x>` → `/embo:<x>` across command
  bodies, agent files, README, TROUBLESHOOTING, CLAUDE.md. Note
  `research:examine` / `research:verify` references become
  `/embo:examine` / `/embo:verify` (the `research:` segment is dropped,
  not renamed).
- **Acceptance gate**: `grep -rn '/dev:' commands/ agents/ *.md` returns
  0 hits post-migration (excluding historical task docs under `tasks/`).

### FR-5 + FR-5b: hooks (the core problem)

**Path rewrite (FR-5)** — in every hook command string and any command
that shells out to RLM, replace home-rooted paths with plugin-root:
- `approve-compound.sh:219`: default `EMBO_CAPTURE_CMD` to
  `${CLAUDE_PLUGIN_ROOT}/hooks/embo-capture.sh`, **falling back** to
  `~/.claude/hooks/embo-capture.sh` when `CLAUDE_PLUGIN_ROOT` is unset
  (manual install). Shape:
  `EMBO_CAPTURE_CMD="${EMBO_CAPTURE_CMD:-${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/embo-capture.sh}"`.
- Commands invoking `~/.claude/rlm_scripts/rlm_repl.py` → **REVISED
  2026-06-19, see below.** Originally rewritten to the inline
  `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/rlm_scripts/rlm_repl.py` form.

**FR-5 REVISION (2026-06-19) — `bin/rlm_repl` wrapper for RLM, NOT inline
`${...}`.** The live install test (story 8) proved the inline form is
unusable: `/embo:init`'s first RLM call halted at a **"Contains
expansion" approval dialog**. Verified via claude-code-guide vs docs:
Claude Code's Bash tool applies a **lexical gate** — any command string
containing `${...}`/`$(...)`/backticks prompts BEFORE the allowlist is
consulted, and **no `permissions` rule can suppress it**. So the inline
form prompts on every RLM-backed command (init/prd/impl/check/…), not
once.

Fix (the officially-documented pattern): ship an executable wrapper at
`plugin/bin/rlm_repl`. A plugin's `bin/` is added to the Bash tool PATH
while enabled, so commands invoke a **bare `rlm_repl …`** — no
expansion in the command string, so no prompt, and a simple
`Bash(rlm_repl *)` rule matches. The wrapper resolves `rlm_repl.py`
relative to its own (symlink-followed) location and does NOT change CWD,
so RLM state stays project-local. This matches the profile's
"allow-listable invocation" rule. Verified live: wrapper runs via
symlink-on-PATH from any CWD, state stays project-local, and
`/embo:init` completes with no prompt on a real project.

- All 13 RLM command invocations now use bare `rlm_repl`.
- `start.md` `allowed-tools` updated to `Bash(rlm_repl *)`.
- Manual install: ship the wrapper to `~/.claude/bin/`, documented as a
  one-line PATH addition (story 7).

The HOOK path rewrite (`approve-compound.sh:219`, still inline `${...}`)
is UNAFFECTED: hooks are invoked by Claude Code's hook runner, not the
Bash tool, so they never hit the expansion gate.

**Executable-bit requirement (2026-06-19, surfaced by story 8):** all
shipped hook scripts AND the `bin/` wrapper MUST be executable
(`chmod +x`). The live install failed with exit 126 because the moved
`embo-capture.sh` lacked the `x` bit (it had only ever been invoked via
`bash X`, which masks the requirement; `approve-compound.sh` invokes it
directly via `$EMBO_CAPTURE_CMD`, which needs `+x`). Fixed on:
approve-compound.sh, embo-capture.sh, behavioral-reminder.sh,
context-guard.sh, fix-hooks.sh, bin/rlm_repl, rlm_scripts/rlm_repl.py.
`.test.sh` files stay non-executable (run via `bash X`).

**Registration (FR-5b)** — the plugin's `hooks/hooks.json` registers the
THREE event handlers (`context-guard.sh`, `behavioral-reminder.sh`,
`approve-compound.sh`) via `${CLAUDE_PLUGIN_ROOT}`. `embo-capture.sh` is
a subprocess helper invoked by `approve-compound.sh` — it ships in
`hooks/` but is NOT declared as a handler (declaring it would register a
second wrapper and re-create the double-fire).

**Double-registration prevention (`fix-hooks.sh`, NEW)** — a doctor +
migration script. Required because conflict resolution is undocumented.

Responsibilities:
1. Read the settings hierarchy that can register embo hooks: user
   `~/.claude/settings.json` and project `.claude/settings.json`
   (managed/plugin are not user-editable; plugin registration is the
   intended one).
2. Detect every registration whose command references an embo hook
   script (match on the stable `approve-compound.sh` /
   `behavioral-reminder.sh` / `context-guard.sh` tokens, any path).
3. Report: list each registration with its source file and resolved
   path; flag when ≥2 sources register the same handler.
4. Offer removal **with explicit per-entry consent**: remove the stale
   manual entry (`~/.claude/...`) so only the plugin registration
   remains. Never edit without confirmation; never touch managed/plugin
   config; back up the file before editing.

**Implementation notes (verified via approach-validator, 2026-06-18 —
all 5 acceptance criteria proven):**
- **Edit pattern**: `cp` to `.bak` → write new JSON to a temp file →
  `mv` temp over the original. `mv` on the same filesystem is an atomic
  POSIX rename (no partial-write window); the `.bak` survives if the
  `mv` is never reached. Recoverable.
- **Detect filter**: use `any(.hooks[]; .command? | strings |
  contains(TOKEN))`, NOT the bare `.hooks[].command | contains(TOKEN)`.
  A hook entry may carry only an `if` field (v2.1.85+) with no
  `command`; the bare form errors on the null. The `.command? | strings`
  guard handles it (verified on a synthetic sample).
- **Token matching** on the bare script filename (`approve-compound.sh`)
  matches all path forms equally (`~/.claude/...`, absolute,
  `${CLAUDE_PLUGIN_ROOT}/...`) — same precedent the re-entrancy guard
  uses (`approve-compound.sh:261,332,424`).
- **jq guard**: jq is an existing hard dependency of embo (already used
  in `approve-compound.sh`), so it is present — but `fix-hooks.sh`
  opens with `command -v jq` and a clear error + nonzero exit, so the
  impossible-case failure is legible rather than cryptic.
- **Schema shape confirmed**: `.hooks.<EventName>[]`, each element
  `{matcher, hooks:[{type, command, [if], [args]}]}` (Context7 / live
  docs).

**Removal scope (decided 2026-06-18 via live test):** `--fix` removes
ALL stale `~/.claude` embo hook registrations, not only the duplicated
ones. Rationale: once the plugin is installed it registers all three
handlers via `${CLAUDE_PLUGIN_ROOT}`, so EVERY `~/.claude` copy is
stale — a single-registered tilde entry would become a duplicate the
moment the plugin loads. Removing them all is the correct migration.
(The report wording is "stale embo registrations", not merely
"duplicates".)

**Stale manual-install command/agent files (advisory only):** beyond
settings registrations, an old cp-install leaves `~/.claude/commands/dev/`
and embo agent files in `~/.claude/agents/`. The plugin now supplies
these as `/embo:*`, so the old `/dev:*` copies are stale and would
shadow/duplicate. `fix-hooks.sh` DETECTS their presence and PRINTS the
exact removal command for the user to run — it does NOT auto-`rm` user
files (the safety rules forbid casual `rm`; deleting directories of
files is riskier than a consented jq edit of one settings file). Advise,
don't delete.

Serves both migration cases with one tool:
- **Case A** (existing user adopts plugin): strip the old
  `~/.claude/settings.json` entries + advise removing old `/dev:*`
  command/agent files.
- **Case B** (maintainer wants repo dogfood): strip the global entry so
  the project registration is the only one in-repo.

### FR-6 / FR-6b: RLM state + profiles

- **RLM state** stays project-local (`.claude/rlm_state/`); only the
  *script* moves into the plugin. No change to indexing behavior.
- **Profiles** remain user-managed under `~/.claude/` (active pointer
  `~/.claude/active-profile.yaml`, definitions `~/.claude/profiles/`).
  The plugin reads them but does not install them. Command read-paths
  already check both user and project scope, so no command logic change
  is required; only docs state this is user-owned config. This keeps the
  profile pointer out of plugin scope by design (NFR path-hygiene
  applies to commands/hooks, not to user-owned config the plugin reads).

### FR-9: self-dogfooding — default OFF

Mechanism EXISTS (project `.claude/settings.json` + `${CLAUDE_PROJECT_DIR}`,
verified). **Default decision: do NOT commit project hook registrations.**
Rationale: the maintainer already holds a working global install;
committing a project registration manufactures the exact undocumented
double-fire collision (Case B). Contributors get hooks by installing
embo (documented). If dogfood-by-project-settings is desired later, it
is gated behind running `fix-hooks.sh` to remove the global entry first.

### Data contracts

- **Hook I/O** (unchanged): PreToolUse receives
  `{tool_name, tool_input.command, cwd}`; returns
  `{hookSpecificOutput:{permissionDecision, updatedInput?}}`. The
  `[embo-capture]` marker contract on stdout is preserved.
- **`fix-hooks.sh` exit codes**: 0 = single/clean registration, no
  action; 1 = duplicates found (report only, no `--fix`); 2 =
  duplicates removed (with `--fix` + consent). Non-destructive by
  default; `--fix` flag required to modify, per-entry `y/N` prompt.

## Trade-offs

**Hook double-fire — considered approaches:**

1. **Rely on the re-entrancy guard** — REJECTED. Only works if Claude
   applies hooks sequentially, which is undocumented. Building core
   infra on undefined harness behavior is unacceptable.
2. **Detect double-fire from inside the hook** — REJECTED. The hook
   sees only its own invocation, not the registration set; detection
   would be timing-based and unreliable (parallel execution).
3. **Prevent double-registration with `fix-hooks.sh` (CHOSEN)** —
   deterministic (reads settings files directly), serves both migration
   cases, and is a troubleshooting tool we want regardless. Guard kept
   as defense-in-depth.

**Repo layout — full move (CHOSEN) vs point plugin.json at `.claude/`:**
Full move matches the spec exactly, makes `${CLAUDE_PLUGIN_ROOT}` paths
natural, and keeps manual-install docs honest (they reference the same
root layout the plugin uses). The larger diff is one-time; `git mv`
preserves history.

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1 manifest | auto-test | unit | `claude plugin validate --strict` → 0 errors |
| FR-2 marketplace | manual-run-user | integration | `/plugin marketplace add povesma/embo` lists embo |
| FR-3 layout | code-only | — | components at root; `.claude-plugin/` has only manifests |
| FR-4 flatten | auto-test | unit | `grep -rn '/dev:' commands/ agents/ *.md` → 0 |
| FR-5 paths | auto-test | unit | `grep -rn '~/.claude' commands/ hooks/` → 0; existing `approve-compound.test.sh` passes with `CLAUDE_PLUGIN_ROOT` set and unset |
| FR-5b registration | manual-run-claude | integration | plugin install → one `[embo-capture]` marker per command (not two) |
| FR-5b fix-hooks | auto-test | unit | new `fix-hooks.test.sh`: seeded dup → exit 1; `--fix` + consent → exit 2, file cleaned; single → exit 0 |
| FR-6 RLM state | manual-run-claude | integration | state still written to project `.claude/rlm_state/` |
| FR-6b profiles | code-only | — | commands read `~/.claude` profile; no plugin-scoped profile path introduced |
| FR-7 test agents | code-only | — | 5 test agents present in `agents/` |
| FR-8 permissions | manual-run-claude | integration | hooks run without allowlist (more prompts, no failure); README lists exact entries |
| FR-9 dogfood | code-only | — | no `hooks` block committed in `.claude/settings.json` |
| FR-10 dual docs | code-only | — | README has complete plugin AND manual install, same component set |
| FR-11 statusline | code-only | — | `statusline.sh` ships; README documents manual copy |

## Files to Create / Modify

**Create**:
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- `hooks/fix-hooks.sh` + `hooks/fix-hooks.test.sh`
- `hooks/hooks.json`

**Move (`git mv`, then rewrite contents)**:
- `.claude/commands/dev/**` → `commands/*.md` (FLATTEN, no subdirs;
  `research/examine.md`→`examine.md`, `research/verify.md`→`verify.md`;
  rewrite `/dev:` and `research:` refs)
- `.claude/agents/*` → `agents/*`
- `.claude/hooks/*` → `hooks/*` (rewrite paths in `approve-compound.sh`)
- `.claude/rlm_scripts/`, `.claude/profiles/`, `.claude/statusline.sh` → root
- bring 5 test agents from `~/.claude/agents/` into `agents/`

**Modify**:
- commands that call `~/.claude/rlm_scripts/...` → `${CLAUDE_PLUGIN_ROOT}` + fallback
- `README.md`, `TROUBLESHOOTING.md`, `CLAUDE.md` (dual install; 11→15 count; `/embo:` names)

## Dependencies

- **External**: claude-mem (MANDATORY; user installs separately —
  NOT a manifest dependency, enforced by runtime check; unchanged tool
  usage).
- **Internal**: existing hook test harnesses (`*.test.sh`) — reused to
  prove path-rewrite didn't regress behavior.

## Security Considerations

- `fix-hooks.sh` edits the user's `~/.claude/settings.json` only with
  `--fix` + explicit per-entry consent, and backs up first. It never
  reads or writes any other user config. (Aligns with the global rule
  against touching user config without permission — here the script asks
  at runtime.)
- No secrets enter the repo. Sanitization pass: the only host-specific
  strings in this design are the maintainer's absolute paths in verified
  evidence lines — replace with `<home>` placeholders before
  `Status: Complete` (the repo name `povesma/embo` is public).

## Rollback Plan

- The migration is additive to git history (branch
  `feature/032-plugin-packaging`); revert = drop the branch.
- For an end user mid-migration: the manual install path remains fully
  functional, so a failed plugin install leaves them on the working cp
  flow. `fix-hooks.sh` backs up settings before editing.

## Open Items for `/dev:tasks`

1. Exact `plugin.json` / `marketplace.json` field values (name, version
   seed, author).
2. `fix-hooks.sh` settings-parse approach (jq read of `~/.claude/settings.json`;
   match heuristic on hook-script tokens).
3. Sequencing: move-and-rewrite before or after authoring `hooks.json`
   (tasks-level ordering).

## References

### Code (verified)
- `.claude/hooks/approve-compound.sh:219` (EMBO_CAPTURE_CMD default),
  lines 261/332/424 (re-entrancy guard), 402-406 / 435-438 (wrap +
  updatedInput emission).
- `.claude/commands/dev/start.md:3,33`, `profile.md:26-27,56-57`
  (profile paths).

### History (claude-mem)
- Hook lineage to not regress: #19624 (filter detection), #21756
  (pipeline decomposition), #18446 (configurable EMBO_CAPTURE_CMD).
- Naming/flatten lineage: task 011. Onboarding docs: task 017.

---

**Next Steps**:
1. Review and approve this design.
2. Run `/dev:tasks` for task breakdown.
