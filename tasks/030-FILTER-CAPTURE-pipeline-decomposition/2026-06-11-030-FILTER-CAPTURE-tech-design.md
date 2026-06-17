# 030-FILTER-CAPTURE: Filter-Triggered Pipeline Capture - Technical Design

**Status**: Draft
**PRD**: [../../bash-output-capture-problem-map.md](../../bash-output-capture-problem-map.md)
(problem map; "Chosen direction: filter-triggered capture" section)
**Created**: 2026-06-11

## Overview

When the model filters Bash output (`cmd | head`, `| grep`, ...), the
filter is an explicit signal that more output exists than is wanted
inline. The hook rewrites such pipelines so the upstream's FULL output
is captured to a file before the filter runs. The model gets: the
filtered view inline, both true exit codes, and a marker pointing at
the full capture — so a wrong filter guess never forces a re-run (P4)
and a failing upstream is never masked by the filter's exit code (P2).

100% coverage is a non-goal. Commands that resist safe decomposition
fall through unwrapped, by design.

## Current Architecture (verified 2026-06-11)

- `~/.claude/hooks/approve-compound.sh` — PreToolUse hook.
  - `decide()` (line 182): per-segment allowlist check → allow / deny /
    fallthrough.
  - `should_wrap()` (line 258): wrap eligibility — re-entrancy guard,
    no redirects, no unsafe constructs, no backgrounding `&`, no
    dangling operators, no interactive heads per segment.
  - Main (line 310): on allow, eligible commands are rewritten to
    `embo-capture.sh --b64 <b64>` via `updatedInput`.
  - `CAPTURE_NOWRAP_HEADS` (line 223): interactive/sudo heads.
- `~/.claude/hooks/embo-capture.sh` — wrapper. Runs
  `bash -c "$CMD" >"$LOG" 2>&1` (stdout+stderr MERGED, line 40),
  preserves exit code, inline iff ≤10 lines and ≤300 bytes, else
  5-line preview + marker `[embo-capture] truncated — N lines, M
  bytes. Full output: <path> (exit=<code>)`.
- Repo copies under `.claude/hooks/` with test suites
  (`approve-compound.test.sh`: 112 cases; `embo-capture.test.sh`: 33
  cases). `./install.sh` syncs to `~/.claude/`.
- Claude Code Bash tool runs commands as `bash -c -l` (login shell,
  non-interactive, not a TTY); natively persists output >30k chars
  before any PostToolUse hook fires.

## Verified External Facts (NotebookLM review, 2026-06-11)

- `permissionDecision: "allow"` + `updatedInput` is fully documented;
  for Bash only the `command` field is applied.
- Rewritten input is re-evaluated against deny and ask rules — the
  wrapper allow-rule `Bash(~/.claude/hooks/embo-capture.sh *)` must
  stay in place.
- Only ONE hook may return `updatedInput` (last-write-wins race).
- PostToolUse `updatedToolOutput` is silently ignored for Bash
  (GitHub #54196, #65403) — PreToolUse rewrite is the only viable
  capture path.
- pipefail/SIGPIPE behavior of the Bash tool is undocumented; standard
  bash defaults apply (pipefail off).

## Proposed Design

### Detection (approve-compound.sh)

New function `split_filter_tail <command>`. Applied on the allow path
only, after `decide()` returns allow and before the existing
`should_wrap` rewrite:

1. **Scope guard**: the command must be a pure pipeline — contains `|`
   but no top-level `&&`, `;`, `||`. Mixed compounds keep today's
   whole-compound wrap (no decomposition). Quote-unaware split stays
   fail-safe: ambiguous parses → no decomposition, fall back to
   whole-compound wrap.
2. Split on `|`. Walk segments from the END. A segment belongs to the
   filter tail iff its normalized head is in `FILTER_HEADS` AND it has
   none of the per-head opt-outs (below).
3. The filter tail is the maximal trailing run of filter segments; the
   upstream is everything before it. Upstream must be non-empty and
   pass the existing `should_wrap` eligibility (minus the
   single-command restriction: upstream may itself contain `|`).
4. If no filter tail → existing behavior unchanged.

```
FILTER_HEADS="head tail grep sed awk cut wc sort uniq jq tr column"
```

Per-head opt-outs (segment present in tail position but NOT treated as
filter → no decomposition):
- `tail -f` / `tail -F` — non-terminating consumer
- `grep -q` — purpose is exit-code-only early exit; decomposition
  changes cost semantics
- `sed -i` — side effect, not a filter
- any filter segment containing a redirect — fail-safe

Upstream exclusions (inherited + new): existing `should_wrap` opt-outs
(redirects, `$(...)`, backticks, heredocs, `&`, interactive/sudo
heads) plus streaming producers relying on consumer termination:
heads `watch`, `journalctl` with `-f`, `tail -f` as upstream, `yes`.
List lives next to `CAPTURE_NOWRAP_HEADS`.

### Rewrite shape

```
embo-capture.sh --filter-b64 <b64(filter-chain)> --b64 <b64(upstream)>
```

The filter chain is re-joined with `|` exactly as written (e.g.
`grep -A2 image | head -40`). The existing re-entrancy guard
(`*embo-capture.sh *`) already prevents double-wrapping.

### Execution (embo-capture.sh, new `--filter-b64` mode)

1. Decode both payloads. Existing `--b64`-only invocation is untouched
   (backward compatible).
2. Run upstream: `bash -c "$UP" >"$LOG" 2>"$LOG.err"` — stdout and
   stderr SEPARATED (in a real pipe, stderr bypasses the filter;
   merging would let the filter eat error text). Record `EU=$?`.
3. Run filter on captured stdout only:
   `bash -c "$FILTER" <"$LOG"` → stdout inline. Record `EF=$?`.
4. Emit `"$LOG.err"` content to stderr (capped at PREVIEW_LINES lines
   + pointer if larger).
5. Always print the marker (filter mode = always more data exists):

```
[embo-capture] filtered view — full output: <path>
  (<N> lines, <M> bytes, upstream exit=<EU>, filter exit=<EF>)
```

6. Exit with `EF` — matches native pipe semantics (pipefail off). The
   upstream's true code is carried by the marker; the shipped rule
   tells the model to trust the marker.

### Accepted semantic differences (by design)

- **SIGPIPE early-exit lost**: upstream always runs to completion.
  Mitigated by the upstream exclusion list; residual risk (expensive
  but terminating producers run longer) is accepted. The Bash tool's
  own timeout (default 2 min) is the backstop. A wrapper-side
  `timeout`/max-bytes cap is a follow-up, not v1 (`timeout` is not
  portable to stock macOS).
- **Sequential, not concurrent**: added latency + full-output disk
  cost accepted.
- **Filtered view may itself be large**: apply the existing
  inline/preview thresholds to the filter output too (reuse the
  `MAX_LINES`/`MAX_BYTES` logic; the marker then serves both roles).

### Rule change (start.md, RULE:REDIRECT-CMD-OUTPUT)

Add one clause: on seeing the `filtered view` marker — the full
unfiltered output is at `<path>`; if the filter missed what you
needed, Read/Grep that file; NEVER re-run the command. Trust
`upstream exit=` for the command's success, `filter exit=` for the
filter's signal (e.g. grep no-match).

## Trade-offs

1. **Filter replacement binaries (`embo-head`, `embo-grep`, ...)** —
   rejected: replacement must consume the whole stream (hangs on
   non-terminating upstreams), cannot see the upstream exit code, and
   multiplies shipped artifacts.
2. **PostToolUse output rewrite** — rejected: `updatedToolOutput`
   ignored for Bash; native 30k truncation precedes the hook.
3. **Pipeline decomposition in the existing wrapper (chosen)** — one
   new flag, both exit codes observable, stderr handled correctly,
   reuses shipped install/test infrastructure.
4. **`ask`+`updatedInput` for non-allowlisted commands** — now
   documented; deliberately deferred to a separate increment after
   this core ships (own UX questions; smaller residual pain once
   re-runs are eliminated for the allowlisted+filtered set).

## Verification Approach

| Requirement | Method | Scope | Expected Evidence |
|-------------|--------|-------|-------------------|
| FR-1: filter-tail detection (incl. opt-outs, scope guard) | `auto-test` | unit | approve-compound.test.sh: new cases pass, 112 old pass |
| FR-2: `--filter-b64` execution: both ECs, stderr separation, marker | `auto-test` | unit | embo-capture.test.sh: new cases pass, 33 old pass |
| FR-3: backward compat: plain `--b64` mode byte-identical behavior | `auto-test` | unit | existing 33 cases pass unchanged |
| FR-4: rule clause in start.md | `code-only` | — | — |
| FR-5: live: allowlisted `cmd \| grep X` → filtered view inline, marker with both ECs, full output in file | `manual-run-claude` | e2e | marker observed; Read shows unfiltered content |
| FR-6: live: failing upstream piped to filter → upstream exit nonzero in marker | `manual-run-claude` | e2e | marker shows `upstream exit=<nonzero>` |
| FR-7: install.sh syncs updated hooks | `manual-run-user` | install | second run clean |

## Files to Create/Modify

**Modify**:
- `.claude/hooks/approve-compound.sh` — `FILTER_HEADS`,
  `split_filter_tail`, rewrite branch in main
- `.claude/hooks/approve-compound.test.sh` — detection cases
- `.claude/hooks/embo-capture.sh` — `--filter-b64` mode, stderr
  separation, dual-EC marker
- `.claude/hooks/embo-capture.test.sh` — filter-mode cases
- `.claude/commands/dev/start.md` — REDIRECT-CMD-OUTPUT clause
- `README.md` — marker contract documentation

**Create**: none (no new shipped artifacts).

## Security Considerations

- Decomposition must never widen approval: detection runs only AFTER
  `decide()` returned allow on the ORIGINAL command; the rewrite
  changes execution shape, not authorization.
- Filter segments are allowlist-checked like any segment today (no
  bypass: `| awk '{system(...)}'` still needs `awk` allowlisted, and
  the unsafe-construct guard already bails on `$(...)`).
- Fail-safe stance preserved: any parse ambiguity → no decomposition.

## Rollback Plan

Remove the rewrite branch (one guarded call site in main); the
`--filter-b64` mode in the wrapper is inert without it. Re-run
`./install.sh`. No state or format migration.

## References

- Problem map: `bash-output-capture-problem-map.md` (PRD)
- Task 029 design: `tasks/029-COMPOUND-CMD-RULE-rework/` (should_wrap,
  normalization, fail-safe triage table)
- NotebookLM notebook: c5f0275c-e052-41d7-86da-410b5771720d
- GitHub: #54196, #65403 (updatedToolOutput), #32105 (updatedInput
  field whitelist), #17944 (BASH_MAX_OUTPUT_LENGTH ignored)

---

**Next Steps**:
1. Review and approve design
2. Run `/dev:tasks` for task breakdown
