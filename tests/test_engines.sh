#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Integration test for the non-ld1 generator engines.
#
# Unlike run_tests.sh, this one uses the *real* binaries and, where pw.x is
# available, checks that what comes out actually loads into Quantum ESPRESSO.
# A pseudopotential that pw.x will not read is not a pseudopotential, however
# well-formed it looks.
#
#   tests/test_engines.sh            everything that is installed
#   tests/test_engines.sh oncvpsp    just that engine
#
# Engines that are not installed are skipped, not failed: the point is to
# verify what is present, and `pseudoforge engines build` is what installs them.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge
WANT=${1:-all}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0

ok_()   { printf '  %sPASS%s  %s\n' "$GREEN"  "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED"    "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
section() { printf '\n%s== %s%s\n' "$DIM" "$1" "$RESET"; }

engine_installed() { "$PSM" engines path "$1" >/dev/null 2>&1; }

# pw_loads <upf> <ecutwfc> <ecutrho> -- does pw.x actually accept this file?
pw_loads() {
    local upf=$1 wfc=$2 rho=$3 el dir=$TMP/pw
    el=$(basename "$upf" | cut -d. -f1)
    mkdir -p "$dir/out"
    cp -f "$upf" "$dir/" || return 1
    cat > "$dir/t.in" <<PWEOF
&CONTROL
  calculation='scf', prefix='t', outdir='$dir/out', pseudo_dir='$dir', disk_io='none'
/
&SYSTEM
  ibrav=2, celldm(1)=10.0, nat=1, ntyp=1
  ecutwfc=$wfc, ecutrho=$rho
  occupations='smearing', smearing='mv', degauss=0.02
/
&ELECTRONS
  conv_thr=1.0d-6, electron_maxstep=100
/
ATOMIC_SPECIES
 $el 1.0 $(basename "$upf")
ATOMIC_POSITIONS alat
 $el 0.0 0.0 0.0
K_POINTS automatic
 4 4 4 0 0 0
PWEOF
    ( cd "$dir" && OMP_NUM_THREADS=1 timeout 900 "${PW_BIN:-/opt/espresso/7.6/pw.x}" \
        -in t.in > t.out 2>&1 )
    grep -q '^!' "$dir/t.out"
}

have_pw() { [ -x "${PW_BIN:-/opt/espresso/7.6/pw.x}" ]; }

# ---------------------------------------------------------------------------
section "engine registry"
n=$("$PSM" engines list 2>&1 | grep -c 'installed\|buildable\|missing')
[ "$n" -ge 4 ] && ok_ "all four engines are registered" || bad_ "engine registry" "only $n listed"

# ---------------------------------------------------------------------------
if [ "$WANT" = all ] || [ "$WANT" = oncvpsp ]; then
section "ONCVPSP -- norm-conserving, writes UPF directly"
if ! engine_installed oncvpsp; then
    skip_ "ONCVPSP not installed (pseudoforge engines build oncvpsp)"
else
    out=$TMP/onc
    "$PSM" generate -e Si,Cu -t nc --engine oncvpsp -x pbe -o "$out" -j 2 --no-test -q \
        >"$TMP/onc.log" 2>&1
    for el in Si Cu; do
        f=$out/pseudos/$el.pbe-oncv.UPF
        if [ -s "$f" ]; then ok_ "$el generated"; else bad_ "$el generated" "see $TMP/onc.log"; continue; fi
        grep -q '</UPF>' "$f" && ok_ "$el UPF is complete" || bad_ "$el UPF is complete"
        "$PSM" validate "$f" >/dev/null 2>&1 && ok_ "$el passes validation" || bad_ "$el passes validation"
    done
    # provenance must say where the parameters came from, not just which engine ran
    prov=$(awk -F'\t' '$1 == "Si" { print $6 }' "$out/state.tsv" 2>/dev/null)
    case $prov in
        vendor|library|pseudoforge) ok_ "provenance recorded ($prov)" ;;
        *) bad_ "provenance recorded" "got '$prov'" ;;
    esac
    if have_pw; then
        if pw_loads "$out/pseudos/Si.pbe-oncv.UPF" 60 240; then
            ok_ "pw.x runs the ONCVPSP file"
        else
            bad_ "pw.x runs the ONCVPSP file" "$TMP/pw/t.out"
        fi
    else
        skip_ "pw.x not available for the load test"
    fi
fi
fi

# ---------------------------------------------------------------------------
if [ "$WANT" = all ] || [ "$WANT" = uspp ]; then
section "USPP -- ultrasoft, via reform.x and upfconv.x"
if ! engine_installed uspp; then
    skip_ "USPP not installed (pseudoforge engines build uspp)"
else
    out=$TMP/usp
    "$PSM" generate -e Si -t us --engine uspp -x pz -o "$out" --no-test -q >"$TMP/usp.log" 2>&1
    f=$out/pseudos/Si.pz-uspp.UPF
    if [ -s "$f" ]; then
        ok_ "Si generated and converted to UPF"
        grep -q '</UPF>' "$f" && ok_ "UPF is complete" || bad_ "UPF is complete"
        # the converter emits one enormous header line and 2500-character data
        # rows; QE's own reader rejects both, so pseudoforge rewraps them
        longest=$(awk '{ if (length() > m) m = length() } END { print m + 0 }' "$f")
        [ "$longest" -lt 1000 ] && ok_ "no over-long lines ($longest chars)" \
                                || bad_ "no over-long lines" "longest is $longest"
        grep -q 'pseudo_type="USPP"' "$f" && ok_ "pseudo_type filled in" || bad_ "pseudo_type filled in"
        grep -q 'element="Si"' "$f" && ok_ "element symbol capitalised" || bad_ "element symbol capitalised"
        if have_pw; then
            if pw_loads "$f" 30 240; then ok_ "pw.x runs the USPP file"
            else bad_ "pw.x runs the USPP file" "$TMP/pw/t.out"; fi
        else
            skip_ "pw.x not available for the load test"
        fi
    else
        bad_ "Si generated and converted to UPF" "see $TMP/usp.log"
    fi
fi
fi

# ---------------------------------------------------------------------------
if [ "$WANT" = all ] || [ "$WANT" = fhi98pp ]; then
section "fhi98PP -- norm-conserving, .cpi output"
if ! engine_installed fhi98pp; then
    skip_ "fhi98PP not installed (pseudoforge engines build fhi98pp)"
else
    out=$TMP/fhi
    "$PSM" generate -e Si -t nc --engine fhi98pp -x pbe -o "$out" --no-test -q >"$TMP/fhi.log" 2>&1
    # The engine runs; whether a UPF appears depends on the QE version, because
    # QE 7.x dropped .cpi/.fhi from its format dispatch.  Either outcome is a
    # pass, as long as pseudoforge keeps the native file and says which happened.
    if [ -s "$out/pseudos/Si.pbe-fhi.UPF" ]; then
        ok_ "Si generated and converted to UPF"
    elif [ -s "$out/pseudos/native/Si.cpi" ]; then
        ok_ "Si generated as .cpi and kept (QE cannot convert FHI files)"
        msg=$(awk -F'\t' '$1 == "Si" { print $11 }' "$out/state.tsv" 2>/dev/null)
        case $msg in
            *"cannot convert FHI"*) ok_ "the reason is reported accurately" ;;
            *) bad_ "the reason is reported accurately" "got '$msg'" ;;
        esac
    else
        bad_ "Si produced something" "see $TMP/fhi.log"
    fi
fi
fi

# ---------------------------------------------------------------------------
section "provenance guards"
# With no engine at all, an import-only library must refuse rather than
# quietly produce something and call it by that library's name.
# A fresh config, so a locally-installed engine recorded in the real
# ~/.pseudoforgerc does not mask what a new user would see.
mkdir -p "$TMP/clean"
outp=$(HOME=$TMP/clean PF_RC=$TMP/clean/.pseudoforgerc ENGINE_DIR=$TMP/clean/engines        PATH=/usr/bin:/bin "$PSM" generate -e Si -p sg15 -t nc 2>&1)
printf '%s' "$outp" | grep -q 'which is not installed' \
    && ok_ "library refused when its engine is missing" \
    || bad_ "library refused when its engine is missing"

# With an engine present it may run, but must not claim to be that library.
if engine_installed oncvpsp; then
    outp=$(PARAMS_CACHE=$TMP/pcache "$PSM" generate -e Si -p sg15 -t nc --dry-run -o "$TMP/prov" 2>&1)
    printf '%s' "$outp" | grep -qE "generation inputs|library" \
        && ok_ "published inputs fetched rather than invented" \
        || bad_ "published inputs fetched rather than invented"
else
    skip_ "published-input fetch (ONCVPSP not installed)"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
