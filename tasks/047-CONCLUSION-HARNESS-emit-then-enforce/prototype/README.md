# 047 prototype — emit-a-conclusion, measure-only

Proves/disproves live whether the model reliably emits a required
conclusion tag (`Data-access:`) before a governed Bash command and acts
consistently with it. **Measures only — denies nothing.**

## Files

- `RULE-DATA-ACCESS.md` — the single rule (model reads it == probe checks it).
- `conclusion-probe.sh` — Stop hook. At turn end reads
  `last_assistant_message` + the turn's Bash commands from the
  transcript; logs one NDJSON row per governed command.
- `conclusion-probe.test.sh` — unit tests, synthetic Stop JSON, zero
  model calls (27 passing).

## Why a Stop hook (not PreToolUse)

Verified via claude-code-guide: PreToolUse/PostToolUse do **not** receive
the assistant's message text (only tool fields + a lagging
`transcript_path`). The **Stop** hook is the only event that reliably
sees assistant prose (`last_assistant_message`) and can act. So
enforcement is per-turn/retrospective — the same shape as the reliable
RESTATE-CORRECTION rule.

## Run it live (needs a real Claude session)

1. Paste `RULE-DATA-ACCESS.md`'s rule into the session rules the model
   reads (e.g. start.md), so the model is actually asked to emit the tag.
2. Register `conclusion-probe.sh` as a **Stop** hook in settings
   (`hooks.Stop[].hooks[].command` → `bash <path>/conclusion-probe.sh`).
3. Work normally for a session that includes ≥15 structured-data Bash
   commands (jq/yq/python-on-json/…), ideally into a long context.
4. Read `.claude/embo_state/conclusion-probe.log`. Each row:
   `{ts, rule, tag, cmd_kind, consistency, transcript_bytes}`.

## Metrics to compute (AC1–AC2)

- **emit-rate** = rows with a non-empty `tag` / all rows.
- **emit-rate vs context fill** = emit-rate bucketed by
  `transcript_bytes` (the decay signal — the make-or-break metric).
- **consistency** = rows `consistent` / rows with a tag; count
  `mismatch` and `no-tag`.

## Interpreting

- High emit-rate + rare mismatch, stable as `transcript_bytes` grows →
  the design works; move to enforcing (deny on no-tag/mismatch at Stop).
- Emit-rate falling with context fill → decay confirmed; add
  UserPromptSubmit re-injection and re-measure before enforcing.
- Frequent mismatch on honest tags → the consistency heuristic
  (`cmd_kind`) is too crude; refine before enforcing.
