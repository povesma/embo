# BUG 2026-09-01: branch creation resolves `base:` against a stale local branch

## Symptom

A `pr-merge` plan with `branch: feat/token-budget-and-principles`,
`base: main` aborted with exit 7:

```
error: Your local changes to the following files would be overwritten by checkout:
	CHANGELOG.md
	plugin/commands/init.md
	plugin/commands/start.md
	tasks/055-TOKEN-AUDIT-shipped-commands-agents/SEED.md
embo-deliver: cannot create branch 'feat/token-budget-and-principles' from base 'main'.
```

The refusal looked like a working-tree problem but was not:
`git diff origin/main HEAD` was empty (the checked-out tree matched
the remote base exactly).

## Root cause

`embo-deliver` creates an absent plan branch with
`git switch -c "$BRANCH" "$BASE"`, which resolves `main` to the
**local** branch. Local `main` was several merges stale (`f00f949`
while `origin/main` was `06cada4`), so git tried to move the working
tree back to old file contents and refused over the uncommitted
changes. Nothing in the executor checks base freshness.

## Workaround used

`git fetch origin main:main` (fast-forward the local base), then
re-run the same plan through a new plan file. Delivery then completed
normally (PR #58).

## Proposed fix (pick in a design pass)

- Create the branch from `origin/<base>` after a `git fetch origin
  <base>` — always current, no local-branch dependency; or
- keep using the local base but verify it equals `origin/<base>`
  first, aborting with guidance that names the exact fast-forward
  command (`git fetch origin <base>:<base>`).

Either way the failure message should say the base is stale — the
current message points at the working tree, which sent diagnosis in
the wrong direction.
