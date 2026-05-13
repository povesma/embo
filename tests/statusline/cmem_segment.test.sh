#!/usr/bin/env bash
# Test harness for cmem_segment() in .claude/statusline.sh.
# Runs the edge-case matrix from claude-mem observation #10353
# against the function with mocked curl output.
#
# Run: bash tests/statusline/cmem_segment.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATUSLINE="$REPO_ROOT/.claude/statusline.sh"

if [ ! -f "$STATUSLINE" ]; then
    echo "FAIL: $STATUSLINE not found"
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq is required to run these tests"
    exit 2
fi

# --- Extract cmem_segment + its required globals from statusline.sh ---
# The script's top-level code reads stdin and exits if jq is missing.
# We need only: RESET / GREEN / YELLOW / RED color vars, CMEM_GREEN_MAX,
# CMEM_YELLOW_MAX, and the cmem_segment() function itself.
HARNESS=$(awk '
    /^RESET=/        {print; next}
    /^GREEN=/        {print; next}
    /^YELLOW=/       {print; next}
    /^RED=/          {print; next}
    /^CMEM_GREEN_MAX=/  {print; next}
    /^CMEM_YELLOW_MAX=/ {print; next}
    /^cmem_segment\(\)/ {in_fn=1; print; next}
    in_fn && /^}/    {print; in_fn=0; next}
    in_fn            {print}
' "$STATUSLINE")

if [ -z "$HARNESS" ]; then
    echo "FAIL: could not extract cmem_segment from statusline.sh"
    exit 2
fi

# shellcheck disable=SC1090
eval "$HARNESS"

# --- Test helpers ---
PASSED=0
FAILED=0
FAILURES=()

assert_contains() {
    local name="$1" actual="$2" needle="$3"
    if [[ "$actual" == *"$needle"* ]]; then
        PASSED=$((PASSED + 1))
        printf "  PASS: %s\n" "$name"
    else
        FAILED=$((FAILED + 1))
        FAILURES+=("$name :: expected to contain '$needle', got: $(printf '%q' "$actual")")
        printf "  FAIL: %s\n" "$name"
    fi
}

assert_not_contains() {
    local name="$1" actual="$2" needle="$3"
    if [[ "$actual" != *"$needle"* ]]; then
        PASSED=$((PASSED + 1))
        printf "  PASS: %s\n" "$name"
    else
        FAILED=$((FAILED + 1))
        FAILURES+=("$name :: expected NOT to contain '$needle', got: $(printf '%q' "$actual")")
        printf "  FAIL: %s\n" "$name"
    fi
}

# ANSI color sentinels (the substrings the function emits)
GREEN_CODE=$'\033[32m'
YELLOW_CODE=$'\033[33m'
RED_CODE=$'\033[31m'

# Build a curl mock that prints a fixed body to stdout.
# The mock function shadows /usr/bin/curl when sourced into the same shell.
make_curl_mock() {
    local body="$1"
    eval "curl() { printf '%s' \"\$(cat <<'CURL_BODY_EOF'
$body
CURL_BODY_EOF
)\"; }"
}

# Reset curl mock between tests
clear_curl_mock() {
    unset -f curl 2>/dev/null || true
}

# Mock for "curl exists but produces empty output" (e.g. timeout / refused)
make_curl_empty_mock() {
    eval "curl() { return 0; }"
}

# Mock for "curl not on PATH" — drop curl from PATH for one invocation.
run_without_curl() {
    local saved_path="$PATH"
    # Provide a PATH that excludes any directory containing curl.
    # Easier: shadow command via a function that says it's missing.
    PATH="/var/empty"
    # command -v is a shell builtin so it still works but won't find curl
    local out
    out=$(cmem_segment)
    PATH="$saved_path"
    printf '%s' "$out"
}

echo "Running cmem_segment edge-case matrix..."
echo

# --- Test 3.3: curl missing from PATH -> mem:NOCURL + red ---
clear_curl_mock
out=$(run_without_curl)
assert_contains "3.3 curl-missing emits NOCURL" "$out" "mem:NOCURL"
assert_contains "3.3 curl-missing colored red" "$out" "$RED_CODE"

# --- Test 3.4: curl returns empty body -> mem:DOWN + red ---
make_curl_empty_mock
out=$(cmem_segment)
assert_contains "3.4 empty-body emits DOWN" "$out" "mem:DOWN"
assert_contains "3.4 empty-body colored red" "$out" "$RED_CODE"

# --- Test 3.5: curl returns {} -> mem:idle + yellow ---
make_curl_mock '{}'
out=$(cmem_segment)
assert_contains "3.5 empty-object emits idle" "$out" "mem:idle"
assert_contains "3.5 empty-object colored yellow" "$out" "$YELLOW_CODE"

# --- Test 3.6: curl returns {"items":[]} -> mem:idle + yellow ---
make_curl_mock '{"items":[]}'
out=$(cmem_segment)
assert_contains "3.6 empty-items emits idle" "$out" "mem:idle"
assert_contains "3.6 empty-items colored yellow" "$out" "$YELLOW_CODE"

# --- Test 3.7: epoch = now-5min -> mem:5m + green ---
now_s=$(date +%s)
epoch_5min_ago=$(( (now_s - 300) * 1000 ))
make_curl_mock "{\"items\":[{\"created_at_epoch\":${epoch_5min_ago}}]}"
out=$(cmem_segment)
assert_contains "3.7 5min-ago emits mem:5m" "$out" "mem:5m"
assert_contains "3.7 5min-ago colored green" "$out" "$GREEN_CODE"

# --- Test 3.8: epoch = now-20min -> mem:20m + yellow ---
epoch_20min_ago=$(( (now_s - 1200) * 1000 ))
make_curl_mock "{\"items\":[{\"created_at_epoch\":${epoch_20min_ago}}]}"
out=$(cmem_segment)
assert_contains "3.8 20min-ago emits mem:20m" "$out" "mem:20m"
assert_contains "3.8 20min-ago colored yellow" "$out" "$YELLOW_CODE"

# --- Test 3.9: epoch = now-60min -> mem:60m + red ---
epoch_60min_ago=$(( (now_s - 3600) * 1000 ))
make_curl_mock "{\"items\":[{\"created_at_epoch\":${epoch_60min_ago}}]}"
out=$(cmem_segment)
assert_contains "3.9 60min-ago emits mem:60m" "$out" "mem:60m"
assert_contains "3.9 60min-ago colored red" "$out" "$RED_CODE"

# --- Test 3.10: malformed JSON (non-empty, unparseable) -> mem:DOWN + red ---
make_curl_mock 'not json{'
out=$(cmem_segment)
assert_contains "3.10 malformed-json emits DOWN" "$out" "mem:DOWN"
assert_not_contains "3.10 malformed-json NOT idle" "$out" "mem:idle"
assert_contains "3.10 malformed-json colored red" "$out" "$RED_CODE"

# --- Test 3.11: epoch in the future (clock skew) -> mem:0m + green ---
epoch_future=$(( (now_s + 60) * 1000 ))
make_curl_mock "{\"items\":[{\"created_at_epoch\":${epoch_future}}]}"
out=$(cmem_segment)
assert_contains "3.11 future-epoch clamped to 0m" "$out" "mem:0m"
assert_contains "3.11 future-epoch colored green" "$out" "$GREEN_CODE"

clear_curl_mock
echo
echo "Results: $PASSED passed, $FAILED failed"
if [ "$FAILED" -gt 0 ]; then
    echo
    echo "Failures:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
exit 0
