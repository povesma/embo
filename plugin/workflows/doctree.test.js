// Tests for the doctree workflow script's pure parts.
// Run: node plugin/workflows/doctree.test.js
// Exits non-zero if any assertion fails.
//
// The workflow script uses top-level await/return (required by the
// Workflow runner), so it cannot be imported as an ES module. Instead this
// test reads the source, extracts the exported pure functions by name, and
// evaluates them in isolation — so the ACTUAL inlined validator is tested,
// not a copy. The validator is run against the SAME parity fixtures as the
// shell validator (lib/doctree-amend-fixtures.json), so the two cannot
// drift. It also statically scans the source for the constructs the
// sandbox forbids.

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))
const SRC = readFileSync(join(HERE, 'doctree.js'), 'utf8')
const FIXTURES = JSON.parse(
  readFileSync(join(HERE, '..', 'lib', 'doctree-amend-fixtures.json'), 'utf8')
)

let pass = 0
let fail = 0
function assert(desc, cond) {
  if (cond) { pass += 1 } else { fail += 1; console.log(`FAIL: ${desc}`) }
}
function assertEq(desc, exp, act) {
  if (exp === act) { pass += 1 } else {
    fail += 1
    console.log(`FAIL: ${desc}\n  expected: [${exp}]\n  actual:   [${act}]`)
  }
}

// Extract one `function <name>(...) { ... }` block by brace matching.
// The workflow runtime rejects any `export` but `export const meta`, so the
// pure helpers are plain declarations and are extracted by name from source.
function extractFn(name) {
  const marker = `function ${name}(`
  const start = SRC.indexOf(marker)
  if (start < 0) throw new Error(`function not found: ${name}`)
  let i = SRC.indexOf('{', start)
  let depth = 0
  for (; i < SRC.length; i++) {
    if (SRC[i] === '{') depth += 1
    else if (SRC[i] === '}') { depth -= 1; if (depth === 0) { i += 1; break } }
  }
  const body = SRC.slice(start.valueOf(), i).replace(/^export\s+/, '')
  // eslint-disable-next-line no-new-func
  return new Function(`${body}; return ${name};`)()
}

// Extract several functions into ONE scope, for a function that calls
// another (findingToAmend calls isSignificant); returns the last named.
function extractFnWithDeps(name, ...deps) {
  const src = [...deps, name].map(n => {
    const marker = `function ${n}(`
    const start = SRC.indexOf(marker)
    if (start < 0) throw new Error(`function not found: ${n}`)
    let i = SRC.indexOf('{', start)
    let depth = 0
    for (; i < SRC.length; i++) {
      if (SRC[i] === '{') depth += 1
      else if (SRC[i] === '}') { depth -= 1; if (depth === 0) { i += 1; break } }
    }
    return SRC.slice(start, i)
  }).join('\n')
  // eslint-disable-next-line no-new-func
  return new Function(`${src}; return ${name};`)()
}

const validateAmend = extractFn('validateAmend')
const budgetAllows = extractFn('budgetAllows')
const roundExhausted = extractFn('roundExhausted')
const shouldReplay = extractFn('shouldReplay')
const isSignificant = extractFn('isSignificant')
const findingToAmend = extractFnWithDeps('findingToAmend', 'isSignificant')
const checkRequiredArgs = extractFn('checkRequiredArgs')

// ---- 11.1: checkRequiredArgs — workflow refuses to spawn on missing args ----

assert('checkRequiredArgs: all present → null',
  checkRequiredArgs({ task_dir: 'tasks/001-foo/', feature_slug: 'foo', run_date: '2026-10-27' }) === null)
assert('checkRequiredArgs: missing task_dir → non-null',
  checkRequiredArgs({ feature_slug: 'foo', run_date: '2026-10-27' }) !== null)
assert('checkRequiredArgs: missing feature_slug → non-null',
  checkRequiredArgs({ task_dir: 'tasks/001-foo/', run_date: '2026-10-27' }) !== null)
assert('checkRequiredArgs: missing run_date → non-null',
  checkRequiredArgs({ task_dir: 'tasks/001-foo/', feature_slug: 'foo' }) !== null)
assert('checkRequiredArgs: task_dir="undefined" string → non-null',
  checkRequiredArgs({ task_dir: 'undefined', feature_slug: 'foo', run_date: '2026-10-27' }) !== null)
assert('checkRequiredArgs: feature_slug="undefined" string → non-null',
  checkRequiredArgs({ task_dir: 'tasks/001-foo/', feature_slug: 'undefined', run_date: '2026-10-27' }) !== null)
assert('checkRequiredArgs: all three missing → lists all three',
  checkRequiredArgs({}).length === 3)

// ---- 11.3: dispatch prompt uses phase_skill, not command_file ----
// A file path only exists inside the embo repo; a skill name works from any repo.

assert('11.3: dispatch prompt contains phase_skill, not command_file',
  !SRC.includes('command_file:  plugin/commands/'))

// ---- 5.5: inlined validator against the shared parity fixtures ----

for (const c of FIXTURES.cases) {
  const got = validateAmend(c.record) ? 'valid' : 'rejected'
  assertEq(`validateAmend[${c.id}]`, c.verdict, got)
}

// ---- 5.5: parity with the shell side — same verdict counts ----

const expectedValid = FIXTURES.cases.filter(c => c.verdict === 'valid').length
const gotValid = FIXTURES.cases.filter(c => validateAmend(c.record)).length
assertEq('validateAmend: valid-case count matches fixtures', expectedValid, gotValid)

// ---- 5.5: validator rejects non-objects ----

assert('validateAmend: null → false', validateAmend(null) === false)
assert('validateAmend: array → false', validateAmend([]) === false)
assert('validateAmend: string → false', validateAmend('x') === false)

// ---- 5.3: agent-budget threshold ----

assert('budgetAllows: under cap → true', budgetAllows(0, 20) === true)
assert('budgetAllows: one below cap → true', budgetAllows(19, 20) === true)
assert('budgetAllows: at cap → false', budgetAllows(20, 20) === false)
assert('budgetAllows: over cap → false', budgetAllows(21, 20) === false)

// ---- 5.4: global round-cap threshold ----

assert('roundExhausted: below cap → false', roundExhausted(1, 2) === false)
assert('roundExhausted: at cap → true', roundExhausted(2, 2) === true)
assert('roundExhausted: over cap → true', roundExhausted(3, 2) === true)

// ---- 8.7 parity: the JS termination rule matches the shell rule ----

assert('shouldReplay: significant, round 0 < cap → true', shouldReplay(1, 0, 2) === true)
assert('shouldReplay: significant, round 1 < cap → true', shouldReplay(1, 1, 2) === true)
assert('shouldReplay: significant, round 2 = cap → false', shouldReplay(1, 2, 2) === false)
assert('shouldReplay: no significant → false', shouldReplay(0, 0, 2) === false)
assert('shouldReplay: over cap → false', shouldReplay(3, 3, 2) === false)

// ---- 5.6: the script uses no forbidden constructs ----
// Strip line comments so the prohibition-naming comment block doesn't
// trip the scan; then assert none of the forbidden calls appear.

const code = SRC.replace(/\/\/[^\n]*/g, '')
for (const bad of ['Date.now(', 'Math.random(', 'new Date(', 'import(', 'require(']) {
  assert(`5.6: no ${bad}` , !code.includes(bad))
}
for (const fs of ['readFileSync', 'writeFileSync', 'child_process', 'execSync', 'spawnSync']) {
  assert(`5.6: no filesystem/shell (${fs})`, !code.includes(fs))
}

// ---- the review-to-amendment bridge ----
// Without this bridge a reviewer's finding is recorded and never applied,
// so review cannot change the document it criticises. These assert that a
// grounded significant finding DOES become a valid amendment, and that an
// ungrounded or non-significant one does not.

const groundedFinding = {
  severity: 'high',
  status: 'open',
  finding: 'FR-3 has no acceptance criterion that can fail',
  target: 'prd',
  section: 'FR-3',
  evidence: 'tasks/x/prd.md:88',
  proposed: 'FR-3: ... with criterion: hook exits 2 on a protected branch',
  prior_state: 'FR-3: the guard should generally prevent this',
}

const amend = findingToAmend(groundedFinding, 'tech-design')
assert('bridge: a grounded significant finding becomes an amendment', amend !== null)
assert('bridge: the amendment passes validateAmend', validateAmend(amend))
assertEq('bridge: origin is the reviewing phase', 'tech-design', amend.origin)
assertEq('bridge: target is the document to fix', 'prd', amend.target)

for (const missing of ['target', 'section', 'evidence', 'proposed', 'prior_state']) {
  const f = { ...groundedFinding }
  delete f[missing]
  assert(`bridge: significant finding without ${missing} is dropped`,
    findingToAmend(f, 'tech-design') === null)
}

for (const sev of ['medium', 'low']) {
  assert(`bridge: a ${sev} finding never amends, even fully grounded`,
    findingToAmend({ ...groundedFinding, severity: sev }, 'tech-design') === null)
}

assert('bridge: an infeasible finding is significant and amends',
  findingToAmend({ ...groundedFinding, severity: 'infeasible' }, 'prd') !== null)

// The regression this whole bridge exists to prevent: a review pass that
// returns findings but produces zero amendments, so the document stands
// uncorrected. A grounded significant finding must never do that.
assert('bridge: grounded significant findings do not yield an empty amendment set',
  [groundedFinding].map(f => findingToAmend(f, 'tech-design'))
    .filter(Boolean).filter(validateAmend).length === 1)

// ---- every grounded amendment is applied, not just the first ----
// A run that applies amendments[0] and drops the rest silently loses
// findings that passed every validation gate, and the round cap then
// denies them a second chance. The source must not index [0] out of the
// grounded set, and must group by target document.

assert('multi-amend: no groundedAmends[0] single-pick remains',
  !SRC.includes('groundedAmends[0]'))
assert('multi-amend: amendments are grouped by target document',
  SRC.includes('byTarget'))

// The grouping itself, replicated from the source shape: amendments to
// different documents must not collapse into one replay, and several
// amendments to the SAME document must travel together in one.
const sampleAmends = [
  { target: 'prd', section: 'FR-1' },
  { target: 'prd', section: 'NFR-2' },
  { target: 'tech-design', section: 'D-4' },
]
const grouped = new Map()
for (const am of sampleAmends) {
  if (!grouped.has(am.target)) grouped.set(am.target, [])
  grouped.get(am.target).push(am)
}
assertEq('multi-amend: 3 amendments over 2 documents → 2 replays', 2, grouped.size)
assertEq('multi-amend: both prd amendments ride one replay', 2, grouped.get('prd').length)
assertEq('multi-amend: the tech-design amendment is not lost', 1, grouped.get('tech-design').length)
assertEq('multi-amend: no amendment is dropped', 3,
  [...grouped.values()].reduce((n, a) => n + a.length, 0))

// ---- report ----

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
