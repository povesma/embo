# 041 — Correction capture via claude-mem custom mode (proven working)

**Status**: Mechanism proven end-to-end 2026-07-15. Ships as opt-in
per-user config. Two known limitations recorded below.

This supersedes the SEED's framing ("no write path, use a local file")
and task 009's PRD assumption ("claude-mem has no write API, corrections
must go to a local `.claude/corrections.jsonl`"). Both were based on the
absence of a *manual* write tool (`save_memory`, removed). They missed
that claude-mem's **automatic observer** can be configured to emit a
custom `correction` observation type — which is the honest capture path
(an independent observer LLM behind a hook), not agent self-reporting.

## What was proven

A user correction was captured as a real, faithful, `type=correction`
observation (id 29191, project `embo`), configured entirely from a mode
file — no claude-mem source patch. Normal observation types stayed
healthy (the augmentation did not degrade general capture).

Verified claude-mem version: **13.11.0**, **worker** runtime.

### Why this is the right architecture

Honest correction capture requires an independent observer watching the
transcript — not the working agent self-reporting its own corrections
(biased, unreliable, competes with the task for attention). claude-mem
already *is* that: a hook fires, a separate observer LLM (Sonnet) reads
the session and classifies. We only needed to teach it the `correction`
type. Prior-art research (LLM-as-judge frameworks) and the claude-mem
source both confirmed this.

## Delivery: a CC command does all of it — NO manual user steps

A plugin exists to remove user actions. The setup below must NOT be a
manual guide; it is the sequence a CC command (e.g. an `/embo` setup
step) performs automatically:

1. Detect the installed claude-mem version, read its `code.json`.
2. Build `~/.claude-mem/modes/code-embo.json` from it via the jq
   program (repo: `code-embo.build.jq`).
3. Write `CLAUDE_MEM_MODES_DIR` into Claude Code's
   `~/.claude/settings.json` `env` block (the verified, in-CC channel).
4. Set `CLAUDE_MEM_MODE=code-embo` in `~/.claude-mem/settings.json`.
5. Reload the worker (stop+start so it inherits the env) and verify the
   log shows `Mode loaded: code-embo` with no fallback.

All five steps are file writes + a process reload the command can do
from within CC. The only thing that was thought to need a shell-profile
edit — the env var — is solved by step 3.

## The working recipe (what the command encodes)

1. **Custom mode file** at a user-owned, update-safe path:
   `~/.claude-mem/modes/code-embo.json`. It is byte-identical to the
   shipped `code.json` EXCEPT five surgical fields (build it
   reproducibly from `code.json` — see the jq build script shipped in
   the repo, do not hand-author):
   - `observation_types`: add a `correction` entry (id/label/description
     /emoji/work_emoji). **This is the one hard gate** — `sdk/parser.ts`
     rewrites any type not in this list to `observation_types[0]`.
   - `prompts.type_guidance`: change "EXACTLY one of these **6** options"
     → **7**, and append a `correction` bullet. (The shipped text
     forbids any type outside its hardcoded list, so a new type is inert
     without this.)
   - `prompts.recording_focus`: append a clause telling the observer to
     record corrections, AND that a correction is a SEPARATE observation
     — if the same turn also has tool activity, emit BOTH the normal
     observation and a distinct correction (else the tool activity wins
     and the correction is mislabeled `discovery`).
   - `prompts.skip_guidance`: append an exception — never skip a turn
     where the user corrected how Claude works. (Without this the
     observer returns an empty/"idle" response on the correction turn
     and the batch is silently dropped.)

2. **`CLAUDE_MEM_MODES_DIR`** env var → `~/.claude-mem/modes`. This is
   the update-survival mechanism: the worker's mode search order is
   `[CLAUDE_MEM_MODES_DIR, <cache>/modes, <cache>/../plugin/modes]` and
   it picks the first that exists. Pointing it at `~/.claude-mem/`
   (never touched by plugin updates) makes the custom mode take
   precedence over the version-pinned cache.

   **It must be a real OS env var on the worker's spawning process** —
   the worker reads `process.env` (`ModeManager.ts:17`), and its env is
   fixed from the spawner's `process.env` (`ProcessManager.ts:346-350`).
   claude-mem's own config CANNOT carry it: its `settings.json` drops
   unknown keys and never writes to env; its `.env` is a 5-key
   credential whitelist.

   **Automatable from within CC (no shell-profile edit):** put it in
   **Claude Code's** own `~/.claude/settings.json` `env` block. CC
   injects that block into the processes it spawns, including
   claude-mem's hooks, which spawn the worker — so it becomes a real OS
   env var on the spawner. VERIFIED LIVE: `CONTEXT_GUARD_THRESHOLD`
   (embo-only, set in CC's env block) is present in the running
   worker's process environment (`ps eww <pid>`). This is the mechanism
   the setup command uses.

3. **`CLAUDE_MEM_MODE=code-embo`** in `~/.claude-mem/settings.json`.

4. **Worker must be fully stopped + started** after the env var is set
   (not `restart` — a running/daemon-restarted worker keeps its stale
   environment and silently falls back to `code`). A fresh session that
   spawns the worker with the env var present is the normal trigger.

### Verify it loaded (not fell back)

Worker log shows `Mode loaded: code-embo` with NO preceding
`Mode file not found ... falling back to 'code'` line. If the fallback
line appears, the env var did not reach the worker process — check
`ps eww <worker-pid> | grep CLAUDE_MEM_MODES_DIR`.

## Known limitations

1. **The `type="correction"` SEARCH FILTER is broken in 13.11.0.**
   `search(type="correction")` returns nothing even though the row
   exists — the MCP `search` tool's `type` parameter has a hardcoded
   allowlist that drops unknown types. BUT plain-text/semantic search
   finds the observation fine (it appears with its correction icon).
   **Consequence for `/embo:improve`**: it must retrieve corrections via
   free-text query (e.g. searching for correction-like content), NOT via
   the `type=` filter. Do not build improve on the type filter.

2. **A correction must arrive as its own fresh top-level user prompt.**
   The observer only sees the user's words via `<user_request>`, which
   is populated only at the session-init boundary (a fresh prompt).
   A correction bundled mid-turn or not delivered as a new prompt is
   invisible to the observer. In practice corrections usually are fresh
   prompts, so this is acceptable.

3. **Global + cross-project.** `CLAUDE_MEM_MODE` and the env var are
   machine-wide; switching to `code-embo` changes capture for every repo
   on the machine (adds the correction type everywhere). This is why it
   ships as documented opt-in, not bundled plugin config.

## Update-survival — PLANNED, NOT YET VERIFIED

The design *should* survive claude-mem plugin updates because
`CLAUDE_MEM_MODES_DIR` points outside the version-pinned cache and is
first in the search order. This is REASONED from source, not observed.

**Test to run when claude-mem next updates:**
1. Note current version. Confirm capture works (create a correction,
   see a `type=correction` row).
2. Update claude-mem (`/plugin` update + `/reload-plugins`).
3. WITHOUT re-editing anything: open a fresh session, confirm the worker
   log still shows `Mode loaded: code-embo` (no fallback), and that a
   new correction is still captured.
4. If it fell back: the new version changed the mode search order or the
   env var handling — re-investigate `worker-service.cjs` mode
   resolution. Record the version that broke it.

Note: a claude-mem update ships a new `code.json`. `code-embo.json` is a
COPY of an older `code.json` plus our 5 fields, so after an update it may
drift from the new shipped prompts. The jq build script must be re-run
against the NEW `code.json` to re-augment from the current base. This is
a maintenance step to document for users.

## Evidence

- Correction observation id 29191, `type=correction`, project `embo`,
  title "No Time Estimates for Tasks" — faithful capture of a real
  user correction given during the 2026-07-15 session. [live]
- Worker log: `Response received {promptNumber=...} <observation>` →
  `STORING obsCount=1` on the correction turn (skip exception worked).
- Regression: same session's other observations correctly typed
  `discovery`/`change`/`feature` (augmentation did not break normal
  capture).
- `search(type="correction")` → empty; free-text search → finds 29191
  (search-filter limitation, item 1 above). [live]
