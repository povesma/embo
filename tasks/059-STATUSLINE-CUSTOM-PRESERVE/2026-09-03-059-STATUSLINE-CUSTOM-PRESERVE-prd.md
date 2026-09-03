# 059: Preserve a user's custom statusline from auto-refresh — PRD

**Status**: Approved for Plan A implementation (2026-09-03).
**Origin**: surfaced this session while reviewing `statusline-refresh.sh`
during `/embo:init` dogfooding.

## Problem

The `plugin/hooks/statusline-refresh.sh` SessionStart hook keeps the
installed statusline current: on every session start it compares the
plugin's bundled `statusline.sh` against the installed copy at
`~/.claude/statusline.sh` and re-copies when they differ (hook source
lines 36–40). This is correct for a standard user — the stable-path
copy would otherwise go stale after a plugin update and never refresh.

But the hook has no way to tell a *stale* copy from an *intentionally
customized* one. A user who edits `~/.claude/statusline.sh` loses those
edits at the next session start: the hook sees a difference and
overwrites. There is no opt-out. The hook prints
`[embo] Refreshed ~/.claude/statusline.sh from the updated plugin.`
when it acts, but session-start output is easy to miss, so in practice
the loss is silent to the user.

Two audiences with opposite needs:

- **Standard user** (installed via `/plugin install`, never customized):
  wants the auto-refresh — zero effort, always current.
- **Custom-statusline user**: wants their edits to survive session
  restarts.

Today the hook serves only the first. This task adds a mechanism so it
serves both.

## Goals

1. A standard user keeps automatic refresh with no action required.
2. A user who customizes the statusline can protect their copy with a
   single, discoverable action and no terminal command.
3. The mechanism is deterministic (the hook decides from
   machine-readable state, not from a human noticing a message).

## Non-goals

- Merging plugin updates into a customized file (three-way merge) — out
  of scope; a protected file simply stops receiving updates.
- Changing how the statusline is installed or where it lives.

## Chosen approach — Plan A: in-file sentinel line

The bundled `statusline.sh` carries a marker line in its header:

```bash
# embo:auto-refresh — remove this line if you customize this file, to stop embo overwriting it on update
```

The refresh hook gains one guard: **before overwriting, it checks
whether the installed copy still contains the `embo:auto-refresh`
token. If the token is absent, the hook skips the overwrite.**

- A fresh install ships with the token present → auto-refresh works as
  today.
- A user who customizes the file removes the marker line (the line
  tells them to) → the hook never touches their file again.
- To opt back into updates: re-add the marker line, or delete the file
  and re-run `install.sh --statusline-only`.

### Why the sentinel-line wording matters

The line does double duty: the `embo:auto-refresh` token is what the
hook matches (machine-readable, stable), and the trailing prose is the
human instruction. Keeping both on one line means a user editing the
header sees the instruction exactly where the actionable token lives.

### Diff/compare subtlety (implementation note)

The hook compares bundled vs installed with `cmp -s`. Because the
bundled file now contains the marker line and a protected file will
have removed it, the two differ by at least that line — which is fine:
the token-absence check runs first and short-circuits the overwrite for
protected files. For unprotected files (token present), a genuine
plugin update still differs elsewhere and refreshes normally. No change
to the `cmp` logic is required; the token check is an added early-exit.

### Failure mode (accepted)

A user who edits the statusline but does not remove the marker line
still gets overwritten. This is the cost of a human-attention signal.
The marker text is placed in the header where an editor is most likely
to see it, which mitigates but does not eliminate the risk. Accepted
because the alternative (a terminal marker-file command) adds friction
for every custom user, and the automatic-detection alternative below is
recorded but not yet built.

## Alternative ideas (recorded, NOT implemented)

### Option A — detect a source/dogfood install via `.git`

When embo is installed from a local directory (dogfood/dev), the hook's
`CLAUDE_PLUGIN_ROOT` points inside the developer's working tree, which
is a git checkout. The hook could test for a `.git` directory at or
above `CLAUDE_PLUGIN_ROOT` and skip the refresh automatically when
found — a developer working on embo never wants their in-repo
`statusline.sh` overwritten, and standard GitHub-plugin installs have no
`.git` in the plugin cache path.

- **Pro:** zero user action; correct inference for the developer case;
  no false positives for standard installs.
- **Con:** protects only the *dogfood developer*, not an end user who
  customized a normal install — so it complements Plan A rather than
  replacing it. Needs verification that the plugin cache path
  (`~/.claude/plugins/cache/embo/...`) truly has no `.git`, and that
  `CLAUDE_PLUGIN_ROOT` resolves to the working tree for a directory-
  source install.
- **Status:** idea only; implement in a follow-up if the dogfood-
  overwrite case proves painful.

### Option C — Claude Code settings toggle

A `settings.json` / `settings.local.json` key (e.g.
`"emboStatuslineRefresh": false`) the hook reads with `jq`. Settable
from the CC UI without a terminal. Rejected for now as heavier than the
sentinel line for the same outcome; revisit if a broader embo settings
namespace is introduced.

## Acceptance criteria

1. Bundled `plugin/statusline.sh` contains the `embo:auto-refresh`
   marker line in its header.
2. `statusline-refresh.sh` skips the overwrite when the installed
   `~/.claude/statusline.sh` does not contain the `embo:auto-refresh`
   token.
3. When the token IS present and the files differ, the hook still
   refreshes (existing behavior preserved).
4. Hook still fails open: any error path exits 0, never blocks the
   session.
5. The behavior is covered by the hook's test script
   (`fix-hooks.sh` tests or an equivalent), including the token-absent
   skip case.

## Related

- `plugin/hooks/statusline-refresh.sh` — the hook being modified.
- `plugin/statusline.sh` — the bundled source that gains the marker.
- Task 035 (plugin update awareness) — adjacent but distinct: 035 is
  "is a newer version available upstream?"; this task is "don't clobber
  my local edits."
- Tasks 008 / 020 — statusline content and freshness indicator; neither
  covers overwrite protection.
