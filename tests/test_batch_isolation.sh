#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Batch isolation.
#
# When caesium failed the 52-element psl-low/US batch with z_valence = -5.0,
# the first suspect was the batch rather than the recipe: ld1.x writes
# fixed-name scratch files (ld1.wfc, vx.pot, ld1.test) into its working
# directory, so sixteen workers sharing one directory would overwrite each
# other's intermediates and produce results that depend on the race.  That
# turned out not to be the cause -- the recipe really was wrong, see
# tests/test_cs.sh -- but "we looked and it was fine" is not a property, and
# nothing in the suite was checking it.
#
# So this suite pins the property the investigation relied on: **a batch
# result does not depend on how many workers ran it, and one element's failure
# is confined to that element.**  If parallelism ever starts changing answers,
# this is the test that says so, instead of a physicist wondering why a number
# moved.
#
# The equivalence run needs ld1.x and is gated behind PF_SLOW_TESTS=1; the
# structural checks run always.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert doctor params engines build recipe input_builder executor project run; do
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

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

printf '\n%s== every element gets its own working directory%s\n' "$DIM" "$RESET"
# ld1.x writes ld1.wfc, vx.pot and friends by fixed name into its cwd.  Two
# workers in one directory is silent cross-contamination, not an error.
for m in run executor; do
    if grep -qE 'work=\$SCRATCH_DIR/\$\$-\$el' "$PF_LIB/$m.sh"; then
        ok_ "$m.sh gives each element a private scratch directory"
    else
        bad_ "$m.sh does not isolate the working directory" \
             "concurrent workers would share ld1.x's fixed-name scratch files"
    fi
done
# and the name must carry the element, not just the pid: within one run every
# worker is a subshell of the same process, so $$ alone is not unique.
grep -qE '\$\$-\$el' "$PF_LIB/run.sh" \
    && ok_ "the directory name carries the element, not only the pid" \
    || bad_ "workers in one run would collide" \
            "\$\$ is the parent pid in a subshell; every worker sees the same value"

printf '\n%s== state is written per element, not to one shared file%s\n' "$DIM" "$RESET"
grep -q 'state_shard' "$PF_LIB/project.sh" \
    && ok_ "each element appends to its own shard" \
    || bad_ "workers append to a shared state file" "interleaved writes can tear a line"
awk '/^state_record\(\)/,/^}/' "$PF_LIB/project.sh" | grep -q 'state_shard' \
    && ok_ "state_record writes to the shard, not to state.tsv" \
    || bad_ "state_record bypasses the shard"

printf '\n%s== a failure is confined to its own element%s\n' "$DIM" "$RESET"
export PROJECT_DIR=$TMP/proj PROJECT_STATE=$TMP/proj/state.tsv
mkdir -p "$PROJECT_DIR/logs" "$PROJECT_DIR/pseudos"
: > "$PROJECT_STATE"
for el in Si Fe O; do
    printf '%s\tus\tpsl-low\tpbe\tscalar\tstd\t%s.UPF\tok\t1\t2\t\n' "$el" "$el" \
        > "$PROJECT_DIR/logs/.state.$el"
    : > "$PROJECT_DIR/pseudos/$el.UPF"
done
printf 'Cs\tus\tpsl-low\tpbe\tscalar\tspnl.1.0.0\t\tfail\t1\t3\tERROR: implausible z_valence=-5.0\n' \
    > "$PROJECT_DIR/logs/.state.Cs"
state_merge

[ "$(state_status Cs)" = fail ] \
    && ok_ "the failing element is recorded as failed" \
    || bad_ "Cs status is '$(state_status Cs)'"
neighbours_ok=1
for el in Si Fe O; do
    [ "$(state_status "$el")" = ok ] || neighbours_ok=0
done
[ "$neighbours_ok" = 1 ] \
    && ok_ "its neighbours keep their own results" \
    || bad_ "a neighbouring element's status changed"
[ -f "$PROJECT_DIR/pseudos/Si.UPF" ] \
    && ok_ "a neighbour's output file is untouched" \
    || bad_ "a neighbour's output disappeared"
# the reason must survive, or the next person debugs it from scratch
awk -F'\t' '$1 == "Cs" { print $11 }' "$PROJECT_STATE" | grep -q 'z_valence' \
    && ok_ "the failure keeps the reason it failed for" \
    || bad_ "the message was dropped on merge"

printf '\n%s== merging is order-independent%s\n' "$DIM" "$RESET"
# Workers finish in whatever order the scheduler picks; the state file must not.
order_a=$(awk -F'\t' '!/^#/ && NF { print $1 }' "$PROJECT_STATE" | paste -sd,)
: > "$PROJECT_STATE"
for el in Cs O Fe Si; do    # deliberately the reverse finishing order
    st=ok; extra=""
    [ "$el" = Cs ] && { st=fail; extra="ERROR: implausible z_valence=-5.0"; }
    printf '%s\tus\tpsl-low\tpbe\tscalar\tstd\t%s.UPF\t%s\t1\t2\t%s\n' \
        "$el" "$el" "$st" "$extra" > "$PROJECT_DIR/logs/.state.$el"
done
state_merge
order_b=$(awk -F'\t' '!/^#/ && NF { print $1 }' "$PROJECT_STATE" | paste -sd,)
[ "$order_a" = "$order_b" ] \
    && ok_ "the state file reads the same whichever worker finished first ($order_b)" \
    || bad_ "merge order leaked into the state file" "$order_a vs $order_b"

printf '\n%s== the same batch, serial and parallel, gives the same answers%s\n' "$DIM" "$RESET"
if [ "${PF_SLOW_TESTS:-0}" != 1 ]; then
    skip_ "equivalence run gated behind PF_SLOW_TESTS=1"
else
    [ -f "${PF_RC:-$HOME/.pseudoforgerc}" ] && . "${PF_RC:-$HOME/.pseudoforgerc}"
fi
if [ "${PF_SLOW_TESTS:-0}" = 1 ] \
   && [ ! -x "${LD1_BIN:-}" ] && ! command -v "${LD1_BIN:-ld1.x}" >/dev/null 2>&1; then
    skip_ "ld1.x not available (LD1_BIN=${LD1_BIN:-unset})"
elif [ "${PF_SLOW_TESTS:-0}" = 1 ]; then
    export OMP_NUM_THREADS=1
    # Cs is in the list on purpose: it is the element this investigation was
    # about, and the one most likely to behave differently under contention.
    ELS=Cs,Si,O,Fe,Ag
    for j in 1 8; do
        ( cd "$ROOT" && ./pseudoforge generate -e "$ELS" -p psl-low -t us -x pbe \
              -j "$j" -o "$TMP/j$j" >/dev/null 2>&1 )
    done
    n1=$(ls "$TMP/j1"/pseudos/*.UPF 2>/dev/null | wc -l)
    n8=$(ls "$TMP/j8"/pseudos/*.UPF 2>/dev/null | wc -l)
    [ "$n1" -gt 0 ] && [ "$n1" = "$n8" ] \
        && ok_ "both runs produced the same number of files ($n1)" \
        || bad_ "serial produced $n1 files, parallel produced $n8"

    # The generation date is stamped into the UPF, so compare everything else.
    differing=""
    for f in "$TMP"/j1/pseudos/*.UPF; do
        b=$(basename "$f")
        [ -f "$TMP/j8/pseudos/$b" ] || { differing="$differing $b(missing)"; continue; }
        cmp -s <(grep -v 'date=' "$f") <(grep -v 'date=' "$TMP/j8/pseudos/$b") \
            || differing="$differing $b"
    done
    [ -z "$differing" ] \
        && ok_ "every pseudopotential is byte-identical at -j 1 and -j 8" \
        || bad_ "parallelism changed the output:$differing" \
                "workers are sharing state that they should not"

    # and the recorded verdicts must agree too
    v1=$(awk -F'\t' '!/^#/ && NF { print $1, $8 }' "$TMP/j1/state.tsv" | sort)
    v8=$(awk -F'\t' '!/^#/ && NF { print $1, $8 }' "$TMP/j8/state.tsv" | sort)
    [ "$v1" = "$v8" ] \
        && ok_ "the per-element verdicts agree" \
        || bad_ "verdicts differ between serial and parallel" \
                "$(diff <(printf '%s\n' "$v1") <(printf '%s\n' "$v8") | head -4)"

    # Cs specifically: the element that started this.
    cs=$(awk -F'\t' '$1 == "Cs" { print $8 }' "$TMP/j8/state.tsv")
    [ "$cs" = ok ] \
        && ok_ "Cs succeeds under contention, not only on its own" \
        || bad_ "Cs status under -j 8 is '$cs'"

    # Nothing may be left behind in the shared scratch root.
    leftovers=$(find "${SCRATCH_DIR:-/tmp/pseudoforge}" -maxdepth 1 -name '*-Cs' 2>/dev/null | wc -l)
    [ "$leftovers" = 0 ] \
        && ok_ "worker scratch directories are cleaned up" \
        || bad_ "$leftovers scratch directory/ies left behind" \
                "a later run could read a stale intermediate"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
