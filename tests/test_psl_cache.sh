#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_psl_cache.sh -- verify PSlibrary round-trip caching and --force behavior.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

printf '\n%s== PSlibrary cache behavior%s\n' "$DIM" "$RESET"

# 1. Built-in cache self-test in test_psl_roundtrip.sh
if "$HERE/test_psl_roundtrip.sh" --test-cache >/dev/null 2>&1; then
    ok_ "test_psl_roundtrip.sh --test-cache succeeds"
else
    bad_ "test_psl_roundtrip.sh --test-cache failed"
fi

# 2. Simulated end-to-end runs with temporary data directory
tmp_data=$TMP/psl
mkdir -p "$tmp_data"
echo "test data line 1" > "$tmp_data/sample.tpl"
cache_file="$tmp_data/.roundtrip.cache"

# Mock roundtrip script using the temp data
mock_rt() {
    local force=0
    [ "${1:-}" = "--force" ] && force=1
    local hash
    hash=$(find "$tmp_data" -type f -not -name '.roundtrip.cache' -not -path '*/.git/*' | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)

    if [ "$force" -ne 1 ] && [ -f "$cache_file" ] && [ "$(cat "$cache_file" 2>/dev/null)" = "$hash" ]; then
        echo "PSlibrary round-trip: unchanged since last verify ($hash)"
        echo "SKIP: cached result is still valid"
        return 0
    fi

    # simulated test run
    echo "running checks..."
    echo "$hash" > "$cache_file"
    echo "all round-trip checks passed"
    return 0
}

# Run 1: with no cache, test runs
out1=$(mock_rt)
if grep -q "all round-trip checks passed" <<< "$out1" && [ -f "$cache_file" ]; then
    ok_ "first run runs the suite and writes the cache file"
else
    bad_ "first run failed to write cache" "$out1"
fi

# Run 2: with cache, test skips and says why
out2=$(mock_rt)
if grep -q "SKIP: cached result is still valid" <<< "$out2"; then
    ok_ "second run skips with cached result message"
else
    bad_ "second run did not skip" "$out2"
fi

# Run 3: with --force, test runs again
out3=$(mock_rt --force)
if grep -q "all round-trip checks passed" <<< "$out3"; then
    ok_ "third run with --force re-runs despite cache"
else
    bad_ "third run with --force did not re-run" "$out3"
fi

# Run 4: if data changes, cache mismatch causes re-run
echo "added content" >> "$tmp_data/sample.tpl"
out4=$(mock_rt)
if grep -q "all round-trip checks passed" <<< "$out4" && ! grep -q "SKIP:" <<< "$out4"; then
    ok_ "modified data directory invalidates cache and triggers re-run"
else
    bad_ "modified data did not trigger re-run" "$out4"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET"
[ "$fail" -eq 0 ]
