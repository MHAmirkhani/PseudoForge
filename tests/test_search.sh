#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Tests for docs search (/search/ and search index)
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

printf '\n%s== 1. Frontend search assets%s\n' "$DIM" "$RESET"

# 1.1 HTML exists
if [ -f "$ROOT/frontend/search/index.html" ]; then
    ok_ "frontend/search/index.html exists"
else
    bad_ "frontend/search/index.html missing"
fi

# 1.2 JS exists
if [ -f "$ROOT/frontend/js/search.js" ]; then
    ok_ "frontend/js/search.js exists"
else
    bad_ "frontend/js/search.js missing"
fi

# 1.3 Degrades gracefully if search_index.json is missing
if grep -q "Documentation index not available" "$ROOT/frontend/js/search.js" && grep -q "tools/build_docs.sh" "$ROOT/frontend/js/search.js"; then
    ok_ "frontend/js/search.js explains how to generate index when missing"
else
    bad_ "frontend/js/search.js missing graceful degradation notice"
fi

printf '\n%s== 2. MkDocs search index%s\n' "$DIM" "$RESET"

idx_path="$ROOT/site/search/search_index.json"
if [ -f "$idx_path" ]; then
    count=$(python3 -c "import json; d = json.load(open('$idx_path')); print(len(d.get('docs', [])))" 2>/dev/null || echo 0)
    if [ "$count" -gt 0 ]; then
        ok_ "site/search/search_index.json is valid with $count indexed sections"
    else
        bad_ "site/search/search_index.json has no indexed docs"
    fi

    # Verify search query resolution
    hits=$(python3 -c "
import json
d = json.load(open('$idx_path'))
matches = [doc for doc in d.get('docs', []) if 'oncvpsp' in doc.get('text', '').lower()]
print(len(matches))
" 2>/dev/null || echo 0)
    if [ "$hits" -gt 0 ]; then
        ok_ "search index query matches expected content ('oncvpsp' -> $hits matches)"
    else
        bad_ "search index query returned 0 matches for 'oncvpsp'"
    fi
else
    skip_ "site/search/search_index.json not yet built (run tools/build_docs.sh)"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET"
[ "$fail" -eq 0 ]
