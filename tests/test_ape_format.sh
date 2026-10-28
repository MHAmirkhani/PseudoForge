#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Test that APE writes the format declared by data/formats.tsv.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

# Check registry
reg_fmt=$(awk -F'\t' '$1 != "#" && $3 ~ /(^| )ape( |$)/ { print $1 }' "$ROOT/data/formats.tsv")
[ "$reg_fmt" = "upf" ] && ok_ "registry records ape writes upf" || bad_ "registry records ape writes $reg_fmt"

# Check builder explicitly sets PPOutputFileFormat = upf
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines build recipe input_builder executor; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_metadata_load; pf_params_load; pf_engines_load
spec_init 2>/dev/null || true
declare -gA SPEC=()
SPEC[xc]=pz; SPEC[rel]=scalar; SPEC[family]=nc; SPEC[profile]=pseudoforge-auto; SPEC[engine]=ape

deck_line=$(ib_build_ape Si "$TMP/in" 2>/dev/null) || true
deck_file=$(printf '%s' "$deck_line" | cut -d$'\x1f' -f1)
if grep -q '^PPOutputFileFormat = upf' "$deck_file" 2>/dev/null; then
    ok_ "ib_build_ape sets PPOutputFileFormat = upf"
else
    bad_ "ib_build_ape does not set PPOutputFileFormat = upf"
fi

# Live test if APE is available
if ! eng_resolve ape >/dev/null 2>&1; then
    skip_ "APE engine not installed"
else
    OUT="$TMP/ape_out"
    if "$PSM" generate -e Si -t nc -p pseudoforge-auto --engine ape -o "$OUT" -q >/dev/null 2>&1; then
        produced=$(ls "$OUT"/pseudos/*.[uU][pP][fF] 2>/dev/null | head -1)
        if [ -n "$produced" ] && [ -s "$produced" ]; then
            ok_ "APE generated $produced matching registry ($reg_fmt)"
            if "$PSM" validate "$produced" >/dev/null 2>&1; then
                ok_ "generated file passes validation"
            else
                bad_ "generated file failed validation"
            fi
        else
            bad_ "no UPF file produced by APE in $OUT/pseudos"
        fi
    else
        bad_ "generate -e Si --engine ape failed"
    fi
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$( [ "$skip" -gt 0 ] && printf '%s' "$YELLOW" || printf '%s' "$DIM" )" "$skip" "$RESET"
[ "$fail" -eq 0 ]
