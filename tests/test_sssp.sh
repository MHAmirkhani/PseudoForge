#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# SSSP selection-table tests.
#
# SSSP is a table of verdicts, not a library, so almost everything that can go
# wrong here is a lookup going quietly wrong: an element resolving to the
# wrong source library, a cut-off dropped, a JSON field read by the wrong
# name.  None of that raises an error -- it produces a run that generates the
# wrong pseudopotential, or the right one at the wrong cut-off, and says
# nothing.
#
# The parser is awk over a fixed-shape JSON file rather than a JSON library,
# because the tool is pure Bash.  That is a deliberate trade and it is the
# main thing these tests exist to pin: the file's shape is an assumption, and
# an upstream reformat would silently return nothing.
#
# Spot values below were read from SSSP 1.3.0 itself, not recalled.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines recipe; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_metadata_load; pf_params_load; pf_engines_load
spec_init 2>/dev/null || true

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

SPEC[xc]=pbe; SPEC[family]=nc

printf '\n%s== the bundled tables%s\n' "$DIM" "$RESET"
for f in PBE_efficiency PBE_precision PBEsol_efficiency PBEsol_precision; do
    p=$(sssp_data_dir)/SSSP_1.3.0_$f.json
    [ -f "$p" ] && ok_ "SSSP_1.3.0_$f.json is bundled" || bad_ "missing SSSP_1.3.0_$f.json"
done
[ -f "$(sssp_data_dir)/LICENSE.txt" ] \
    && ok_ "upstream LICENSE.txt travels with the tables" \
    || bad_ "LICENSE.txt is missing from the bundled data"

printf '\n%s== table selection%s\n' "$DIM" "$RESET"
SPEC[xc]=pbe; SSSP_ACCURACY=efficiency
case $(sssp_table) in *PBE_efficiency.json) ok_ "PBE + efficiency picks the right table" ;;
                      *) bad_ "wrong table: $(sssp_table)" ;; esac
SSSP_ACCURACY=precision
case $(sssp_table) in *PBE_precision.json) ok_ "precision picks the precision table" ;;
                      *) bad_ "wrong table: $(sssp_table)" ;; esac
SSSP_ACCURACY=efficiency
SPEC[xc]=pbesol
case $(sssp_table) in *PBEsol_efficiency.json) ok_ "PBEsol picks the PBEsol table" ;;
                      *) bad_ "wrong table: $(sssp_table)" ;; esac
SPEC[xc]=pbe

# SSSP published PBE and PBEsol only.  Anything else has to fail rather than
# quietly hand back the PBE table under another name.
SPEC[xc]=blyp
if sssp_table >/dev/null 2>&1; then
    bad_ "BLYP returned a table" "SSSP covers PBE and PBEsol only; a silent fallback is the wrong physics"
else
    ok_ "a functional SSSP never published is refused"
fi
SPEC[xc]=pbe

printf '\n%s== parsing the table%s\n' "$DIM" "$RESET"
n=$(sssp_elements | grep -c .)
[ "$n" = 103 ] && ok_ "103 elements parsed" \
    || bad_ "parsed $n elements, expected 103" \
            "if this is 0 the JSON shape changed and every lookup now returns nothing"

# Spot checks read from the shipped 1.3.0 PBE efficiency table.
while IFS='|' read -r el want_lib want_wfc want_rho; do
    IFS=$'\t' read -r fn lib wfc rho md5 < <(sssp_entry "$el") || { bad_ "$el not found"; continue; }
    if [ "$lib" = "$want_lib" ] && [ "$wfc" = "$want_wfc" ] && [ "$rho" = "$want_rho" ]; then
        ok_ "$el -> $lib at $wfc/$rho Ry"
    else
        bad_ "$el -> $lib at $wfc/$rho" "expected $want_lib at $want_wfc/$want_rho"
    fi
done <<'ROWS'
Si|100US|30.0|240.0
Ag|SG15|50.0|200.0
Al|100PAW|30.0|240.0
Ac|100US|40.0|320.0
ROWS

# The md5 is what makes a downloaded file checkable; losing it is silent.
IFS=$'\t' read -r fn lib wfc rho md5 < <(sssp_entry Si)
case $md5 in
    ????????????????????????????????) ok_ "the md5 checksum is carried through" ;;
    *) bad_ "md5 for Si came back as '$md5'" "without it a fetched file cannot be verified" ;;
esac

printf '\n%s== mapping a source onto a profile%s\n' "$DIM" "$RESET"
while IFS='|' read -r label want; do
    got=$(sssp_profile_for "$label" 2>/dev/null || printf 'NONE')
    [ "$got" = "$want" ] && ok_ "$label -> $want" || bad_ "$label -> $got, expected $want"
done <<'ROWS'
100PAW|psl-high
100US|psl-high
031PAW|psl-031
SG15|sg15
SG15-1.1|sg15
Dojo|pseudodojo
GBRV-1.2|gbrv
GBRV-1.5|gbrv
MalteSachs|marburg
ROWS

# An unknown label must fail rather than guess.  Guessing here substitutes a
# different library's pseudopotential for the one SSSP actually verified.
if sssp_profile_for "SomeLibraryAddedIn2030" >/dev/null 2>&1; then
    bad_ "an unknown source label was mapped anyway" "guessing swaps in a library SSSP never tested"
else
    ok_ "an unknown source label is refused rather than guessed"
fi

printf '\n%s== family inferred from the file name%s\n' "$DIM" "$RESET"
while IFS='|' read -r name want; do
    got=$(sssp_family_for "$name")
    [ "$got" = "$want" ] && ok_ "$name -> $want" || bad_ "$name -> '$got', expected $want"
done <<'ROWS'
Al.pbe-n-kjpaw_psl.1.0.0.UPF|paw
Si.pbe-n-rrkjus_psl.1.0.0.UPF|us
Ag_ONCV_PBE-1.0.oncvpsp.upf|nc
ROWS

printf '\n%s== coverage%s\n' "$DIM" "$RESET"
# Recorded rather than remembered: most of SSSP resolves to libraries this
# tool generates, and a drop would mean a mapping quietly broke.
gen=0; tot=0
for el in $(sssp_elements); do
    tot=$((tot + 1))
    sssp_can_generate "$el" 2>/dev/null && gen=$((gen + 1))
done
if [ "$gen" -ge 80 ]; then
    ok_ "$gen of $tot elements resolve to a profile PseudoForge can generate"
else
    bad_ "only $gen of $tot resolve to a generatable profile" \
         "this was 87 when the mapping was written; a drop means a label stopped matching"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
