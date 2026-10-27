#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_element.sh -- test suite for the element tool
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines recipe provenance element cli http; do
    # shellcheck disable=SC1090
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done

pf_config_defaults 2>/dev/null || true
pf_elements_load; pf_xc_load; pf_profiles_load; pf_engines_load; pf_metadata_load

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  SKIP  %s\n' "$1"; skip=$((skip + 1)); }

# 1. Unknown element fails cleanly
if element_summary_for "Xx" >/dev/null 2>&1; then
    bad_ "element_summary_for should fail for unknown element Xx"
else
    ok_ "element_summary_for fails cleanly for unknown element Xx"
fi

# 2. Known element succeeds and sets outputs
if element_summary_for "Si" >/dev/null 2>&1; then
    ok_ "element_summary_for succeeds for Si"
    [ "$EL_OUT_SYMBOL" = "Si" ] && ok_ "sets symbol Si" || bad_ "wrong symbol: $EL_OUT_SYMBOL"
    [ "$EL_OUT_NAME" = "Silicon" ] && ok_ "sets name Silicon" || bad_ "wrong name: $EL_OUT_NAME"
    [ "$EL_OUT_Z" -eq 14 ] && ok_ "sets Z=14" || bad_ "wrong Z: $EL_OUT_Z"
    [ "$EL_OUT_TOTAL" -ge 1 ] && ok_ "found native files for Si ($EL_OUT_TOTAL total)" || bad_ "no files found"
else
    bad_ "element_summary_for failed for Si"
fi

# 3. Case insensitivity (si -> Si)
if element_summary_for "si" >/dev/null 2>&1; then
    [ "$EL_OUT_SYMBOL" = "Si" ] && ok_ "normalizes lowercase 'si' to 'Si'" || bad_ "did not normalize: $EL_OUT_SYMBOL"
else
    bad_ "lowercase 'si' failed"
fi

# 4. Human renderer
h_out=$(element_render_human 2>&1)
echo "$h_out" | grep -q 'Si (Silicon, Z=14)' && ok_ "human renderer includes header" || bad_ "header missing: $h_out"
echo "$h_out" | grep -q 'NC — norm-conserving' && ok_ "human renderer includes NC section" || bad_ "NC missing"

# 5. JSON renderer
j_out=$(element_render_json 2>&1)
grep -q '"symbol": "Si"' <<< "$j_out" && ok_ "json renderer has symbol field" || bad_ "symbol missing from json"
grep -q '"families":' <<< "$j_out" && ok_ "json renderer has families object" || bad_ "families missing from json"

# 6. CLI dispatcher
cli_out=$("$ROOT/pseudoforge" element Si 2>&1)
echo "$cli_out" | grep -q 'Si (Silicon, Z=14)' && ok_ "CLI pseudoforge element Si outputs header" || bad_ "CLI output missing header"

# 7. CLI help
help_out=$("$ROOT/pseudoforge" element --help 2>&1)
echo "$help_out" | grep -q 'pseudoforge element' && ok_ "CLI pseudoforge element --help works" || bad_ "help output missing"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
