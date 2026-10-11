#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Engine-native functional checks (xc_engine_native).
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert params engines recipe input_builder; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_engines_load; spec_init

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0
ok_()  { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_() { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }

SPEC[engine]=atompaw

printf '\n%s== xc_engine_native for AtomPAW%s\n' "$DIM" "$RESET"

for fn in pz lda pw pbe pbesol r2scan r2scan-01; do
    if xc_engine_native "$fn" atompaw; then
        ok_ "xc_engine_native $fn atompaw is true"
    else
        bad_ "xc_engine_native $fn atompaw was false"
    fi
done

for fn in scan tpss m06l pbe0 hse06 rvv10 vdw-df2; do
    if xc_engine_native "$fn" atompaw; then
        bad_ "xc_engine_native $fn atompaw was true (should be false)"
    else
        ok_ "xc_engine_native $fn atompaw is false"
    fi
done

if xc_engine_native r2scan && ! xc_engine_native scan && ! xc_engine_native tpss && xc_engine_native pbe; then
    ok_ "xc_engine_native defaults to SPEC[engine] when second argument is omitted"
else
    bad_ "xc_engine_native without second argument disagreed with explicit atompaw"
fi

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET"
[ "$fail" -eq 0 ]
