#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Regression test for the GTH engine and its coefficient conversion.
#
# The conversion this locks down is the one place in PseudoForge where physics
# is re-derived rather than copied: psp.par holds a fully relativistic fit with
# separate j = l +/- 1/2 coefficients, and CP2K's format wants the
# degeneracy-weighted average of eq. (16) of Hartwigsen, Goedecker and Hutter
# (1998).  Get that wrong and the output still looks like a plausible GTH block
# -- right shape, right magnitudes, wrong pseudopotential.
#
# The check is therefore not "does it produce something" but "does it reproduce
# CP2K's own published table, digit for digit", run over every element and
# functional that ships with a published pair.  That is 322 comparisons, and it
# is the only test here that could catch a sign error in the averaging.
#
#   tests/test_gth.sh           the fast subset (default)
#   tests/test_gth.sh --all     every published element (slower)
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge
MODE=${1:-}

export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth params engines; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_metadata_load; pf_params_load; pf_engines_load
spec_init 2>/dev/null || true

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN"  "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED"    "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
section() { printf '\n%s== %s%s\n' "$DIM" "$1" "$RESET"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
section "functional mapping"
# ---------------------------------------------------------------------------
for pair in "pz:pade" "pbe:pbe" "pbesol:pbesol" "blyp:blyp" "bp:bp" "olyp:olyp"; do
    want=${pair#*:}; got=$(gth_xc_keyword "${pair%:*}" 2>/dev/null)
    [ "$got" = "$want" ] && ok_ "${pair%:*} -> $want" || bad_ "${pair%:*} -> ${got:-nothing}, expected $want"
done
# A functional GTH has no table for must be refused, not silently substituted.
for bad in scan r2scan hse pbe0; do
    if gth_xc_keyword "$bad" >/dev/null 2>&1; then
        bad_ "$bad was accepted" "GTH has no $bad table; accepting it would hand back the wrong functional"
    else
        ok_ "$bad refused"
    fi
done

# ---------------------------------------------------------------------------
section "psp.par -> CP2K conversion against the published tables"
# ---------------------------------------------------------------------------
if [ "$MODE" = --all ]; then
    KWS="pade pbe blyp bp olyp hcth120 hcth407 pbesol"
else
    KWS="pbe pade"
fi

checked=0; mismatched=0; first=""
for kw in $KWS; do
    gdir=$(gth_data_root)/generate/$kw
    [ -d "$gdir" ] || continue
    for d in "$gdir"/*; do
        el=$(basename "$d")
        # the fast subset: a spread of channel counts and a known-mangled file
        if [ "$MODE" != --all ]; then
            case $el in Si|O|C|Fe|Ti|Au|Hg|Tl|At|Bi|Pb|Rn|H|Cu|W) ;; *) continue ;; esac
        fi
        inputs=$(gth_inputs "$kw" "$el" 2>/dev/null) || continue
        q=$(printf '%s' "$inputs" | grep -oE 'q[0-9]+$' | tr -d q)
        tbl=$(gth_table cp2k "$kw" "$el" "$q" 2>/dev/null) || continue
        psp=$(ls "$inputs"/psp_*/psp.par 2>/dev/null | head -1)
        [ -n "$psp" ] || continue
        val=$(gth_valence_from_atom_dat "$inputs/atom/atom.dat")
        lbl=$(head -1 "$tbl" | cut -d' ' -f2-)
        gth_psp_to_cp2k "$psp" "$el" "$lbl" "$val" > "$TMP/out" 2>/dev/null
        checked=$((checked + 1))
        if ! diff -q "$TMP/out" <(sed '/^$/d' "$tbl") >/dev/null 2>&1; then
            mismatched=$((mismatched + 1))
            [ -z "$first" ] && first=$(diff "$TMP/out" <(sed '/^$/d' "$tbl") | head -6)
        fi
    done
done
if [ "$checked" -eq 0 ]; then
    skip_ "no bundled GTH data to check against"
elif [ "$mismatched" -eq 0 ]; then
    ok_ "$checked/$checked reproduce the published table byte for byte"
else
    bad_ "$mismatched of $checked do not match the published table" "$first"
fi

# The spin-orbit average is the one derived quantity; pin it to a number that
# can be checked by hand against the paper.  Si l=1 averages 2.44066517 (j=3/2)
# and 2.41249987 (j=1/2) to 2.43127673, which is what CP2K publishes.
si_inputs=$(gth_inputs pbe Si 2>/dev/null)
if [ -n "$si_inputs" ]; then
    got=$(gth_psp_to_cp2k "$(ls "$si_inputs"/psp_*/psp.par)" Si GTH-PBE-q4 "    2    2" \
          | awk 'NR==7{print $3}')
    [ "$got" = "2.43127673" ] \
        && ok_ "spin-orbit average, Si l=1 -> 2.43127673" \
        || bad_ "spin-orbit average, Si l=1 -> ${got:-nothing}" "expected 2.43127673 (HGH 1998 eq. 16)"
else
    skip_ "spin-orbit average (no bundled Si inputs)"
fi

# ---------------------------------------------------------------------------
section "structural validation"
# ---------------------------------------------------------------------------
good=$(gth_table cp2k pbe Si 2>/dev/null)
if [ -n "$good" ]; then
    gth_validate_block "$good" >/dev/null 2>&1 \
        && ok_ "a published block validates" \
        || bad_ "a published block was rejected"

    # Each of these is a way a half-written file can look fine by byte count.
    sed '/^$/d' "$good" > "$TMP/ok"
    head -5 "$TMP/ok"                                    > "$TMP/truncated"
    sed 's/2.43127673/NaN/'          "$TMP/ok"           > "$TMP/nan"
    sed 's/^    2    2$/    0    0/' "$TMP/ok"           > "$TMP/nozval"
    sed 's/0.44000000    1 /0.44000000    3 /' "$TMP/ok" > "$TMP/badcount"
    for case in truncated nan nozval badcount; do
        if gth_validate_block "$TMP/$case" >/dev/null 2>&1; then
            bad_ "$case was accepted" "a damaged coefficient block must not validate"
        else
            ok_ "$case rejected"
        fi
    done
else
    skip_ "structural validation (no bundled table)"
fi

# ---------------------------------------------------------------------------
section "engine"
# ---------------------------------------------------------------------------
if ! "$PSM" engines path gth >/dev/null 2>&1; then
    skip_ "gth engine not installed (pseudoforge engines build gth)"
else
    bin=$("$PSM" engines path gth 2>/dev/null)
    [ -x "$(dirname "$bin")/atom.x" ] \
        && ok_ "atom.x installed beside pseudo.x" \
        || bad_ "atom.x missing" "a GTH fit needs both programs"

    # The published-coefficient path: fast, and must be exact.
    if "$PSM" generate -p cp2k-gth -e Si -x pbe -t nc --format gth -o "$TMP/pub" >/dev/null 2>&1; then
        out=$(ls "$TMP/pub"/pseudos/*.gth 2>/dev/null | head -1)
        if [ -n "$out" ] && diff -q "$out" <(sed '/^$/d' "$good") >/dev/null 2>&1; then
            ok_ "generate writes the published Si coefficients unchanged"
        else
            bad_ "generate did not reproduce the published Si block"
        fi
    else
        bad_ "generate failed for cp2k-gth Si"
    fi

    # The refit path is slow, so it is opt-in.  When it does run, the thing
    # worth asserting is not that it matches -- it must not -- but that it
    # lands close and is labelled as this tool's work rather than CP2K's.
    if [ "$MODE" = --all ]; then
        if GTH_REFIT=1 GTH_CYCLES=40 "$PSM" generate -p cp2k-gth -e Si -x pbe -t nc \
             --format gth -o "$TMP/refit" >/dev/null 2>&1; then
            out=$(ls "$TMP/refit"/pseudos/*.gth 2>/dev/null | head -1)
            if grep -q PSEUDOFORGE "$out" 2>/dev/null; then
                ok_ "refit is labelled PSEUDOFORGE, not as the library"
            else
                bad_ "refit output is not labelled" "a refit is not CP2K's pseudopotential and must not claim to be"
            fi
            rl=$(awk 'NR==5{print $1}' "$out")
            close=$(awk -v a="$rl" 'BEGIN{d=a-0.43563383; if(d<0)d=-d; print (d<0.01)?"yes":"no"}')
            [ "$close" = yes ] \
                && ok_ "refit r_l=$rl lands near the published 0.43563383" \
                || bad_ "refit r_l=$rl is far from the published 0.43563383"
        else
            bad_ "refit run failed"
        fi
    else
        skip_ "refit (slow; run tests/test_gth.sh --all)"
    fi
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
