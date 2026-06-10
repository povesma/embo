# 028 — Bash output: full capture, no flood, no prompt, no re-run

**Status**: Draft · **2026-06-09** · defect fix · PRD skipped (problem
established below + verified live this session).

## Problem

When the model runs a Bash command to inspect output, three things must
hold at once — and today none of the available techniques delivers all
three:

1. **No flood** — output the model does not need must not enter context.
2. **No re-run** — the needed lines come from a single execution (slow
   and non-idempotent commands must not run twice).
3. **No prompt** — achieving 1 and 2 must not trip a permission gate.

Failure modes observed:
- **Plain command**: the Bash tool caps inline output at 30k chars and
  auto-saves the overflow to `…/tool-results/<id>.txt`. **Under** 30k it
  all floods inline (breaks 1); the model can't predict size to avoid it.
- **`| tail -N`**: guesses N → re-run (breaks 2); pipeline reports the
  filter's exit code, masking failures.
- **`> tmp/x` redirect**: off-workspace `/tmp` trips the filesystem
  sandbox → prompt (breaks 3); even in-project, it relies on the model
  remembering to do it.

This is not fixable by reshaping commands — most are third-party. It
must be solved by the harness layer we control: a hook.

## Mechanism

A **PreToolUse hook on Bash** rewrites each eligible command via
`updatedInput` to run it through a shipped wrapper, `embo-capture`. The
wrapper:

- runs the command, tee-ing **full** stdout/stderr to a per-call file in
  the in-project scratch dir;
- preserves and re-emits the command's **real exit code**;
- prints output inline unchanged when it is **≤10 lines AND ≤300 bytes**
  (trivial results need no file, no extra Read);
- otherwise prints the first ~5 lines + one marker line and stops; the
  model recognizes the marker and Read/Greps the file for the rest.

The decision is made **after** the run (measured, not predicted); the
capture is done by the **hook**, not a model redirect (no prompt); the
full output is on disk from the **first** run (no re-run); the inline
result is bounded by the wrapper (no flood). All three requirements met,
for any command and any size.

## Invocation contract (wrapper interface — stable)

The hook must hand an **arbitrary** shell string (pipes, quotes, `$`,
globs) to the wrapper without quoting hazards. Chosen form: **base64**.

- Hook rewrites `tool_input.command` → `embo-capture --b64 <base64>`
  where `<base64>` encodes the original command string.
- Wrapper decodes, runs `bash -c "$decoded"`, tees full output to the
  per-call file, captures `$?`, prints inline-or-marker, then
  `exit "$ec"` (faithful exit code; the hook itself must exit 0 for the
  `updatedInput` to take effect).

Why base64 over single-quote escaping (option b) or args (option a):
avoids ALL shell metacharacter and quoting bugs; keeps the rewritten
command a single clean token that is trivially allow-listed
(`Bash(embo-capture *)`) and trivially recognized for the re-entrancy
guard below. Validated against the hooks reference: `updatedInput.command`
is executed through a shell, so the rewritten string re-parses normally;
exit code propagates when the hook exits 0 (claude-code-guide,
2026-06-09).

## Re-entrancy guard (MANDATORY)

The hook rewrites every eligible Bash command, and the rewritten command
(`embo-capture …`) is itself a Bash command. Whether `updatedInput`
re-fires PreToolUse is **not documented** (claude-code-guide could only
say "likely not"). Therefore the hook MUST, as its first check, **skip
any command already beginning with `embo-capture`** — emit no rewrite,
fall through. This makes the design correct under either harness
behavior: if hooks do re-fire, the guard stops the infinite wrap; if
they do not, the guard is a harmless no-op. It is also the natural place
to skip the wrapper for commands the user invokes directly.

## Marker contract (stable — the model depends on it)

```
<first ~5 lines>
[embo-capture] truncated — <N> lines, <M> bytes. Full output:
  <path>  (exit=<code>)
```

`[embo-capture]` is the recognizable prefix. `start.md` documents it:
output was capped, full text is at `<path>`, exit is `<code>`; Read/Grep
the path; **never re-run**. Thresholds fixed (≤10 lines AND ≤300 bytes);
not configurable in v1.

## Why this design (validated vs. official docs, 2026-06-09)

- **PostToolUse cannot rewrite tool output** (read-only) → interception
  must be pre-execution.
- **PreToolUse `updatedInput` with exit 0 is prompt-free** → the rewrite
  itself does not gate.
- **Permission matching is against the rewritten command** → installer
  must add `Bash(embo-capture *)`, else every command prompts.
- **Wrapper stdout stays far under 30k** → harness truncation never
  fires; the model always sees the marker, never a silent cut.
- **Exit code is plain process pass-through** → `exit $?` is faithful.

## Acceptance criteria

1. Large-output command → model gets preview+marker only, reads the
   failing lines from the file, **no second run, no prompt**.
2. Tiny-output command (`git rev-parse HEAD`) → inline, no marker, no
   extra Read.
3. Model-visible exit code = wrapped command's real exit code (both
   paths).
4. No prompt for the rewritten command (with the installer allow-rule).
5. Scratch dir gitignored; captured output never committed.

## Opt-outs (v1) — run unwrapped

- Interactive / streaming / long-running commands (stdin, watched live:
  servers, REPLs, progress bars). Conservative default: when unsure, do
  **not** wrap (a mis-wrapped interactive command hangs).
- Commands already containing a redirect (`>`/`>>`) — not re-wrapped.
- Value-extraction commands (stdout is data) — no stderr folded in.

## Key risk — single rewriter

`approve-compound.sh` already rewrites via `updatedInput` (reflexive-tail
strip). Docs: when multiple hooks rewrite one tool, the last wins and
order is non-deterministic. The capture rewrite and the tail-strip must
live in **one hook** (or a strict order). Resolve in `/dev:tasks`.

## Files

- **new** `.claude/hooks/embo-capture.sh` (or `.py`) — the wrapper.
- **modify** the Bash PreToolUse hook — append capture rewrite, with
  opt-out detection; coordinate with the tail-strip.
- **modify** `install.sh` — ship wrapper, add `Bash(embo-capture *)`
  allow-rule, register/confirm hook. Idempotent; manual steps documented.
- **modify** `.claude/commands/dev/start.md` — RULE:REDIRECT-CMD-OUTPUT
  collapses to: run plainly; recognize the `[embo-capture]` marker;
  Read/Grep the file; never re-run. No model-issued redirect remains.
- `.gitignore` — scratch dir already covered (`tmp/`, line 33); confirm.

## Rejected alternative

Manual redirect to in-project `tmp/` (the earlier 028 resolution). Keeps
the model in the loop, floods sub-30k output, and depends on the model
remembering — the prose dependency this task proved unreliable. The
wrapper removes the need for any model-issued redirect.

## Sources

Live tests this session; Context7 `/websites/code_claude` (redirect
matching, compound hardening, hook cannot override deny/ask); 30k
truncation (anthropics/claude-code #19901, #12054); wrapper design
validated via claude-code-guide against the official hooks reference
(PostToolUse read-only; PreToolUse `updatedInput` prompt-free; permission
matches rewritten command), 2026-06-09.
