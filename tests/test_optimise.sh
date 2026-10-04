#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The rc optimiser: its rule, its refusals, and one real sweep.
#
# The rule is tested on its own (opt_choose) against tables whose right answer
# can be read off by hand; the command is tested for what it refuses; and,
# gated behind PF_SLOW_TESTS=1, a real ONCVPSP sweep checks that the choice is
# reproducible from the recipe it saves.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
PSM=$ROOT/pseudoforge
for m in core sink config elements optimise; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
T=$'\t'

row() { printf '%s\n' "$*" | tr '|' '\t'; }

want() {   # want <label> <expected scale|none> <min-rank> <rows...>
    local label=$1 exp=$2 min=$3; shift 3
    { printf '#scale\tstatus\tverdict\tmax_dE_Ry\tecutwfc\tfile\tproject\n'; for r in "$@"; do row "$r"; done; } > "$TMP/t.tsv"
    local got; got=$(opt_choose "$TMP/t.tsv" "$min") || got=none
    got=${got%%$T*}
    [ "$got" = "$exp" ] && ok_ "$label -> $exp" || bad_ "$label: chose $got, expected $exp"
}

printf '\n%s== the rule%s\n' "$DIM" "$RESET"
# The measured Si/ONCVPSP sweep: 1.1 and 1.2 tie at 15 Ry; 1.1 has the smaller error.
want "measured Si sweep, cutoff tie broken by the error" 1.1 3 \
    "0.9|ok|good|0.002340|21|a|p" "1.0|ok|good|0.001726|18|a|p" \
    "1.1|ok|good|0.001190|15|a|p" "1.2|ok|good|0.003140|15|a|p" \
    "1.3|ok|marginal|0.005240|12|a|p"
want "the softest candidate is not taken if it falls below the grade" 1.2 3 \
    "1.2|ok|good|0.003|15|a|p" "1.3|ok|marginal|0.005|12|a|p"
want "lowering the grade admits it" 1.3 2 \
    "1.2|ok|good|0.003|15|a|p" "1.3|ok|marginal|0.005|12|a|p"
want "no cutoff scan: the largest scale that passes" 1.2 3 \
    "1.0|ok|good|0.0017|-|a|p" "1.2|ok|good|0.0031|-|a|p" "1.4|ok|marginal|0.0084|-|a|p"
want "a failed generation is never chosen" 1.0 3 \
    "1.0|ok|good|0.0017|18|a|p" "1.3|fail|excellent|0.0001|10|a|p"
want "no-data is never eligible" none 1 \
    "1.0|ok|no-data|-|18|a|p" "1.2|ok|no-data|-|15|a|p"
want "a partly measured ladder is not compared by cutoff" 1.2 3 \
    "1.0|ok|good|0.001|12|a|p" "1.2|ok|good|0.002|-|a|p"
want "ok-warn counts as generated" 1.1 3 \
    "1.1|ok-warn|excellent|0.0008|20|a|p"

printf '\n%s== what the command refuses%s\n' "$DIM" "$RESET"
refused() {   # refused <label> <pattern> <args...>
    local label=$1 pat=$2; shift 2
    local out; out=$("$PSM" optimise "$@" -o "$TMP/r" 2>&1); local rc=$?
    if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q "$pat"; then ok_ "$label"
    else bad_ "$label (exit $rc)" "$(printf '%s' "$out" | tail -1)"; fi
}
refused "more than one element"          "one element at a time" -e Si,Ge -t nc
refused "an element range"               "one element at a time" -e 1-36 -t nc
refused "--rcut-scale given by hand"     "sets --rcut-scale itself" -e Si --rcut-scale 1.2
refused "an unknown grade"               "min-grade must be"     -e Si --min-grade great
refused "a non-numeric scale"            "not a positive number" -e Si --scales 1.0,x
refused "an engine without --rcut-scale" "honours --rcut-scale"  -e Si -t us -p pseudoforge-auto -x pbe --engine uspp --scales 1.0
"$PSM" optimise --help >/dev/null 2>&1 && ok_ "--help exits 0" || bad_ "--help fails"

printf '\n%s== a real sweep%s\n' "$DIM" "$RESET"
if [ "${PF_SLOW_TESTS:-0}" = 1 ] && "$PSM" engines path oncvpsp >/dev/null 2>&1; then
    export OMP_NUM_THREADS=1
    name=pf-test-opt-$$
    "$PSM" optimise -e Si -t nc -p pseudoforge-auto -x pbe --engine oncvpsp \
        --scales 1.0,1.2,1.4 -o "$TMP/o" --save-recipe "$name" >/dev/null 2>&1
    c=$(cat "$TMP/o/choice" 2>/dev/null)
    case $c in 1.0|1.2|1.4) ok_ "a scale from the ladder was chosen ($c)" ;; *) bad_ "no choice recorded" ;; esac
    rows=$(grep -vc '^#' "$TMP/o/optimise.tsv" 2>/dev/null)
    [ "$rows" = 3 ] && ok_ "every rung is recorded in optimise.tsv" || bad_ "optimise.tsv has $rows rows, not 3"
    "$PSM" generate --recipe "$name" -o "$TMP/re" >/dev/null 2>&1
    a=$(ls "$TMP"/o/rc-"$c"/pseudos/*.UPF 2>/dev/null | head -1)
    b=$(ls "$TMP"/re/pseudos/*.UPF 2>/dev/null | head -1)
    if [ -n "$a" ] && [ -n "$b" ] && diff <(grep -v -iE 'date|generated|author|<PP_INFO|input' "$a") \
                                          <(grep -v -iE 'date|generated|author|<PP_INFO|input' "$b") >/dev/null; then
        ok_ "the saved recipe reproduces the chosen pseudopotential"
    else
        bad_ "the saved recipe does not reproduce the chosen file" "$a vs $b"
    fi
    "$PSM" recipe delete "$name" >/dev/null 2>&1
else
    skip_ "a real ONCVPSP sweep (needs ONCVPSP and PF_SLOW_TESTS=1)"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
