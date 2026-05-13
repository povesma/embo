# Statusline tests

Bash unit tests for segments in `.claude/statusline.sh`.

## Run

```bash
bash tests/statusline/cmem_segment.test.sh
```

## What's covered

`cmem_segment.test.sh` runs the edge-case matrix from claude-mem
observation #10353 against the `cmem_segment()` function with
mocked `curl` output:

- `curl` missing from PATH (`mem:NOCURL`)
- empty response body (`mem:DOWN`)
- empty object / empty items array (`mem:idle`)
- valid epoch 5/20/60 min ago (`mem:Xm` green/yellow/red tiers)
- malformed JSON, non-empty body (`mem:DOWN`)
- future epoch / clock skew (`mem:0m`)
