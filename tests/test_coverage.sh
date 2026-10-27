#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_coverage.sh -- test suite for the coverage matrix tool
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT="$ROOT" PF_LIB="$ROOT/lib" PF_DATA="$ROOT/data"

for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines recipe advise provenance element coverage cli http; do
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

# 1. Default coverage matrix runs and populates output
if coverage_matrix "" "" >/dev/null 2>&1; then
    ok_ "coverage_matrix succeeds without filters"
    [ "${#COV_OUT_PROFILES[@]}" -ge 5 ] && ok_ "populates standard profiles (${#COV_OUT_PROFILES[@]})" || bad_ "profiles missing"
    [ "${#COV_OUT_ELEMENTS[@]}" -ge 10 ] && ok_ "populates elements (${#COV_OUT_ELEMENTS[@]})" || bad_ "elements missing"
else
    bad_ "coverage_matrix failed"
fi

# 2. Filter by profile
if coverage_matrix "psl-high" "" >/dev/null 2>&1; then
    [ "${#COV_OUT_PROFILES[@]}" -eq 1 ] && [ "${COV_OUT_PROFILES[0]}" = "psl-high" ] \
        && ok_ "filters to single profile psl-high" || bad_ "profile filter failed"
else
    bad_ "profile filter call failed"
fi

# 3. Filter by element
if coverage_matrix "" "Fe" >/dev/null 2>&1; then
    [ "${#COV_OUT_ELEMENTS[@]}" -eq 1 ] && [ "${COV_OUT_ELEMENTS[0]}" = "Fe" ] \
        && ok_ "filters to single element Fe" || bad_ "element filter failed"
else
    bad_ "element filter call failed"
fi

# 4. Human renderer
h_out=$(coverage_matrix "" "Fe" >/dev/null 2>&1 && coverage_render_human 2>&1)
grep -q "Coverage — element × profile" <<< "$h_out" && ok_ "human output includes header" || bad_ "header missing"
grep -q "Fe" <<< "$h_out" && ok_ "human output includes element Fe" || bad_ "element missing"
grep -q "Legend:" <<< "$h_out" && ok_ "human output includes Legend" || bad_ "legend missing"

# 5. JSON renderer
j_out=$(coverage_matrix "psl-high" "Si" >/dev/null 2>&1 && coverage_render_json 2>&1)
grep -q '"element": "Si"' <<< "$j_out" && ok_ "json output includes element Si" || bad_ "element missing from json"
grep -q '"profile": "psl-high"' <<< "$j_out" && ok_ "json output includes profile psl-high" || bad_ "profile missing from json"
grep -q '"state":' <<< "$j_out" && ok_ "json output includes state field" || bad_ "state missing from json"

# 6. CLI pseudoforge coverage
cli_out=$("$ROOT/pseudoforge" coverage --element Fe 2>&1)
grep -q "Coverage — element × profile" <<< "$cli_out" && ok_ "CLI coverage outputs header" || bad_ "CLI header missing"
grep -q "Legend:" <<< "$cli_out" && ok_ "CLI coverage outputs legend" || bad_ "CLI legend missing"

# 7. CLI help
help_out=$("$ROOT/pseudoforge" coverage --help 2>&1)
grep -q "pseudoforge coverage" <<< "$help_out" && ok_ "CLI coverage --help works" || bad_ "help output missing"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
