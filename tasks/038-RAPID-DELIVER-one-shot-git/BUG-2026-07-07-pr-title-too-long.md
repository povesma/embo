# T038 BUG — embo-deliver sets PR title to the full commit message

**Reported:** 2026-07-07 (found while using `/embo:git deliver` in the
`infra` project during T034).
**Severity:** breaks `pr` and `pr-merge` modes for any commit that has
a body (i.e. almost every real commit).

## Symptom

`embo-deliver --plan <plan>` in `pr-merge` mode commits and pushes
successfully, then fails at PR creation:

```
pull request create failed: GraphQL: Title is too long (maximum is 256 characters) (createPullRequest)
embo-deliver: committed, pushed to <branch>; PR not created
```

Exit code 5. Because the commit + push already succeeded, the operator
must finish with a manual `gh pr create` + `gh pr merge`. Observed on
2 of 3 pr-merge deliveries in one session (the successes only had short
enough total messages).

## Root cause

`plugin/bin/embo-deliver` lines 180-181:

```sh
run gh pr create --base "$BASE" --head "$BRANCH" \
    --title "$MESSAGE" --fill \
```

`$MESSAGE` is the **entire** commit message (subject + body). GitHub
caps PR titles at 256 characters, so any commit with a normal multi-line
body overflows the title. The `--fill` flag is also redundant and
conflicts with an explicit `--title`.

## Fix

Use only the first line of the message as the title, pass the rest as
the body, and drop `--fill`:

```sh
PR_TITLE=$(printf '%s\n' "$MESSAGE" | head -1)
run gh pr create --base "$BASE" --head "$BRANCH" \
    --title "$PR_TITLE" --body "$MESSAGE" \
  || fail "$STEPS; PR not created" 5
```

(Body may repeat the subject line; that is harmless. Alternatively pass
the body-only portion.)

## Verify

A plan whose `message:` block has a subject line plus a multi-paragraph
body should open a PR whose title is just the subject and whose body is
the full message — no "Title is too long" error, exit 0 through merge.
