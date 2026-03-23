# 008-STATUSLINE: Status Line Configuration & Improvements - Technical Design

**Status**: Draft
**PRD**: [2026-03-19-008-STATUSLINE-prd.md](2026-03-19-008-STATUSLINE-prd.md)
**Created**: 2026-03-19

---

## Overview

Three deliverables:

1. **`.claude/statusline.sh`** — a new Bash script shipped in the repo, replacing
   the user's current ad-hoc script. Reads Claude Code's stdin JSON, applies tilde
   abbreviation and `USED/TOTAL` context display.

2. **`statusline-setup` skill** (`.claude/agents/statusline-setup.md`) — a Claude
   Code skill that reads `~/.claude/settings.json`, lists available statusline
   scripts in `~/.claude/`, allows the user to pick one, and writes/updates the
   `statusLine` block. Supports switching between multiple scripts.

3. **`install.sh` + `README.md` updates** — `install.sh` copies `statusline.sh`,
   sets `+x`, then prompts the user and optionally patches `~/.claude/settings.json`
   using `jq`. README gains a statusline setup step with both script and manual
   paths. Both macOS/Linux and Windows paths covered.

---

## Proposed Design

### Component 1: `.claude/statusline.sh`

**Location**: `.claude/statusline.sh` (repo) → copied to `~/.claude/statusline.sh`

**Data contract** — fields read from stdin JSON:

| Field | jq path | Fallback |
|-------|---------|----------|
| Model display name | `.model.display_name` | `"Unknown"` |
| Current directory | `.workspace.current_dir // .cwd` | `""` |
| Total cost USD | `.cost.total_cost_usd` | `0` |
| Context window size | `.context_window.context_window_size` | `null` → `"?"` |
| Input tokens (current) | `.context_window.current_usage.input_tokens` | `0` |
| Cache write tokens | `.context_window.current_usage.cache_creation_input_tokens` | `0` |
| Cache read tokens | `.context_window.current_usage.cache_read_input_tokens` | `0` |

**Internal logic — tilde abbreviation**:

```bash
DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
DIR="${DIR/#$HOME/\~}"   # bash parameter expansion; POSIX-portable fallback: sed
```

The `${var/#pattern/replacement}` form replaces prefix only, so `/Users/foo` → `~`
and `/Users/foobar` is not affected (only exact prefix match).

**Internal logic — short-form number formatting**:

```bash
short_num() {
    local n=$1
    if [ -z "$n" ] || [ "$n" = "null" ]; then echo "?"; return; fi
    if   [ "$n" -ge 1000000 ]; then echo "$((n / 1000000))M"
    elif [ "$n" -ge 1000 ];    then echo "$((n / 1000))K"
    else echo "$n"; fi
}
```

Values are truncated (not rounded), consistent with the existing `used_percentage`
display convention. `1000000` → `1M`, `200000` → `200K`, `999` → `999`.

**Internal logic — used token count**:

```bash
# current_usage may be null before first API call; default all fields to 0
USED=$(echo "$input" | jq -r '
  (.context_window.current_usage.input_tokens // 0) +
  (.context_window.current_usage.cache_creation_input_tokens // 0) +
  (.context_window.current_usage.cache_read_input_tokens // 0)
')
```

This mirrors Claude Code's own `used_percentage` formula (confirmed via Context7 docs).

**Internal logic — context window size**:

```bash
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // "null"')
# CTX_SIZE is either a number or the string "null"
```

`"null"` string sentinel is used (not shell empty string) because `jq -r` outputs
the literal string `null` for JSON null. `short_num` treats `"null"` as `?`.

**Output format**:

```
{DIR} | {BRANCH} | {MODEL} | {USED_SHORT}/{CTX_SHORT} ${COST} | {TIME}
```

Example:
```
~/AI/claude_code_RLM_mem | feature/007-health-check | Sonnet 4.6 | 30K/200K $0.072 | 08:32:39
```

Git branch: `git branch --show-current 2>/dev/null` — silently omitted if not
in a git repo (empty string, segment dropped).

Cost format: `printf '$%.3f' "$COST"` — matches existing convention.

Time: `date +%H:%M:%S`.

**Null-safety invariant**: script must never exit non-zero or produce empty output.
If `jq` is missing, fall back to `echo "[statusline: jq not found]"` and exit 0.

**Performance**: all fields computed from a single `input=$(cat)` read; `jq` called
multiple times but against an in-memory string (no disk I/O beyond git branch).
Expected runtime: <50ms on modern hardware.

---

### Component 2: `statusline-setup` skill

**Location**: `.claude/agents/statusline-setup.md`

This is a Claude Code skill (invoked via `/statusline-setup`), not a standalone
script. It uses the `Read` and `Edit`/`Write` tools to manipulate
`~/.claude/settings.json`.

**Behaviour contract**:

1. **Discover available scripts**: `Glob ~/.claude/statusline*.sh` — lists all
   scripts matching the pattern (e.g. `statusline.sh`, `statusline-minimal.sh`,
   `statusline-color.sh`).

2. **Present choice**: If multiple scripts found, ask user which to activate.
   If only one, confirm before proceeding. If none, instruct user to run
   `install.sh` first.

3. **Read current settings**: `Read ~/.claude/settings.json`. If file doesn't
   exist, treat as `{}`.

4. **Detect existing `statusLine` block**: If present, show current value and
   ask user to confirm overwrite.

5. **Write updated settings**: Use `Edit` to patch the `statusLine` key, or
   `Write` if creating from scratch. The resulting block:
   ```json
   "statusLine": {
     "type": "command",
     "command": "~/.claude/statusline.sh"
   }
   ```
   Path uses `~/.claude/` (not absolute) so it works for any user — Claude Code
   expands `~` in the command path.

6. **Confirm**: Print the new `statusLine` block and instruct user to restart
   Claude Code for the change to take effect.

**Multi-script switching**: By globbing `~/.claude/statusline*.sh`, the skill
naturally supports any number of named variants the user has installed. Users can
add their own scripts (e.g. `statusline-minimal.sh`) and switch via the skill.

**Skill does NOT**: create or modify `statusline.sh` itself; manage non-statusline
settings; handle Windows paths (Windows users use manual steps).

---

### Component 3: `install.sh` changes

**New block** (added after the existing hooks section):

```bash
# statusline
if [ -f "$REPO_DIR/.claude/statusline.sh" ]; then
    cp "$REPO_DIR/.claude/statusline.sh" "$TARGET/statusline.sh"
    chmod +x "$TARGET/statusline.sh"
    echo "  statusline: copied to $TARGET/statusline.sh"

    # Patch settings.json if jq is available
    SETTINGS="$TARGET/settings.json"
    if command -v jq >/dev/null 2>&1; then
        if [ ! -f "$SETTINGS" ]; then
            echo '{}' > "$SETTINGS"
        fi
        if jq -e '.statusLine' "$SETTINGS" > /dev/null 2>&1; then
            echo "  settings.json: statusLine already configured — skipping"
            echo "    (run /statusline-setup to switch scripts)"
        else
            echo ""
            echo "  Configure statusline? (recommended)"
            read -r -p "  Add statusLine to $SETTINGS? [y/N] " yn
            case "$yn" in
                [Yy]*)
                    jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}' \
                        "$SETTINGS" > /tmp/_rlm_settings.tmp \
                        && mv /tmp/_rlm_settings.tmp "$SETTINGS"
                    echo "  settings.json: statusLine added"
                    ;;
                *)
                    echo "  settings.json: skipped — see README for manual step"
                    ;;
            esac
        fi
    else
        echo "  settings.json: jq not found — manual step required"
        echo "    Install jq: brew install jq  (macOS) | apt install jq  (Linux)"
        echo "    Then add to $SETTINGS:"
        echo '    { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }'
    fi
fi
```

**Failure modes handled**:
- `jq` absent → prints install instruction and required JSON block, continues
- `statusLine` already present → skips with message, suggests `/statusline-setup`
- User declines → skips silently, prints manual step reminder
- `settings.json` absent → creates as `{}` before patching

**`install.ps1`** (Windows): copies `statusline.sh` but does NOT attempt
`settings.json` patching (no `jq` equivalent assumed). Prints a manual step
instruction with the JSON to add.

---

### Component 4: `README.md` changes

**In the macOS/Linux manual steps block** (after step 5 — make REPL executable),
add a new numbered step:

```
# 6. Configure statusline (optional but recommended)
# Requires jq: brew install jq
cp .claude/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
# Add to ~/.claude/settings.json:
# { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }
# Or run: /statusline-setup
```

**In "What Gets Installed"** tree, add:
```
└── statusline.sh               # Status line script
```

**In a new "Statusline" section** (or within Verification):
- Explain `jq` prerequisite
- Show the `settings.json` block
- Mention `/statusline-setup` skill for switching scripts
- Note: restart Claude Code after `settings.json` change

---

## Files to Create / Modify

**Create**:
- `.claude/statusline.sh` — the statusline script
- `.claude/agents/statusline-setup.md` — the setup skill

**Modify**:
- `install.sh` — add statusline copy + optional settings.json patch
- `README.md` — add statusline step to macOS/Linux and Windows manual instructions,
  update "What Gets Installed" tree, add Statusline section
- `CLAUDE.md` (repo) — add `statusline.sh` to File Structure listing

**Optionally modify**:
- `install.ps1` — add statusline copy step with manual settings.json instruction
- `TROUBLESHOOTING.md` — add note about null `current_usage` before first API call

---

## Rejected Alternatives

**Static model→context-window map in the script**
Rejected because Claude Code already provides `context_window_size` in the
runtime JSON. A static map would need manual updates on every new model release
and would be wrong for custom/fine-tuned models.

**`install.sh` silently patches settings.json without prompt**
Rejected because `settings.json` is the user's global config — silently modifying
it violates the principle of least surprise. A prompt with a clear skip path is
safer.

**Single built-in `/statusline` command instead of custom skill**
The built-in `/statusline` accepts natural language and generates a new script
each time. Our skill is different: it manages switching between pre-existing named
scripts and patches `settings.json` directly. The two are complementary.

---

## Security Considerations

- `install.sh` writes to `~/.claude/` only — no system-wide changes
- `settings.json` patching uses `jq` with atomic write (`tmp` file + `mv`) to
  avoid partial writes
- The statusline script reads only stdin and runs `git branch` — no secrets,
  no network calls, no eval

---

## Performance Considerations

- Script runs after every assistant turn; must be fast
- Single `input=$(cat)` read; multiple `jq` invocations on in-memory string
- `git branch --show-current` is fast but can be slow on large repos with
  filesystem issues — if this becomes a problem, cache to `/tmp` with a 5s TTL
  (out of scope for this task, noted for future)

---

**Next Steps:**
1. Review and approve this design
2. Run `/rlm-mem:plan:tasks` to break into tasks
