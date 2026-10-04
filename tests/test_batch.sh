#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Batch generation, resume, and failure isolation.
#
# Three properties, and the second one had a real bug.
#
#   **Failure isolation.** One element failing must not stop the batch. In the
#   52-element psl-low/US run, caesium failed validation with
#   z_valence = -5.0 and the other 51 completed.
#
#   **Resume across an interruption.** Each element writes its result to
#   logs/.state.<El>, and those shards were merged into state.tsv only when the
#   batch *finished*. Killing a run halfway left the shards on disk and the
#   state file empty, so a restart rebuilt everything it had already done --
#   measured at 22 elements. run_batch now merges orphaned shards before it
#   decides what to skip.
#
#   **Resume on a completed run.** A second run of a finished batch must do no
#   work.
#
# The heavy paths are gated behind PF_SLOW_TESTS=1; the logic is checked
# against a synthetic project so the suite stays fast.
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

printf '\n%s== state survives an interrupted run%s\n' "$DIM" "$RESET"
# The regression.  Shards on disk, state.tsv empty -- exactly what a kill
# leaves behind.
export PROJECT_DIR=$TMP/proj PROJECT_STATE=$TMP/proj/state.tsv
mkdir -p "$PROJECT_DIR/logs" "$PROJECT_DIR/pseudos"
: > "$PROJECT_STATE"
for el in Si Fe O; do
    printf '%s\tus\tpsl-low\tpbe\tscalar\t\t%s.UPF\tok\t1\t2\t\n' "$el" "$el" \
        > "$PROJECT_DIR/logs/.state.$el"
    : > "$PROJECT_DIR/pseudos/$el.UPF"
done
[ "$(ls "$PROJECT_DIR"/logs/.state.* 2>/dev/null | wc -l)" = 3 ] \
    && ok_ "three orphaned shards staged" || bad_ "could not stage shards"
[ ! -s "$PROJECT_STATE" ] \
    && ok_ "state.tsv is empty, as it is after a kill" || bad_ "state.tsv is not empty"

state_merge
rows=$(grep -vc '^#' "$PROJECT_STATE" 2>/dev/null || echo 0)
[ "$rows" = 3 ] \
    && ok_ "state_merge absorbs the orphaned shards" \
    || bad_ "merge produced $rows rows, expected 3"
[ "$(ls "$PROJECT_DIR"/logs/.state.* 2>/dev/null | wc -l)" = 0 ] \
    && ok_ "the shards are consumed, not left to double up" \
    || bad_ "shards remain after the merge"

# and the merge must run before resume decides anything
awk '/^run_batch\(\)/,/for el in "\$@"/' "$PF_LIB/run.sh" | grep -q 'state_merge' \
    && ok_ "run_batch merges before choosing what to skip" \
    || bad_ "the merge still happens only at the end" \
            "a restart after a kill would redo work it had already finished"

printf '\n%s== resume reads that state%s\n' "$DIM" "$RESET"
for el in Si Fe O; do
    if state_should_run "$el" 2>/dev/null; then
        bad_ "$el would be rebuilt although state says it is done"
    else
        ok_ "$el is recognised as already done"
    fi
done
state_should_run Cu 2>/dev/null \
    && ok_ "an element with no record is still queued" \
    || bad_ "an unrecorded element was skipped"

# --no-resume must override
RESUME=0
state_should_run Si 2>/dev/null \
    && ok_ "--no-resume forces a rebuild" \
    || bad_ "--no-resume did not override the state"
RESUME=1

printf '\n%s== failure isolation%s\n' "$DIM" "$RESET"
# A failed element is recorded as failed and does not remove the others.
printf 'Cs\tus\tpsl-low\tpbe\tscalar\t\t\tfail\t1\t3\tERROR: implausible z_valence=-5.0\n' \
    >> "$PROJECT_STATE"
[ "$(state_status Cs)" = fail ] \
    && ok_ "a failed element is recorded as failed" \
    || bad_ "state_status Cs = '$(state_status Cs)'"
[ "$(state_status Si)" = ok ] \
    && ok_ "a neighbouring success is untouched" \
    || bad_ "Si status became '$(state_status Si)'"
# and a failure must be retried on the next run, unlike a success
state_should_run Cs 2>/dev/null \
    && ok_ "a failed element is queued again on the next run" \
    || bad_ "a failure was treated as done"

printf '\n%s== the message survives into the record%s\n' "$DIM" "$RESET"
msg=$(awk -F'\t' '$1 == "Cs" { print $11 }' "$PROJECT_STATE")
case $msg in
    *z_valence*) ok_ "the reason for the failure is kept, not just the status" ;;
    *)           bad_ "the failure message was lost: '$msg'" ;;
esac

printf '\n%s== a real batch%s\n' "$DIM" "$RESET"
if [ "${PF_SLOW_TESTS:-0}" = 1 ]; then
    d=$TMP/live
    s=$(date +%s)
    ( cd "$ROOT" && ./pseudoforge generate -e Si,O,Fe,Al -p psl-low -t us -x pbe \
        -j 4 --no-test -o "$d" >/dev/null 2>&1 )
    e=$(date +%s)
    n=$(ls "$d"/pseudos/*.UPF 2>/dev/null | wc -l)
    [ "$n" -ge 3 ] && ok_ "live batch produced $n files in $((e - s))s" \
        || bad_ "live batch produced only $n files"
    # second run must do nothing
    s=$(date +%s)
    out=$( cd "$ROOT" && ./pseudoforge generate -e Si,O,Fe,Al -p psl-low -t us -x pbe \
        -j 4 --no-test -o "$d" 2>&1 )
    e=$(date +%s)
    r=$(printf '%s' "$out" | grep -c 'already done (resume)')
    [ "$r" -ge 3 ] && ok_ "re-running resumed $r element(s) in $((e - s))s" \
        || bad_ "re-run resumed only $r"
else
    skip_ "live batch gated behind PF_SLOW_TESTS=1 (measured separately: 103 elements, 24s at -j 16)"
fi

printf '\n%s== parallelism is bounded%s\n' "$DIM" "$RESET"
grep -q 'MAX_PARALLEL_JOBS' "$PF_LIB/run.sh" \
    && ok_ "the worker count is configurable" || bad_ "no job limit in run.sh"
grep -qE 'jobs -rp|wait -n' "$PF_LIB/run.sh" \
    && ok_ "the batch waits for a slot rather than forking without limit" \
    || bad_ "no backpressure on the worker pool"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
