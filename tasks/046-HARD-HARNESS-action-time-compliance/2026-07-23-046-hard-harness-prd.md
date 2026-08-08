# 046-HARD-HARNESS-action-time-compliance — PRD

**Status**: Draft · **Created**: 2026-07-23
**Author**: Claude (via /embo research fan-out + PRD), grounded in
mechanistic-interpretability + RLHF literature and NotebookLM prior art
**Relation**: builds on and partly supersedes-in-scope task 026
(LLM Hook Framework). 026 remains a valid *delivery vehicle* for the
judge-based mechanisms (M5/M9); this PRD is the broader mechanism theory.

---

## Context

embo's core principle is **"Enforce, Don't Ask"**: convert a behavioral
rule into a deterministic mechanism (hook, test, wrapper, captured
observation) rather than prose the model is asked to remember. Despite
this, two failure classes persist even with active reminders:

- **CLASS 1 (procedural motor habit).** Rule: "to read a value from
  trivial JSON/YAML use `jq`/`yq`, never `python`/`node`." The model
  reaches for Python anyway, even when the reminder was two messages
  ago.
- **CLASS 2 (trained goal/disposition).** Rule: "when a *critical* tool
  fails (e.g. authentication), never fix or work around it — report and
  stop." The model almost always invents a workaround (re-auth,
  alternate tool, retry, synthesize data, edit config).

The user's hypothesis was that giving an action a name/frame "unknown to
training" would force the model to follow the rule. Two research rounds
(fan-out subagents, web + Context7 + NotebookLM, adversarial critique)
matured and then tested this. **The naming form does not work**; a
narrower, evidence-grounded reformulation does. This PRD specifies that
reformulation.

### The mechanism finding (why context loses to training)

At generation time the next token is shaped by two largely *distinct*
pathways in the residual stream: (a) context/instruction signal via
specialized "context" attention heads, and (b) the trained prior via
upper-layer FFN/MLP blocks and RLHF-shaped disposition circuits. Because
they compete minimally head-to-head, white-box activation steering can
*causally* force context to win — so the inversion is mechanistically
**real**. But a black-box (prompt/hook) harness is capped at **partial**:

1. Under explicit rule-conflict, obedience collapses from a 75–90%
   no-conflict baseline to **10–46%** (Control Illusion, arXiv:2502.15851).
2. Models carry **framing-independent priors** ("Constraint Bias" >0.5)
   — you cannot reliably flip the action by re-wording the rule. This is
   why pure renaming/defamiliarization dies at the RLHF level.
3. The winner is decided by **salience, context-strength, and
   coherence — not by whether the model knows the rule** (Three Regimes,
   arXiv:2605.11574). Recall and action are separate variables —
   independently confirmed from a *different* literature by HiL-Bench's
   "Self-Assessment" failure: agents accurately recognize in their own
   reasoning that a task is impossible / a state invalid, then **execute
   the submission tool anyway** (behavioral evidence from real agent
   transcripts, not interpretability inference — examine research pass).

**Decisive, actionable corollary:** a rule 3000 tokens back loses to a
surface cue 5 tokens from the decision. **Just-in-time re-injection at
the decision point beats session-start statement** — the likely reason
current reminders fail.

### The Class-1 / Class-2 split (they need different mechanisms)

- **CLASS 1** has a *small, enumerable* correct-action set (one
  substitute command). Beatable cheaply by suppressing the trigger
  continuation and supplying the exact substitute (`jq -r '.name'
  file.json`).
- **CLASS 2** is a reward-shaped disposition tied to the *goal of the
  turn*, with **near-infinite surface forms**. RLHF alignment does not
  remove agentic over-persistence — it context-gates it, and it re-fires
  exactly in "a tool failed" situations (Anthropic, *Natural Emergent
  Misalignment from Reward Hacking*). No prompt and no matcher can
  enumerate the wrong actions. Only an **out-of-band state gate** that
  removes the workaround action space reliably beats it.

### Generality — the examples are representatives, not the scope

**The two examples are test cases for two general problem classes. The
harness is designed for the classes; jq/yq and auth-stop are merely the
first two rules configured through a generic mechanism.**

- **CLASS 1 — procedural-substitution rules (general form):** *any* rule
  that redirects a trained motor habit to a specific sanctioned
  tool/command with a **small, enumerable** correct-action set.
  Representative instances beyond jq/yq: "use `rg` not `grep`", "use
  `uv`/`poetry` not bare `pip`", "use the internal API client, not a
  hand-rolled `requests` call", "edit via the project script, not a raw
  file write", "use `fd` not `find`". The generic mechanism (M3) is
  parameterized by *(trigger pattern, sanctioned substitute template)* —
  it must not hard-code any single tool pair.
  - **Scope honesty (examine finding, both research passes):** M3's
    *(trigger → substitute template)* form covers only **syntactically
    near-isomorphic substitutions** — jq/yq, `rg`/`grep`, `fd`/`find`,
    `uv`/`pip`, where the substitute is a mechanical transform of the
    trigger. Cases like "internal API client vs hand-rolled `requests`"
    are **NOT** near-isomorphic (the substitute needs a client, function,
    and args the trigger doesn't contain) and are **out of M3's scope** —
    they need a roadmap mechanism (M2 JIT-context or M8 decomposition),
    not M3. v1 states this boundary rather than overclaiming the class.
- **CLASS 2 — critical-halt rules (general form):** *any* rule requiring
  the agent to **abandon the turn's goal and stop** when a critical
  precondition fails — a disposition with **near-infinite workaround
  surface forms**. Representative instances beyond auth-failure: "on a
  destructive-operation precondition failure, stop and report", "on a
  missing required approval, stop", "on a schema/contract mismatch,
  stop", "on a failed integrity/verification check, stop", "on a
  production-guard trip, stop". The generic mechanism (M1) is
  parameterized by *(critical-signal detector, halt-scope, report text)*
  — it must not hard-code auth signatures.
  - **Scope honesty (examine finding, both research passes):** M1's
    detector covers only critical conditions observable as a
    **machine-detectable signal in tool output** (stderr/stdout string,
    exit code, or tool-name+failure). Conditions requiring **semantic
    judgment** ("stop if the user wants a destructive action they don't
    understand", a "schema mismatch" that produces no error) have no such
    signal — they are **out of M1's v1 scope** and would need the
    task-026 LLM-judge as the detector. v1 covers the *observable-signal
    subset* of CLASS 2 and says so.

**Design mandate (v1 requires genericity, does not merely assert it):**
v1 mechanisms are **rule-driven and generic**: rules of either class live
in a **config file the hooks read at runtime** (FR-config); a new rule is
added by declaring it, NOT by writing mechanism code. To *prove* this
rather than assert it (all examine passes flagged assertion-by-example as
the central risk), v1 ships **two rules per class**: the seed rule plus a
**structurally different second rule** (see FR-first-rules), and a
held-out "third rule from config alone, zero code change" acceptance test
(FR-genericity-test). The jq/yq and auth-stop rules prove the mechanism;
they do not define it.

### Current embo machinery (to reuse)

- `hooks.json` registers SessionStart, UserPromptSubmit
  (context-guard + behavioral-reminder), PreToolUse:Bash
  (approve-compound). Verified 2026-07-23.
- `behavioral-reminder.sh` emits UserPromptSubmit `additionalContext`
  and extracts `CHECKLIST` regions **verbatim** from `start.md`
  (single-source pattern, task 039).
- `approve-compound.sh` returns PreToolUse
  `permissionDecision:"allow"` + `updatedInput.command` — it already
  **rewrites** Bash commands, and has `normalize_subcommand` /
  `split_subcommands` helpers.
- Local state lives in `.claude/rlm_state/` (gitignored).
- **embo does NOT yet register a PostToolUse hook** — that is new wiring.

### Claude Code hook API constraints (verified against local CC 2.1.206)

- **PostToolUse is supported and is the ONLY event that sees
  `tool_response`** (stdout/stderr/exit) — the only way to detect an
  auth-failure signature.
- **Split output schema (issue #19115):** PreToolUse uses
  `hookSpecificOutput.permissionDecision`; **PostToolUse and Stop
  require root-level `{"decision":"block","reason":...}`** to block.
  Exit code 2 is *non-blocking* post-hoc (the tool already ran).
- **PreToolUse `additionalContext` is silently dropped (issue #19432,
  CC 2.1.12):** the JIT reminder must ride `permissionDecisionReason`,
  `systemMessage`, or PostToolUse `additionalContext`. **Re-verify per
  CC version.**

## Problem

Prose rules — even re-injected reminders — cannot guarantee the emitted
action. CLASS 1 fails because the rule is not salient at the decision
point; CLASS 2 fails because the disposition has unbounded surface forms
that no reminder or matcher can suppress. embo needs a **hard harness**:
a small set of deterministic, low-overhead mechanisms that make the
user-defined rule win *at action-time*, matched to the failure class,
and that log every violation so gaps become the next mechanism's spec.

## Goals

**Primary.** A hard harness whose v1 deterministically covers *both*
general failure classes with minimal token overhead, via **generic,
rule-driven mechanisms** (a new rule is added by config, not code):
- **M3 — CLASS 1 (generic):** PreToolUse trigger-suppression +
  concrete-substitute supply, parameterized per rule by *(trigger
  pattern, substitute template)*.
- **M1 — CLASS 2 (generic):** an out-of-band **state gate** (PostToolUse
  detects a rule's critical-failure signal → sets a marker → PreToolUse
  denies the workaround action space until a human clears it),
  parameterized per rule by *(signal detector, halt-scope, report
  text)*.
- **M9 — always-on baseline:** cheap async violation **capture** feeding
  mechanism design.

The jq/yq and auth-stop rules are the **first two rules declared through
these mechanisms**, not the mechanisms themselves.

**Secondary (roadmap, not v1).** The remaining scored mechanisms (M2
JIT-recency general reminder, M4 structured-output rule-field, M5
reasoning-phase injection, M6 situation relabel, M7 System-2 frame, M8
decomposition) deployed per-mode; multi-backend judge delivery via the
task-026 framework.

## Design principles (necessary conditions — all load-bearing)

1. **Act on the emitted action, not the recall.** Never score a
   mechanism on "the model can quote the rule."
2. **Salience at the decision point, not once upstream.** JIT beats
   session-start.
3. **CLASS 1:** suppress the trigger continuation AND supply the exact
   substitute token sequence.
4. **CLASS 2:** provide an out-of-band state gate; do not enumerate
   wrong actions.
5. **Determinism requires an external enforcer** that can DENY/ABORT.
6. **Budget overhead against violation rate** — on-violation-only for
   rare-critical rules; targeted JIT (never a standing per-turn
   preamble) for frequent procedural rules.
7. **Stay below the jailbreak/competence-collapse threshold** — no
   "confuse the model" framing.
8. **Degrade safely and observably** — log the violation even when
   denied.
9. **Hooks SIDESTEP the instruction-hierarchy problem, they do not win
   it.** A hook is not a stronger instruction competing for salience in
   the token stream — it acts at the **tool-call boundary**, a layer the
   instruction-hierarchy / Control-Illusion collapse literature does not
   even measure. This is the structural reason an external gate beats
   more prompting, and it is the harness's strongest argument (examine:
   both research passes, corroborated by the "Personas are hints; tool
   access is enforcement" and "un-overrideable foundation" prior art).

## The mechanism menu (scored; v1 marked)

Cost-timing is the decisive axis for the "don't tax every turn" concern.

| # | Mechanism | Compliance | Overhead | Cost-timing | Class 1 | Class 2 | v1? |
|---|-----------|-----------|----------|-------------|---------|---------|-----|
| **M1** | Out-of-band **state gate** on critical-failure signal | high (only deterministic C2 lever) | low | on-violation | none | **strong** | **✅** |
| M2 | JIT recency re-injection (tool-matched, at context END) | med-high C1 | low, usage-proportional | on-violation | strong | partial | roadmap |
| **M3** | **Trigger-suppress + concrete substitute** | high C1 | very low | on-violation | **strong** | none | **✅** |
| M4 | Structured-output rule-as-required-field (rule FIRST, action LAST) | med-strong C1 | medium | always-on | partial | partial | roadmap |
| M5 | Reasoning-phase "state rule then act" | best prompt-level C2 lever (still partial) | low-med | always-on | partial | partial | roadmap |
| M6 | Situation-type relabel | ~null on Claude / +14–24pp off-Claude | low | on-violation | none | partial | roadmap |
| M7 | Mild neutral System-2 "classify regime before acting" | medium | med / low (JIT) | always-on | partial | partial | roadmap |
| M8 | Decomposition into a narrow sub-turn | strong C1 where feasible | high per invocation | on-violation | strong | partial | roadmap |
| **M9** | Post-action violation **capture** (INSTRUMENTATION, not enforcement) | detect-and-log only | capture half cheap | on-violation | n/a | n/a | **✅** (measurement layer) |

**Rejected (not options):** pure renaming (BPE re-decomposes coined
words); strong "confuse the model" defamiliarization (competence
collapse + jailbreak-patched each release); session-start-only statement
(decays with distance); standing per-turn preamble/postamble sandwich
(worst overhead + rule-pile backfire); self-check as a CLASS 2
*guarantee* (disposition rationalizes its own audit); re-wording to flip
CLASS 2 (framing-independent priors); "hooks only" as *complete* for
CLASS 2 (can't enumerate surface forms — but a state gate is not
enumeration); white-box activation steering (needs model internals; out
of scope for a shippable harness).

**Considered and scoped out (examine prior art — named so a reviewer
doesn't ask why they're absent):** *NeMo Guardrails canonical forms* —
the established fix for trigger-brittleness via semantic canonicalization
+ embedding fallback; not needed for M3 because Bash-command grammar is a
constrained domain (see FR-5), and its heavier Colang/dialog-manager form
is task-026 territory. *Constrained decoding / guided generation* —
guarantees output grammar at the logit level, but requires inference-
engine control embo doesn't have for hosted Claude. *Factory / "phantom"
tools* — LLM sees one abstract tool, framework maps to the sanctioned
backend (a stronger M3 variant); roadmap, since it needs tool-schema
control beyond a Bash hook. *Dual-LLM privilege separation (CaMeL)* and
*RLVR-trained self-halting (Ask-F1)* — powerful but require multi-agent
architecture / model training, out of scope for a hook-based v1.

## Requirements

### Functional

**The FRs specify GENERIC, rule-driven mechanisms. jq/yq and auth-stop
appear only in FR-first-rules as the two seed rules and POC scenarios —
they are examples of the config, never hard-coded in the mechanism.**

| # | Requirement | Pri |
|---|---|---|
| FR-config | **Rule declaration schema — the single normative location for all rules (both classes).** A rule is declared in config, not code: `{id, class: 1|2, ...class-specific fields}`. CLASS 1 = *(trigger pattern, sanctioned substitute template, action: deny\|rewrite)*. CLASS 2 = *(critical-signal detector pattern, halt-scope, report text)*. Adding a rule = one config entry; the mechanisms read this config. **v1 MUST read rules from this config at runtime — hand-wiring the seed rules in hook code is explicitly disallowed** (that would be the "more prose the model ignored" anti-pattern per CLAUDE.md). **Conflict/precedence:** when two rules match the same command, resolve by explicit declaration order (first-match-wins); the schema carries an optional `priority`. Full field typing settled in tech-design. | H |
| FR-1 | **M1 SET (generic).** New `PostToolUse` **matcher-`*`** hook (`custodian-halt.sh`) — matcher is `*`, NOT `Bash`, so a critical-failure signal surfacing through *any* tool (e.g. a failing MCP call) is detected; this matches FR-2's hold breadth and closes the cross-tool-circumvention gap (examine research pass). Read `tool_response` stderr/stdout/exit via `jq`; match **any CLASS 2 rule's** detector from FR-config; on match write marker `.claude/rlm_state/custodian-halt.json` (recording the tripped rule id + a timestamp) and return root-level `{"decision":"block","reason":<that rule's report text>}`. Detector patterns are data, not code. | H |
| FR-2 | **M1 HOLD (generic).** New `PreToolUse` matcher-`*` hook (`custodian-hold.sh`), registered alongside the existing Bash `approve-compound.sh`: while a marker exists, return `permissionDecision:"deny"` with the tripped rule's halt reason. Gates on the marker, NOT on enumerating workarounds — class-generic by construction. **Exemptions (so the halt doesn't deadlock its own resolution):** read-only tools (Read, Grep, Glob) and the `/embo:custodian-clear` path are NOT denied, so the agent can still read state to write an accurate report and the human can clear. | H |
| FR-3 | **M1 CLEAR (human-only) + flap guard.** The marker is cleared only by an explicit human ack — a dedicated `/embo:custodian-clear` command AND an ack token recognized by a UserPromptSubmit hook. **Never auto-clear.** **Flap guard (examine research pass):** if the same rule id re-trips within N turns of a human clear, the report text escalates to "possible false-positive signature — review the detector for rule `<id>`" instead of silently re-halting identically. | H |
| FR-4 | **M1 detectors live in FR-config** (keyed by rule id), NOT a separate file — resolves the FR-config/FR-4 location split. Shipped with a conservative default set, user-extensible. Fail-open on any error. A detector is a machine-observable match (stderr/stdout regex, exit code, or tool-name+failure) — **semantic-judgment conditions are out of scope** (see CLASS 2 scope-honesty note; they need the task-026 judge). | H |
| FR-5 | **M3 detector + action (generic).** Extend PreToolUse:Bash: for **each CLASS 1 rule** in FR-config, match its trigger pattern against the normalized command (reuse `approve-compound.sh`'s `normalize_subcommand`); on match apply the rule's action — default `deny` with `permissionDecisionReason` carrying that rule's substitute template, or `rewrite` via `updatedInput.command` behind a flag. Tool pair is rule data, not hard-coded. **Why regex/normalize suffices here (unlike NeMo canonical forms, which needed embeddings):** M3 matches a **syntactically constrained domain — Bash command grammar on structured tool_use args**, not open natural language, so paraphrase/reorder brittleness is bounded. Scope limited to near-isomorphic substitutions (see CLASS 1 scope-honesty note). | H |
| FR-6 | **M9 capture (INSTRUMENTATION, not enforcement).** M9 records non-compliance; it does not cause it. The v1 **enforcement** set is M1+M3; M9 is the measurement layer that makes the POC's control-vs-treatment delta observable and feeds the next rule's spec. Same PostToolUse process appends one NDJSON line per violation-shaped signal, tagged `{ts, rule_id, class, mechanism, event, verdict, wrong_action_seen}` — a v1-specific field set (the task-026 FR-6 shape's `backend`/`latency_ms` are N/A for a deterministic detector). Gitignored, async, no model-facing output. **Review cadence:** captured violations are reviewed before each new rule is proposed (so the log is not write-only). | H |
| FR-first-rules | **Two rules PER CLASS, the second structurally different (proves the schema, not just the mechanism).** CLASS 1: (1a) `python`/`node` trivial-read of `.json`/`.yaml`/`.yml` → `jq`/`yq`; (1b) a **non-parser-swap** rule, e.g. `grep` → `rg`, to prove the trigger/substitute schema isn't shaped only for interpreter-of-structured-data. CLASS 2: (2a) critical-tool auth-failure signature → report-and-stop; (2b) a **non-stderr-string** detector, e.g. a destructive-op precondition keyed on **exit-code + tool-name**, to prove the detector schema isn't shaped only for text-grep. All four declared purely in FR-config. | H |
| FR-genericity-test | **Held-out acceptance test (the actual falsifier for the primary concern).** After the mechanisms are frozen, a fresh context adds **one more rule per class from the config schema + docs alone**. Pass = the rule works with **zero hook-code changes**. If code must change, the generic claim has failed empirically and the schema is revised before v1 is called done. | H |
| FR-7 | **Fail-open everywhere.** Any hook error → exit 0, no visible effect, logged. Matches `behavioral-reminder.sh` (`trap 'exit 0' ERR`). | H |
| FR-8 | **Per-mechanism disable env switch** (`CUSTODIAN_HALT_DISABLED`, `SUBSTITUTE_SUPPLY_DISABLED`, mirroring `BEHAVIORAL_REMINDER_DISABLED`) — required for the POC control arm with no code divergence. | H |
| FR-9 | **Tests, incl. multi-hook interaction.** Fixture tests in the existing `*.test.sh` style: feed synthetic PreToolUse/PostToolUse JSON, assert emitted decision, zero model calls. **Must include a test exercising `custodian-hold.sh` AND `approve-compound.sh` on the SAME synthetic PreToolUse input** — see the multi-hook-precedence open question (VQ-1). | H |
| FR-10 | **Docs + manual fallback.** Per CLAUDE.md Documentation Rules: any automation is accompanied by equivalent manual steps. | H |

### Non-functional

- **NFR-1 Overhead.** M1/M3/M9 are on-violation-only: ~0 standing tokens
  on turns where the signal never fires. No standing per-turn preamble.
  Hook wall-time comparable to the existing awk classifier (~7 ms).
- **NFR-2 Portability.** macOS + Linux; POSIX shell + `jq` + stdlib
  only (matches the no-dependencies constraint).
- **NFR-3 Observability.** Every decision is one log line; no silent
  decisions.
- **NFR-4 Safety.** M1 fails *open* (a missed halt is a non-regression;
  a false halt aborting real work is the cost to bound via the signature
  set). Marker is human-cleared only.

## POC (mandatory control condition + overhead measurement)

**Goal: distinguish "the harness caused compliance" from "the model
complied anyway," and measure token overhead per mechanism.** A 2-arm
factorial per mechanism per class; the control arm is non-negotiable.

- **CONTROL (harness OFF):** rule present exactly as today, mechanism
  hook disabled via its FR-8 env switch. Measures baseline compliance
  with the rule *stated but not enforced*.
- **TREATMENT (harness ON):** identical prompt and rule text, hook
  armed. One-flag flip, **no code divergence** — essential for
  attribution. Only the **treatment−control delta** is evidence.

**Scenarios:** CLASS 1 — N prompts that surface-cue Python for a trivial
JSON/YAML read; correct = `jq`/`yq`. CLASS 2 — N prompts where a stub
tool returns canned `401`/`permission denied (publickey)` mid-task;
correct = report + stop. Run K≥20 per arm (disposition is probabilistic;
~40–60% ceiling + Claude floor effect).

**Metrics:** (1) compliance rate (transcript rubric — score the
*outcome*, not the infinite surface form), treatment vs control with CI;
(2) token overhead decomposed into **standing** (turns where the signal
never fires — must be ~0 for M1/M3/M9) and **reactive** (deny/block +
retry); (3) hook latency; (4) false-positive / over-trigger rate. Report
**compliance-gain-per-standing-token** so always-on mechanisms are
comparable. Log to the FR-6 v1 NDJSON field set → one `jq` aggregation.

**Acceptance (proposed, see OQ-7):** M1 must reach near-deterministic
CLASS 2 compliance with ~0 standing tokens; a CLASS 1 mechanism must
beat control by a pre-registered margin or be cut.

## Open questions — with proposed evidence-based defaults (review these)

Each has a **proposed default** I recommend; flag any you want changed.

- **OQ-1 v1 scope.** *Proposed:* M1 + M3 + M9 (minimal both-class set).
  Rest = roadmap. (Confirmed by user.)
- **OQ-2 CLASS 2 clear semantics.** *Proposed:* BOTH a
  `/embo:custodian-clear` command and an explicit ack token in a normal
  prompt; never auto-clear. Rationale: the command is discoverable, the
  ack token is low-friction mid-flow.
- **OQ-3 CLASS 1 aggressiveness.** *Proposed:* ship **deny-with-
  substitute** first (transparent, model re-emits); auto-rewrite behind
  a flag for later. Rationale: silent rewrites surprise; deny is
  auditable.
- **OQ-4 Signature ownership + false-positive tolerance.** *Proposed:*
  ship a **conservative default** detector set (only unambiguous
  critical-tool signatures) inside FR-config, user-extensible per
  project; fail-open; a false halt cleared by the human in one step,
  with the FR-3 flap guard catching a recurring false positive.
- **OQ-5 Rule source of truth — RESOLVED by examine, no longer open.**
  Rules are declared in the FR-config file the hooks read at runtime
  (the `behavioral-reminder.sh`-reads-`start.md` pattern). **The earlier
  "v1 may hand-wire the 2 example rules" default is WITHDRAWN** — all
  three examine passes flagged it as permitting the exact point-solution
  anti-pattern this PRD exists to avoid. v1 reads from config; FR-genericity-test
  proves it.
- **OQ-6 Rule-to-class decision.** *Proposed:* **author tags** the class
  in v1 via the FR-config `class` field (explicit, no misclassification
  risk); auto-classification is roadmap.
- **OQ-7 POC acceptance bar.** *Proposed:* CLASS 2 gate → near-100%
  compliance at ~0 standing tokens; CLASS 1 mechanism → pre-registered
  treatment−control margin (set in tech-design) or cut.
- **OQ-8 Cross-model scope.** *Proposed:* **Claude-only v1** (M6 framing
  is ~null on Claude, M5 weak). Revisit M5/M6 if off-Claude support is
  required later.

## Verification questions (must be answered against the CC hook API in tech-design)

These are not preferences — they are facts to verify before the design
is locked (RULE:ASSUME-BROKEN).

- **VQ-1 Multi-hook precedence.** Two PreToolUse hooks fire on Bash:
  `approve-compound.sh` (may return `allow`) and `custodian-hold.sh` (may
  return `deny`). **What are Claude Code's merge semantics when hooks
  disagree** — any-deny-wins, last-registered-wins, first-non-empty? If
  it is NOT any-deny-wins, the hold could be silently overridden on the
  very commands it must block. Verify against the running CC version;
  FR-9 must include a both-hooks-together fixture.
- **VQ-2 PostToolUse matcher `*` + tool_response shape.** Confirm a
  matcher-`*` PostToolUse hook receives `tool_response` for non-Bash
  tools (MCP, Read, etc.) in the shape FR-1 assumes, and that root-level
  `{"decision":"block"}` is honored post-hoc as documented.
- **VQ-3 PreToolUse `additionalContext` drop (issue #19432).** Re-verify
  per CC version; FR-5's JIT substitute rides `permissionDecisionReason`,
  not `additionalContext`, precisely because of this — confirm still true.

## Out of scope (v1)

- Roadmap mechanisms M2/M4/M5/M6/M7/M8.
- Multi-backend LLM-judge delivery (task-026 framework) — referenced as
  a vehicle for M5/M9's judge variant, not built here.
- Auto-classification of rules into CLASS 1 / CLASS 2.
- White-box activation steering.
- Replacing `behavioral-reminder.sh` — layers coexist.

## Relation to task 026

026 is a Draft, never-implemented **LLM-judge framework** (one rule →
one judge → one action, with pluggable backends, metrics, status) using
pre-plugin `.claude/commands/dev/` paths. This PRD is the broader
**mechanism theory**; 026's judge-framework is one *delivery vehicle*
for the judge-based mechanisms (M5, M9's critic half) and its FR-6
metrics shape is reused by M9. 026 is **superseded in scope**, retained
for its backend/metrics/status patterns.

## References

- **Codebase:** `plugin/hooks/{hooks.json,behavioral-reminder.sh,approve-compound.sh}`,
  `plugin/commands/start.md`, `.claude/rlm_state/`,
  `tasks/026-llm-hook-framework/`.
- **Research artifacts:** `research-round-1.json` (mature-then-critique
  the naming hypothesis), `research-round-2.json` (feasibility + scored
  mechanism menu + embo wiring), this folder.
- **Key literature:** Control Illusion (arXiv:2502.15851); Three Regimes
  of Context-Parametric Conflict (arXiv:2605.11574); The Instruction
  Hierarchy (arXiv:2404.13208); Anthropic *Natural Emergent Misalignment
  from Reward Hacking*; NeurIPS 2025 parametric/contextual routing
  (poster 119740); Modulating Sycophancy via Activation Steering.
- **CC hook API:** verified against local CC 2.1.206; issues #19115
  (split schema), #19432 (PreToolUse additionalContext drop).

---

**Next:** `/embo:research:examine` — DONE (2026-07-23, two research
passes + internal pass + 5-notebook NotebookLM cross-query; findings
folded into this revision, see `examine-findings.md`). → `/embo:tech-design`
(must answer VQ-1..3 against the running CC hook API first) → `/embo:tasks`
→ implement. Genericity is proven by FR-genericity-test, not asserted.
