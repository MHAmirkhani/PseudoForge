#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Validators, checked against real engine output.
#
# Every validator here is run against a file an engine actually wrote before it
# is trusted on anything new.  That rule exists because it has been broken
# three times, always the same way: a check that looks reasonable, was written
# against an imagined format, and rejects good data.
#
#   pslp     searching for the word "ghost" matched the tool's own explanatory
#            prose -- "the ghost state analysis will assume a zero reference
#            energy" -- and reported a ghost in a clean pseudopotential.
#   .vps     looked for a "Vps.public" keyword that does not exist in the
#            OpenMX format; rejected every file ADPACK produces.
#   .vps     flagged the banner of asterisks the format opens with as a
#            Fortran overflow marker.
#
# A validator that rejects valid output is worse than none: it turns a working
# engine into a mysterious failure. So the fixtures come first, and the rule is
# written down in docs/ENGINES.md.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines upf; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load 2>/dev/null

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

FIX=$HERE/fixtures

printf '\n%s== every fixture is accepted%s\n' "$DIM" "$RESET"
# The direction that matters.  If a validator rejects one of these, the
# validator is wrong and the fixture is right -- these are real engine output.
n=0
for f in "$FIX"/vps/*.vps "$FIX"/upf/*.UPF "$FIX"/pawxml/*.xml "$FIX"/gth/*.gth; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    if out=$(upf_validate_any "$f" 2>&1); then
        ok_ "$(basename "$f") accepted"
    else
        bad_ "$(basename "$f") REJECTED" "$(printf '%s' "$out" | head -1)"
    fi
done
[ "$n" -gt 0 ] && ok_ "$n fixture(s) checked" || skip_ "no fixtures present"

printf '\n%s== the specific traps, pinned%s\n' "$DIM" "$RESET"
v=$(ls "$FIX"/vps/*.vps 2>/dev/null | head -1)
if [ -n "$v" ]; then
    # trap 1: the banner of asterisks is decoration, not an overflow
    head -3 "$v" | grep -q '\*\*\*\*' \
        && ok_ "the .vps fixture really does open with an asterisk banner" \
        || skip_ "this .vps has no banner to guard against"
    vps_validate "$v" >/dev/null 2>&1 \
        && ok_ "the banner is not read as a Fortran overflow" \
        || bad_ "a real .vps was rejected" "the overflow check must require digits on the line"

    # trap 2: the keywords must be ones the format actually uses
    for k in valence.electron grid.num Pseudo.Potentials; do
        grep -qi "$k" "$v" \
            && ok_ "'$k' is a real keyword in this format" \
            || bad_ "'$k' does not appear in real output" "the validator is checking an invented keyword"
    done
    grep -qi 'Vps.public' "$v" \
        && bad_ "'Vps.public' exists after all -- revisit the note in vps_validate" \
        || ok_ "'Vps.public' is confirmed absent (it was invented)"
else
    skip_ ".vps fixture not present"
fi

x=$(ls "$FIX"/pawxml/*.xml 2>/dev/null | head -1)
if [ -n "$x" ]; then
    # trap 3: AtomPAW mislabels meta-GGA as type="LDA"
    out=$(pawxml_validate "$x" 2>&1)
    if grep -qi 'MGGA\|R2SCAN' "$x"; then
        printf '%s' "$out" | grep -q 'WARNING' \
            && ok_ "the meta-GGA type/name mismatch is reported" \
            || bad_ "AtomPAW's type=\"LDA\" on a meta-GGA set was not flagged"
    fi
    printf '%s' "$out" | grep -qi 'not readable by Quantum ESPRESSO' \
        && ok_ "PAW-XML says plainly that QE cannot read it" \
        || bad_ "no note that PAW-XML is not UPF"
else
    skip_ "PAW-XML fixture not present"
fi

printf '\n%s== corruption is still caught%s\n' "$DIM" "$RESET"
# Accepting real files is only half of it; the checks must still bite.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if [ -n "$v" ]; then
    sed 's/\([0-9]\)\.\([0-9][0-9]\)/******/' "$v" | head -60 > "$TMP/of.vps"
    printf 'valence.electron 6.0\ngrid.num 1000\nPseudo.Potentials\n  1.0 ****** 2.0\n' > "$TMP/of.vps"
    vps_validate "$TMP/of.vps" >/dev/null 2>&1 \
        && bad_ "an overflow inside numeric data was not caught" \
        || ok_ "an overflow inside numeric data is caught"

    grep -v 'Pseudo.Potentials' "$v" > "$TMP/trunc.vps"
    vps_validate "$TMP/trunc.vps" >/dev/null 2>&1 \
        && bad_ "a .vps missing its potential table passed" \
        || ok_ "a missing Pseudo.Potentials block is caught"
fi

printf 'nonsense\n' > "$TMP/bad.xml"
pawxml_validate "$TMP/bad.xml" >/dev/null 2>&1 \
    && bad_ "a non-PAW-XML file passed pawxml_validate" \
    || ok_ "a file that is not PAW-XML is rejected"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
