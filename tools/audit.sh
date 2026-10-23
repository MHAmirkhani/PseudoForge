#!/usr/bin/env bash
# tools/audit.sh -- systematic audit of PseudoForge's features.
#
# Runs each subcommand in a scratch dir, captures exit code, message,
# and any produced files.  Produces AUDIT.md and AUDIT-raw.tsv.
#
# Usage:  tools/audit.sh [--quick]      --quick: skip engine-dependent tests

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge

SCRATCH=$(mktemp -d)
TMP=$(mktemp -d)
trap 'rm -rf "$SCRATCH" "$TMP"' EXIT

# The audit must be reproducible on any machine and must never wait on a
# terminal. Two guards, one fix each:
#
# - An isolated PF_RC stops the user's real config from overriding the
#   mock engines this audit sets up. A .pseudoforgerc with LD1_BIN
#   pointing at the real ld1.x was silently winning over the export
#   above, so the "generate ld1" test was driving the real engine.
#
# - exec </dev/null closes the other half: any subprocess that reads
#   stdin and finds the terminal instead of EOF waits at a prompt
#   forever. The audit should fail such a test, not hang on it.
export PF_RC="${PF_RC_AUDIT:-$TMP/audit-rc}"
: > "$PF_RC"
exec < /dev/null

OUT=$ROOT/AUDIT.md
RAW=$ROOT/AUDIT-raw.tsv
: > "$RAW"

QUICK=0
[ "${1:-}" = --quick ] && QUICK=1

export PF_VAR_DIR=${PF_VAR_DIR:-$HOME/pf-var}
export PF_NATIVE_DIR=${PF_NATIVE_DIR:-$HOME/pf-native}
export PF_DECOMPRESSED_DIR=${PF_DECOMPRESSED_DIR:-$HOME/pf-var/decompressed}
export RECIPE_DIR=${RECIPE_DIR:-$SCRATCH/recipes}
export LD1_BIN=${LD1_BIN:-$ROOT/tests/mock/ld1.x}
[ -z "${UPFCONV_BIN:-}" ] && [ -x /opt/espresso/7.6/upfconv.x ] && export UPFCONV_BIN=/opt/espresso/7.6/upfconv.x

pass=0; fail=0; warn=0; skip=0

# run <label> <cmd...>
run() {
    local label=$1; shift
    local t0=$SECONDS
    local out rc=0
    out=$("$@" 2>&1) || rc=$?
    local dt=$((SECONDS - t0))
    local status
    if [ $rc -eq 0 ]; then
        status=PASS; pass=$((pass+1))
    else
        status=FAIL; fail=$((fail+1))
    fi
    printf '%s\t%s\t%s\t%s\n' "$status" "$label" "$dt" "${out//$'\n'/ | }" >> "$RAW"
    printf '  %-4s  %-45s (%ds)\n' "$status" "$label" "$dt"
    if [ $rc -ne 0 ]; then
        printf '        %s\n' "$out" | head -3
    fi
}

# run_expect_fail <label> <pattern> <cmd...>
#
# The command must exit non-zero AND its output must contain the expected
# pattern.  Used for the refuse cases: an unsupported conversion, --rcut-scale
# on an engine that does not implement it, a functional a profile does not
# publish.
run_expect_fail() {
    local label=$1; shift
    local pattern=$1; shift
    local t0=$SECONDS
    local out rc=0
    out=$("$@" 2>&1) || rc=$?
    local dt=$((SECONDS - t0))
    if [ $rc -eq 126 ] || [ $rc -eq 127 ]; then
        printf '  %-4s  %-45s (%ds) -- rc=%d (command not found)\n' FAIL "$label" "$dt" "$rc"
        printf 'FAIL\t%s\t%s\trc=%d: %s\n' "$label" "$dt" "$rc" "${out//$'\n'/ | }" >> "$RAW"
        fail=$((fail+1))
    elif [ $rc -ne 0 ]; then
        if [ -n "$pattern" ] && [[ "$out" != *"$pattern"* ]]; then
            printf '  %-4s  %-45s (%ds) -- failed with unexpected error\n' FAIL "$label" "$dt"
            printf 'FAIL\t%s\t%s\tunexpected error: expected pattern "%s", got: %s\n' "$label" "$dt" "$pattern" "${out//$'\n'/ | }" >> "$RAW"
            printf '        expected: %s\n' "$pattern"
            printf '        got:      %s\n' "$(head -n 2 <<< "$out" | tr '\n' ' ')"
            fail=$((fail+1))
        else
            printf '  %-4s  %-45s (%ds)\n' PASS "$label" "$dt"
            printf 'PASS\t%s\t%s\trefused as expected\n' "$label" "$dt" >> "$RAW"
            pass=$((pass+1))
        fi
    else
        printf '  %-4s  %-45s (%ds) -- command succeeded, should have refused\n' FAIL "$label" "$dt"
        printf 'FAIL\t%s\t%s\tcommand succeeded, should have refused\n' "$label" "$dt" >> "$RAW"
        fail=$((fail+1))
    fi
}

# decompress_store <out> <glob>
#
# Copy one file from the store, decompressing it if needed.  Returns
# non-zero if no match.
decompress_store() {
    local out=$1 pat=$2 src
    src=$(find -L "$PF_NATIVE_DIR" -name "$pat" 2>/dev/null | head -1)
    [ -n "$src" ] || return 1
    case $src in
        *.gz) gzip -dc "$src" > "$out" ;;
        *)    cp -f "$src" "$out" ;;
    esac
    [ -s "$out" ]
}

echo "=== audit start ==="
echo "scratch: $SCRATCH"
echo

# ---------- subcommand --help ----------
echo "== subcommand --help =="
for cmd in generate validate convert import engines native optimise doctor wizard list show recipe plot report config citation; do
    out=$("$PSM" "$cmd" --help 2>&1)
    rc=$?
    # A `--help` invocation is OK if the command exits 0 and does not
    # print an 'unknown option' / 'unknown subcommand' error.  The
    # subcommands that print the full cli_usage() -- generate, wizard,
    # tui, help, version -- are correct as they are; the check does not
    # try to require a command-specific block.
    if [ $rc -ne 0 ] || echo "$out" | grep -qiE 'unknown option|unknown subcommand'; then
        printf '  BAD-HELP  %s\n' "$cmd"
        printf 'BAD-HELP\t%s\t0\t%s\n' "$cmd" "${out//$'\n'/ | }" >> "$RAW"
        warn=$((warn+1))
    else
        printf '  OK-HELP   %s\n' "$cmd"
        printf 'OK-HELP\t%s\t0\t\n' "$cmd" >> "$RAW"
    fi
done
echo

# ---------- help lists every subcommand ----------
echo "== help lists every subcommand =="
HELP=$("$PSM" help 2>&1)
for cmd in generate validate convert import engines native optimise doctor wizard list show recipe plot report config; do
    if echo "$HELP" | grep -q "\b$cmd\b"; then
        printf '  OK-HELP-LIST   %s\n' "$cmd"
    else
        printf '  MISSING-LIST   %s\n' "$cmd"
        warn=$((warn+1))
    fi
done
echo

# ---------- version / credits ----------
echo "== basics =="
run "version"           "$PSM" version
run "help"              "$PSM" help
run "list profiles"     "$PSM" list profiles
run "list functionals"  "$PSM" list functionals
run "list elements"     "$PSM" list elements
run "doctor"            "$PSM" doctor
echo

# ---------- generate for each engine ----------
# NOTE FOR MAINTAINERS:
# Full mode exercises generation across all supported engines (ld1, oncvpsp,
# opium, uspp, fhi98pp, gth, atompaw, adpack).
# --quick legitimately skips these engine-dependent runs to save execution
# time, but gate verification MUST run in full mode so any engine regressions
# or interactive hangs are caught.
if [ "$QUICK" = 0 ]; then
    echo "== generate: one element per engine =="
    declare -A eng_prof=(
        [ld1]=psl-high
        [oncvpsp]=pseudodojo
        [opium]=opium
        [uspp]=gbrv
        [fhi98pp]=fhi
        [gth]=cp2k-gth
        [atompaw]=atompaw
        [adpack]=adpack
    )
    declare -A eng_fam=(
        [ld1]=nc
        [oncvpsp]=nc
        [opium]=nc
        [uspp]=us
        [fhi98pp]=nc
        [gth]=nc
        [atompaw]=paw
        [adpack]=nc
    )
    declare -A eng_xc=(
        [ld1]=pbe
        [oncvpsp]=pbe
        [opium]=pbe
        [uspp]=pbe
        [fhi98pp]=pw
        [gth]=pbe
        [atompaw]=pbe
        [adpack]=pz
    )
    declare -A eng_el=(
        [ld1]=Si
        [oncvpsp]=Si
        [opium]=Si
        [uspp]=Si
        [fhi98pp]=Si
        [gth]=Si
        [atompaw]=Si
        [adpack]=Na
    )
    # Engines that only have one relativity mode need it stated.
    declare -A eng_rel=(
        [ld1]=scalar
        [oncvpsp]=scalar
        [opium]=scalar
        [uspp]=scalar
        [fhi98pp]=scalar
        [gth]=scalar
        [atompaw]=scalar
        [adpack]=full
    )
    for eng in ld1 oncvpsp opium uspp fhi98pp gth atompaw adpack; do
        d=$SCRATCH/gen-$eng
        mkdir -p "$d"
        run "generate $eng" \
            "$PSM" generate -e "${eng_el[$eng]}" -t "${eng_fam[$eng]}" \
                -x "${eng_xc[$eng]}" -r "${eng_rel[$eng]}" \
                -p "${eng_prof[$eng]}" \
                -o "$d" -q
    done
    echo
fi

# ---------- convert paths ----------
echo "== convert =="
# Find a real UPF in the store
UPF=$(find -L "$PF_NATIVE_DIR" -name '*.UPF' 2>/dev/null | head -1)
if [ -z "$UPF" ]; then
    UPF=$(find -L "$PF_NATIVE_DIR" -name '*.UPF.gz' 2>/dev/null | head -1)
    [ -n "$UPF" ] && gunzip -c "$UPF" > "$SCRATCH/sample.UPF" && UPF=$SCRATCH/sample.UPF
fi
if [ -z "$UPF" ]; then
    UPF=$(find -L "$ROOT/tests/fixtures" -name '*.UPF' 2>/dev/null | head -1)
fi
if [ -n "$UPF" ]; then
    if command -v upfconv.x >/dev/null 2>&1 || ([ -n "${UPFCONV_BIN:-}" ] && [ -x "${UPFCONV_BIN:-}" ]); then
        run "convert upf -> xml" "$PSM" convert "$UPF" --to xml -o "$SCRATCH/c-xml" -q
    else
        printf '  %-4s  %-45s (upfconv.x not installed)\n' SKIP "convert upf -> xml"
        printf 'SKIP\tconvert upf -> xml\t0\tupfconv.x missing\n' >> "$RAW"
        skip=$((skip+1))
    fi
fi

# refuse cases: gth -> upf (must refuse)
GTH=$(find -L "$PF_NATIVE_DIR" -name '*.gth.gz' 2>/dev/null | head -1)
if [ -n "$GTH" ]; then
    gunzip -c "$GTH" > "$SCRATCH/sample.gth"
    "$PSM" convert "$SCRATCH/sample.gth" --to upf -o "$SCRATCH/c-gth" >/dev/null 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        printf '  PASS  convert gth -> upf is refused\n'
        pass=$((pass+1))
    else
        printf '  FAIL  convert gth -> upf should have been refused\n'
        fail=$((fail+1))
    fi
fi
echo

# ---------- validate sample files ----------
echo "== validate =="
if [ -n "$UPF" ]; then
    run "validate UPF v2" "$PSM" validate "$UPF" -q
fi
echo


# ---------- convert refuse cases ----------
echo "== convert refuse cases =="

# gth -> upf (refused: GTH is analytic coefficients, not a radial table)
if decompress_store "$SCRATCH/sample.gth" '*.gth.gz'; then
    run_expect_fail "convert gth -> upf (refused)" \
        "is not a format conversion" \
        "$PSM" convert "$SCRATCH/sample.gth" --to upf -o "$SCRATCH/cv-gth"
fi

# vps -> upf (refused: semilocal V_l(r), no KB form)
if decompress_store "$SCRATCH/sample.vps" '*.vps.gz'; then
    run_expect_fail "convert vps -> upf (refused)" \
        "is not a format conversion" \
        "$PSM" convert "$SCRATCH/sample.vps" --to upf -o "$SCRATCH/cv-vps"
fi

# pawxml -> upf (refused: UPF has no place for tau)
PXML=$(find -L "$PF_NATIVE_DIR" -name '*.xml' -path '*r2scan*' 2>/dev/null | head -1)
if [ -n "$PXML" ]; then
    case $PXML in
        *.gz) gzip -dc "$PXML" > "$SCRATCH/sample-paw.xml" ;;
        *)    cp -f "$PXML" "$SCRATCH/sample-paw.xml" ;;
    esac
    run_expect_fail "convert pawxml -> upf (refused)" \
        "is not a format conversion" \
        "$PSM" convert "$SCRATCH/sample-paw.xml" --to upf -o "$SCRATCH/cv-paw"
fi

# psp8 -> upf (refused: no tool performs this)
if decompress_store "$SCRATCH/sample.psp8" '*.psp8.gz'; then
    run_expect_fail "convert psp8 -> upf (refused)" \
        "nothing performs this conversion" \
        "$PSM" convert "$SCRATCH/sample.psp8" --to upf -o "$SCRATCH/cv-psp8"
fi
echo

# ---------- physics flags ----------
echo "== physics flags (ld1 + psl-high + Si) =="
declare -a pf_flags=(
    "--rcut-scale 1.1"
    "--core-hole 1s"
    "--gipaw"
    "--lsd"
    "--grid -7.0:0.0125:100.0"
    "--upf 2"
    "--nc-form semilocal"
    "--beta 0.3"
    "--tr2 1.0d-10"
    "--nlcc on"
    "--lloc 2"
    "--rcore 1.5"
)
for flag in "${pf_flags[@]}"; do
    tag=$(printf '%s' "$flag" | tr -c 'a-zA-Z0-9' '_')
    d=$SCRATCH/flag-$tag
    # Unquoted $flag: word-split so "--rcut-scale 1.1" becomes two arguments.
    # shellcheck disable=SC2086
    run "generate ld1 $flag" \
        "$PSM" generate -e Si -t nc -x pbe -p psl-high -o "$d" $flag -q
done
echo

# ---------- refused flags ----------
echo "== flags that should be refused =="
# --projector is only supported on ld1 (refused on other engines), accepted on
# ld1 for a non-local channel, and refused on ld1 when the channel is lloc.
run_expect_fail "generate oncvpsp --projector 3P:0.5 (refused on non-ld1)" \
    "--projector is only available with ld1" \
    "$PSM" generate -e Si -t nc -x pbe -p sg15 --engine oncvpsp -o "$SCRATCH/pj-oncv" --projector 3P:0.5 -q
run "generate ld1 --projector 3P:0.5 (accepted on non-local channel)" \
    "$PSM" generate -e Si -t nc -x pbe -p psl-high -o "$SCRATCH/pj-ok" --projector 3P:0.5 --no-test -q
run_expect_fail "generate ld1 --projector 3D:0.5 (refused on local channel)" \
    "local channel" \
    "$PSM" generate -e Si -t nc -x pbe -p psl-high -o "$SCRATCH/pj-bad" --projector 3D:0.5 -q
# --upf 1 is refused: QE 7.x's ld1.x no longer writes UPF v1.
run_expect_fail "generate ld1 --upf 1 (refused)" \
    "UPF v1 is not supported" \
    "$PSM" generate -e Si -t nc -x pbe -p psl-high -o "$SCRATCH/upf1-bad" --upf 1 -q
echo

# ---------- rcut-scale refuse cases ----------
echo "== --rcut-scale refused on engines that lack it =="
run_expect_fail "generate uspp --rcut-scale (refused)" \
    "--rcut-scale is not available with USPP" \
    "$PSM" generate -e Si -t us -x pbe -p gbrv -o "$SCRATCH/rc-uspp" --rcut-scale 1.1 -q
run_expect_fail "generate fhi98pp --rcut-scale (refused)" \
    "--rcut-scale is not available with fhi98PP" \
    "$PSM" generate -e Si -t nc -x pw -p fhi -o "$SCRATCH/rc-fhi" --rcut-scale 1.1 -q
run_expect_fail "generate gth --rcut-scale (refused)" \
    "--rcut-scale is not available with GTH" \
    "$PSM" generate -e Si -t nc -x pbe -p cp2k-gth -o "$SCRATCH/rc-gth" --rcut-scale 1.1 -q
run_expect_fail "generate atompaw --rcut-scale (refused)" \
    "--rcut-scale is not available with AtomPAW" \
    "$PSM" generate -e Si -t paw -x pbe -p atompaw -o "$SCRATCH/rc-atompaw" --rcut-scale 1.1 -q
echo

# ---------- augfun on PAW ----------
if [ "$QUICK" = 0 ] || "$PSM" engines path atompaw >/dev/null 2>&1; then
    echo "== augfun on PAW =="
    run "generate atompaw --augfun AE" \
        "$PSM" generate -e Si -t paw -x pbe -p atompaw -o "$SCRATCH/af-paw" --augfun AE -q
    echo
fi

# ---------- other subcommands ----------
echo "== other subcommands =="
run "show psl-high"     "$PSM" show psl-high
run "citation psl-high" "$PSM" citation psl-high
run "config --show"     "$PSM" config --show
run "list recipes Si"   "$PSM" list recipes Si
run "list sets"         "$PSM" list sets
run "recipe Si (print)" "$PSM" recipe Si -t nc -p psl-high -x pbe
run "recipe save"       "$PSM" recipe save audit-recipe -e Si -t nc -p psl-high -x pbe
run "recipe list"       "$PSM" recipe list
run "recipe load"       "$PSM" recipe load audit-recipe
echo

# ---------- import ----------
echo "== import =="
mkdir -p "$SCRATCH/import-src"
if [ -n "$UPF" ] && [ -f "$UPF" ]; then
    cp -f "$UPF" "$SCRATCH/import-src/one.UPF"
    run "import a directory of UPFs" \
        "$PSM" import "$SCRATCH/import-src" -o "$SCRATCH/imported" -q
fi
echo

# ---------- report + plot on a completed project ----------
echo "== report / plot on a completed project =="
GENPROJ=$SCRATCH/gen-ld1
if [ -d "$GENPROJ" ] && [ -f "$GENPROJ/state.tsv" ]; then
    run "report $GENPROJ" "$PSM" report "$GENPROJ"
    # plot may refuse if no backend (gnuplot missing); that is a soft fail
    "$PSM" plot "$GENPROJ" >/dev/null 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
        printf '  %-4s  %-45s\\n' PASS "plot $GENPROJ"
        printf 'PASS\\tplot on a project\\t0\\t\\n' >> "$RAW"
        pass=$((pass+1))
    else
        # Look for the "no backend" hint specifically
        msg=$("$PSM" plot "$GENPROJ" 2>&1)
        case $msg in
            *"gnuplot"*|*"backend"*|*"no plotting"*)
                printf '  %-4s  %-45s (no plot backend; not a failure)\\n' SKIP "plot $GENPROJ"
                printf 'SKIP\\tplot on a project (no backend)\\t0\\t\\n' >> "$RAW"
                skip=$((skip+1)) ;;
            *)
                printf '  %-4s  %-45s\\n' FAIL "plot $GENPROJ"
                printf 'FAIL\\tplot on a project\\t0\\t%s\\n' "${msg//$'\n'/ | }" >> "$RAW"
                fail=$((fail+1)) ;;
        esac
    fi
fi
echo


# ---------- validate on all supported formats ----------
echo "== validate: every format the reader handles =="
#
# upf_validate_any dispatches by extension: UPF (v1 and v2), psp8, PAW-XML,
# GTH, OpenMX .vps, FHI .cpi.  The UPF path is tested in the earlier
# section; the others are exercised here on files taken from the store or
# from tests/fixtures.
validate_one() {   # <label> <glob> [<search-root>]
    local label=$1 pat=$2 root=${3:-$PF_NATIVE_DIR}
    local src out
    src=$(find -L "$root" -name "$pat" 2>/dev/null | head -1)
    if [ -z "$src" ]; then
        printf '  %-4s  %-45s (no sample found)\n' SKIP "$label"
        printf 'SKIP\t%s\t0\tno sample\n' "$label" >> "$RAW"
        skip=$((skip+1))
        return
    fi
    # Keep the extension: upf_validate_any dispatches by it, so a temp file
    # called "val-validate_vps" without a suffix is reported as unknown
    # format rather than as the file it actually is.
    local tag=${label// /_}
    local ext=${src##*.}
    [ "$ext" = gz ] && ext=$(basename "${src%.gz}"); ext=${ext##*.}
    out=$SCRATCH/val-$tag.$ext
    case $src in
        *.gz) gzip -dc "$src" > "$out" ;;
        *)    cp -f "$src" "$out" ;;
    esac
    run "$label" "$PSM" validate "$out" -q
}

validate_one "validate psp8"     '*.psp8'     "$ROOT/tests/fixtures"
validate_one "validate PAW-XML"  '*.xml'      "$ROOT/tests/fixtures"
validate_one "validate GTH"      '*.gth'      "$ROOT/tests/fixtures"
validate_one "validate vps"      '*.vps'      "$ROOT/tests/fixtures"
validate_one "validate cpi"      '*.cpi'      "$ROOT/tests/fixtures"
echo

# ---------- --source online ----------
echo "== --source online =="
#
# The mirror in the shipped configuration (pseudo.amirkhani.me) is not
# reachable from a build machine that is not online; if it is down, the
# fetch falls back to the upstream site.  A run that fails because of the
# network is not a code fault, so this section reports SKIP in that case
# and PASS only if a published file is actually fetched.
online_probe() {
    local url=$1
    if command -v curl >/dev/null 2>&1; then
        curl -sI --max-time 5 "$url" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --spider --timeout=5 "$url" 2>/dev/null
    else
        return 1
    fi
}

if online_probe https://pseudopotentials.quantum-espresso.org 2>/dev/null \
   || online_probe https://raw.githubusercontent.com 2>/dev/null; then
    # A small library -- sg15 is the smallest NC set the site links.
    d=$SCRATCH/online
    mkdir -p "$d"
    if "$PSM" generate -e Si -t nc -x pbe -p sg15 --source online -o "$d" -q >/dev/null 2>&1; then
        got=$(find "$d/pseudos" -iname '*.upf' 2>/dev/null | head -1)
        if [ -n "$got" ]; then
            printf '  %-4s  %-45s\\n' PASS "fetch sg15 Si from the site"
            printf 'PASS\\tfetch sg15 Si\\t0\\t\\n' >> "$RAW"
            pass=$((pass+1))
        else
            printf '  %-4s  %-45s (ran but wrote no file)\\n' FAIL "fetch sg15 Si"
            printf 'FAIL\\tfetch sg15 Si\\t0\\twrote no file\\n' >> "$RAW"
            fail=$((fail+1))
        fi
    else
        printf '  %-4s  %-45s (network or upstream refused)\\n' SKIP "fetch sg15 Si"
        printf 'SKIP\\tfetch sg15 Si\\t0\\tnetwork or upstream\\n' >> "$RAW"
        skip=$((skip+1))
    fi
else
    printf '  %-4s  %-45s (no route to any library)\\n' SKIP "fetch sg15 Si"
    printf 'SKIP\\tfetch sg15 Si\\t0\\tno network\\n' >> "$RAW"
    skip=$((skip+1))
fi
echo

# ---------- error handling ----------
echo "== error handling =="

# Missing element in a profile that does not cover it
run_expect_fail "generate an element a profile does not cover" \
    "matched nothing" \
    "$PSM" generate -e Og -t nc -x pbe -p psl-high -o "$SCRATCH/eh-og" -q

# Bad --params directory
run_expect_fail "generate with a nonexistent --params dir" \
    "not a directory" \
    "$PSM" generate -e Si -t nc -x pbe -p psl-high -o "$SCRATCH/eh-params" --params /nonexistent/path/for/params -q

# Bad element symbol
run_expect_fail "generate with an unknown element" \
    "matched nothing" \
    "$PSM" generate -e Xx -t nc -x pbe -p psl-high -o "$SCRATCH/eh-el" -q

# Bad family
run_expect_fail "generate with an unknown family" \
    "unknown family" \
    "$PSM" generate -e Si -t xyz -p psl-high -o "$SCRATCH/eh-fam" -q

# Bad functional for a profile
run_expect_fail "generate with a functional a profile does not publish" \
    "has no PZ" \
    "$PSM" generate -e Si -t us -x pz -p gbrv -o "$SCRATCH/eh-xc" -q

# --rcut-scale with a non-numeric value
run_expect_fail "generate --rcut-scale not a number" \
    "must be a positive number" \
    "$PSM" generate -e Si -t nc -x pbe -p psl-high -o "$SCRATCH/eh-rc" --rcut-scale abc -q

# Missing engine on an import-only profile
run_expect_fail "generate on a profile that needs download" \
    "has no nc recipes" \
    "$PSM" generate -e Si -t nc -x pbe -p dacapo -o "$SCRATCH/eh-dl" -q

# validate on a nonexistent file
run_expect_fail "validate a nonexistent file" \
    "does not exist" \
    "$PSM" validate "$SCRATCH/does-not-exist.UPF" -q

# convert with a missing --to
run_expect_fail "convert with no --to" \
    "convert to what" \
    "$PSM" convert "$UPF" -o "$SCRATCH/eh-conv"

# convert with a bad source file
run_expect_fail "convert with a nonexistent source" \
    "no such file" \
    "$PSM" convert "$SCRATCH/nope.UPF" --to xml -o "$SCRATCH/eh-conv2"
echo

echo "=== audit summary ==="
echo "pass: $pass  fail: $fail  warn: $warn"
echo "raw:   $RAW"

# ---------- write AUDIT.md ----------
{
    echo "# PseudoForge Audit"
    echo
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ "$QUICK" = 1 ]; then
        echo "Mode: Quick (--quick: skips engine-dependent generation tests for 8 engines: ld1, oncvpsp, opium, uspp, fhi98pp, gth, atompaw, adpack)"
    else
        echo "Mode: Full (all subcommands and engine generation tests)"
    fi
    echo
    echo "## Summary"
    echo "- PASS: $pass"
    echo "- FAIL: $fail"
    echo "- WARN: $warn"
    echo
    echo "## Raw results"
    echo
    echo '```'
    cat "$RAW"
    echo '```'
} > "$OUT"

echo
echo "report: $OUT"

[ "$fail" -eq 0 ] || exit 1
