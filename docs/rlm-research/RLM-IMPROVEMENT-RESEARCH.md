# RLM Improvement Research for embo

*Deep research into modern Recursive Language Model (RLM) implementations,
aimed at improving embo's RLM subsystem for large-codebase work — both
LOCATING information and using recursion + a code-execution REPL to SOLVE
analysis/problem-solving tasks safely.*

- **Date**: 2026-08-17
- **Method**: Gemini Notebook (`gemini-notebook-mcp`) deep research — three
  deep passes (core/ecosystem, GitHub implementations, video lectures) plus
  direct addition of author lectures. ~138 sources.
- **Notebook**: `RLM for embo — recursive code analysis, problem-solving, safe REPL execution`
  (`b535c58e-aed6-4dbb-8c9d-f824f1a691ba`) —
  <https://notebooklm.google.com/notebook/b535c58e-aed6-4dbb-8c9d-f824f1a691ba>
- **Primary source**: Recursive Language Models — Zhang, Kraska, Khattab,
  arXiv:2512.24601 (code: github.com/alexzhang13/rlm).
- **Scope locked with the requester**: paper + ecosystem sources; retrieval
  and recursive problem-solving weighted equally; safety as a first-class
  section; deliverable = research report + embo mapping.

> **How this report was produced (the RLM principle, dogfooded).** The raw
> Gemini Notebook query answers were ~100K–110K characters each. They were
> read and distilled inside subagents so the bulk never entered the main
> agent's context — exactly the "push bulk into sub-calls, keep the root
> context small" pattern this research is about. A gap observed while doing
> this: embo's *direct* REPL use (`rlm_repl exec` printing back to the main
> agent) does NOT keep the context clean; only the `rlm-subcall` subagent
> path does. See "Mapping to embo", items around context hygiene.

---

## 1. Core RLM Method

- **Root model + `llm_query` sub-call recursion.** The outer "root LM"
  (depth=0) never reads the full prompt. It writes Python that chunks the
  context and calls a cheaper "callee"/sub-LM (e.g. GPT-5-mini, Claude
  Haiku) via a pre-loaded `llm_query(prompt)` function, then
  aggregates/filters/re-queries the short returned values. [Recursive
  Language Models, arXiv:2512.24601]
- **Context-as-variable / the variable–token split.** The entire prompt is
  held as a RAM-resident string variable (`context`) inside a persistent,
  sandboxed Python REPL (Jupyter-like). This splits "variable space" (all
  source text in memory) from "token space" (what the LLM actually sees).
  The root is "blindfolded" — it sees only constant-size metadata (length,
  type, previews) and tokenizes slices on demand via `print(context[:1000])`
  or regex. [arXiv:2512.24601]
- **Unbounded output, not just input.** State kept in REPL variables lets
  the model build a large result across iterations (appending to a list) and
  finalize by returning a pointer via `FINAL_VAR(var_name)` — beating
  output-token-window limits. [arXiv:2512.24601]
- **Context rot and how RLM avoids it.** Context rot = progressive
  degradation (lost focus, missed details, hallucination) as input length
  grows *even within the physical window*, driven by attention dilution /
  "lost-in-the-middle". RLM bypasses it because no single LLM call ever
  ingests the raw giant context: the root stays small and focused on
  orchestration, and sub-calls only see small, relevant slices where
  attention is sharp. [arXiv:2512.24601; Context Rot — Chroma]
- **The exact loop (Algorithm 1).** (1) init REPL, load prompt as `context`,
  pre-import `llm_query`; (2) root sees only constant-size metadata of REPL
  state + prior outputs; (3) root emits one Python block in `repl` tags;
  (4) execute in sandbox, capture stdout; (5) append *only metadata* of
  stdout back to root history; (6) if `Final`/`FINAL_VAR` set → return, else
  loop to `max_iterations`; a fallback extractor salvages an answer if the
  budget is hit without submission. [arXiv:2512.24601]
- **Benchmarks / cost / latency.**
  - OOLONG (131K tok): RLM(GPT-5-mini) 56.5% vs vanilla GPT-5 44.0%.
  - OOLONG-Pairs: base models ≤0.1%; RLM(GPT-5 depth=1) 58.0%, depth=3 76.0%.
  - BrowseComp+ (1K docs, 6–11M tok): vanilla 0% (exceeds context),
    RLM(GPT-5) 91.33%.
  - Post-trained RLM-Qwen3-8B beat base by median 28.3% and length-
    generalized from 64K → 1M tokens.
  - Cost is comparable-to-cheaper than long-context prompting (regex skips
    irrelevant docs) but with **high tail-cost variance** (confused runs loop
    expensively). Latency is the weak point: REPL + sub-calls are
    sequential/blocking; the authors note async batched sub-calls as the fix.
    [arXiv:2512.24601]

---

## 2. Retrieval — Locating Information in Large Codebases

- **SCIP (Sourcegraph Code Intelligence Protocol).** Compiler-plugin
  indexing (`scip-typescript`, `scip-java`) gives compiler-grade symbol
  graphs, type resolution, overrides, scope shadowing — but is
  **non-file-incremental**: any edit rebuilds the whole project graph (high
  latency). [SCIP; RFC 001 tree-sitter file-incremental indexing discussion]
- **Tree-sitter AST parsing.** Incremental per-file parsing at ~100k
  lines/sec, no build deps; extracts definitions, scopes, imports/exports.
  **jCodeMunch MCP** builds symbol-level indices keyed by stable IDs
  `{file_path}::{qualified_name}#{kind}`, letting agents fetch a symbol's
  block instead of a whole file — cited at ~80% (5×) token reduction.
  [jCodeMunch MCP — VirtusLab]
- **File-incremental indexing.** **Ellipsis** chunks by Tree-sitter AST and
  maps chunk IDs → content SHA hashes; on commit it deletes stale hashes and
  re-embeds only changed chunks (seconds). **Crader** restricts the
  Tree-sitter parse + DB update to modified files only (~3 orders of
  magnitude lower incremental latency); provides AST chunks with scope/type
  metadata + import/export relations. [TypeScript Repository Indexing for
  Code Agent Retrieval, arXiv:2604.18413]
- **Chunking with overlap.** Fallback = fixed-size line ranges with
  overlapping boundaries ("lines" strategy) so code isn't cut mid-statement;
  preferred = **AST-bounded chunking** (functions/classes/headers) for
  structurally complete units and better embedding quality. [Chunking
  strategy sources]
- **Agentic Map-Reduce (A-MapReduce).** Reformulates wide-scope searches to
  avoid "topological blindness". Parameterized as Θq = (Task Matrix M, Task
  Template P, Batching Strategy B). A manager agent plans the matrix +
  batching (per-atom, attribute-wise, or open), dispatches parallel search
  agents, reduces to a markdown table, and runs a **delta-patch** round to
  fill missing fields. Search logic self-refines via an **experiential
  memory** of past trajectories. Contrast with LangChain `map_reduce`
  (parallel cheap-tier map, strong-model reduce) vs `refine` (sequential,
  chunk N depends on N-1). [Executing Wide Search via Agentic MapReduce,
  arXiv; LangChain chain types]
- **Hierarchical / recursive summarization.** Hierarchical Agentic RAG = top
  manager plans, subordinate agents do domain tasks (SQL, vector, web),
  manager synthesizes. RLM treats recursion as programmatic execution:
  `llm_query` on localized segments returns into REPL variables (not the
  root chat), keeping the root clean; deep nesting uses
  `rlm_query(context, query)` to spawn child REPL sessions. [Agentic RAG
  survey, arXiv; arXiv:2512.24601]
- **REPL navigation by the root model.** Probe (`print(context[:1000])`),
  grep (`re.findall(r'pattern', context)`) to find anchors like
  decorators/endpoints without loading files into the prompt, then
  batch/delegate slices to `llm_query`/`llm_query_batched`, stitch child
  results as Python values, submit via `FINAL(answer)` / `FINAL_VAR(name)`.
  [arXiv:2512.24601; Towards Data Science — RLM one-example deep dive]

---

## 3. Recursive Problem-Solving (not just retrieval)

- **Programmatic decomposition + symbolic recursion.** The model writes
  `for`/`while` loops to partition and delegate; sub-calls (`llm_query`) run
  in isolation and return values into REPL memory, so bulk reading is pushed
  into narrow depth-1 leaf calls and the root window stays clean.
  [arXiv:2512.24601]
- **Parallel fan-out.** `llm_query_batched(prompts)` runs a prompt list
  concurrently over an async worker pool to kill the sequential bottleneck.
  [DSPy RLM]
- **Persistent tool-use loop = "exploratory data science".** The stateful
  REPL keeps variables/imports/functions alive: inspect → grep-filter (regex
  instead of neural attention) → accumulate into lists/dicts; nothing returns
  to the root prompt unless explicitly printed. [DSPy — RLM: exploring large
  contexts with code]
- **Self-correction / verification.** DSPy RLM validates `SUBMIT()` returns
  against **Pydantic type signatures**; on mismatch the stack trace is piped
  back as a new turn to guide correction. For hard reasoning, the root
  decomposes into a **DAG of self-contained nodes**, runs ready nodes in
  parallel (`llm_batch`), verifies each child against constraints, and
  memoizes only verified answers before injecting into parents. Runtime
  timeouts / `stderr` tracebacks feed back for recovery. [DSPy RLM]
- **DSPy RLM module design.** `dspy.RLM` drops into any signature as an
  inference-time strategy; inputs → REPL variables, typed output fields
  enforced on `SUBMIT()`; an **extract pass** salvages an answer if
  `max_iters` is hit; generated code **always runs in an interpreter, never
  in-process**; under **`dspy.Flex`** the module's Python source becomes a
  hyperparameter that **`dspy.GEPA`** can rewrite (change chunking, add
  helpers) to maximize the metric. [DSPy is the easiest way to use RLMs —
  Isaac Miller]
- **prime-rl (Prime Intellect).** Async RL disaggregates training from
  rollout generation; **Flow-GRPO** targets long-horizon credit assignment +
  tool reliability. Case "Fast Ask" (Ramp Sheets): a 3B model post-trained
  with a deterministic reward (correctness + speed + token conciseness) beat
  a frontier model on exact-match by 4% at a fraction of latency. [prime-rl;
  Ramp Labs]
- **Google ADK.** Uses low-level `BaseAgent` to override event streaming for
  deep recursive loops; **lazy file loading** initializes the RLM with
  reference objects (GCS/local) and fetches only requested sections.
  [Recursive Language Models in ADK]
- **Strands Agents + Amazon Bedrock AgentCore.** Serverless isolated ARM64
  containers; async long-running task-ID polling (trigger → session ID →
  poll) so multi-minute 10M-token runs don't hit HTTP timeouts. [RLMs on AWS
  with Strands Agents — Manu Mishra]
- **Self-improving agents (Prime Agent "Continual Harness").** Harness state
  H = (ρ prompts, G sub-agents, K skills/tools, M memory) is loaded into the
  IPython REPL as `rlm.harness` and is CRUD-editable by the model itself; a
  background **`/refine`** pipeline audits trajectories and applies the
  smallest edit (a prompt tweak or a new on-disk "skill") when it spots a
  recurring bottleneck or reusable tactic — turning successful trajectories
  into hardened deterministic code. [Prime Agent: A self-improving RLM agent]

---

## 4. Safe Execution of Model-Generated Python (first-class)

*embo's `rlm_repl exec` runs arbitrary Python. The tension to resolve:
safety must stay #1, yet routine operations must not prompt the user. This
section is the design input for that.*

- **Defense in depth; app-level limits are not enough.** LLM output is
  untrusted at execution; language-level guards (blocking imports, stripping
  `ctypes`) can be bypassed via WASM/native FFI, so isolation must be
  enforced at the runtime level. [Isolation strategies sources]
- **WASM/Pyodide + Deno — caution.** Pyodide (CPython→WASM) under Deno's
  permission model restricts FS/network by default, **but** Python in
  Pyodide can run arbitrary JavaScript and, with broad host perms, resolve
  Emscripten C symbols (`emscripten_run_script_string`, `system`) to escape.
  Pydantic **archived** its Pyodide MCP server, warning there is "no safe way
  to run Python within pyodide safely with reasonable latency" and Deno can't
  prevent OOM. [pydantic/mcp-run-python; langchain-sandbox]
- **Docker is not a sandbox for untrusted code.** Shares the host kernel;
  relies on namespaces/cgroups/AppArmor/seccomp; a single kernel bug
  (e.g. CVE-2024-21626) enables escape. [Container isolation sources]
- **gVisor.** User-space Go kernel intercepts syscalls; an escape needs a
  Sentry bug *and* a host-kernel bug. Cost: ~10–30% I/O tax. [gVisor;
  Firecracker vs gVisor — Northflank]
- **Firecracker microVMs.** Rust VMM on KVM, stripped device model, ~100–125ms
  boot, ≤5 MiB overhead/VM. **Kata Containers** wrap each container in a
  microVM with native K8s APIs. [Firecracker; Kata sources]
- **Managed services.** E2B = ephemeral Firecracker microVMs, session-scoped;
  Modal = gVisor, high concurrency + GPUs; Daytona = sub-90ms cold start
  (note: archived/closed mid-2026); Beam (beta9) = gVisor+runc with
  persistence. [Sandbox comparison sources — Modal/Northflank/Beam/Blaxel]
- **Filesystem lockdown.** Ephemeral FS destroyed on session end; read-only
  root; writable only in a scoped `tmpfs` with `noexec,nosuid,nodev` + size
  caps; avoid host bind mounts — use copy-in/out or **git worktree pairing**
  to diff modifications before they touch real files. [Filesystem rules
  sources]
- **Network isolation / allowlisting.** Default-deny egress; egress proxy
  inspecting TLS SNI for domain allowlists; DNS filtering to stop exfil via
  subdomain encoding; block RFC-1918 + `169.254.169.254` metadata (SSRF).
  [Network governance sources]
- **Resource limits via cgroups v2** (OS-level, since code can override app
  limits): `cpu.max`; hard `memory.max` with swap disabled (kill on OOM,
  don't freeze host); `pids.max` (neutralize fork bombs); host-managed
  wall-clock timeouts (30–120s). [cgroups/microVM limit sources]
- **HITL risk-tiering (the key pattern for embo's approval friction).**
  Gating every call causes approval fatigue and rubber-stamping (one study:
  humans missed ~1 in 3 threats when approving agent commands). Classify
  tools into tiers:
  - **Low** (read-only: read/glob/grep, planning) → **auto-execute**, logged.
  - **Medium** (cheap local mutations, scratchpad/cache) → **auto-execute**,
    batch-reviewed.
  - **High** (`run_bash`/`rm -rf`, editing source, external/irreversible) →
    **pre-action gate**, explicit approval.
  [Runtime Control for AI Agents — Unleash; Human-in-the-loop — Strands;
  "Humans missed 1 in 3 threats" — Reddit study]
- **Pre-action gate, not post-action.** An interceptor runs in middleware
  *before* the tool: match an allowlist or run a lightweight secondary LLM
  risk classifier on the argument strings; on high risk, suspend the loop and
  show the exact tool name + deserialized args. On deny, return a mock tool
  message ("Permission denied … do not retry without asking") so the model
  replans. A per-session "always allow" toggle caches the decision.
  [Pre-action gate sources]
- **Precedent: existing CLIs.** Claude Code and OpenAI's Codex CLI both use
  **bubblewrap** on Linux and **Seatbelt** on macOS; the "acceptEdits mode →
  allow writes to the project path only" write-path check is a concrete
  capability-scoped gate embo can mirror. [bubblewrap/Seatbelt; write-path
  sources]

---

## 5. Mapping to embo — Most Actionable Improvements

Each item names the embo component it touches and the source(s) that back it.
These are research-supported directions, not yet decisions; they are the raw
material for a PRD / tech-design.

1. **File-incremental re-index (SHA-per-file).** `rlm_repl.py` — store a
   content SHA per path in state; on re-index, only re-scan changed files.
   Fixes the "no incremental re-index" gap. [Crader/Ellipsis —
   arXiv:2604.18413]
2. **Tree-sitter symbol layer with stable IDs.** `rlm_repl.py` — store
   `{file_path}::{qualified_name}#{kind}` entries so the root can fetch a
   function/class block by name instead of a whole file (~80% token savings),
   and grep can target symbols. Fixes "no content/summaries stored". [jCodeMunch;
   Tree-sitter; Crader] **This is the one improvement that genuinely requires a
   third-party dependency — see the "Dependency policy" recommendation below.**
3. **Repo-wide grep returning file+line anchors.** `rlm_repl.py` helpers —
   embo's grep only works in single-file mode, which blocks the core RLM
   navigation pattern ("grep for anchors, then delegate slices"). [arXiv:2512.24601]
4. **Batch the `rlm-subcall` fan-out.** `rlm-subcall` agent + command layer —
   embo's sequential Haiku sub-calls are the exact bottleneck the paper
   flags; dispatch chunk analyses concurrently. [arXiv:2512.24601; DSPy]
5. **Chunk overlap + AST-bounded chunks.** `rlm_repl.py` (`chunk_indices`) —
   overlapping line windows as fallback, Tree-sitter boundaries as primary;
   fixes "no chunk-overlap merging". [Chunking sources]
6. **Constant-size-metadata contract + `FINAL_VAR`.** command layer / REPL —
   return only stdout metadata (length + truncated prefix) to the root; add
   explicit `FINAL_VAR(name)` termination + a fallback extractor at
   `max_iterations`. Controls tail-cost. [arXiv:2512.24601 Algorithm 1]
7. **Context hygiene: prefer the subagent path over direct exec.** command
   layer — direct `rlm_repl exec` prints results into the main agent's
   context; only `rlm-subcall` keeps bulk out. Route bulk-producing RLM work
   through the subagent by default. [Observed this session; arXiv:2512.24601]
8. **Replace the exec approval prompt with tiered pre-action gating.**
   hooks + permissions — auto-run Low-tier (read-only peek/grep/chunk over
   the in-memory `context`); keep the human gate only for High-tier
   (filesystem writes, network, `rm`, arbitrary shell). Resolves the
   safety-vs-friction tension without a blanket prompt. [Risk tiering;
   pre-action gate; bubblewrap/Seatbelt; acceptEdits write-path]
9. **Sandbox `exec` with OS-level limits + capability scoping.** `rlm_repl.py`
   / wrapper — even without full microVMs, apply cgroups-style CPU/mem/pids/
   timeout caps, a read-only FS with a `noexec` tmpfs scratch, and
   default-deny network for the REPL; consider git-worktree copy-on-write so
   writes diff before touching source. [cgroups v2; filesystem lockdown; git
   worktree pairing]
10. **Harden persistence beyond the fragile pickle.** `rlm_repl.py` — move
    index state to a robust store (SHA-keyed records / SQLite) enabling
    incremental upsert/delete and an experiential-memory table. **`sqlite3` is
    in the Python stdlib, so this needs no new dependency** and is compatible
    with the current "no dependencies" rule as written. [A-MapReduce
    experiential memory; Ellipsis SHA mapping]
11. **Optional: self-improving command layer.** command layer + `/embo:improve`
    — a `/refine`-style background audit that promotes recurring successful
    tactics into on-disk skills mirrors embo's existing "enforce, don't ask"
    / correction-capture philosophy. [Prime Agent Continual Harness; DSPy
    Flex + GEPA]

### Dependency policy — recommendation

embo's current constraint (CLAUDE.md) is "No dependencies: REPL uses stdlib
only." This research recommends **relaxing that rule to allow OPTIONAL
dependencies for RLM power features, with graceful degradation when the
dependency is absent.** Rationale and scope:

- Of the 11 items above, only **#2 (Tree-sitter symbol layer)** genuinely
  needs a third-party package. **#10 (SQLite state)** does not — `sqlite3` is
  stdlib. The other nine are pure-stdlib changes.
- The value of #2 is large (symbol-level fetch, ~80% token reduction, the
  basis for symbol-aware grep and incremental symbol indexing), so a blanket
  no-dependency rule blocks embo's single biggest retrieval upgrade.
- **Proposed shape:** Tree-sitter (and any future power dep) is an *optional
  extra*. If importable, embo uses the symbol layer; if not, it falls back to
  the stdlib regex/line-based path with no error. The zero-dependency install
  keeps working exactly as today. This preserves embo's "installs everywhere"
  property while unlocking the upgrade for users who opt in.
- **Decision needed:** amend CLAUDE.md's "Key Constraints" from "No
  dependencies" to "No *required* dependencies; optional extras permitted with
  stdlib fallback." (Recorded here as a recommendation; the actual CLAUDE.md
  edit belongs to the implementing task, not this report.)

### Recommended first scope — the cheap, high-impact cluster

If/when this moves past research, anchor the first task on three items that
are small, need **no** new dependency, and directly fix friction observed this
session:

- **#3 Repo-wide grep returning file+line anchors** — unblocks the core RLM
  navigation loop; currently grep is single-file-only.
- **#7 Context hygiene / prefer the subagent path** — route bulk-producing RLM
  work through `rlm-subcall` by default so results don't flood the main
  agent's context (the gap the requester caught live).
- **#8 Tiered pre-action gating for `exec`** — auto-run read-only Low-tier
  operations, gate only High-tier (writes/network/shell). Resolves the
  approval-prompt friction without weakening safety.

Deferred to later tasks: #1 (incremental index — medium, stdlib-only),
#2 (Tree-sitter — needs the dependency-policy decision first), #9 (OS-level
sandbox — largest effort).

---

## 6. Notable Implementations & Sources (for follow-up)

**Reference / library code**
- `alexzhang13/rlm` — official plug-and-play RLM inference library, multiple
  sandboxes. `alexzhang13/rlm-minimal` — gist-like minimal implementation.
- `fullstackwebdev/rlm_repl` — RLM based on the Zhang/Kraska/Khattab paper.
- DSPy — `dspy.RLM` module, `dspy.PythonInterpreter`, `dspy.Flex` + `GEPA`.

**RLM for Claude Code (closest prior art to embo)**
- `Tenobrus/claude-rlm` — RLM for Claude Code skills.
- `marknutter/recursive-ai` — RLM for Claude Code.
- `Brainqub3` Claude-code RLM scaffold (embo's cited ancestor).

**Sandboxing / safe execution**
- `pydantic/mcp-run-python` (archived — read the warning),
  `langchain-ai/langchain-sandbox` (Pyodide + Deno), E2B, Modal, Beam
  (beta9), Kata/Firecracker/gVisor comparisons.

**Video lectures (author-featured)**
- MIT CSAIL Explains: Recursive Language Models — youtu.be/umbtFGPzdAM
- Scaling LLMs to 10M+ Tokens (MIT CSAIL RLMs) — youtu.be/1knD5bpCm74
- Ep. 40: Alex Zhang, RLM creator (MIT CSAIL) — youtu.be/fXSFVi3JEEo
- Recursive Language Models w/ Alex Zhang — youtu.be/6Dr3SUmHFco

**Full provenance**: all ~138 sources live in the Gemini Notebook linked at
the top; the four distilled query answers (with `.citations` UUIDs and
`.references` cited-text) were extracted via subagent and are the basis for
the citations above.
