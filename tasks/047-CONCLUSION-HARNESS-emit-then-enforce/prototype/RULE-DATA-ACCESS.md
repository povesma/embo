<!-- RULE:DATA-ACCESS — prototype rule for task 047. This is the SINGLE
     maintenance home: the same text the model reads is the spec the
     probe checks. Paste into start.md's session rules for a live run. -->
### Emit a data-access conclusion before touching structured data

Before running any Bash command that reads or parses a structured-data
file (JSON / YAML / TOML), first emit one line, on its own:

`Data-access: <jq | yq | interpreter | n/a> — <one-line reason>`

- Prefer **jq** (JSON) / **yq** (YAML) for reading or extracting values.
- Use **interpreter** (python/node/…) only when the task is genuinely
  more than field extraction — transforming, validating across records,
  or logic a query can't express. State that reason.
- **n/a** when the command only names such a file but does not parse its
  structure (e.g. moving or listing it).

Then run a command consistent with what you stated. You — not a regex —
decide whether the rule applies, because you know what the command is
for. The tag is your own conclusion; the harness only checks it is
present and that the command you run matches it.
