# 037: Migrate embo commands to claude-mem server runtime — PRD

**Status**: Draft
**Created**: 2026-07-02

---

## Problem

embo commands use `CLAUDE_MEM_RUNTIME=worker` tools (`search`,
`get_observations`, `timeline`). The claude-mem plugin now exposes a
`server-beta` runtime (`CLAUDE_MEM_RUNTIME=server`) with a REST backend
(`/v1/*`) and a new tool family (`observation_search`, `observation_context`,
`observation_add`, `memory_add`).

CLAUDE.md deferred this migration until server-beta reaches GA
— verified via: `CLAUDE.md:77–88`, 2026-07-02. The deferral trigger
("when server-beta leaves beta") is now met: the update arrived
2026-07-02 and the tools are present and loadable.

Two concrete gaps caused by staying on worker:

1. **No write path** — `observation_add` / `memory_add` require server
   runtime and fail with `"requires CLAUDE_MEM_RUNTIME=server"` on
   worker. This blocks the `/embo:wrapup` session observation step and
   any future command that needs to persist a memory.
   — verified via: live `observation_add` call, 2026-07-02

2. **No projectId-scoped memory** — server runtime enables centralized
   memory shared across developers and agents via `projectId`. Worker
   runtime is per-user only.

## Scope

**1. Verify server runtime stability** (blocks everything else)
- Set `CLAUDE_MEM_RUNTIME=server` and confirm `observation_search`,
  `observation_context`, `observation_add` work end-to-end
- Confirm existing worker-runtime reads (`search` → `observation_search`,
  `get_observations` → `observation_context`) produce equivalent results
- If server-beta is still unstable or the tool mapping is incomplete,
  stop here and record findings — do not migrate

**2. Migrate read tools in all commands**

Tool mapping (worker → server):

| Worker tool | Server tool |
|---|---|
| `search(query, project, limit)` | `observation_search(query, projectId, limit)` |
| `get_observations(ids)` | `observation_context(query, projectId)` |

Affected commands (all use `search` or `get_observations`):
`start.md`, `impl.md`, `prd.md`, `tech-design.md`, `tasks.md`,
`check.md`, `improve.md`, `init.md`
— verified via: `grep -r "mcp__plugin_claude-mem_mcp-search__search" plugin/commands/`, 2026-07-02
[exact file list to confirm in tech-design]

**3. Add write capability to `/embo:wrapup`**
- Re-add the session observation step using `observation_add`
- This was removed from `wrapup.md` because it required server runtime
  — migration unblocks it

**4. Set `CLAUDE_MEM_RUNTIME=server` in project/user env**
- Add to `~/.claude/settings.json` `env` block
- Update `CLAUDE.md` runtime section to reflect GA status

## Constraints (verified)

- Worker tools (`search`, `get_observations`) refuse to load under
  server runtime — verified via tool description: "worker-mode memory
  access" — confirmed 2026-07-02
- Server tools (`observation_search`, `observation_context`,
  `observation_add`) refuse under worker runtime — verified via live
  call 2026-07-02
- `observation_context` is a single-call replacement for the current
  two-step `search` + `get_observations` pattern — [assumption, verify
  in tech-design]
- `projectId` scoping: server runtime requires a project ID; current
  commands pass `project` (a string name). Mapping needs verification
  — [assumption, verify in tech-design]

## Out of Scope

- Migrating the statusline (`cmem_segment` in `statusline.sh`) — that
  uses a separate REST path; covered separately if needed
- Changing memory content or observation format
- Rollback tooling — if server runtime proves unstable, revert by
  removing the env var

## Success Metrics

- All commands that currently use `search` produce equivalent results
  via `observation_search` — verified by running `/embo:start` and
  comparing session summaries before and after
- `observation_add` succeeds in `/embo:wrapup` after migration
- No command produces a "wrong runtime" error after migration

---

**Next**: `/embo:tech-design` — verify server runtime stability and
confirm the exact tool mapping before touching any command file.
