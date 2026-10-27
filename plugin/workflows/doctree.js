export const meta = {
  name: 'doctree',
  description: 'Build a feature doc tree (PRD, tech-design, tasks) with reviewed phases',
  phases: [
    { title: 'PRD' },
    { title: 'Tech-design' },
    { title: 'Tasks' },
  ],
}

// This script resolves NONE of its configuration: everything arrives via
// `args`, resolved by the entry command (commands/doctree.md). It cannot
// read the profile, touch the filesystem, shell out, import() modules, or
// call new Date() / Date.now() / Math.random() — those would break resume
// or are unavailable in the workflow sandbox. The run date arrives in
// args.run_date. The amendment validator below is an inlined copy of the
// shell doctree_validate_amend, kept in step by the shared parity fixtures
// in lib/doctree-amend-fixtures.json (exercised by lib/doctree-lib.test.sh
// for the shell side and workflows/doctree.test.js for this side).

const PHASES = [
  { key: 'prd', title: 'PRD', suffix: 'prd', modelArg: 'model_prd' },
  { key: 'tech-design', title: 'Tech-design', suffix: 'tech-design', modelArg: 'model_tech_design' },
  { key: 'tasks', title: 'Tasks', suffix: 'tasks', modelArg: 'model_tasks' },
]

// validateAmend(record) -> true when the AMEND record is well-formed by
// the mechanical rules (field presence + enum shape), false otherwise.
// Mirrors doctree_validate_amend in lib/doctree-lib.sh. Does NOT resolve
// evidence or match a live section — those are live checks. Kept
// self-contained (its enums are local) so it stands alone as an inlined
// sandbox copy and is extractable for the parity test.
function validateAmend(record) {
  const REQUIRED = [
    'target', 'section', 'finding', 'evidence', 'proposed',
    'origin', 'severity', 'status', 'prior_state',
  ]
  const TARGETS = ['prd', 'tech-design', 'tasks']
  const SEVERITIES = ['high', 'medium', 'low', 'infeasible']
  const STATUSES = ['open', 'resolved']
  if (record === null || typeof record !== 'object' || Array.isArray(record)) {
    return false
  }
  for (const field of REQUIRED) {
    const v = record[field]
    if (v === undefined || v === null || String(v).length === 0) return false
  }
  if (!TARGETS.includes(record.target)) return false
  if (!SEVERITIES.includes(record.severity)) return false
  if (!STATUSES.includes(record.status)) return false
  return true
}

// The digest schema every phase stage must return (fixed shape, per the
// phase agent's output contract).
const DIGEST_SCHEMA = {
  type: 'object',
  properties: {
    document: { type: 'string' },
    summary: { type: 'string' },
    decisions_taken: { type: 'number' },
    blocked: { type: 'array', items: { type: 'object' } },
    amend: { type: 'array', items: { type: 'object' } },
    canary: { type: 'string' },
  },
  required: ['document', 'summary', 'decisions_taken', 'blocked', 'amend', 'canary'],
}

// The findings schema a review pass returns. severity in
// {high, medium, low, infeasible}; status open|resolved; significant =
// {high, infeasible} (defined once, matches doctree_finding_is_significant).
const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    pass: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          phase: { type: 'string' },
          section: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low', 'infeasible'] },
          status: { type: 'string', enum: ['open', 'resolved'] },
          finding: { type: 'string' },
          // A significant finding must carry these three as well, or it
          // cannot become an amendment and so cannot change the document
          // it is about. target names the document the fix belongs in,
          // which is not always the reviewed one.
          target: { type: 'string', enum: ['prd', 'tech-design', 'tasks'] },
          evidence: { type: 'string' },
          proposed: { type: 'string' },
          prior_state: { type: 'string' },
        },
        required: ['severity', 'status', 'finding'],
      },
    },
  },
  required: ['pass', 'findings'],
}

function isSignificant(f) {
  return f && (f.severity === 'high' || f.severity === 'infeasible')
}

// findingToAmend(finding, originPhase) -> an AMEND record, or null.
// This is the bridge that lets a REVIEW change a document. Without it a
// reviewer's finding is recorded and nothing else: the replay path only
// consumes amendments, so review stays advisory and the document it
// criticises is never corrected. Returns null when the reviewer did not
// supply the grounding fields; validateAmend is still the gate, so an
// ungrounded record cannot slip through here.
function findingToAmend(f, originPhase) {
  if (!isSignificant(f)) return null
  if (!f.target || !f.section || !f.evidence || !f.proposed || !f.prior_state) return null
  return {
    target: f.target,
    section: f.section,
    finding: f.finding,
    evidence: f.evidence,
    proposed: f.proposed,
    origin: originPhase,
    severity: f.severity,
    status: f.status || 'open',
    prior_state: f.prior_state,
  }
}

function reviewPrompt(ph, doc, pass, reviewerFamily) {
  return [
    `You are the ${pass} review pass for the ${ph.key} phase of a doc-tree run.`,
    `Review the document at ${doc} independently — you did NOT author it.`,
    pass === 'research'
      ? 'Judge it against prior art via the NotebookLM MCP.'
      : 'Judge it against the codebase and internal consistency.',
    'Return findings per the schema: each with a severity',
    '(high | medium | low | infeasible) and a status (open | resolved).',
    '',
    'A finding you mark high or infeasible is SIGNIFICANT, and a',
    'significant finding is expected to fix the document, not merely',
    'describe what is wrong with it. So for each one also return:',
    '  target      — which document the fix belongs in (prd |',
    '                tech-design | tasks); it is not always this one',
    '  section     — the exact section heading the fix changes',
    '  evidence    — a resolvable citation: a file:line in this repo, a',
    '                command and its output, or a reachable URL. Your own',
    '                reasoning is NOT evidence.',
    '  proposed    — the replacement text for that section, written out',
    '  prior_state — the section\'s current text, verbatim, so the change',
    '                can be reverted',
    '',
    'A significant finding missing any of these is dropped: it cannot be',
    'applied and it will not change the document. If you cannot ground a',
    'concern in resolvable evidence, mark it medium or low instead of',
    'inflating its severity — medium and low are recorded as open items',
    'and never replay.',
    `Reviewer family: ${reviewerFamily || 'sonnet'}.`,
  ].join('\n')
}

function docPath(taskDir, runDate, slug, suffix) {
  const dir = taskDir.replace(/\/+$/, '')
  return `${dir}/${runDate}-${slug}-${suffix}.md`
}

function dispatchPrompt(ph, a, upstreamDocs) {
  const sources = a.seed_doc ? [a.seed_doc, ...upstreamDocs] : upstreamDocs
  return [
    'You are running as a spawned doc-tree phase. Dispatch brief:',
    '',
    '```yaml',
    `phase:         ${ph.key}`,
    'mode:          full',
    `task_dir:      ${a.task_dir}`,
    `feature_slug:  ${a.feature_slug}`,
    `phase_skill:   embo:${ph.key}`,
    'skip_steps:    ["the mandatory clarifying-question step"]',
    `seed_doc:      ${a.seed_doc || '(none)'}`,
    `upstream_docs: ${JSON.stringify(upstreamDocs)}`,
    '```',
    '',
    a.feature_description
      ? `What the feature is: ${a.feature_description}`
      : 'The brief carries no feature description; the sources below define it.',
    '',
    sources.length
      ? `READ THESE FIRST, in order — they state what the feature is:\n${sources.map(s => `  - ${s}`).join('\n')}`
      : 'No source documents exist yet; this phase defines the feature from scratch.',
    '',
    `Run date for the document filename: ${a.run_date}.`,
    'Set the environment variable EMBO_DOCTREE_UNATTENDED for your run so',
    'the phase command takes its unattended branch. Follow your output',
    'contract exactly: write the document under task_dir and return the',
    'fixed-shape digest and nothing else.',
  ].join('\n')
}

// --- Budget and round counters: runtime properties, not prose ---
// Exported as pure helpers so lib tests can exercise the thresholds
// without running the whole workflow.

// budgetAllows(spent, max) -> may another agent be spawned?
function budgetAllows(spent, max) {
  return spent < max
}

// roundExhausted(round, cap) -> has the GLOBAL round counter hit the cap?
// round is one full pass over all three phases, not a per-phase count.
function roundExhausted(round, cap) {
  return round >= cap
}

// shouldReplay(significantCount, round, cap) -> replay the affected phase?
// The termination rule (D8): replay only while there is a significant
// finding AND the round counter is below the cap. Mirrors the shell
// doctree_should_replay so both paths terminate identically.
function shouldReplay(significantCount, round, cap) {
  return significantCount >= 1 && round < cap
}

// checkRequiredArgs(a) -> null when all required fields are present, or an
// array of missing field names. The workflow refuses to spawn any agent when
// required fields are absent: an undefined task_dir or feature_slug produces
// a broken dispatch brief that stalls the phase agent before it can do work.
function checkRequiredArgs(a) {
  const missing = ['task_dir', 'feature_slug', 'run_date'].filter(k => {
    const v = a[k]
    if (!v) return true
    const s = String(v).trim()
    return s.length === 0 || s === 'undefined' || s === 'null'
  })
  return missing.length === 0 ? null : missing
}

const a = args || {}

const missing = checkRequiredArgs(a)
if (missing) {
  return { error: `required args missing: ${missing.join(', ')}`, missing }
}

const maxAgents = typeof a.max_agents === 'number' ? a.max_agents : 20
const roundCap = typeof a.round_cap === 'number' ? a.round_cap : 2
let agentCount = 0
let round = 0 // GLOBAL round count: one full pass over all three phases, not per-phase

const produced = []
const upstreamDocs = []
const allBlocked = []
let capHitWithFindings = false

round = 1
for (const ph of PHASES) {
  if (!budgetAllows(agentCount, maxAgents)) {
    log(`agent budget (${maxAgents}) reached before ${ph.key}; stopping`)
    break
  }
  phase(ph.title)
  const model = a[ph.modelArg]
  agentCount += 1
  const digest = await agent(
    dispatchPrompt(ph, a, upstreamDocs.slice()),
    { label: `phase:${ph.key}`, phase: ph.title, model, schema: DIGEST_SCHEMA, agentType: 'embo:doctree-phase' }
  )
  if (!digest || !digest.document) {
    log(`phase ${ph.key} returned no document; stopping`)
    break
  }
  // Amendments the AUTHOR raised about an upstream document. Review-derived
  // amendments are added below, once the review passes have run.
  const amendments = Array.isArray(digest.amend) ? digest.amend.filter(validateAmend) : []
  if (Array.isArray(digest.blocked)) {
    for (const b of digest.blocked) allBlocked.push({ phase: ph.key, ...b })
  }

  // --- Review: two passes, spawned by the lead (never by the authoring
  // agent), running different lenses. Both must run (FR-5).
  let findings = []
  if (budgetAllows(agentCount, maxAgents)) {
    const reviewerFamily = a.reviewer_model_family || 'sonnet'
    agentCount += 2
    const passes = await parallel([
      () => agent(reviewPrompt(ph, digest.document, 'research', reviewerFamily),
        { label: `review:${ph.key}:research`, phase: ph.title, model: reviewerFamily, schema: FINDINGS_SCHEMA, agentType: 'embo:examine-advisor' }),
      () => agent(reviewPrompt(ph, digest.document, 'internal', reviewerFamily),
        { label: `review:${ph.key}:internal`, phase: ph.title, model: reviewerFamily, schema: FINDINGS_SCHEMA, agentType: 'embo:examine-advisor' }),
    ])
    findings = passes.filter(Boolean).flatMap(p => (Array.isArray(p.findings) ? p.findings : []))

    // Convert each significant finding into an amendment, so a review can
    // CHANGE the document it criticises instead of only describing it.
    // A significant finding that arrives ungrounded is dropped here and
    // said so out loud — a silent drop reads as "review found nothing".
    const sig = findings.filter(isSignificant)
    const reviewAmends = sig
      .map(f => findingToAmend(f, ph.key))
      .filter(Boolean)
      .filter(validateAmend)
    const dropped = sig.length - reviewAmends.length
    if (dropped > 0) {
      log(`${dropped} of ${sig.length} significant finding(s) on ${ph.key} lacked grounding (target/section/evidence/proposed/prior_state) and cannot amend the document`)
    }
    if (reviewAmends.length > 0) {
      log(`${reviewAmends.length} review finding(s) on ${ph.key} became amendment(s)`)
      amendments.push(...reviewAmends)
    }
  } else {
    log(`agent budget (${maxAgents}) reached before reviewing ${ph.key}; review skipped`)
  }
  const significant = findings.filter(isSignificant)

  produced.push({
    phase: ph.key,
    document: digest.document,
    decisions_taken: digest.decisions_taken,
    canary: digest.canary,
    amendments,
    findings,
    significant_count: significant.length,
  })
  upstreamDocs.push(digest.document)

  // --- Back-pressure: a significant finding with a grounded amendment
  // targeting an upstream document re-spawns that phase in section-scoped
  // mode, bounded by the global round cap (D7/D8). The round counter is
  // GLOBAL — one increment per replay, not per phase — so the cap bounds
  // total cost. A medium/low finding never replays.
  const groundedAmends = amendments.filter(validateAmend)
  if (significant.length > 0 && roundExhausted(round, roundCap)) {
    log(`round cap (${roundCap}) reached with ${significant.length} significant finding(s) open — CLOSE, stopping for approval`)
    capHitWithFindings = true
  } else if (shouldReplay(significant.length, round, roundCap)
      && groundedAmends.length > 0
      && budgetAllows(agentCount, maxAgents)) {
    round += 1
    // ALL grounded amendments are applied, not just the first. Amendments
    // can name different target documents, so they are grouped by target
    // and each affected document gets one replay carrying every amendment
    // for it. Applying one and dropping the rest silently loses findings
    // that passed every validation gate, and the round cap then denies
    // them a second chance.
    const byTarget = new Map()
    for (const am of groundedAmends) {
      if (!byTarget.has(am.target)) byTarget.set(am.target, [])
      byTarget.get(am.target).push(am)
    }
    const targets = [...byTarget.keys()]
    log(`replay round ${round}: ${groundedAmends.length} amendment(s) from ${ph.key} across ${targets.length} document(s): ${targets.join(', ')}`)
    for (const [target, amends] of byTarget) {
      if (!budgetAllows(agentCount, maxAgents)) {
        log(`agent budget (${maxAgents}) reached; ${amends.length} amendment(s) to ${target} NOT applied`)
        break
      }
      agentCount += 1
      const sections = amends.map(am => am.section)
      await agent(
        [
          'You are a section-scoped replay of a doc-tree phase.',
          `Re-run phase ${target} in section-scoped mode, changing ONLY`,
          `these sections: ${sections.map(s => `"${s}"`).join(', ')}.`,
          'Apply every amendment below to its own named section:',
          '',
          ...amends.map(am => [
            '```yaml',
            `section:  ${am.section}`,
            `finding:  ${am.finding}`,
            `evidence: ${am.evidence}`,
            `proposed: ${am.proposed}`,
            '```',
          ].join('\n')),
          '',
          'Leave every other section byte-for-byte unchanged. Apply ALL of',
          'them — a partial application silently loses a reviewed finding.',
          'Set EMBO_DOCTREE_UNATTENDED for your run.',
        ].join('\n'),
        { label: `replay:${target}:${sections.length} section(s)`, phase: PHASES.find(p => p.key === target)?.title || ph.title, schema: DIGEST_SCHEMA, agentType: 'embo:doctree-phase' }
      )
    }
  }

  // escalation: halt stops at the first blocked item.
  if (a.escalation === 'halt' && Array.isArray(digest.blocked) && digest.blocked.length > 0) {
    log(`escalation=halt: stopping at first blocked item in ${ph.key}`)
    break
  }
}

return {
  documents: produced.map(p => p.document),
  phases: produced,
  blocked: allBlocked,
  rounds: round,
  agents_spawned: agentCount,
  round_cap: roundCap,
  cap_hit_with_findings: capHitWithFindings,
}
