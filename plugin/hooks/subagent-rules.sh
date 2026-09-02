#!/usr/bin/env bash
# subagent-rules.sh — SubagentStart hook.
# Injects the main agent's judgment rules into every spawned subagent:
# extracts the CHECKLIST regions from commands/start.md (single source),
# keeps only the ones meaningful without a human channel
# (WITHSTAND-CRITICISM, AVOID-APPROVAL), and prepends a static preamble
# carrying DECIDE-OR-ASK / RESEARCH-VERIFY reworded for an agent that
# cannot ask the user. The block opens with an imperative salience header
# because additionalContext lands in prunable user context, not the
# system prompt. Stateless; fails open (never blocks a spawn).
# See: tasks/055-SUBAGENT-RULE-INHERITANCE-unattended-agents/

trap 'exit 0' ERR

# --- Disable switch ---
[ "${SUBAGENT_RULES_DISABLED:-0}" = "1" ] && exit 0

HEADER='=== BINDING SUBAGENT RULES (you are a subagent: you have NO channel to ask the human — DECIDE, do not stall) ==='

PREAMBLE='[SUBAGENT DECIDE-OR-ASK] Question tools and approval prompts reach no one. Resolve every recoverable
choice yourself with evidence (peer files, tests, docs) and state the choice + reason in your report. Never
perform an irreversible or destructive action (delete, force-push, merge, overwrite shared state) — report it
as a blocker instead of acting.
[SUBAGENT RESEARCH-VERIFY] Your own confidence is not evidence. Before asserting any tool, API, or library
behavior, check the current documentation; if you cannot verify a claim, mark it provisional in your report.'

# --- Extract the kept CHECKLIST regions from start.md (single source) ---
# Each region starts on a line matching `^[<NAME> checklist` and ends at
# the next `<!-- /CHECKLIST -->`. A region is kept only when its header
# names a rule that works without a human channel.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
START_MD="$HOOK_DIR/../commands/start.md"
CHECKLISTS=""
if [ -n "$HOOK_DIR" ] && [ -f "$START_MD" ]; then
  CHECKLISTS="$(awk '
    /<!-- \/CHECKLIST -->/ { if (keep) printf "%s", buf; f = 0; keep = 0; buf = "" }
    f { buf = buf $0 "\n" }
    /^\[.*checklist/ && !f { f = 1; buf = $0 "\n"; keep = ($0 ~ /^\[(WITHSTAND-CRITICISM|AVOID-APPROVAL) checklist/) }
    END { if (f && keep) printf "%s", buf }
  ' "$START_MD" 2>/dev/null || true)"
fi

CTX="$HEADER
$PREAMBLE"
if [ -n "$CHECKLISTS" ]; then
  CTX="$CTX

$CHECKLISTS"
fi

# --- Output JSON ---
jq -n --arg ctx "$CTX" '{
    hookSpecificOutput: {
        hookEventName: "SubagentStart",
        additionalContext: $ctx
    }
}'
