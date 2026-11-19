#!/usr/bin/env bash
# Run with v1.3.6, QE 7.6, and the indicated generators installed.
set -euo pipefail

if [[ $# != 2 ]]; then
    printf 'Usage: LD1_BIN=/path/ld1.x PW_BIN=/path/pw.x %s REPOSITORY NEW_OUTPUT_DIR\n' "$0" >&2
    exit 2
fi
repo=$(realpath "$1")
examples=$(cd "$(dirname "$0")" && pwd)
mkdir "$2"
cd "$2"
export PF_RC="$PWD/empty.rc" SCRATCH_DIR="$PWD/scratch" PARAMS_CACHE="$PWD/params-cache"
export PF_AUTO_INSTALL_LD1=no OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
: > "$PF_RC"
unset OMPI_MCA_btl

run() {
    local name=$1
    shift
    "$repo/pseudoforge" generate --source local -j 1 -o "$PWD/$name" "$@" > "$name.log" 2>&1
}

run si-cutoff -e Si --engine ld1 -p psl-high -t paw -x pbe -r scalar \
    --formats upf --cutoff-scan --cutoffs '30 40 50 60 70 80 90 100'
run fe-atomic -e Fe --engine ld1 -p psl-high -t paw -x pbe -r scalar --formats upf
run opium-pw91 -e Si --engine opium -p pseudoforge-auto -t nc -x pw91 -r scalar \
    --formats upf --no-test
mkdir -p "$PARAMS_CACHE/sg15/extracted"
cp "$examples/../results/retarget-auto/Si.sg15-pbe-original.dat" \
    "$PARAMS_CACHE/sg15/extracted/Si.dat"
run oncv-pbesol -e Si --engine oncvpsp -p pseudoforge-auto -t nc -x pbesol -r scalar \
    --formats upf --no-cutoff-scan
if run atompaw-refusal -e Si --engine atompaw -p atompaw -t paw -x r2scan \
    -r scalar --formats paw-xml; then
    printf 'Unexpected success for relativistic AtomPAW r2SCAN\n' >&2
    exit 1
fi
grep -F 'cannot generate meta-GGA with a relativistic solver' atompaw-refusal.log
run atompaw-native -e Si --engine atompaw -p atompaw -t paw -x r2scan -r nonrel \
    --formats 'paw-xml paw-abinit'
