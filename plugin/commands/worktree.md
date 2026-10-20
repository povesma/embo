---
description: >
  Run work in a parallel git worktree that shares this repo's RLM index
  and memory: open one on a branch, list the open ones, or clean one up
  after its work has landed.
---

# /embo:worktree — parallel sessions in a git worktree

A worktree is a second checkout of this repo on its own branch, so a
second session can work without disturbing your current tree. embo
anchors its state to the main tree, so a worktree session shares the
RLM index and claude-mem memory — no re-index, and removing a worktree
never destroys embo state.

Claude Code owns the worktree lifecycle. This command drives the
native `EnterWorktree` / `ExitWorktree` tools and adds the parts they
leave to you: a name derived from the branch, a base-ref that matches
what you are working on, and a cleanup that refuses to throw away
uncommitted work.

## Modes

`/embo:worktree <branch>` — open one · `list` — show them ·
`remove [path]` — clean one up

Read the mode from the user's words; ask only if genuinely unclear.

## Before anything: the tool gate

If `EnterWorktree` is not available in this session, stop and say:

> Worktree tools are not available here (they need a recent Claude
> Code). You can run `git worktree add` by hand, or work in the main
> tree.

Do not fall back to raw `git worktree add` on your own. A worktree
created outside the native tool is state the harness cannot see or
clean up.

## Open a worktree — `/embo:worktree <branch>`

**1. Refuse to nest.** Compare the two paths:

```bash
git rev-parse --path-format=absolute --git-dir
git rev-parse --path-format=absolute --git-common-dir
```

Different means you are already inside a linked worktree. Stop and
say so — worktrees are opened from the main tree.

**2. Check the base.** Native worktrees branch from the remote default
branch (`worktree.baseRef: "fresh"`), NOT from where you are. So a
worktree opened off a feature branch will not contain that branch's
work, and uncommitted or unpushed files will be missing inside it.

Before entering, say in one line which base the worktree will have and
what that means for the files in play — above all when the current
branch is not the default one, or when `git status --porcelain` is not
empty. The user may want `worktree.baseRef: "head"` in settings
instead; name it, do not set it for them.

**3. Enter.** Call `EnterWorktree` with `name` set to the branch with
slashes replaced by hyphens (`feat/my-thing` -> `feat-my-thing`), so
the directory is recognisable and nobody has to invent a name. Reusing
a name resumes that worktree.

**4. Confirm where you landed:**

```bash
git branch --show-current
```

Report the worktree path and branch. Then work normally — commit,
push, open a PR exactly as you would in the main tree.

## List — `/embo:worktree list`

```bash
git worktree list
```

Report each path with its branch. Mark the one you are in, if any.

## Clean up — `/embo:worktree remove [path]`

Only after the work has landed (merged, or abandoned on purpose).
There is no merge step here: you merge however you normally do.

**Inside the worktree being removed**, call `ExitWorktree` with
`action: "remove"`. **From the main tree**, name the worktree to
remove.

If removal is refused for uncommitted or unmerged work, **do not
force it and do not retry with a force flag.** Show the files:

```bash
git -C <path> status --porcelain -uno
```

Then put the choice to the user: commit them to the branch, or
confirm explicitly that they are to be discarded. Files that exist
only in a worktree exist nowhere else — a forced removal destroys
them permanently.

Deleting the branch too is a separate, explicit step: `git branch -d`
(which refuses unmerged work). Never `-D` unless the user asks for it
in those terms, having been told what it drops.

## What this does not do

- **No merging.** Use your normal PR or merge flow.
- **No dependency install.** A fresh worktree may need the project's
  own setup (`npm install` and the like); say so rather than guessing
  at the command.
- **Subagents do not call these tools.** The worktree lifecycle
  belongs to the session that opened it; a subagent cannot exit one.
