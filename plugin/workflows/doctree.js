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
export function validateAmend(record) {
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

function reviewPrompt(ph, doc, pass, reviewerFamily) {
  return [
    `You are the ${pass} review pass for the ${ph.key} phase of a doc-tree run.`,
    `Review the document at ${doc} independently — you did NOT author it.`,
    pass === 'research'
      ? 'Judge it against prior art via the NotebookLM MCP.'
      : 'Judge it against the codebase and internal consistency.',
    'Return findings per the schema: each with a severity',
    '(high | medium | low | infeasible) and a status (open | resolved).',
    'A high or infeasible finding is significant and may trigger a replay;',
    'medium and low are recorded but do not. Reviewer family:',
    `${reviewerFamily || 'sonnet'}.`,
  ].join('\n')
}

function docPath(taskDir, runDate, slug, suffix) {
  const dir = taskDir.replace(/\/+$/, '')
  return `${dir}/${runDate}-${slug}-${suffix}.md`
}

function dispatchPrompt(ph, a, upstreamDocs) {
  return [
    'You are running as a spawned doc-tree phase. Dispatch brief:',
    '',
    '```yaml',
    `phase:         ${ph.key}`,
    'mode:          full',
    `task_dir:      ${a.task_dir}`,
    `feature_slug:  ${a.feature_slug}`,
    `command_file:  plugin/commands/${ph.key}.md`,
    'skip_steps:    ["the mandatory clarifying-question step"]',
    `upstream_docs: ${JSON.stringify(upstreamDocs)}`,
    '```',
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
export function budgetAllows(spent, max) {
  return spent < max
}

// roundExhausted(round, cap) -> has the GLOBAL round counter hit the cap?
// round is one full pass over all three phases, not a per-phase count.
export function roundExhausted(round, cap) {
  return round >= cap
}

const a = args || {}

const maxAgents = typeof a.max_agents === 'number' ? a.max_agents : 20
const roundCap = typeof a.round_cap === 'number' ? a.round_cap : 2
let agentCount = 0
let round = 0 // GLOBAL round count: one full pass over all three phases, not per-phase

const produced = []
const upstreamDocs = []
const allBlocked = []

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
  // Keep only well-formed amendments (inlined validator, parity fixtures).
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
}
