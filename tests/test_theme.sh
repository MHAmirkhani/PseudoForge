#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_theme.sh -- static tests for light/dark theme toggle and CSS selectors
# Note: A headless browser test would be better to verify rendering,
# but is not available in this environment; static assertions are used instead.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

printf '\n%s== 1. Theme toggle presence in HTML pages%s\n' "$DIM" "$RESET"

for page in "$ROOT"/frontend/*.html "$ROOT"/frontend/*/*.html; do
    [ -f "$page" ] || continue
    rel=${page#"$ROOT"/}
    if grep -q 'id="theme-toggle"' "$page"; then
        ok_ "$rel has id=\"theme-toggle\""
    else
        bad_ "$rel missing id=\"theme-toggle\""
    fi
done

printf '\n%s== 2. theme.js storage and attribute behavior%s\n' "$DIM" "$RESET"

THEME_JS="$ROOT/frontend/js/theme.js"
if [ -f "$THEME_JS" ]; then
    ok_ "frontend/js/theme.js exists"
else
    bad_ "frontend/js/theme.js missing"
fi

if grep -q "localStorage\.getItem(['\"]theme['\"])" "$THEME_JS"; then
    ok_ "theme.js reads localStorage.getItem('theme')"
else
    bad_ "theme.js does not read localStorage.getItem('theme')"
fi

if grep -q "document\.documentElement\.dataset\.theme" "$THEME_JS"; then
    ok_ "theme.js sets dataset.theme on documentElement"
else
    bad_ "theme.js does not set dataset.theme on documentElement"
fi

printf '\n%s== 3. CSS theme selectors in main.css%s\n' "$DIM" "$RESET"

MAIN_CSS="$ROOT/frontend/css/main.css"
if [ -f "$MAIN_CSS" ]; then
    ok_ "frontend/css/main.css exists"
else
    bad_ "frontend/css/main.css missing"
fi

if grep -qE '\[data-theme="light"\]|:root\[data-theme="light"\]' "$MAIN_CSS"; then
    ok_ "main.css contains [data-theme=\"light\"] selector"
else
    bad_ "main.css missing [data-theme=\"light\"] selector"
fi

if grep -qE '\[data-theme="dark"\]|:root\[data-theme="dark"\]' "$MAIN_CSS"; then
    ok_ "main.css contains [data-theme=\"dark\"] selector"
else
    bad_ "main.css missing [data-theme=\"dark\"] selector"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
