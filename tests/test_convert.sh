#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Format-conversion tests.
#
# The thing this suite is really guarding is the boundary between converting a
# file and making a different pseudopotential.  A converter that quietly
# crosses that line produces output which passes every structural check and is
# the wrong physics, so the refusals are tested as carefully as the successes.
#
# Two traps found while writing the module, both pinned below:
#
#   upfconv.x exits 0 whether or not it worked.  A file it cannot read gives
#   "readpp: file X could not be read" and status zero, so the log is the
#   authority, not $?.
#
#   upfconv.x names its own output and does not say so: converting to UPF v2 it
#   writes "<name>.cpi.UPF2", not "<name>.UPF".  Globbing for the expected name
#   found nothing and reported a successful conversion as a failure.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert params engines upf; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load 2>/dev/null
pf_convert_load

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FIX=$HERE/fixtures
PSM=$ROOT/pseudoforge

printf '\n%s== format detection%s\n' "$DIM" "$RESET"
while IFS='|' read -r name want; do
    [ -n "$name" ] || continue
    : > "$TMP/$name"
    got=$(cvt_detect "$TMP/$name" 2>/dev/null || printf 'none')
    [ "$got" = "$want" ] && ok_ "$name -> $want" || bad_ "$name detected as '$got', expected $want"
done <<'ROWS'
a.upf|upf
a.psp8|psp8
a.vps|vps
a.gth|gth
a.van|van
a.cpi|cpi
a.fhi|fhi
ROWS

# .xml is ambiguous: PAW-XML and QE's own schema share the extension, so the
# content has to decide.
x=$(ls "$FIX"/pawxml/*.xml 2>/dev/null | head -1)
if [ -n "$x" ]; then
    [ "$(cvt_detect "$x")" = pawxml ] \
        && ok_ "a PAW-XML file is told apart from QE's xml by content" \
        || bad_ "PAW-XML detected as $(cvt_detect "$x")"
else
    skip_ "no PAW-XML fixture"
fi

printf '\n%s== a real conversion%s\n' "$DIM" "$RESET"
# .van is the path exec_uspp already relies on, so it is the one to pin.
# Prefer the fixture.  Searching /tmp first picked up a scratch file that a
# previous run had already cleaned away, and the test failed on a stale path
# rather than on anything about the converter.
van=$(ls "$FIX"/van/*.van 2>/dev/null | head -1)
[ -n "$van" ] || van=$(find /tmp -name '*.van' 2>/dev/null | head -1)
if [ -n "$van" ] && cvt_tool_available upfconv; then
    out=$(cvt_convert "$van" upf "$TMP" 2>/dev/null)
    if [ -n "$out" ] && [ -s "$out" ]; then
        ok_ "van -> UPF produced $(basename "$out") ($(wc -c < "$out") bytes)"
        upf_validate "$out" >/dev/null 2>&1 \
            && ok_ "the converted UPF passes UPF validation" \
            || bad_ "the converted UPF fails validation"
        [ -f "$out.provenance" ] \
            && ok_ "a provenance record was written beside it" \
            || bad_ "no provenance record for the conversion"
        for k in source.format target.format conversion.path conversion.kind converter.version; do
            grep -q "^$k=" "$out.provenance" \
                && ok_ "provenance records $k" \
                || bad_ "provenance has no $k"
        done
    else
        bad_ "van -> UPF produced nothing"
    fi
else
    skip_ "no .van available, or upfconv.x missing"
fi

printf '\n%s== upfconv traps%s\n' "$DIM" "$RESET"
# A file upfconv cannot read must be reported as a failure even though the
# tool exits 0.
printf 'this is not a pseudopotential\n' > "$TMP/junk.cpi"
if cvt_convert "$TMP/junk.cpi" upf "$TMP" >/dev/null 2>&1; then
    bad_ "an unreadable file was reported as converted" \
         "upfconv.x exits 0 on failure; the log is the authority"
else
    ok_ "an unreadable source is caught despite exit 0"
fi
grep -q 'exits 0 whether or not it succeeded' "$PF_LIB/convert.sh" \
    && ok_ "the exit-code trap is documented in the module" \
    || bad_ "the exit-code trap is not documented"
grep -q 'UPF2' "$PF_LIB/convert.sh" \
    && ok_ "the .UPF2 naming quirk is handled" \
    || bad_ "output detection does not allow for .UPF2"

printf '\n%s== every declared path, against a real file%s\n' "$DIM" "$RESET"
#
# One file per path, written by the engine that writes that format -- not
# hand-made. tests/fixtures/SOURCE.txt records where each came from. A
# validator written against an imagined layout has twice rejected valid files
# in this tree; the same applies to a conversion said to work.
#
# A path that cannot be exercised says so and is counted as a skip. It is not
# counted as a pass, and it does not quietly vanish from the list.
CVTDIR=$TMP/paths; mkdir -p "$CVTDIR"

cvt_try() {              # cvt_try <fixture> <as-name> <to> <expect: ok|fail>
    local fix=$1 as=$2 to=$3 expect=$4 got out
    if [ ! -f "$fix" ]; then
        skip_ "${as##*.} -> $to: no fixture ($(basename "$fix"))"
        return
    fi
    cp -f "$fix" "$CVTDIR/$as"
    if out=$("$PSM" convert "$CVTDIR/$as" --to "$to" 2>&1); then got=ok; else got=fail; fi
    if [ "$got" = "$expect" ]; then
        case $got in
            ok)   ok_ "${as##*.} -> $to converted $(basename "$as")" ;;
            fail) ok_ "${as##*.} -> $to fails here, as recorded" ;;
        esac
    else
        bad_ "${as##*.} -> $to: expected $expect, got $got" \
             "$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
    fi
    printf '%s' "$out" > "$CVTDIR/${as}.out"
}

cvt_try "$FIX/van/Si.van"                  SiV.van   upf ok
cvt_try "$FIX/van/Si.van"                  SiB.vdb   upf ok
cvt_try "$FIX/upf/Si.pbe-oncv.UPF"         SiX.UPF   xml ok
# ld1.x's own RRKJ3, lowercase as ld1 writes it. upfconv matches only
# '.RRKJ3'; the converter stages the file under that name. This failed until
# it did.
cvt_try "$FIX/rrkj3/Si.pbe-rrkjus-ld1.rrkj3" SiR.rrkj3 upf ok
# No reader for these in QE 7.x -- refused, and refused at runtime too.
cvt_try "$FIX/cpi/Si.pz-fhi98pp.cpi"       SiC.cpi   upf fail
cvt_try "$FIX/cpi/Si.pz-fhi98pp.cpi"       SiF.fhi   upf fail
cvt_try "$FIX/cpmd/Si.pbe-opium.cpmd"      SiM.cpmd  upf fail

# Every converted UPF must pass validation -- which now includes QE's 1024-
# character line limit, the rule a converted .van used to break unnoticed.
for f in SiV SiB SiR; do
    if [ -s "$CVTDIR/$f.UPF" ]; then
        if upf_validate "$CVTDIR/$f.UPF" >/dev/null 2>&1; then
            ok_ "  $f.UPF passes UPF validation"
        else
            bad_ "  $f.UPF does not validate" "$(upf_validate "$CVTDIR/$f.UPF" | head -1)"
        fi
    fi
done

# The refusals, with the reason taken from QE's own source.
for k in cpi:upf fhi:upf cpmd:upf; do
    if [ "${CVT_KIND[$k]}" = refused ] && [ "${CVT_REFUSAL[$k]:-}" = no-tool ]; then
        ok_ "${k%%:*} -> upf is refused as no-tool"
    else
        bad_ "${k%%:*} -> upf is ${CVT_KIND[$k]:-unset}/${CVT_REFUSAL[$k]:-unset}" \
             "upfconv.x in QE 7.x has no reader for it (upflib/read_ps.f90)"
    fi
    case ${CVT_NOTE[$k]} in
        *read_ps*) ok_ "  and the reason names QE's dispatch" ;;
        *)         bad_ "  the refusal does not say where the reader is missing" ;;
    esac
done

# No exact path is left undemonstrated.
left=""
for k in "${CVT_ORDER[@]}"; do [ -n "${CVT_CAVEAT[$k]:-}" ] && left="$left $k"; done
if [ -z "$left" ]; then
    ok_ "no registered path carries an undemonstrated caveat"
else
    bad_ "still undemonstrated:$left"
fi

# The validator, against upfconv's real output -- not a hand-made long line.
UPFCONV=$(cvt_upfconv_bin 2>/dev/null)
if [ -n "$UPFCONV" ]; then
    rw=$TMP/raw; mkdir -p "$rw"; cp "$FIX/van/Si.van" "$rw/"
    ( cd "$rw" && OMP_NUM_THREADS=1 "$UPFCONV" -u Si.van >/dev/null 2>&1 )
    raw=$(ls "$rw"/*.UPF2 2>/dev/null | head -1)
    if [ -n "$raw" ]; then
        if upf_validate "$raw" >/dev/null 2>&1; then
            bad_ "raw upfconv output passes validation" \
                 "it has a row longer than QE's 1024-character reader limit"
        else
            ok_ "raw upfconv output is rejected (line longer than QE reads)"
        fi
        cp "$raw" "$rw/norm.UPF"; upf_normalise "$rw/norm.UPF"
        if upf_validate "$rw/norm.UPF" >/dev/null 2>&1; then
            ok_ "  and upf_normalise makes it valid"
        else
            bad_ "  upf_normalise did not repair it"
        fi
    fi
else
    skip_ "upfconv.x not found -- validator regression not run"
fi

# Exact is a claim about physics, so it is checked with physics: pw.x reads
# .van, .RRKJ3 and QE-XML itself, so each source read natively must give the
# same energy as its conversion. Earlier the only check was validation, and a
# converted .van passed that while being unreadable.
PWX=$(command -v pw.x 2>/dev/null || true)
[ -n "$PWX" ] || PWX=${QE_ROOT_DIR:-/opt/espresso}/pw.x
[ -x "$PWX" ] || PWX=$(ls "${QE_ROOT_DIR:-/opt/espresso}"/*/pw.x 2>/dev/null | head -1)
if [ "${PF_SLOW_TESTS:-0}" = 1 ] && [ -x "${PWX:-}" ]; then
    pwe() {   # pwe <dir> <pp> [ecutrho] -> total energy
        local d=$1 pp=$2 rho=${3:-} tag
        tag=$(printf '%s' "$pp" | tr '.' '_')
        cat > "$d/$tag.in" <<EOF
&control
  calculation='scf', prefix='$tag', outdir='./t_$tag', pseudo_dir='$d'
/
&system
  ibrav=2, celldm(1)=10.26, nat=2, ntyp=1, ecutwfc=30.0 ${rho:+, ecutrho=$rho}
/
&electrons
  conv_thr=1.0d-10
/
ATOMIC_SPECIES
Si 28.086 $pp
ATOMIC_POSITIONS crystal
Si 0.00 0.00 0.00
Si 0.25 0.25 0.25
K_POINTS automatic
4 4 4 1 1 1
EOF
        ( cd "$d" && OMP_NUM_THREADS=1 timeout 900 "$PWX" -in "$tag.in" > "$tag.out" 2>&1 )
        grep '^!' "$d/$tag.out" | awk '{print $5}'
    }
    pw=$TMP/pw; mkdir -p "$pw"
    cp "$FIX/van/Si.van" "$pw/SiV.van"
    cp "$FIX/rrkj3/Si.pbe-rrkjus-ld1.rrkj3" "$pw/SiR.RRKJ3"
    cp "$FIX/upf/Si.pbe-oncv.UPF" "$pw/SiX.UPF"
    cp "$CVTDIR/SiV.UPF" "$pw/SiV-conv.UPF" 2>/dev/null
    cp "$CVTDIR/SiR.UPF" "$pw/SiR-conv.UPF" 2>/dev/null
    cp "$CVTDIR/SiX.xml" "$pw/SiX-conv.xml" 2>/dev/null
    for pair in "SiV.van SiV-conv.UPF 240" "SiR.RRKJ3 SiR-conv.UPF 240" "SiX.UPF SiX-conv.xml"; do
        set -- $pair
        a=$(pwe "$pw" "$1" "${3:-}"); b=$(pwe "$pw" "$2" "${3:-}")
        if [ -n "$a" ] && [ "$a" = "$b" ]; then
            ok_ "pw.x: $1 native and $2 give the same energy ($a Ry)"
        else
            bad_ "pw.x: $1 native = ${a:-none}, $2 = ${b:-none}" \
                 "a path registered exact must reproduce the source's physics"
        fi
    done
else
    skip_ "pw.x equivalence of every exact path (needs pw.x and PF_SLOW_TESTS=1)"
fi

# psp8: not converted to, generated. The registry refuses the conversion, so
# this is the path that has to work instead.
if "$PSM" engines path oncvpsp >/dev/null 2>&1 && [ "${PF_SLOW_TESTS:-0}" = 1 ]; then
    p8=$TMP/psp8
    ( cd "$ROOT" && OMP_NUM_THREADS=1 ./pseudoforge generate -e Si -t nc \
          -p pseudoforge-auto -x pbe --engine oncvpsp --format psp8 -o "$p8" ) >/dev/null 2>&1
    f=$(ls "$p8"/pseudos/*.psp8 2>/dev/null | head -1)
    if [ -n "$f" ] && [ -s "$f" ]; then
        ok_ "ONCVPSP wrote psp8 natively ($(basename "$f"))"
        if psp8_validate "$f" >/dev/null 2>&1; then
            ok_ "  and it passes the psp8 header check"
        else
            bad_ "  but it does not pass psp8_validate" "$(psp8_validate "$f" | head -1)"
        fi
    else
        bad_ "--format psp8 produced no psp8 file" "this is the only route to psp8 now"
    fi
    # --format upf,psp8 has to give both files. ONCVPSP writes one format per
    # run unless psfile is `both` -- its own validator says "psfile must ==
    # psp8 or upf or both" -- and the deck was hardcoded to upf, so this
    # combination silently produced one file while the reference page for the
    # engine documented two.
    bo=$TMP/both
    ( cd "$ROOT" && OMP_NUM_THREADS=1 ./pseudoforge generate -e Si -t nc \
          -p pseudoforge-auto -x pbe --engine oncvpsp --format upf,psp8 -o "$bo" ) >/dev/null 2>&1
    nu=$(ls "$bo"/pseudos/*.UPF 2>/dev/null | wc -l)
    n8=$(ls "$bo"/pseudos/*.psp8 2>/dev/null | wc -l)
    if [ "$nu" -ge 1 ] && [ "$n8" -ge 1 ]; then
        ok_ "--format upf,psp8 writes both"
    else
        bad_ "--format upf,psp8 wrote $nu UPF and $n8 psp8" \
             "psfile must be 'both' for ONCVPSP to emit two formats from one run"
    fi
else
    skip_ "native psp8 generation (needs ONCVPSP and PF_SLOW_TESTS=1)"
fi

# The deck is where this was wrong, so the deck is what is checked.
if grep -q "printf 'both" "$PF_LIB/input_builder.sh"; then
    ok_ "the builder knows psfile=both, not only upf and psp8"
else
    bad_ "psfile has no 'both' case" \
         "--format upf,psp8 can then only produce one of the two"
fi

printf '\n%s== round trip%s\n' "$DIM" "$RESET"
# psp8, and the tool that never existed.
#
# These three paths were registered as `exact`, performed by ABINIT's
# `pspconvert`. There is no such program: it is absent from the ABINIT 8.10.3
# and 9.10.3 source trees and from the conda-forge binaries of 8.10.2 and
# 10.0.3, `abitk` has no pseudopotential subcommand, and QE's upfconv.x does
# not list psp8 among the formats it reads. The registry promised a conversion
# that could never run, and the report's "AVAILABLE: no" column read as an
# install away.
#
# They are refusals now, of kind `no-tool` -- distinct from the physics
# refusals, because "nobody wrote it" and "the numbers are not there" are
# different answers. This block is the regression: if `pspconvert` comes back,
# it fails.
for k in psp8:upf upf:psp8 fhi:psp8; do
    if [ "${CVT_KIND[$k]}" = refused ]; then
        ok_ "${k%%:*} -> ${k##*:} is refused"
    else
        bad_ "${k%%:*} -> ${k##*:} is registered as ${CVT_KIND[$k]}" \
             "no tool performs it; a path nobody can run must not be listed as available"
    fi
    if [ "${CVT_REFUSAL[$k]:-}" = no-tool ]; then
        ok_ "  and refused as no-tool, not as physics"
    else
        bad_ "  the refusal kind is '${CVT_REFUSAL[$k]:-unset}'" \
             "this conversion is possible in principle; only the tool is missing"
    fi
done

# Comments may name it -- that is the record of why it is gone. Code may not.
if grep -rn 'pspconvert' "$PF_LIB"/*.sh | grep -qvE ':[[:space:]]*#'; then
    bad_ "pspconvert is referenced as live code again" \
         "it is not a program that exists -- see the note in convert.sh"
else
    ok_ "pspconvert survives only in the comment recording why it is gone"
fi

if grep -q 'no psp8 converter' "$PF_LIB/convert.sh"; then
    ok_ "and the registry records what was checked"
else
    bad_ "the finding is not written down where the next reader will look"
fi

# The route that does work: ONCVPSP writes psp8 itself.
if grep -q 'ib_oncv_psfile' "$PF_LIB/input_builder.sh"; then
    ok_ "the deck builder honours a psp8 request"
else
    bad_ "psfile is forced to upf, so --format psp8 cannot work"
fi
if grep -q 'psp8_validate' "$PF_LIB/upf.sh"; then
    ok_ "psp8 output has its own validator, not the generic byte check"
else
    bad_ "psp8 files fall through to the size-and-NaN check only"
fi

printf '\n%s== refusals are reasoned, not missing features%s\n' "$DIM" "$RESET"
for k in pawxml:upf vps:upf gth:upf; do
    if [ "${CVT_KIND[$k]}" = refused ]; then
        ok_ "${k%%:*} -> ${k##*:} is refused"
    else
        bad_ "${k%%:*} -> ${k##*:} is not marked refused"
    fi
    n=$(printf '%s' "${CVT_NOTE[$k]}" | wc -c)
    if [ "$n" -gt 80 ]; then
        ok_ "  and the reason is spelled out ($n chars)"
    else
        bad_ "  the reason is too thin to be useful"
    fi
done


# The specific reasons matter -- these are the findings, not boilerplate.
case ${CVT_NOTE[pawxml:upf]} in
    *"kinetic-energy density"*) ok_ "PAW-XML refusal names the lost term" ;;
    *) bad_ "PAW-XML refusal does not say what is lost" ;;
esac
case ${CVT_NOTE[pawxml:upf]} in
    *"AtomPAW writes UPF itself"*) ok_ "and points at the real answer for LDA/GGA" ;;
    *) bad_ "PAW-XML refusal does not mention PWSCFOUT" ;;
esac
case ${CVT_NOTE[vps:upf]} in
    *semilocal*|*Semilocal*) ok_ ".vps refusal names the semilocal/separable gap" ;;
    *) bad_ ".vps refusal does not explain the form mismatch" ;;
esac

# A conversion that would change the physical object must not be registered
# at all, in either direction.
for k in nc:us us:paw upf:uspp; do
    [ -z "${CVT_KIND[$k]:-}" ] \
        && ok_ "no cross-family path $k is registered" \
        || bad_ "$k is registered" "that is a different physical object, not a file format"
done

printf '\n%s== the refused paths really are refused at runtime%s\n' "$DIM" "$RESET"
if [ -n "$x" ]; then
    if cvt_convert "$x" upf "$TMP" >/dev/null 2>&1; then
        bad_ "PAW-XML was converted to UPF" "for meta-GGA that silently drops the defining term"
    else
        ok_ "converting the r2SCAN PAW-XML to UPF is refused"
    fi
fi
v=$(ls "$FIX"/vps/*.vps 2>/dev/null | head -1)
if [ -n "$v" ]; then
    cvt_convert "$v" upf "$TMP" >/dev/null 2>&1 \
        && bad_ "an OpenMX .vps was converted to UPF" \
        || ok_ "converting an OpenMX .vps to UPF is refused"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
