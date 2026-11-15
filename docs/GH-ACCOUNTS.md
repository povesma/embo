# Multiple GitHub accounts — per-directory isolation

When you work across GitHub accounts (personal vs. work, open-source
vs. company), you need `gh` to use the right account in each project
directory — without affecting other directories or other open terminals.

`gh auth switch` is a global state change: it rewrites a single
active-account flag in `~/.config/gh/hosts.yml` and immediately affects
every terminal, IDE, and background script on the machine. It is the
wrong tool for per-directory isolation.

This guide describes two approaches that provide true isolation.
Both work on **macOS and Linux** (including WSL). Neither works on
native Windows.

---

## Approach A — `GH_CONFIG_DIR` + direnv (no token ever in env)

`gh` reads all its state — credentials, settings — from the directory
named by `GH_CONFIG_DIR`. By exporting a different path per project,
you redirect `gh` to a separate, isolated config. Tokens stay in
the macOS Keychain / Linux secret store; only a harmless filesystem
path enters the environment.

### One-time setup

**1. Install direnv.**

```bash
# macOS
brew install direnv

# Debian/Ubuntu
sudo apt install direnv

# Arch
sudo pacman -S direnv
```

**2. Hook direnv into your shell** (add to the end of `~/.zshrc` or
`~/.bashrc`, then restart the shell or `source` the file):

```bash
eval "$(direnv hook zsh)"   # zsh
# eval "$(direnv hook bash)" # bash
```

This is a one-time change. Every new terminal tab, tmux window, or
Helix terminal that sources your shell RC will have direnv active.

**3. Create a config directory for each account** and authenticate
into each one. The directories live in `~/.config/`, outside any repo:

```bash
# Already exists if you have used gh before — your default account.
# If it is the wrong default, run:
GH_CONFIG_DIR=~/.config/gh-personal gh auth login

# Work / secondary account:
GH_CONFIG_DIR=~/.config/gh-work gh auth login
```

Verify both are set up:

```bash
GH_CONFIG_DIR=~/.config/gh-personal gh auth status
GH_CONFIG_DIR=~/.config/gh-work     gh auth status
```

**4. Add an `.envrc` file to each project directory.**

The file contains only a path, not a credential:

```bash
# ~/code/personal-project/.envrc
export GH_CONFIG_DIR=$HOME/.config/gh-personal
```

```bash
# ~/code/work-project/.envrc
export GH_CONFIG_DIR=$HOME/.config/gh-work
```

**5. Trust each `.envrc` once:**

```bash
cd ~/code/personal-project && direnv allow
cd ~/code/work-project     && direnv allow
```

direnv will not execute any `.envrc` it has not been explicitly
trusted — a rogue `.envrc` appearing in your filesystem cannot run.

### How it works

When you `cd` into a project, direnv silently exports `GH_CONFIG_DIR`.
`gh` reads that directory, finds the username from `hosts.yml` there,
and fetches the token from the macOS Keychain using that username.
The token never appears in any environment variable.

When you `cd` out, direnv unsets `GH_CONFIG_DIR`, reverting to the
default `~/.config/gh/`.

### Compatibility with Claude Code

Claude Code inherits the environment of the shell that launched it.
Start CC after `cd`-ing into the project directory (so direnv has
already loaded `.envrc`), and all `gh` calls CC makes will use the
correct account.

This is the normal flow in iTerm2, tmux, tmuxp, and Helix — you
`cd` first, then start CC.

**Limitation:** if you open an IDE (VS Code, etc.) from the macOS
Dock or an application menu (not from a terminal), it starts outside
the direnv hook and will not have `GH_CONFIG_DIR` set. Open the IDE
from an already-activated terminal (`code .`) to inherit the variable.

### Fail-loud variant

If you want `gh` to fail with an auth error in any directory that lacks
an `.envrc` (rather than silently using a fallback account), do not
authenticate into `~/.config/gh/` at all — leave it absent or empty.
Any `gh` or `git push` in an unconfigured directory fails immediately,
making the missing `.envrc` obvious.

### Nested `.envrc` files

If a subdirectory inside your project has its own `.envrc`, direnv
uses that file instead of the parent's. To inherit the parent's
`GH_CONFIG_DIR` while adding more variables, add this at the top
of the subdirectory `.envrc`:

```bash
source_up_if_exists
```

---

## Approach B — `ghx` wrapper (PATH-based, no global switch)

[`ghx`](https://github.com/barnuri/ghx) is a thin binary that
installs as a `gh` shim earlier in `$PATH`. When you run `gh`,
`ghx` intercepts the call, looks up which account to use from its
own config (based on the current directory), fetches the token
from the macOS Keychain, and launches the real `gh` with the token
passed to that one child process only.

It never calls `gh auth switch`, so switching in one terminal does
not affect any other terminal.

### Setup

**1. Install `ghx`:**

```bash
# macOS / Linux (installs to ~/.local/bin by default)
curl -fsSL https://raw.githubusercontent.com/barnuri/ghx/main/install.sh | bash
```

Ensure `~/.local/bin` is earlier in `$PATH` than the real `gh`.

**2. Map directories to accounts** in `~/.config/ghx/config.yaml`:

```yaml
profiles:
  personal:
    user: your-personal-login
  work:
    user: your-work-login
dirs:
  ~/code/personal-project: personal
  ~/code/work:             work
default: personal
```

**3. Optionally, add a `.ghx` file** (one line: a profile name) in
a repo to declare its account in the repo itself:

```
# .ghx
work
```

The `.ghx` file contains only a profile name — no token.

### How it works

`ghx` calls `gh auth token --user <login>` to retrieve the token
from the macOS Keychain, then starts the real `gh` with `GH_TOKEN`
set in the child process environment only. The token exists only
for the duration of that one `gh` call.

It works for Claude Code automatically: CC inherits `$PATH` from
its parent shell, so the `ghx` shim intercepts every `gh` call CC
makes.

**Tradeoff vs. Approach A:** the token is in `GH_TOKEN` inside the
`gh` child process while it runs. This is the same as how any process
running as you can access a token — but it is marginally more exposure
than the `GH_CONFIG_DIR` approach, where the token never enters any
environment variable.

---

## Summary

| | `GH_CONFIG_DIR` + direnv | `ghx` |
|---|---|---|
| Token in any env var | Never | Child process only, per call |
| Token on disk in repo | No | No (`.ghx` holds a name, not a token) |
| Global `gh auth switch` | Never | Never |
| Shell RC change needed | Yes (`eval "$(direnv hook ...)"`) | No |
| CC compatibility | Requires terminal launch before CC | Works regardless of how CC was launched |
| Platform | macOS, Linux, WSL | macOS, Linux, WSL |

Both approaches leave credentials in the macOS Keychain / Linux secret
store and prevent global state mutation. Choose `GH_CONFIG_DIR` +
direnv if you want the cleanest security boundary; choose `ghx` if
you want a simpler setup with no shell RC change.
