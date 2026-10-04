#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The VPS disk budget.
#
# The target is 1 core, 1 GB of RAM and **10 GB of disk**. The layout is meant
# to sit under 8 GB, leaving room for logs, the OS and a bad day.
#
# This is not a nice-to-have. The architecture depends on the machine being
# small: it serves pre-built files and converts them, and it does not hold the
# engines, Quantum ESPRESSO, GSL, LAPACK, cmake or ninja. A layout that grew
# past the budget would mean one of those had crept in, or the native tree had
# stopped being curated -- and the first symptom on a real deployment is a full
# disk, which is the worst way to find out.
#
# So the budget is asserted here, before deployment, from the same directory
# list `pseudoforge native size` reports on.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

BUDGET_MB=${PF_VPS_BUDGET_MB:-8192}
DISK_MB=10240          # what the VPS actually has

# The planned allocation, in MB. These are the figures the architecture was
# designed around; the test is that they still add up and that the real
# artefacts fit inside their share.
declare -A PLAN=(
    [native]=1024
    [converter]=100
    [cache]=2048
    [db]=100
    [docs]=50
    [www]=10
)

printf '\n%s== the plan fits the machine%s\n' "$DIM" "$RESET"
planned=0
for d in "${!PLAN[@]}"; do planned=$((planned + PLAN[$d])); done
printf '  planned: %sM of a %sM budget on a %sM disk\n' "$planned" "$BUDGET_MB" "$DISK_MB"

[ "$planned" -le "$BUDGET_MB" ] \
    && ok_ "the planned layout is ${planned}M, inside the ${BUDGET_MB}M budget" \
    || bad_ "the plan already exceeds the budget by $((planned - BUDGET_MB))M"

[ "$BUDGET_MB" -le "$DISK_MB" ] \
    && ok_ "the budget leaves $((DISK_MB - BUDGET_MB))M for the OS and logs" \
    || bad_ "the budget is larger than the disk"

printf '\n%s== the layout is the one the code and the installer agree on%s\n' "$DIM" "$RESET"
# Three places name these directories. If they disagree, the installer creates
# one thing and the server looks for another.
INSTALL=$ROOT/deploy/scripts/install-vps.sh
missing=""
for d in "${!PLAN[@]}"; do
    grep -q "$d" "$INSTALL" || missing="$missing $d"
done
[ -z "$missing" ] \
    && ok_ "install-vps.sh creates every directory in the plan" \
    || bad_ "the installer does not create:$missing"

grep -q 'native converter cache db docs www' "$PF_LIB/cli.sh" \
    && ok_ "pseudoforge native size reports on the same list" \
    || bad_ "the size report and the installer name different directories"

printf '\n%s== a representative tree stays inside its share%s\n' "$DIM" "$RESET"
V=$TMP/var
for d in "${!PLAN[@]}"; do mkdir -p "$V/$d"; done

# Real artefacts where there are any: the docs and the frontend are built from
# this repository and their size is a fact, not an estimate.
if [ -d "$ROOT/site" ]; then
    cp -r "$ROOT/site/." "$V/docs/" 2>/dev/null
    docs_mb=$(du -sm "$V/docs" | cut -f1)
    [ "$docs_mb" -le "${PLAN[docs]}" ] \
        && ok_ "the built docs are ${docs_mb}M, inside ${PLAN[docs]}M" \
        || bad_ "the built docs are ${docs_mb}M, over the ${PLAN[docs]}M share"
else
    skip_ "no built site/ to measure (run mkdocs build)"
fi

if [ -d "$ROOT/frontend" ]; then
    cp -r "$ROOT/frontend/." "$V/www/" 2>/dev/null
    www_kb=$(du -sk "$V/www" | cut -f1)
    [ "$((www_kb / 1024))" -le "${PLAN[www]}" ] \
        && ok_ "the frontend is ${www_kb}kB, inside ${PLAN[www]}M" \
        || bad_ "the frontend is $((www_kb / 1024))M, over the ${PLAN[www]}M share"
else
    bad_ "no frontend/ to measure"
fi

# A native file is about 200 kB to 2 MB. 1 GB is therefore of the order of a
# thousand files, which is a curated table rather than everything ever made.
sample=$(find "$ROOT/tests/fixtures" -type f -size +10k 2>/dev/null | head -5)
if [ -n "$sample" ]; then
    printf '%s\n' "$sample" | while IFS= read -r f; do cp "$f" "$V/native/"; done
    avg_kb=$(du -sk "$V/native" | cut -f1)
    n=$(printf '%s\n' "$sample" | grep -c .)
    per=$((avg_kb / n))
    room=$(( PLAN[native] * 1024 / (per > 0 ? per : 1) ))
    ok_ "at ~${per}kB per file, ${PLAN[native]}M holds about $room files"
    [ "$room" -ge 200 ] \
        && ok_ "which is enough for a curated table" \
        || bad_ "only $room files fit; the native share is too small to be useful"
else
    skip_ "no fixtures large enough to size a native file from"
fi

printf '\n%s== the total, measured%s\n' "$DIM" "$RESET"
total_mb=$(du -sm "$V" | cut -f1)
printf '  measured: %sM\n' "$total_mb"
[ "$total_mb" -le "$BUDGET_MB" ] \
    && ok_ "the representative tree is ${total_mb}M, inside ${BUDGET_MB}M" \
    || bad_ "the representative tree is ${total_mb}M, over the ${BUDGET_MB}M budget"

printf '\n%s== pseudoforge native size enforces it%s\n' "$DIM" "$RESET"
out=$(PF_VAR_DIR=$V PF_VPS_BUDGET_MB=$BUDGET_MB "$ROOT/pseudoforge" native size "$V" 2>&1)
rc=$?
[ "$rc" = 0 ] \
    && ok_ "it reports the tree as within budget" \
    || bad_ "it reported over budget for a small tree" "$out"
printf '%s' "$out" | grep -q BUDGET \
    && ok_ "and prints the budget alongside the total" \
    || bad_ "the budget is not shown"

# The negative control: a budget of 0 must fail, or the check is decoration.
PF_VAR_DIR=$V PF_VPS_BUDGET_MB=0 "$ROOT/pseudoforge" native size "$V" >/dev/null 2>&1 \
    && bad_ "a zero budget passed" "the check never actually bites" \
    || ok_ "a tree over its budget is reported as over budget"

printf '\n%s== the VPS does not hold what it must not hold%s\n' "$DIM" "$RESET"
# The architecture depends on this machine being unable to generate. An
# installer that quietly pulled in a compiler would undo that without anyone
# noticing until the disk filled.
forbidden=""
for pkg in gfortran gcc g++ make cmake ninja libxc gsl lapack quantum-espresso espresso; do
    grep -qE "apt-get install.*\b$pkg\b" "$INSTALL" && forbidden="$forbidden $pkg"
done
[ -z "$forbidden" ] \
    && ok_ "install-vps.sh installs no compiler or numerical library" \
    || bad_ "the installer would install:$forbidden" \
            "the VPS does not run engines; that is the architecture, not an optimisation"

grep -qE 'engines build' "$INSTALL" \
    && bad_ "the installer builds engines" \
    || ok_ "and it does not build any engine"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
