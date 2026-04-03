# AWSK Research: Intent Classification for UserPromptSubmit Hook

Date: 2026-04-02

## Problem

The behavioral-reminder hook fires on every user prompt. It must classify
intent (CRITICISM, IMPL_REQUEST, GIT_REQUEST) to inject the right reminder.
The original implementation used bash `case` with exact phrase matching,
which missed natural phrasing like "let's commit and push".

## Constraint

- Runs on every prompt -- must be fast (target: <100ms)
- macOS out of the box, no heavy dependencies
- No LLM API calls (too slow and expensive per-prompt)

## Approaches Benchmarked (macOS ARM64)

| Approach                         | Time    | Dependencies             | Accuracy     |
|----------------------------------|---------|--------------------------|--------------|
| bash `case` + jq (original)     | ~34ms   | jq                       | Low (exact phrases only) |
| bash `[[ =~ ]]` regex + jq      | ~15ms   | jq                       | Medium       |
| **awk weighted scoring + jq**    | **~7ms**| jq + awk (built-in)      | **Good**     |
| Pre-compiled Go binary           | ~10ms   | Go build step            | Good+        |
| Perl + JSON::PP                  | ~44ms   | perl (built-in)          | Good (PCRE)  |
| Python3 subprocess               | ~190ms  | python3                  | N/A (too slow)|
| Python3 + scikit-learn/spaCy     | 300-800ms| pip install (50-200MB)  | High         |
| Python3 + ONNX Runtime           | 200-500ms| pip install (~150MB)    | High         |
| fastText (Go wrapper)            | ~15-20ms| Go + model file (~5MB)  | Very high    |
| **Python daemon (Unix socket)**  | **~5-10ms**| python3 + ML lib + daemon| **Highest** |

## ML Approaches: The Real Future

ML-based classification is the best long-term solution -- it handles
paraphrasing, novel phrasing, and subtle intent signals that keyword matching
will always miss (e.g., "save my work to the repo" as a git intent).

The current blockers are performance and complexity, not capability:

- **Python startup** (~190ms) exceeds the per-prompt budget
- **Library footprint** (50-200MB) conflicts with "no heavy dependencies"
- **Daemon approach** solves both (~5-10ms, warm process) but adds lifecycle
  management complexity (launchd, crash recovery, port/socket handling)

Once the daemon performance issue is solved cleanly, ML classification
should replace AWSK. The daemon approach with a small trained model
(fastText or similar) would be the ideal target architecture.

## Current Solution: Awk Weighted Keyword Scoring (AWSK)

Chosen as a pragmatic interim approach while ML performance is unresolved.

### How It Works

1. Input is padded with spaces and lowercased for word-boundary simulation
2. awk scans for keywords, each with a numeric weight (1-3)
3. Negative patterns subtract score (e.g., "committed to" -3 from git score)
4. A threshold (2) determines whether the category fires
5. Single pipeline: `printf | tr | awk` -- one subprocess

### Benefits Over Case Matching

- **Broad coverage**: "commit" alone (weight 2) fires; no need to enumerate
  every phrase like "commit my changes", "commit these changes", etc.
- **False positive resistance**: "committed to this approach" triggers
  "committed to" (-3) which cancels out " commit" (+2), net score < 0
- **Tunable**: adjust weights and thresholds without restructuring code
- **Fast**: ~7ms total (jq parse + awk scoring)

### Limitations

- Still substring matching (no true word boundaries in awk)
- Novel intents with no keyword overlap will be missed
- Weights are hand-tuned, not learned from data
- Will be superseded by ML once the daemon approach is viable
