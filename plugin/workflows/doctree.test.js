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

// Extract one `export function <name>(...) { ... }` block by brace matching.
function extractFn(name) {
  const marker = `export function ${name}(`
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

const validateAmend = extractFn('validateAmend')
const budgetAllows = extractFn('budgetAllows')
const roundExhausted = extractFn('roundExhausted')

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

// ---- report ----

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
