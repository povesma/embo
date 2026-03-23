# Ideas

## Rejected

### Session Cost Budget & Alert Hook
**Rejected by Dmytro**: 2026-03-19
A `cost-guard.sh` hook that warns when session cost crosses a
user-defined threshold ($5, $10, $20). Pauses at hard cap.

### Auto-Generated Session Changelog
**Rejected by Dmytro**: 2026-03-19
`/rlm-mem:discover:changelog` — diffs working tree against session
start commit, queries claude-mem for session observations, synthesizes
a human-readable changelog (files changed, features, decisions, open
items).

### Smart Context Compaction Command
**Rejected by Dmytro**: 2026-03-19
`/rlm-mem:develop:compact` — saves working state to claude-mem before
context compression, so `/discover:start` picks up exactly where you
left off in a fresh window.

## Under Consideration

### Workflow Self-Improvement from User Corrections
**Status**: Worth further consideration
**Proposed**: 2026-03-20

Users frequently correct Claude during sessions — rejecting approaches, redirecting
to web/docs, changing code style. These corrections die with the session. Proposal:
(1) teach `impl.md` to capture corrections as claude-mem observations typed
`correction` (what happened → what user wanted → workflow step); (2) add
`/rlm-mem:develop:review-corrections` command that queries correction history,
groups by pattern, and lets the user curate which ones get promoted into command
prompts. No auto-evolution — user is the curator. Industry context: Windsurf
memories, Augment RLDB, Copilot Memory all converge on two-tier (stable rules +
evolving memories) but none fully auto-evolve yet.

Also considered: shared `_commons.md` to DRY duplicated rules across 8 commands.
Runtime Read is unreliable (agent may skip). Build-time inject is sound but
premature — defer until shared rules section grows.

---

### Settings Profiles & Management (`/rlm-mem:config:profile`)
**Status**: Worth further consideration
**Proposed**: 2026-03-19

**Notes from Dmytro (2026-03-19):**
- Viable but too complex for a regular user as-is
- Presets are the strongest part — focus there
- Danger zone: changing hooks can break commands that rely on
  them (e.g. disabling PostToolUse hook silently breaks
  claude-mem observation capture, which breaks `/discover:start`)
- Could evolve into parameterized workflow behavior — presets
  that control not just settings but the whole development
  workflow personality (conservative vs autonomous vs team)
- Needs deeper thinking before PRD

#### Background: Claude Code Settings Scoping

Claude Code has a 4-level settings hierarchy:

| Scope | File | Committed? | Overrides |
|-------|------|-----------|-----------|
| Managed | System-level (IT/MDM) | N/A | Top — cannot be overridden |
| User | `~/.claude/settings.json` | No | Your global defaults |
| Project | `.claude/settings.json` | **Yes** | Overrides user; shared with team |
| Local | `.claude/settings.local.json` | **No** | Overrides all; personal only |

**Merge rules**: Arrays (permissions, hooks) **concatenate** across scopes.
Scalars (booleans, strings) **override** — more-specific scope wins.
Project settings **can restrict** user permissions (deny overrides allow).

#### What this feature would do

A command/skill `/rlm-mem:config:profile` that manages all three
user-accessible scopes (user, project, local) in one place.

**Core capabilities:**

1. **List & inspect** — Show the effective merged settings for the
   current project, highlighting which scope each value comes from.
   Like `git config --show-origin` but for Claude Code settings.

2. **Profile presets** — Ship named profiles as template files in
   the repo:
   - `profiles/conservative.json` — ask before every edit, no
     auto-approve, strict permissions
   - `profiles/autonomous.json` — auto-approve reads/edits, deny
     only destructive ops (rm, git push --force)
   - `profiles/team-standard.json` — team-shared hooks, MCP
     servers, standard env vars for the project

3. **Apply profile** — User picks a profile; the skill shows a
   diff of what would change vs current settings, asks for
   confirmation, then writes to the correct scope:
   - Team-shared settings → `.claude/settings.json` (committed)
   - Personal preferences → `.claude/settings.local.json` (gitignored)
   - Global defaults → `~/.claude/settings.json`

4. **Scope-aware editing** — "Allow RLM-Mem hooks in this project"
   → adds to project-level settings. "Set my default model to
   Opus everywhere" → adds to user-level settings. The skill
   knows which scope is appropriate for each setting type.

5. **Diff & audit** — Before applying, show exactly what changes
   at which scope. After applying, confirm the effective merged
   result. This prevents the common footgun of putting a
   project-specific permission in user-level settings (leaks to
   all projects) or a personal preference in project-level
   settings (forces it on teammates).

**What this is NOT:**
- Not a general `settings.json` editor — only manages profiles
  and scope-aware operations relevant to RLM-Mem workflows
- Not a replacement for the built-in `/config` — complements it
  with profile management and scope awareness

#### Example workflow

```
> /rlm-mem:config:profile

Current settings (3 scopes active):
  User:    ~/.claude/settings.json (12 keys)
  Project: .claude/settings.json (not found)
  Local:   .claude/settings.local.json (not found)

Available profiles:
  1. conservative — ask before edits, strict permissions
  2. autonomous — auto-approve edits, deny destructive ops
  3. team-standard — shared hooks, MCP servers, env vars

Which profile? > 2

Applying "autonomous" to project scope (.claude/settings.json):
  + permissions.allow: Bash(python3 ~/.claude/rlm_scripts/*)
  + permissions.allow: Read, Write, Edit, Glob, Grep
  + permissions.deny: Bash(rm -rf *), Bash(git push --force)
  + hooks.PostToolUse: claude-mem hook
  + env.CONTEXT_GUARD_THRESHOLD: 85

Confirm? [y/N] > y
Written to .claude/settings.json (commit to share with team)
```

---

### PR Review with Inline Traceability Annotations
**Status**: Worth further consideration
**Proposed**: 2026-03-19

#### The problem

A GitHub PR reviewer sees **only the diff** — changed lines of
code. The PR description may link to a task or PRD, but the
reviewer must manually cross-reference: "which acceptance criterion
does this hunk satisfy?" and "does this match the tech design?"

Claude-mem is irrelevant here — a human reviewer has no access to
it. The review must be self-contained within what GitHub shows.

#### Three annotation mechanisms on GitHub

Research (2026-03-19) revealed GitHub supports **three distinct
ways** to attach context to PR code:

**1. PR Review Comments** (Review API)
- `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews`
- Inline comments on specific diff lines, posted as a "review"
- Appears as conversation bubbles in the Files Changed tab
- **Limitation**: `position` is diff-relative (offset from `@@`
  hunk header), not file line number — must parse diff to compute
- **Limitation**: Cannot comment on lines outside the diff
- Supports multiple comments per single API call (batched)
- Appears as a regular review — can be COMMENT, APPROVE, or
  REQUEST_CHANGES

**2. Check Run Annotations** (Checks API)
- `POST /repos/{owner}/{repo}/check-runs`
- Annotations appear as colored markers in the diff margin:
  red (error), yellow (warning), blue (info)
- Uses **real file line numbers** (not diff positions) — much
  simpler to implement
- Supports `start_line`, `end_line`, `start_column`, `end_column`
- Supports `title`, `message`, and `raw_details` per annotation
- **Key advantage**: Works on lines OUTSIDE the diff too
- **Key advantage**: Visually distinct from human review comments
  (diamond icon vs circle icon) — doesn't pollute the review
  conversation
- **Limitation**: Max 50 annotations per check run; reviewdog
  uses this as fallback when Review API can't reach the line
- Requires a GitHub App or Actions token (not just PAT)

**3. PR Description + Commit Messages** (passive context)
- Not inline, but structured PR descriptions with links to
  `tasks/` files give the reviewer a navigation map
- Commit messages can reference task IDs (`Task 2.1: ...`)
- Cheapest to implement; no API calls needed

#### Proposed approach: layered strategy

Rather than picking one mechanism, use all three for different
purposes:

**Layer 1 — Structured PR description** (on `gh pr create`):
- Auto-generated from task list: which tasks are complete, which
  files map to which tasks
- Links to PRD, tech-design, task list in the repo
- This is the "table of contents" for the reviewer

**Layer 2 — Check Run annotations** (on PR create or push):
- One annotation per changed file, attached to the first changed
  line, showing which task(s) that file implements
- Uses real line numbers (simpler than diff-position math)
- Blue (info) severity — non-intrusive, doesn't block merge
- Visually distinct from human reviews (diamond vs circle icons)
- Annotation `title`: task ID; `message`: acceptance criteria
- Example in the diff margin:
  ```
  ℹ️ Task 2.1: Add short_num() helper
     AC: ≥1M→NM, ≥1K→NK, null→?
     Tech Design: §Component 1
  ```

**Layer 3 — Review comments** (only for complex hunks):
- For hunks where the connection to a task isn't obvious from the
  file name alone, post a review comment explaining the
  traceability chain
- Batched into a single review (avoids notification spam)
- Posted as COMMENT (not APPROVE/REQUEST_CHANGES) to avoid
  interfering with human review workflow

#### What reviewdog teaches us

[reviewdog](https://github.com/reviewdog/reviewdog) is the
established tool for this pattern. Key lessons:
- Use Review API for comments within the diff, Check annotations
  as fallback for lines outside the diff
- Supports `rdformat` (reviewdog diagnostic format) with severity,
  rule codes, URLs, multiline ranges, and code suggestions
- We don't need reviewdog itself (it's for linter output), but its
  architecture validates the layered approach

#### What CodeRabbit / AI review tools teach us

Tools like [CodeRabbit](https://github.com/coderabbitai/ai-pr-reviewer)
and [Qodo](https://www.qodo.ai/) post AI-generated inline comments.
Key lessons:
- Large PRs can generate 50+ comments — notification fatigue is
  real; batch into one review, keep annotations terse
- Separate "walkthrough summary" (PR description) from "line-level
  detail" (inline) — don't repeat info at both levels
- AI review comments should be visually distinguishable from human
  comments (use a bot account or Check annotations)

#### How it works (implementation sketch)

```
/rlm-mem:review:annotate-pr <pr-number>

1. gh pr diff <pr-number> → get changed files and hunks
2. Read tasks/*-tasks.md → map files to tasks/subtasks
3. Read tasks/*-tech-design.md → extract relevant clauses
4. Read tasks/*-prd.md → extract acceptance criteria
5. For each changed file:
   a. Match to task(s) by file path (from "Relevant Files" section)
   b. Compose annotation: task ID + AC + tech-design clause
   c. Post as Check Run annotation (Layer 2)
6. For ambiguous hunks (file maps to multiple tasks):
   a. Use Claude to match hunk content → specific subtask
   b. Post as Review comment (Layer 3)
7. Update PR description with structured task summary (Layer 1)
```

**All context comes from files in the repo** (`tasks/` directory).
No claude-mem dependency. A human reviewer can click through to
the linked PRD/tech-design and independently verify every claim.

#### Auth investigation (2026-03-19)

**Key finding**: `gh` CLI reuses existing `gh auth login` credentials
for all API calls. If the user can `gh pr create`, they can also
`gh api .../pulls/{id}/reviews` — no extra tokens needed.

**Three implementation paths investigated:**

| Path | Tool | Line addressing | Auth | Dependency |
|------|------|----------------|------|------------|
| **A** | `gh-comment` ext | file:line (real) | `gh auth` ✅ | Extension install |
| **B** | `gh api` raw | diff position | `gh auth` ✅ | None |
| **C** | Check annotations | file:line (real) | Checks:write ❌ | GitHub App or Actions |

**Plan A** (`gh-comment` extension — recommended):
```bash
gh extension install silouanwright/gh-comment
gh comment review 4 \
  --comment "statusline.sh:49:Task 2.1: short_num() helper" \
  --event COMMENT
```
Uses `file:line:message` — real line numbers. Extension translates
to diff positions internally. Simplest UX.

**Plan B** (`gh api` — no extension dependency):
```bash
gh api repos/{owner}/{repo}/pulls/4/reviews \
  -f commit_id=abc123 -f event=COMMENT \
  -f 'comments[0][path]=.claude/statusline.sh' \
  -f 'comments[0][position]=6' \
  -f 'comments[0][body]=Task 2.1: short_num()'
```
Requires diff-position math (offset from `@@` hunk header, not
file line number). Doable but error-prone.

**Plan C** (Check annotations — deferred):
Requires `checks:write` permission. Fine-grained PATs may not
support it. Only viable in GitHub Actions CI, not local CLI.
Nicest UX (colored margin markers, distinct from review comments)
but auth barrier too high for typical developer.

**Revised layer strategy:**
- Layer 1 (PR description): `gh pr edit --body` — zero friction
- Layer 2 (inline annotations): Plan A or B — uses existing auth
- Layer 3 (Check annotations): **deferred** to CI-only future work

#### Open questions

- **Extension dependency**: Plan A requires `gh-comment` install.
  Should we make this a prerequisite or fall back to Plan B?
  Plan B needs diff-position math which is the hardest part.
- **Automation**: Run on `gh pr create` via hook, or explicit
  command only? Automatic risks noise on small PRs.
- **Granularity**: One annotation per file (coarse) vs one per
  hunk (fine)? Start coarse, let users opt into fine.
- **Unmatched hunks**: What to do when a changed hunk doesn't
  map to any task? Flag as "uncovered by task list" (scope drift
  signal) or silently skip?

#### Multi-platform consideration (2026-03-19, web-verified)

**Bitbucket** (Cloud + Data Center):
- Layer 2 (inline comments): `POST .../pullrequests/{id}/comments`
  with `inline` object (`path`, `from`/`to` line numbers). Auth:
  App Password or OAuth — no special restrictions.
  [Source](https://developer.atlassian.com/cloud/bitbucket/rest/api-group-pullrequests/)
- Layer 3 (Code Insights): Annotations must belong to a Report.
  Up to 1000 annotations/report, bulk POST 100 at a time. Auth:
  regular OAuth — **NOT restricted to Apps** like GitHub Check Runs.
  More permissive than GitHub. Only annotations on lines in the PR
  diff are displayed.
  [Source](https://support.atlassian.com/bitbucket-cloud/docs/code-insights/)

**GitLab**: Merge Request Discussions API for inline comments
(not yet verified — needs research).

The core hunk→task matching logic is platform-agnostic — only
the API posting layer needs per-platform adapters.

#### Sources

- [gh-comment extension](https://github.com/silouanwright/gh-comment) — line-specific PR comments via `gh` CLI
- [gh-pr-review extension](https://github.com/agynio/gh-pr-review) — full inline review support, LLM-ready
- [Feature request: inline comments in gh pr](https://github.com/cli/cli/issues/12396) — confirms native `gh` doesn't support it
- [GitHub Check Runs & Annotations](https://github.blog/news-insights/product-news/introducing-check-runs-and-annotations/)
- [GitHub REST API: Pull Request Reviews](https://docs.github.com/en/rest/pulls/reviews)
- [GitHub REST API: Check Runs](https://docs.github.com/en/rest/checks/runs)
- [reviewdog](https://github.com/reviewdog/reviewdog) — annotation routing architecture (Review API + Check fallback)
- [CodeRabbit AI PR Reviewer](https://github.com/coderabbitai/ai-pr-reviewer)
- [Qodo AI Code Review](https://www.qodo.ai/blog/best-automated-code-review-tools-2026/)
