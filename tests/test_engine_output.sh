#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# What engines hand back, checked as something a DFT code will read.
#
# Every item below shipped as "ok" before it was caught:
#
#   * --rcut-scale was applied by ld1 alone; six engines ignored it and still
#     named their output "-rc1p2", a file labelled scaled that was not;
#   * APE writes UPF v1 with the functional field blank -- pw.x stops with
#     "unrecognized dft" -- and QE 7.6 misreads APE's v1 layout even when it
#     is filled in: bulk Si 645 kbar, against 46 once rewritten as v2;
#   * APE reports ghost states in its own log, and nothing read the line:
#     bulk Si -59.73 Ry where ONCVPSP gives -15.76;
#   * exec_upfconv looked for "<input>.UPF2", which is not the name upfconv
#     gives a .UPF input, so APE's rewrite always "failed";
#   * `validate` ran the UPF checker on every format and treated --help as a
#     file name.
#
# Fast checks run everywhere. Engine runs are skipped when the engine is not
# built; pw.x physics is gated behind PF_SLOW_TESTS=1.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
PSM=$ROOT/pseudoforge
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert params engines upf input_builder; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load 2>/dev/null

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export OMP_NUM_THREADS=1
have_engine() { "$PSM" engines path "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
printf '\n%s== --rcut-scale: applied where implemented, refused where not%s\n' "$DIM" "$RESET"

for e in ld1 oncvpsp opium ape; do
    ib_rc_scalable "$e" && ok_ "$e is declared scalable" || bad_ "$e is not declared scalable"
done
for e in uspp atompaw fhi98pp gth adpack; do
    if ib_rc_scalable "$e"; then
        bad_ "$e claims --rcut-scale support" "it has no implementation"
    else
        r=$(ib_rc_refusal "$e")
        [ -n "$r" ] && ok_ "$e is refused, with a reason" || bad_ "$e is refused with no reason"
    fi
done

# The scaling itself, on the real deck shapes, without running an engine.
cat > "$TMP/oncv.dat" <<'EOF'
# l, rc, ep, ncon, nbas, qcut  (lmax+1 lines, l's must be in order)
    0    2.70    0.00    5    8    5.00
    1    2.70    0.00    5    8    5.00
#
# LOCAL POTENTIAL
# lloc, lpopt, rc(5), dvloc0
    4    5    2.7  0.0
#
# OUTPUT GRID
# rlmax, drl
    5.0  0.01
EOF
cp "$TMP/oncv.dat" "$TMP/oncv2.dat"
if ib_scale_rc oncvpsp "$TMP/oncv.dat" 1.2 2>/dev/null; then
    got=$(awk '/^# *l, *rc/ { g = 1; next } g && NF >= 6 { print $2; exit }' "$TMP/oncv.dat")
    [ "$got" = 3.2400 ] && ok_ "oncvpsp: rc 2.70 x 1.2 = $got" || bad_ "oncvpsp: rc scaled to '$got', not 3.2400"
    got=$(awk '/rc\(5\)/ { g = 1; next } g && NF >= 4 { print $3; exit }' "$TMP/oncv.dat")
    [ "$got" = 3.2400 ] && ok_ "oncvpsp: rc(5) of the local potential scaled too" || bad_ "oncvpsp: rc(5) is '$got'"
else
    bad_ "oncvpsp deck could not be scaled"
fi
# Past ONCVPSP's output grid is a broken construction, not a softer one.
if ib_scale_rc oncvpsp "$TMP/oncv2.dat" 2.0 2>/dev/null; then
    bad_ "oncvpsp: a radius beyond rlmax was accepted"
else
    ok_ "oncvpsp: a radius beyond rlmax is refused"
fi

printf '[Pseudo]\n2 1.89 1.89\nopt\n' > "$TMP/op.param"
ib_scale_rc opium "$TMP/op.param" 1.2 2>/dev/null
[ "$(sed -n '2p' "$TMP/op.param")" = "2 2.2680 2.2680" ] \
    && ok_ "opium: the channel count is kept and both radii are scaled" \
    || bad_ "opium: [Pseudo] line is '$(sed -n '2p' "$TMP/op.param")'"

printf '%%PPComponents\n  3  |  0  |  2.38 | tm\n  3  |  1  |  3.56 | tm\n%%\n' > "$TMP/inp.ape"
ib_scale_rc ape "$TMP/inp.ape" 1.2 2>/dev/null
got=$(awk -F'|' '/tm/ { gsub(/ /, "", $3); printf "%s ", $3 }' "$TMP/inp.ape")
[ "$got" = "2.8560 4.2720 " ] && ok_ "ape: both PPComponents radii scaled" || bad_ "ape: radii are '$got'"

printf 'no radius block here\n' > "$TMP/empty.dat"
if ib_scale_rc oncvpsp "$TMP/empty.dat" 1.2 2>/dev/null; then
    bad_ "a deck with no radius block was 'scaled' silently"
else
    ok_ "a deck with no radius block is an error, not a no-op"
fi

# Refused up front, before any engine runs, and nothing named -rc is written.
out=$("$PSM" generate -e Si -t us -p pseudoforge-auto -x pbe --engine uspp \
        --rcut-scale 1.2 -o "$TMP/uspp" 2>&1); rc=$?
if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'not available with'; then
    ok_ "uspp --rcut-scale is refused before running"
else
    bad_ "uspp --rcut-scale was not refused (exit $rc)"
fi
n=$(ls "$TMP"/uspp/pseudos/*rc1p2* 2>/dev/null | wc -l)
[ "$n" = 0 ] && ok_ "  and no file carrying -rc1p2 was written" || bad_ "  $n file(s) named -rc1p2 exist"

# End to end on an engine that has it, when that engine is built.
if have_engine oncvpsp; then
    "$PSM" generate -e Si -t nc -p pseudoforge-auto -x pbe --engine oncvpsp -o "$TMP/o1" >/dev/null 2>&1
    "$PSM" generate -e Si -t nc -p pseudoforge-auto -x pbe --engine oncvpsp --rcut-scale 1.2 -o "$TMP/o2" >/dev/null 2>&1
    if ! cmp -s "$TMP"/o1/inputs/Si.dat "$TMP"/o2/inputs/Si.dat && ls "$TMP"/o2/pseudos/*rc1p2* >/dev/null 2>&1; then
        ok_ "oncvpsp: the -rc1p2 file comes from a scaled deck"
    else
        bad_ "oncvpsp: scaled run's deck is identical, or no -rc1p2 file"
    fi
else
    skip_ "oncvpsp end-to-end scaling (engine not built)"
fi

# ---------------------------------------------------------------------------
printf '\n%s== upfconv output naming%s\n' "$DIM" "$RESET"
grep -q 'produced=${in%.*}.UPF2' "$PF_LIB/executor.sh" \
    && ok_ "exec_upfconv also finds <prefix>.UPF2, the name a .UPF input gets" \
    || bad_ "exec_upfconv only looks for <input>.UPF2"

# ---------------------------------------------------------------------------
printf '\n%s== the validator: can a DFT code actually use this file?%s\n' "$DIM" "$RESET"

f=$TMP/blank.UPF
sed 's/functional="[^"]*"/functional=""/' "$HERE/fixtures/upf/Si.pbe-oncv.UPF" > "$f"
if upf_validate "$f" >/dev/null 2>&1; then
    bad_ "a v2 file naming no functional passes" "pw.x stops on it: unrecognized dft"
else
    ok_ "a v2 file naming no functional is rejected"
fi
upf_validate "$HERE/fixtures/upf/Si.pbe-oncv.UPF" >/dev/null 2>&1 \
    && ok_ "the ONCVPSP fixture still passes" || bad_ "the ONCVPSP fixture no longer passes"

# The line limit applies to v2 (QE's XML reader), not to v1.
printf '<UPF version="2.0.1">\n<PP_HEADER functional="PBE" element="Si" pseudo_type="NC" z_valence="4"/>\n%s\n</UPF>\n' \
    "$(printf '1.0 %.0s' $(seq 1 300))" > "$TMP/long.UPF"
# Captured first: upf_validate exits 1 here, which is correct, and under
# pipefail piping it into grep would fail the check whatever grep found.
msg=$(upf_validate "$TMP/long.UPF" 2>/dev/null)
case $msg in
    *"stops at 1024"*) ok_ "a v2 line over 1024 characters is named as QE's reader limit" ;;
    *)                 bad_ "the 1024-character rule did not fire on a v2 file" ;;
esac

# A NaN in a header attribute is not a diverged solve.
# This fixture writes <PP_MESH> with no attributes; match either spelling.
sed -E 's/<PP_MESH( |>)/<PP_MESH xmin="-Infinity"\1/' "$HERE/fixtures/upf/Si.pbe-oncv.UPF" > "$TMP/inf.UPF"
msg=$(upf_validate "$TMP/inf.UPF" 2>/dev/null)
case $msg in
    *"not a number"*"converter"*) ok_ "Infinity in an attribute is reported as a header value" ;;
    *"did not converge"*)         bad_ "Infinity in an attribute is blamed on the atomic solve" ;;
    *)                            bad_ "Infinity in an attribute was not reported" "$msg" ;;
esac

# ---------------------------------------------------------------------------
printf '\n%s== every file must say it is what it is labelled%s\n' "$DIM" "$RESET"
# The first native store put 1,493 files under labels they did not carry, and
# every VWN file had no exchange. label_mismatch reads the file's own header.
. "$PF_LIB/validate.sh"
ONCV=$HERE/fixtures/upf/Si.pbe-oncv.UPF
lm() {   # lm <expect catch|pass> <label> <file> <xc> <rel>
    local why; why=$(label_mismatch "$3" "$4" "$5")
    if { [ "$1" = catch ] && [ -n "$why" ]; } || { [ "$1" = pass ] && [ -z "$why" ]; }; then
        ok_ "$2${why:+ ($why)}"
    else
        bad_ "$2: expected $1" "${why:-no disagreement reported}"
    fi
}
lm pass  "a PBE scalar file labelled pbe/scalar passes"    "$ONCV" pbe scalar
lm catch "the same file labelled pz is caught"             "$ONCV" pz  scalar
lm catch "the same file labelled pbesol is caught"         "$ONCV" pbesol scalar
lm catch "the same file labelled full-relativistic is caught" "$ONCV" pbe full
sed -E 's/functional="[^"]*"/functional=" NOX  VWN  NOGX NOGC"/' "$ONCV" > "$TMP/nox.UPF"
lm catch "a header with no exchange is caught whatever was asked" "$TMP/nox.UPF" vwn scalar
vps=$HERE/fixtures/vps/F.pz-adpack.vps
vx=$(awk '$1=="xc.type"{print $2; exit}' "$vps"); ve=$(awk '$1=="eq.type"{print $2; exit}' "$vps")
case $ve in sch) vr=nonrel ;; sdirac) vr=scalar ;; dirac) vr=full ;; *) vr=scalar ;; esac
case $(printf '%s' "$vx" | tr a-z A-Z) in GGA) vxc=pbe ;; *) vxc=pz ;; esac
lm pass  "an ADPACK .vps labelled as its own xc.type/eq.type passes ($vxc/$vr)" "$vps" "$vxc" "$vr"
other=$([ "$vr" = full ] && echo scalar || echo full)
lm catch "the same .vps labelled $other is caught" "$vps" "$vxc" "$other"

# The corrected VWN mapping, and the refusals that keep libraries honest.
grep -qE $'^vwn\tvwn\tSLA VWN\t' "$PF_DATA/xc.tsv" \
    && ok_ "vwn maps to 'SLA VWN' -- exchange included" \
    || bad_ "vwn does not map to 'SLA VWN'" "QE has no short name VWN; alone it means correlation only"
for args in "-p gbrv -t us -x pz" "-p fhi -t nc -x pbe" "-p vanderbilt -t us -x pbe" \
            "-p adpack -t nc -x pbe -r scalar" "-p cp2k-gth -t nc -x pbe -r full"; do
    out=$("$PSM" generate -e Si $args -o "$TMP/refuse" 2>&1)
    if printf '%s' "$out" | grep -qE "has no .*(it publishes|it has)"; then
        ok_ "refused: $args"
    else
        bad_ "not refused: $args" "$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -m1 -E 'ERROR|ok|fail')"
    fi
done

# ---------------------------------------------------------------------------
printf '\n%s== the validate command%s\n' "$DIM" "$RESET"
"$PSM" validate --help >/dev/null 2>&1 && ok_ "validate --help exits 0" || bad_ "validate --help fails"
"$PSM" validate --help 2>&1 | grep -q 'basename' \
    && bad_ "validate --help still prints basename's help" \
    || ok_ "validate --help does not pass the flag to basename"
out=$("$PSM" validate "$HERE/fixtures/vps/F.pz-adpack.vps" 2>&1)
case $out in
    *"not a UPF"*) bad_ "a .vps is checked as if it were a UPF" ;;
    *OK*)          ok_ "a .vps is checked by its own validator" ;;
    *)             bad_ "validate on a .vps: $(printf '%s' "$out" | tail -1)" ;;
esac

# ---------------------------------------------------------------------------
printf '\n%s== APE output%s\n' "$DIM" "$RESET"
if have_engine ape; then
    "$PSM" generate -e Si -t nc -p pseudoforge-auto -x pbe --engine ape -o "$TMP/ape" >/dev/null 2>&1
    st=$(awk -F'\t' '$1 == "Si" { print $8 }' "$TMP/ape/state.tsv" 2>/dev/null)
    note=$(awk -F'\t' '$1 == "Si" { print $11 }' "$TMP/ape/state.tsv" 2>/dev/null)
    u=$(ls "$TMP"/ape/pseudos/*.UPF 2>/dev/null | head -1)
    case $st in ok|ok-warn) ok_ "Si PBE with APE generates ($st)" ;; *) bad_ "Si PBE with APE: $st" "$note" ;; esac
    if [ -n "$u" ]; then
        [ "$(upf_format "$u")" = v2 ] && ok_ "  written as v2 (QE misreads APE's v1)" || bad_ "  still v1"
        grep -qE 'functional=" *PBE' "$u" && ok_ "  names its functional (PBE)" || bad_ "  functional not named"
    fi
    case $note in
        *ghost*) ok_ "  APE's ghost report was read, and the retry recorded" ;;
        *)       bad_ "  the Si ghost retry is not recorded" "APE reports a ghost with its default local potential" ;;
    esac

    PWX=$(command -v pw.x 2>/dev/null || true)
    [ -n "$PWX" ] || PWX=$(ls "${QE_ROOT_DIR:-/opt/espresso}"/pw.x "${QE_ROOT_DIR:-/opt/espresso}"/*/pw.x 2>/dev/null | head -1)
    if [ "${PF_SLOW_TESTS:-0}" = 1 ] && [ -n "$u" ] && [ -x "${PWX:-}" ]; then
        pwE() {
            local d=$TMP/pw$2; mkdir -p "$d"; cp "$1" "$d/pp.UPF"
            printf "&control\n calculation='scf', prefix='x', outdir='./t', pseudo_dir='%s'\n/\n&system\n ibrav=2, celldm(1)=10.26, nat=2, ntyp=1, ecutwfc=40.0\n/\n&electrons\n conv_thr=1d-9\n/\nATOMIC_SPECIES\nSi 28.086 pp.UPF\nATOMIC_POSITIONS crystal\nSi 0.00 0.00 0.00\nSi 0.25 0.25 0.25\nK_POINTS automatic\n4 4 4 1 1 1\n" "$d" > "$d/pw.in"
            ( cd "$d" && timeout 900 "$PWX" -in pw.in > pw.out 2>&1 )
            grep -m1 '^!' "$d/pw.out" | awk '{ print $5 }'
        }
        ea=$(pwE "$u" a); eo=$(pwE "$HERE/fixtures/upf/Si.pbe-oncv.UPF" o)
        if [ -n "$ea" ] && [ -n "$eo" ] && awk -v a="$ea" -v b="$eo" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d < 0.05) }'; then
            ok_ "  pw.x: bulk Si $ea Ry, against ONCVPSP $eo Ry"
        else
            bad_ "  pw.x: APE Si ${ea:-none} Ry, ONCVPSP ${eo:-none} Ry" "they agreed to 2 mRy when this was fixed"
        fi
    else
        skip_ "  pw.x check of APE's Si (needs pw.x and PF_SLOW_TESTS=1)"
    fi
else
    skip_ "APE output (engine not built)"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
