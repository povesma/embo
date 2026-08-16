---
description: >
  Manage embo workflow profiles (quality / fast / minimal): list, show,
  and activate the profile that configures tools, testing, and rules.
---

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

1. Activate the named profile with one bare command:
   ```bash
   embo-profile set <name>
   ```
   `embo-profile` searches the profile dirs (project, then user, then
   the plugin's built-ins), validates the `name` field, and writes
   `~/.claude/active-profile.yaml` atomically. It exits non-zero with a
   message if the profile is not found or is invalid — relay that and
   stop.

2. On success, output confirmation:
   ```
   ✅ Profile activated: <name>

   <description>

   Key settings:
   - Code style: <line_length> chars, comments: <comments>
   - Testing: <approach>, subagents: <subagents list or "none">
   - Workflow: docs-first: <docs_first>, corrections: <on/off>
   - Tools: RLM: <on/off>
   - Git: commit style: <commit_style or "conventional">
   - Required MCPs: <list or "none">
   ```

### Mode: `list`

1. List available profiles with one bare command:
   ```bash
   embo-profile list
   ```
   It prints each profile's `name — description` across all search dirs
   (deduped) and marks the active one.

2. Present the result as a readable table, ending with:
   ```
   Activate with: /embo:profile use <name>
   Deactivate with: /embo:profile off
   ```

### Mode: `off`

1. Deactivate the active profile with one bare command:
   ```bash
   embo-profile reset
   ```
   It removes `~/.claude/active-profile.yaml` (idempotent). Commands then
   fall back to the canonical `default.yaml`.

2. Output confirmation:
   ```
   Profile deactivated. Commands will use the default profile.
   ```

## Error Handling

- Profile YAML missing `name` field → "Invalid profile: missing
  'name' field in <path>"
- No profiles directory exists → "No profiles found. Run install.sh
  or create profiles in ~/.claude/profiles/"
- YAML parse error → show the error, don't activate
