# 034: Verify the Windows PowerShell install/uninstall scripts — Handoff

**Status**: Scripts written on macOS, UNVERIFIED. Needs a Windows CC
session to test and fix.
**Origin**: split from the install.sh/uninstall.sh work (commits
1e89087, bbcaa3c on `feature/032-plugin-packaging`), 2026-06-21.
**Why a handoff**: the scripts were authored on macOS, which has no
PowerShell, so they could not be run, syntax-checked, or tested. Per
the project's "assume it does not work until proven" rule, treat them
as broken until this task proves otherwise.

## What was built (and why)

Goal: Windows users get the SAME capability as macOS/Linux — a scripted
dependency installer and a scripted standalone install/uninstall — not
just manual doc steps. The macOS/Linux side ships `install.sh` (two
modes) and `uninstall.sh`, both verified end-to-end by `install.test.sh`
(39 assertions, all passing in a sandbox HOME).

The Windows equivalents:

- **`install.ps1`** — PowerShell parity with `install.sh`.
  - Default mode: dependency installer. Checks Python 3.8–3.12 and
    Node 20+ (report-only — prints the `winget` command, never installs
    a language runtime). Offers to install jq (winget), uv
    (`irm https://astral.sh/uv/install.ps1 | iex`), and bun
    (`irm bun.sh/install.ps1 | iex` — the irm script, NOT winget, which
    has an open PATH bug oven-sh/bun#20868). Also checks bash.
  - `-Standalone`: deps + copy `plugin/` into `~/.claude/` under the
    `/embo:*` namespace; register the 3 real hooks with literal
    `bash ~/.claude/hooks/*.sh` paths; set statusLine; add permissions.
    Skips hook registration if bash is absent (a registered `.sh` hook
    with no bash silently drops prompts in Claude Code).
  - Flags: `-Standalone`, `-Force` (non-interactive, default no),
    `-Yes` (with `-Force`, accept all).
  - Edits settings.json with native `ConvertFrom-Json -AsHashtable` /
    `ConvertTo-Json -Depth 100` — NO jq used by the script itself.
- **`uninstall.ps1`** — PowerShell parity with `uninstall.sh`. Removes a
  manual install of EITHER era (current `/embo:*` and pre-plugin
  `/dev:*`), strips only embo-specific settings.json entries (3 hooks,
  statusLine, `Bash(rlm_repl *)` + pre-plugin
  `Bash(python3 ~/.claude/rlm_scripts/rlm_repl.py:*)` + embo-capture
  permission), keeps non-embo hooks, profiles, active-profile.yaml, and
  generic permissions. Backs up settings.json first. Per-file confirm.
  NOT for the plugin — that is `/plugin uninstall embo@embo`.

## Hard requirement discovered

**PowerShell 7+ (`pwsh`) is REQUIRED.** Both scripts use
`ConvertFrom-Json -AsHashtable`, which does NOT exist in Windows
PowerShell 5.1 (the default `powershell.exe`). On 5.1 they will error
immediately. REFERENCE.md documents this; run with
`pwsh -ExecutionPolicy Bypass -File .\install.ps1`. Decide in this task:
either (a) keep the pwsh-7 requirement and document it clearly (current
choice), or (b) rewrite the JSON handling to be 5.1-compatible (avoid
`-AsHashtable`, use PSCustomObject + Add-Member). Option (a) is simpler;
(b) reaches more machines.

## PowerShell risks to check FIRST (static review never ran)

A static review was started but cancelled. Check these specific
PowerShell pitfalls before/while testing — each is a plausible bug:

1. **`ConvertTo-Json -Depth`** — default is 2 and SILENTLY truncates
   nested objects to type-name strings. Both scripts use `-Depth 100`;
   confirm every `ConvertTo-Json` call has it. A truncated settings.json
   is the highest-impact failure.
2. **Single-element array collapsing** — `$x = @(... | Where-Object)`
   can unwrap a 1-element result to a scalar. CRITICAL for
   `hooks.<event>`: Claude Code expects a JSON ARRAY. Verify that after
   round-trip, `hooks.UserPromptSubmit` with ONE entry still serializes
   as `[ {...} ]`, not `{...}`. Check the `+= @{...}` appends in
   install.ps1 and the `Where-Object` filters in uninstall.ps1.
3. **Modifying a hashtable while iterating** — uninstall.ps1 does
   `foreach ($event in @($s['hooks'].Keys)) { ... .Remove($event) }`.
   Confirm the `@(...)` snapshot prevents "collection was modified".
4. **`-AsHashtable` on PS 5.1** — see hard requirement above.
5. **Dotted member access on -AsHashtable output** — `$g.hooks`,
   `$h.command` on hashtables. In PS, `$hashtable.key` works as member
   access; confirm it behaves on the nested structures.
6. **`Test-Cmd` WindowsApps stub rejection** — kept from the old
   install.ps1; verify it still rejects the MS Store python/node stubs.

## Test plan (mirror install.test.sh, in PowerShell)

Run all against a THROWAWAY profile dir, never the real `~/.claude`.
Override the target by setting `$env:USERPROFILE` to a temp dir before
invoking, the same way install.test.sh overrides `HOME`.

1. **Deps mode** — `install.ps1 -Force` on a machine with everything
   present: reports all five found, exit 0, makes no changes.
2. **Standalone install** — `install.ps1 -Standalone -Force -Yes` into a
   temp profile: assert `bin\rlm_repl` + `rlm_scripts\rlm_repl.py` are
   siblings; `commands\embo\start.md` and `commands\embo\research` exist;
   3 agents; settings.json has the 3 hooks registered with `bash ~/...`
   paths (NOT `${CLAUDE_PLUGIN_ROOT}`, NOT embo-capture/fix-hooks as
   hooks), statusLine set, `Bash(rlm_repl *)` in permissions; and
   `hooks.UserPromptSubmit` is a JSON ARRAY.
3. **Pre-plugin uninstall** — build a fake pre-plugin profile
   (`commands\dev\`, old rlm_repl.py, embo hooks + a NON-embo hook, old
   `Bash(python3 ...rlm_repl.py:*)` permission, generic permissions, a
   non-embo Read permission), run `uninstall.ps1 -Force -Yes`: assert all
   embo files/entries gone, non-embo hook + profiles + active-profile +
   generic permissions KEPT, backup created.
4. **Round-trip** — `uninstall.ps1` on the standalone install from step
   2 cleans back to kept profiles + generic permissions.
5. Consider writing `install.ps1.test.ps1` (Pester or plain) as the
   Windows analogue of `install.test.sh`, so this is repeatable.

## Files

- `install.ps1`, `uninstall.ps1` (repo root) — the scripts to verify.
- `install.sh`, `uninstall.sh`, `install.test.sh` (repo root) — the
  VERIFIED bash reference; the .ps1 must produce the same end state.
- `docs/REFERENCE.md` §Windows — user-facing docs (already updated;
  re-check accuracy after fixing the scripts).

## Done when

- Both `.ps1` scripts run on Windows (pwsh 7) and produce a profile tree
  + settings.json byte-equivalent in MEANING to the bash versions.
- A repeatable Windows test exists and passes.
- `install.test.sh`-style verification is documented as passing.
- Mark `[X]` only after a real Windows run, not after reading the code.
