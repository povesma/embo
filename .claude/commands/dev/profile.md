# Workflow Profile Management

Activate, list, or deactivate workflow configuration profiles.

## When to Use

- Starting work on a project with different needs than your default
- Switching between quality-first and speed-first workflows
- Checking which profiles are available

## Arguments

This command accepts one of three modes via arguments:

- `use <name>` — activate a named profile
- `list` — show all available profiles
- `off` — deactivate the current profile

If no argument is provided, default to `list`.

## Process

### Mode: `use <name>`

1. Search for `<name>.yaml` in these locations (first match wins):
   - `.claude/profiles/<name>.yaml` (project scope)
   - `~/.claude/profiles/<name>.yaml` (user scope)

2. If not found, list available profiles and stop with an error.

3. Read the YAML file and verify it has a `name` field.

4. Copy the file to `~/.claude/active-profile.yaml`:
   ```bash
   cp <found_path> ~/.claude/active-profile.yaml
   ```

5. Output confirmation:
   ```
   ✅ Profile activated: <name>

   <description>

   Key settings:
   - Code style: <line_length> chars, comments: <comments>
   - Testing: <approach>, subagents: <subagents list or "none">
   - Workflow: docs-first: <docs_first>, corrections: <on/off>
   - Tools: RLM: <on/off>, memory: <memory_backend>
   - Git: commit style: <commit_style or "conventional">
   - Required MCPs: <list or "none">
   ```

### Mode: `list`

1. Scan for `.yaml` files in:
   - `~/.claude/profiles/` (user scope)
   - `.claude/profiles/` (project scope, if it exists)

2. For each file, read the `name` and `description` fields.

3. Check if `~/.claude/active-profile.yaml` exists and read its
   `name` to identify the active profile.

4. Output a table:
   ```
   Available profiles:

   Name       | Description                              | Scope   | Active
   -----------|------------------------------------------|---------|-------
   quality    | Full workflow — docs-first, TDD, RLM...  | user    | ◀
   fast       | Speed mode — test-after, relaxed docs... | user    |
   minimal    | Bare bones — no RLM, no memory...        | user    |

   Activate with: /dev:profile use <name>
   Deactivate with: /dev:profile off
   ```

### Mode: `off`

1. Remove the active profile:
   ```bash
   rm -f ~/.claude/active-profile.yaml
   ```

2. Output confirmation:
   ```
   Profile deactivated. Commands will use built-in defaults.
   ```

## Error Handling

- Profile YAML missing `name` field → "Invalid profile: missing
  'name' field in <path>"
- No profiles directory exists → "No profiles found. Run install.sh
  or create profiles in ~/.claude/profiles/"
- YAML parse error → show the error, don't activate
