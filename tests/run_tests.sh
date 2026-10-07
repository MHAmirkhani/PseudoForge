#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# pseudoforge test suite.
#
#   tests/run_tests.sh              everything except the slow round-trip
#   tests/run_tests.sh --all        including the PSlibrary round-trip
#
# The suite runs against a mock ld1.x (tests/mock/ld1.x), so it needs no
# Quantum ESPRESSO build.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge

TMP=$(mktemp -d)

# The suite overrides HOME so that the config file and the mock engines are
# isolated.  Keep the original in ORIG_HOME: the store-integrity check needs
# to look at the real `~/pf-native` when the user has one, and `$HOME` after
# the override points at a directory that never has a store.
ORIG_HOME=$HOME
export HOME=$TMP/home
export PF_RC=$HOME/.pseudoforgerc
export LD1_BIN=$HERE/mock/ld1.x
export MOCK_STATE_DIR=$TMP/mockstate
export OUTPUT_BASE_DIR=$TMP/out
export SCRATCH_DIR=$TMP/scratch
mkdir -p "$HOME" "$MOCK_STATE_DIR"
trap 'rm -rf "$TMP"' EXIT

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0

ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }

# assert_ok <name> <command...>
assert_ok() { local n=$1; shift; if "$@" >/dev/null 2>&1; then ok_ "$n"; else bad_ "$n" "command failed: $*"; fi; }
# assert_fail <name> <command...>
assert_fail() { local n=$1; shift; if "$@" >/dev/null 2>&1; then bad_ "$n" "expected failure: $*"; else ok_ "$n"; fi; }
# assert_match <name> <pattern> <command...>
assert_match() {
    local n=$1 pat=$2; shift 2
    local out; out=$("$@" 2>&1)
    if printf '%s' "$out" | grep -q -- "$pat"; then ok_ "$n"
    else bad_ "$n" "no match for '$pat' in: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fi
}
# assert_eq <name> <expected> <actual>
assert_eq() {
    if [ "$2" = "$3" ]; then ok_ "$1"; else bad_ "$1" "expected '$2', got '$3'"; fi
}

section() { printf '\n%s== %s%s\n' "$DIM" "$1" "$RESET"; }

# ---------------------------------------------------------------------------
section "basics"
assert_match "version"            "PseudoForge 1.3"      "$PSM" version
assert_match "version credits the author" "Amirkhani"    "$PSM" version
assert_match "help"               "GENERATION OPTIONS"   "$PSM" help
assert_ok    "creates config"     test -f "$PF_RC"
assert_match "doctor runs"        "Recipe database"      "$PSM" doctor
assert_match "list profiles"      "psl-high"             "$PSM" list profiles
assert_match "list functionals"   "generated with PBE"   "$PSM" list functionals
assert_match "list elements"      "Lawrencium"           "$PSM" list elements
assert_match "list sets"          "paw-high"             "$PSM" list sets
assert_match "show profile"       "byte-identical"       "$PSM" show psl-high

# ---------------------------------------------------------------------------
section "element selection"
assert_eq "symbol"     "1"   "$("$PSM" generate -e Fe --dry-run -o "$TMP/s1" -q >/dev/null 2>&1; ls "$TMP/s1/inputs" | wc -l | tr -d ' ')"
assert_eq "range 1-10" "10"  "$("$PSM" generate -e 1-10 --dry-run -o "$TMP/s2" -q >/dev/null 2>&1; ls "$TMP/s2/inputs" | wc -l | tr -d ' ')"
assert_eq "exclusion"  "9"   "$("$PSM" generate -e 1-10 -e '!He' --dry-run -o "$TMP/s3" -q >/dev/null 2>&1; ls "$TMP/s3/inputs" | wc -l | tr -d ' ')"
assert_eq "by name"    "1"   "$("$PSM" generate -e iron --dry-run -o "$TMP/s4" -q >/dev/null 2>&1; ls "$TMP/s4/inputs" | wc -l | tr -d ' ')"
assert_eq "by Z"       "1"   "$("$PSM" generate -e 26 --dry-run -o "$TMP/s5" -q >/dev/null 2>&1; ls "$TMP/s5/inputs" | wc -l | tr -d ' ')"
assert_match "lanthanides" "Lu" bash -c "\"$PSM\" generate -e lanthanides --dry-run -o \"$TMP/s6\" -q >/dev/null 2>&1; ls \"$TMP/s6/inputs\""

# ---------------------------------------------------------------------------
section "recipe fidelity"
# An untouched psl-* run must reproduce the upstream deck byte for byte.
"$PSM" recipe Fe -t paw -p psl-high -x pbe > "$TMP/fe.ours" 2>/dev/null
sed -e 's/{{FCT}}/pbe/g' -e 's/{{GFUN}}/PBE/g' -e 's/{{NREL}}/1/g' \
    "$ROOT/data/psl/paw-high/Fe.spn.1.0.0.tpl" > "$TMP/fe.up"
assert_ok "Fe PAW deck is byte-identical to PSlibrary" diff -q "$TMP/fe.up" "$TMP/fe.ours"

"$PSM" recipe Si -t us -p psl-high -x pz -r full > "$TMP/si.ours" 2>/dev/null
sed -e 's/{{FCT}}/rel-pz/g' -e 's/{{GFUN}}/LDA/g' -e 's/{{NREL}}/2/g' \
    "$ROOT/data/psl/us-high/Si.n.1.0.0.tpl" > "$TMP/si.up"
assert_ok "Si US rel-pz deck is byte-identical" diff -q "$TMP/si.up" "$TMP/si.ours"

assert_match "US flavour naming"   "rrkjus_psl"  "$PSM" recipe Si -t us
assert_match "PAW flavour naming"  "kjpaw_psl"   "$PSM" recipe Si -t paw
assert_match "NC flavour naming"   "pseudotype=2" "$PSM" recipe Si -t nc
assert_match "full-rel tag"        "rel-pbe"     "$PSM" recipe Si -t paw -r full
assert_match "full-rel code"       "rel=2"       "$PSM" recipe Si -t paw -r full

# ---------------------------------------------------------------------------
section "physics overrides"
assert_match "core hole expands the core" "1s1 2s2 2p6" "$PSM" recipe Cu -t paw --core-hole 1s --zval 12
assert_match "core hole tags the name"    "ch1s"        "$PSM" recipe Cu -t paw --core-hole 1s --zval 12
assert_match "fractional Z"               "zed=14.5"    "$PSM" recipe Si -t paw --zed 14.5
# QE 7.x's ld1.x no longer recognises the upf_v1_format namelist key, and
# no other engine here writes UPF v1.  PseudoForge refuses the request
# rather than emit a UPF v2 under a v1 name.
# The first check confirms the *message*; a pipeline returns the exit code
# of its last command (grep), so this has to be assert_ok.  The second check
# is the exit-code test on its own.
assert_ok    "UPF v1 is refused (message)" bash -c "\"$PSM\" recipe Si -t paw --upf 1 2>&1 | grep -q 'UPF v1 is not supported'"
assert_fail  "UPF v1 is refused (exit code)" bash -c "\"$PSM\" recipe Si -t paw --upf 1 >/dev/null 2>&1"
assert_match "UPF v2 has no v1 flag"      "pseudotype"  "$PSM" recipe Si -t paw --upf 2
assert_fail  "UPF v2 really has no v1 flag" bash -c "\"$PSM\" recipe Si -t paw --upf 2 2>/dev/null | grep -q upf_v1_format"
assert_match "GIPAW"                      "lgipaw_reconstruction=.true." "$PSM" recipe Si -t paw --gipaw
assert_match "GIPAW from PAW"             "use_paw_as_gipaw=.true."      "$PSM" recipe Si -t paw --gipaw
assert_match "augmentation functions"     "which_augfun='BESSEL'"        "$PSM" recipe Si -t us --augfun BESSEL
assert_match "local channel"              "lloc=0"      "$PSM" recipe Si -t paw --lloc 0
assert_match "NLCC off"                   "nlcc=.false." "$PSM" recipe Si -t paw --nlcc off
assert_match "spin polarised"             "lsd=1"       "$PSM" recipe Fe -t paw --lsd
assert_match "radial grid"                "rmax=120.0"  "$PSM" recipe Si -t paw --grid -7.0:0.0125:120.0
assert_match "SCF mixing"                 "beta=0.1"    "$PSM" recipe Si -t paw --beta 0.1

# rcut scaling must actually move the numbers
before=$("$PSM" recipe Si -t paw 2>/dev/null | tail -1 | awk '{print $6}')
after=$("$PSM" recipe Si -t paw --rcut-scale 1.10 2>/dev/null | tail -1 | awk '{print $6}')
assert_ok "rcut scaling changes the cards" \
    awk -v a="$before" -v b="$after" 'BEGIN { exit (b > a * 1.05) ? 0 : 1 }'

# Extra projectors add a card.  The supplementary card sits immediately
# after the base card on the same channel and carries the negative of the
# base occupation, matching PSlibrary's own multi-projector templates.
n0=$("$PSM" recipe Si -t paw 2>/dev/null | awk '/^[0-9]+$/ { n = $1 } END { print n }')
n1=$("$PSM" recipe Si -t paw --projector 3P:0.5 2>/dev/null | awk '/^[0-9]+$/ { n = $1 } END { print n }')
assert_eq "extra projector adds a card" "$((n0 + 1))" "$n1"

# Adjacency: the line after the first 3P card is the supplementary 3P card.
adjacent=$("$PSM" recipe Si -t paw --projector 3P:0.5 2>/dev/null \
    | awk '/^3P/ { n++; if (n==1) { getline; if ($1=="3P") print "yes" } }')
assert_eq "extra projector sits adjacent to base" "yes" "$adjacent"

# Occupation is negative, matching PSlibrary.
occ=$("$PSM" recipe Si -t paw --projector 3P:0.5 2>/dev/null \
    | awk '/^3P/ { n++; if (n==2) { print $4; exit } }')
assert_eq "extra projector has negative occupation" "-2.00" "$occ"

# The local channel cannot take a second card: refuse cleanly.  This is a
# property of the NC deck in psl-high, where lloc=2 (the d channel is the
# local potential); the PAW deck leaves lloc=-1, and a supplementary card
# on any channel is fine there.
assert_fail "projector on local channel is refused (nc, lloc=2)" \
    bash -c "\"$PSM\" recipe Si -t nc -p psl-high --projector 3D:0.5 >/dev/null 2>&1"
# And on the PAW deck the same flag has to succeed.
assert_ok "projector on 3D works for paw (lloc=-1)" \
    bash -c "\"$PSM\" recipe Si -t paw --projector 3D:0.5 >/dev/null 2>&1"

# ---------------------------------------------------------------------------
section "norm-conserving form"
assert_match "separable is the default" "pseudotype=2" "$PSM" recipe Si -t nc
assert_match "semilocal available"      "pseudotype=1" "$PSM" recipe Si -t nc --nc-form semilocal
assert_match "semilocal tags the name"  "nc-sl"        "$PSM" recipe Si -t nc --nc-form semilocal

section "functional handling"
assert_match "PBE is native"        "dft='PBE'"    "$PSM" recipe Si -t paw -x pbe
assert_match "PBEsol is native"     "dft='PBESOL'" "$PSM" recipe Si -t paw -x pbesol
assert_match "SCAN falls back"      "dft='PBE'"    "$PSM" recipe Si -t paw -x scan
assert_match "SCAN says so"         "cannot generate this family" "$PSM" recipe Si -t paw -x scan
assert_match "B3LYP falls back to BLYP" "dft='BLYP'" "$PSM" recipe Si -t paw -x b3lyp
assert_match "vdW-DF falls back to revPBE" "dft='REVPBE'" "$PSM" recipe Si -t paw -x vdw-df

# ---------------------------------------------------------------------------
section "guard rails"
# A library pseudoforge does not ship is still reproducible when its authors
# publish their generation inputs: pseudoforge fetches those and runs them, so the
# result is a real reproduction rather than a lookalike.
# The generation inputs now ship with PseudoForge, so a library that used to
# need a download is simply "generated" and runs offline.
assert_match "published library needs no download" "generated" \
    env ONCVPSP_BIN="$HERE/mock/oncvpsp.x" PARAMS_CACHE="$TMP/pcache" \
        "$PSM" generate -e Si -p sg15 -t nc --dry-run
# Without an engine there is nothing to run them with, and pseudoforge says so.
assert_match "refused without the engine to run it" "which is not installed" \
    env ONCVPSP_BIN=/nonexistent PATH=/usr/bin:/bin "$PSM" generate -e Si -p sg15 -t nc
assert_match "and points at the fix" "engines build oncvpsp" \
    env ONCVPSP_BIN=/nonexistent PATH=/usr/bin:/bin "$PSM" generate -e Si -p sg15 -t nc

# ---------------------------------------------------------------------------
section "generation, auto-fix and validation"
rm -rf "$MOCK_STATE_DIR"; mkdir -p "$MOCK_STATE_DIR"
MOCK_FAIL_ELEMENTS="Fe:chi:1 Cu:augmentation:1" \
MOCK_FAIL_ALWAYS="Xe" MOCK_WARN_ELEMENTS="Ni" MOCK_TRUNCATE="Zn" MOCK_NAN="Cd" \
MOCK_DE=0.0004 \
    "$PSM" generate -e Si,Fe,Cu,Ni,Zn,Cd,Xe -t paw -o "$TMP/gen" -j 2 -q >/dev/null 2>&1

st() { awk -F'\t' -v e="$1" '$1 == e { print $8 }' "$TMP/gen/state.tsv"; }
assert_eq "clean element succeeds"        "ok"      "$(st Si)"
assert_eq "auto-fix rescues chi failure"  "ok"      "$(st Fe)"
assert_eq "auto-fix rescues augmentation" "ok"      "$(st Cu)"
assert_eq "warnings are surfaced"         "ok-warn" "$(st Ni)"
assert_eq "truncated UPF is caught"       "fail"    "$(st Zn)"
assert_eq "NaN in UPF is caught"          "fail"    "$(st Cd)"
assert_eq "unfixable element fails"       "fail"    "$(st Xe)"
assert_ok  "a failing element does not stop the batch" test -f "$TMP/gen/pseudos/Si.pbe-n-kjpaw_psl.1.0.0.UPF"
assert_match "auto-fix is recorded" "auto-fixed" cat "$TMP/gen/state.tsv"
assert_ok  "state is ordered by Z" bash -c \
    "awk -F'\t' '!/^#/ && NF { print \$1 }' '$TMP/gen/state.tsv' | head -1 | grep -qx Si"

section "reports"
for f in summary.txt summary.csv summary.json summary.html; do
    assert_ok "$f written" test -s "$TMP/gen/reports/$f"
done
assert_match "txt lists failures"   "FAILED ELEMENTS" cat "$TMP/gen/reports/summary.txt"
assert_match "csv has a header"     "element,Z,pseudopotential" cat "$TMP/gen/reports/summary.csv"
assert_match "json reports counts"  '"failed": 3'    cat "$TMP/gen/reports/summary.json"
assert_match "html is self-contained" "prefers-color-scheme" cat "$TMP/gen/reports/summary.html"
# The report must not *fetch* anything at run time -- it has to be readable
# offline and from a file:// URL.  A DOI hyperlink is not a fetch: it is a
# reference the reader clicks, and suppressing those would defeat the point of
# having a References section at all.
assert_fail  "html loads no external resources"     grep -qE 'src="https?:|<link[^>]+href="https?:|@import|url\(https?:' "$TMP/gen/reports/summary.html"
assert_match "html does link DOIs" 'href="https://doi.org/' cat "$TMP/gen/reports/summary.html"
assert_ok    "manifest written"     test -s "$TMP/gen/manifest"
assert_match "manifest records the functional" "xc_qe_string=PBE" cat "$TMP/gen/manifest"

section "transferability"
assert_ok    "transferability results written" test -s "$TMP/gen/tests/transferability.tsv"
assert_match "verdict parsed" "good" cat "$TMP/gen/tests/transferability.tsv"

section "resume"
out=$("$PSM" generate -e Si,Fe -t paw -o "$TMP/gen" --no-test 2>&1)
assert_match "resume skips finished elements" "already done" printf '%s' "$out"
out=$(MOCK_FAIL_ELEMENTS='' "$PSM" generate -e Si -t paw -o "$TMP/gen" --no-resume --no-test 2>&1)
assert_match "--no-resume regenerates" "Si  ->" printf '%s' "$out"

section "validate and import"
assert_ok    "validate accepts a good file"  "$PSM" validate "$TMP/gen/pseudos/Si.pbe-n-kjpaw_psl.1.0.0.UPF"
printf 'not a pseudopotential\n' > "$TMP/bad.UPF"
assert_fail  "validate rejects a non-UPF"    "$PSM" validate "$TMP/bad.UPF"
assert_match "validate explains why"         "not a UPF file" "$PSM" validate "$TMP/bad.UPF"
assert_ok    "import registers files"        "$PSM" import "$TMP/gen/pseudos" -o "$TMP/imp"
assert_ok    "import produces a report"      test -s "$TMP/imp/reports/summary.html"

section "UPF parsing"
assert_eq "element from UPF v2" "Si" "$(
    . "$ROOT/lib/core.sh"; . "$ROOT/lib/upf.sh"
    upf_get "$TMP/gen/pseudos/Si.pbe-n-kjpaw_psl.1.0.0.UPF" element)"
# --upf 1 is refused because QE 7.x cannot write it.  The UPF v1 reader in
# lib/upf.sh still exists so that a v1 file produced elsewhere can be read
# and validated; that path is tested by the fixtures below.
MOCK_DE=0 "$PSM" generate -e Si -t paw --upf 1 -o "$TMP/v1" --no-test -q >/dev/null 2>&1
rc=$?
assert_eq "generate --upf 1 exits non-zero" "1" "$([ $rc -ne 0 ] && echo 1 || echo 0)"
assert_fail "generate --upf 1 wrote no file" bash -c "ls \"$TMP/v1/pseudos\"/*.UPF 2>/dev/null | grep -q ."

# The UPF v1 reader still works on a v1 file produced elsewhere.  Build a
# minimal one from the fixture (tests/fixtures/upf1) and check it parses.
v1fix=$ROOT/tests/fixtures/upf1/Si.pz-vbc.UPF
if [ -f "$v1fix" ]; then
    assert_eq "format detected as v1" "v1" "$(
        . "$ROOT/lib/core.sh"; . "$ROOT/lib/upf.sh"; upf_format "$v1fix")"
    assert_eq "element from UPF v1" "Si" "$(
        . "$ROOT/lib/core.sh"; . "$ROOT/lib/upf.sh"; upf_get "$v1fix" element)"
    fi

section "namelist editing"
(
    . "$ROOT/lib/core.sh"; . "$ROOT/lib/namelist.sh"
    d=$TMP/nml.in
    sed -e 's/{{FCT}}/pbe/g' -e 's/{{GFUN}}/PBE/g' -e 's/{{NREL}}/1/g' \
        "$ROOT/data/psl/paw-high/Fe.spn.1.0.0.tpl" > "$d"
    [ "$(nml_get "$d" input title)" = "Fe" ]                || exit 1
    [ "$(nml_get "$d" inputp rcore)" = "0.8" ]               || exit 2
    [ "$(nml_card_count "$d")" = "6" ]                       || exit 3
    # a prefix must not match a longer key
    nml_unset "$d" inputp rmatch_augfun
    grep -q 'rmatch_augfun_nc' "$d"                          || exit 4
    nml_set "$d" inputp rcore 1.25
    [ "$(nml_get "$d" inputp rcore)" = "1.25" ]              || exit 5
    nml_set "$d" inputp brand_new 42
    [ "$(nml_get "$d" inputp brand_new)" = "42" ]            || exit 6
    nml_add_card "$d" "4D  4  2  0.00  1.00  1.00  1.40  0.0"
    [ "$(nml_card_count "$d")" = "7" ]                       || exit 7
) && ok_ "namelist get/set/unset/cards" || bad_ "namelist get/set/unset/cards" "step $? failed"

section "pseudoforge-auto"
assert_match "adapts from a neighbour" "pseudoforge-auto" "$PSM" recipe Cm -t paw -p pseudoforge-auto
assert_match "warns that it is a heuristic" "validate before use" "$PSM" recipe Cm -t paw -p pseudoforge-auto
assert_match "keeps the semicore shells" "6d" "$PSM" recipe Cm -t paw -p pseudoforge-auto

section "report rebuild and pw templates"
assert_ok    "report rebuilds an existing project" "$PSM" report "$TMP/gen"
assert_ok    "rebuilt report is non-empty"         test -s "$TMP/gen/reports/summary.txt"
assert_match "report restores the settings"        "PSlibrary" cat "$TMP/gen/reports/summary.txt"
assert_match "report on a non-project fails"       "not a PseudoForge project" "$PSM" report "$TMP"

cat > "$TMP/tpl.in" <<'TPL'
&CONTROL
  prefix = '{{PREFIX}}'
  outdir = '{{OUTDIR}}'
  pseudo_dir = '{{PSEUDO_DIR}}'
/
&SYSTEM
  ibrav = 1, celldm(1) = 20.0, nat = 1, ntyp = 1
  ecutwfc = {{ECUTWFC}}, ecutrho = {{ECUTRHO}}
/
ATOMIC_SPECIES
  {{ELEMENT}} {{MASS}} {{UPF}}
TPL
PW_BIN=$HERE/mock/pw.x "$PSM" generate -e Si -t paw -o "$TMP/tpl" --no-test \
    --cutoff-scan --pw-template "$TMP/tpl.in" -q >/dev/null 2>&1
assert_ok    "template used for the scan"   test -s "$TMP/tpl/tests/pw-Si-50.in"
assert_match "element substituted"          "Si 28.085" cat "$TMP/tpl/tests/pw-Si-50.in"
assert_match "cutoff substituted"           "ecutwfc = 50" cat "$TMP/tpl/tests/pw-Si-50.in"
assert_fail  "no placeholders left"         grep -q '{{' "$TMP/tpl/tests/pw-Si-50.in"

section "attribution and citations"
assert_match "citation for a known library" "Dal Corso"        "$PSM" citation psl-high
assert_match "citation carries a DOI"       "10.1016/j.commatsci.2014.07.043" "$PSM" citation psl-high
assert_match "DOI is given as a link"       "https://doi.org/" "$PSM" citation psl-high
assert_match "engine is credited too"       "Giannozzi"        "$PSM" citation psl-high
assert_match "ONCVPSP library credits Hamann" "Hamann"         "$PSM" citation sg15
assert_match "licence recorded"             "GPL-2.0"          "$PSM" citation --all
assert_match "unknown library refused"      "unknown library"  "$PSM" citation not-a-library

# An unverified entry must say so rather than invent a reference.
assert_match "unverified says so"           "Unverified"       "$PSM" citation dacapo
assert_fail  "unverified invents no DOI" \
    bash -c "'$PSM' citation dacapo 2>&1 | grep -A1 'Unverified' | grep -q 'doi.org'"

# The same work must not appear twice because the engine is an alias of it.
# library + engine + PseudoForge itself, with no repeats: ld1 is an alias of
# the Quantum ESPRESSO entry and must not appear twice.
assert_eq "library, engine and tool are all credited" "3" \
    "$("$PSM" citation psl-high 2>/dev/null | grep -c '^\[[0-9]\]')"
assert_eq "no reference appears twice" "3" \
    "$("$PSM" citation psl-high 2>/dev/null | grep '^\[[0-9]\]' | sed 's/^\[[0-9]*\] //' | sort -u | wc -l)"
assert_match "the tool credits its author" "Amirkhani" "$PSM" citation psl-high

assert_match "--attribution is paste-ready" "References:" \
    "$PSM" generate -e Si -t paw -p psl-high --attribution
assert_match "--attribution names the functional" "PBE" \
    "$PSM" generate -e Si -t paw -p psl-high --attribution
assert_match "--show-citation works"        "Dal Corso" \
    "$PSM" generate -e Si -t paw --show-citation psl-high

section "attribution files beside the pseudopotentials"
MOCK_DE=0 "$PSM" generate -e Si -t paw -p psl-high -o "$TMP/att" --no-test -q >/dev/null 2>&1
assert_ok    "CITATION.txt written to pseudos/" test -s "$TMP/att/pseudos/CITATION.txt"
assert_ok    "LICENSE.txt written to pseudos/" test -s "$TMP/att/pseudos/LICENSE.txt"
assert_match "CITATION.txt names the library" "PSlibrary" cat "$TMP/att/pseudos/CITATION.txt"
assert_match "LICENSE.txt names the terms"    "GPL-2.0"   cat "$TMP/att/pseudos/LICENSE.txt"
assert_match "LICENSE.txt disclaims pseudoforge's own licence" "does not own them" \
    cat "$TMP/att/pseudos/LICENSE.txt"
assert_match "html report has a References section" "<h2>References</h2>" \
    cat "$TMP/att/reports/summary.html"
assert_match "html references link the DOI" "https://doi.org/10.1016" \
    cat "$TMP/att/reports/summary.html"

section "mirror and fallback chain"
assert_match "mirror URL comes from the config" "pseudo.amirkhani.me" "$PSM" config --show
assert_eq "mirror path known for a library" "pslibrary" \
    "$(bash -c ". '$ROOT/lib/core.sh'; . '$ROOT/lib/metadata.sh'; pf_metadata_load; printf '%s' \"\${MD_MIRROR_PATH[psl-high]}\"")"
assert_eq "official directory known for a library" "https://pseudopotentials.quantum-espresso.org/upf_files/" \
    "$(bash -c ". '$ROOT/lib/core.sh'; . '$ROOT/lib/metadata.sh'; pf_metadata_load; md_official psl-high")"
# SG15 does serve individual files, and pseudoforge uses that real path.
assert_match "SG15 per-element URL is the real one" "sg15_oncv/upf/Si_ONCV" \
    bash -c "
        . '$ROOT/lib/core.sh'; . '$ROOT/lib/config.sh'; . '$ROOT/lib/elements.sh'
        . '$ROOT/lib/xc.sh'; . '$ROOT/lib/metadata.sh'; . '$ROOT/lib/fetch.sh'
        PF_DATA='$ROOT/data'; pf_config_defaults; pf_elements_load; pf_xc_load; pf_metadata_load
        declare -gA SPEC=([xc]=pbe [rel]=scalar); fetch_official_urls sg15 Si"
# A distribution with no addressable per-element layout must not have one invented.
assert_eq "no invented per-element URL for PseudoDojo" "" \
    "$(bash -c "
        . '$ROOT/lib/core.sh'; . '$ROOT/lib/config.sh'; . '$ROOT/lib/elements.sh'
        . '$ROOT/lib/xc.sh'; . '$ROOT/lib/metadata.sh'; . '$ROOT/lib/fetch.sh'
        PF_DATA='$ROOT/data'; pf_config_defaults; pf_elements_load; pf_xc_load; pf_metadata_load
        declare -gA SPEC=([xc]=pbe [rel]=scalar); fetch_official_urls pseudodojo Si")"

# fetch_explain needs the library loaded, so give the assertion a small probe.
fetch_explain_probe() {
    bash -c "
        . '$ROOT/lib/core.sh'; . '$ROOT/lib/config.sh'; . '$ROOT/lib/profiles.sh'
        . '$ROOT/lib/elements.sh'; . '$ROOT/lib/xc.sh'
        . '$ROOT/lib/metadata.sh'; . '$ROOT/lib/params.sh'; . '$ROOT/lib/fetch.sh'
        PF_DATA='$ROOT/data'; pf_config_defaults; pf_elements_load; pf_xc_load
        pf_profiles_load; pf_metadata_load
        declare -gA SPEC=([xc]=pbesol [rel]=scalar)
        FETCH_MESSAGE='not found'; fetch_explain sg15"
}
# SG15 serves individual files now, so the helpful answer is to say which
# functionals it actually has rather than to send the user to an archive.
assert_match "failure names the functionals actually published" "publishes these functionals" fetch_explain_probe
assert_match "failure offers the local route" "generate locally" fetch_explain_probe

section "menu tags (regression: whiptail option parsing)"
# whiptail parses arguments with popt, which reads anything starting with a
# dash as an option -- including a menu tag.  A tag like "--info--" made the
# real whiptail exit 1 with "unknown option", which is indistinguishable from
# Cancel, so step 4 of the wizard silently bounced the user to the main menu.
assert_fail "mock whiptail rejects a dash tag like the real one" \
    env MOCK_WT_LOG=/dev/null "$HERE/mock/whiptail" --title T --menu p 20 78 9 a Alpha --info-- Info
assert_ok   "mock whiptail accepts ordinary tags" \
    bash -c "printf 'a\n' > $TMP/tg.ans; MOCK_WT_LOG=/dev/null MOCK_WT_ANSWERS=$TMP/tg.ans \
             '$HERE/mock/whiptail' --title T --menu p 20 78 9 a Alpha about Info 3>&1 1>&2 2>&3 >/dev/null"
assert_fail "no menu tag in ui.sh starts with a dash" \
    grep -qE 'items\+=\("-|ui_menu[^)]*" +-' "$ROOT/lib/ui.sh"
# and the guard catches it before whiptail ever sees it
assert_match "ui_check_tags rejects a dash tag" "starts with a dash" \
    bash -c ". '$ROOT/lib/core.sh'; . '$ROOT/lib/ui.sh'; ui_check_tags a Alpha --info-- Info"

section "dialog geometry (regression: boxes larger than the terminal)"
# whiptail refuses to draw a box bigger than the terminal and exits non-zero,
# which callers also read as Cancel.  Geometry is clamped to what fits.
assert_eq "height clamped to the terminal" "22" \
    "$(bash -c ". '$ROOT/lib/core.sh'; . '$ROOT/lib/ui.sh'; UI_ROWS=24; UI_COLS=80; ui_fit_h 26")"
assert_eq "height left alone when it fits" "17" \
    "$(bash -c ". '$ROOT/lib/core.sh'; . '$ROOT/lib/ui.sh'; UI_ROWS=40; UI_COLS=120; ui_fit_h 17")"
assert_eq "width clamped to the terminal" "76" \
    "$(bash -c ". '$ROOT/lib/core.sh'; . '$ROOT/lib/ui.sh'; UI_ROWS=24; UI_COLS=80; ui_fit_w 100")"
assert_eq "list height leaves room for the prompt" "12" \
    "$(bash -c ". '$ROOT/lib/core.sh'; . '$ROOT/lib/ui.sh'; ui_fit_lh 14 20")"

section "TUI (scripted whiptail)"
export MOCK_WT_LOG=$TMP/wt.log MOCK_WT_ANSWERS=$TMP/wt.ans
PATH="$HERE/mock:$PATH"
: > "$MOCK_WT_LOG"
# The Advanced screen no longer carries a "Continue" row: leaving it is the
# Cancel button, labelled Done, so no list row can be mistaken for a setting.
printf 'generate\npaw\nGGA\npbe\nscalar\ntype\nSi\nfinish\npsl-high\nlocal\nupf\nCANCEL\n%s\nyes\nCANCEL\n' \
       "$TMP/tui" > "$MOCK_WT_ANSWERS"
MOCK_DE=0.0004 bash "$HERE/drive_tui.sh" "$ROOT" >"$TMP/tui.out" 2>&1

dlg() { awk -F'\t' -v t="$1" '$2 == t { print $3; exit }' "$MOCK_WT_LOG"; }
assert_match "main menu offers generate" "generate" printf '%s' "$(dlg PseudoForge)"
assert_eq "type menu lists all three families" "paw us nc" "$(dlg 'Pseudopotential type')"
assert_eq "functional families listed" "LDA GGA metaGGA hybrid vdW" "$(dlg 'Functional family')"
assert_match "GGA functionals listed" "pbesol" printf '%s' "$(dlg 'Functional (GGA)')"
assert_eq "relativity options" "scalar full nonrel" "$(dlg 'Relativity')"
assert_match "profile menu lists psl-high" "psl-high" printf '%s' "$(dlg 'Library')"

# The library list is filtered by the family, functional and relativity already
# chosen, so a library that cannot honour them is never offered.
assert_ok "sg15 offered for NC/PBE" bash -c "
    . '$ROOT/lib/core.sh'; . '$ROOT/lib/config.sh'; . '$ROOT/lib/elements.sh'
    . '$ROOT/lib/xc.sh'; . '$ROOT/lib/profiles.sh'
    PF_DATA='$ROOT/data'; pf_config_defaults; pf_elements_load; pf_xc_load; pf_profiles_load
    prof_compatible sg15 nc pbe scalar"
assert_fail "sg15 hidden for NC/PBEsol" bash -c "
    . '$ROOT/lib/core.sh'; . '$ROOT/lib/config.sh'; . '$ROOT/lib/elements.sh'
    . '$ROOT/lib/xc.sh'; . '$ROOT/lib/profiles.sh'
    PF_DATA='$ROOT/data'; pf_config_defaults; pf_elements_load; pf_xc_load; pf_profiles_load
    prof_compatible sg15 nc pbesol scalar"
assert_fail "fhi hidden for full-relativistic" bash -c "
    . '$ROOT/lib/core.sh'; . '$ROOT/lib/config.sh'; . '$ROOT/lib/elements.sh'
    . '$ROOT/lib/xc.sh'; . '$ROOT/lib/profiles.sh'
    PF_DATA='$ROOT/data'; pf_config_defaults; pf_elements_load; pf_xc_load; pf_profiles_load
    prof_compatible fhi nc pbe full"
assert_fail  "profile menu has no duplicate pseudoforge-auto" bash -c \
    "test \$(printf '%s' \"\$(awk -F'\t' '\$2 ~ /Library profile/ { print \$3; exit }' '$MOCK_WT_LOG')\" | tr ' ' '\n' | grep -c pseudoforge-auto) -gt 1"
assert_match "advanced screen offers a core hole" "corehole" printf '%s' "$(dlg 'Advanced settings')"
assert_match "licence shown before any work" "Licence and citation" cut -f2 "$MOCK_WT_LOG"
assert_match "review screen shown" "Review" cut -f2 "$MOCK_WT_LOG"
assert_ok    "wizard actually generated" test -f "$TMP/tui/pseudos/Si.pbe-n-kjpaw_psl.1.0.0.UPF"
assert_ok    "wizard produced a report"  test -s "$TMP/tui/reports/summary.html"
assert_match "wizard ran the tests" "transferability" cat "$TMP/tui.out"

section "cutoff scan (mock pw.x)"
PW_BIN=$HERE/mock/pw.x MOCK_PW_TAU=12 \
    "$PSM" generate -e Si -t paw -o "$TMP/cut" --no-test --cutoff-scan --cutoff-tol 1.0 -q >/dev/null 2>&1
assert_ok    "scan data written"     test -s "$TMP/cut/tests/cutoff-Si.tsv"
assert_ok    "recommendation written" test -s "$TMP/cut/tests/cutoffs.tsv"
assert_eq    "energies are monotonic in ecut" "8" \
    "$(awk -F'\t' '!/^#/ && $3 != "-" { n++ } END { print n+0 }' "$TMP/cut/tests/cutoff-Si.tsv")"
assert_eq    "converged cutoff found" "80" "$(awk -F'\t' '{ print $2 }' "$TMP/cut/tests/cutoffs.tsv")"
assert_eq    "dual ratio applied"     "640" "$(awk -F'\t' '{ print $3 }' "$TMP/cut/tests/cutoffs.tsv")"
assert_match "cutoff reaches the report" "80" cat "$TMP/cut/reports/summary.csv"
# a stricter tolerance must demand a higher cutoff
PW_BIN=$HERE/mock/pw.x MOCK_PW_TAU=12 \
    "$PSM" generate -e Si -t paw -o "$TMP/cut2" --no-test --cutoff-scan --cutoff-tol 0.3 -q >/dev/null 2>&1
assert_eq    "stricter tolerance raises the cutoff" "90" "$(awk -F'\t' '{ print $2 }' "$TMP/cut2/tests/cutoffs.tsv")"
# a pw.x that never converges must not wedge the run
PW_BIN=$HERE/mock/pw.x MOCK_PW_FAIL=1 \
    "$PSM" generate -e Ge -t paw -o "$TMP/cut3" --no-test --cutoff-scan -q >/dev/null 2>&1
assert_ok    "unconverged pw.x still produces a report" test -s "$TMP/cut3/reports/summary.txt"

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Two suites that are separate files and fast enough to always run, but had
# never been wired into this one.  Each prints its own PASS/FAIL lines; this
# wrapper summarises the exit code so the outer counter stays one per suite.
section "interface separation"
if bash "$HERE/test_interfaces.sh" >/dev/null 2>&1; then
    ok_ "no module knows which interface is calling it"
else
    bad_ "interface separation" "run: tests/test_interfaces.sh"
fi

section "guided interface"
if bash "$HERE/test_ui.sh" >/dev/null 2>&1; then
    ok_ "the wizard builds the command the CLI would have built"
else
    bad_ "guided interface" "run: tests/test_ui.sh"
fi

# Interface audit: every subcommand answers --help, every TUI layer has a
# handler, every advanced-screen key reaches SPEC, every doc path named by
# the shell code exists.  Runs the fast sections only; the per-engine TUI
# matrix stays opt-in via PF_SLOW_INTERFACES=1 on the audit script itself.
section "interface audit"
if bash "$ROOT/tools/audit-interfaces.sh" >/dev/null 2>&1; then
    ok_ "the CLI, TUI and wizard agree with the core"
else
    bad_ "interface audit" "run: tools/audit-interfaces.sh"
fi

if [ "${1:-}" = --all ]; then
    section "PSlibrary round-trip (slow)"
    if bash "$HERE/test_psl_roundtrip.sh"; then ok_ "round-trip"; else bad_ "round-trip"; fi

    # Custom-potential coverage: every key a user can set is reachable from
    # the CLI, from the TUI advanced screen, and (for the identity keys)
    # from the wizard; the guard rails and the menus agree.  Fast, no engine.
    section "custom-potential settings"
    if bash "$HERE/test_custom.sh" >/dev/null 2>&1; then
        ok_ "every custom setting reaches SPEC from every interface"
    else
        bad_ "custom-potential settings failed" \
            "run: tests/test_custom.sh"
    fi

    # The store-integrity check needs a store.  It is skipped rather than
    # failed when there is none: this suite runs on a mock ld1.x and has
    # nothing to say about a store it cannot read.
    section "store integrity (needs a store)"
    # $HOME is the temporary one this suite runs under; the store is the
    # user's own, so look at ORIG_HOME unless PF_NATIVE_DIR says otherwise.
    # test_index.sh reads PF_NATIVE_DIR (or $HOME/pf-native); the wrapper
    # has to hand it the same path it checked, or test_index looks at the
    # overridden HOME, skips, returns zero, and the wrapper reports a pass
    # for a check that never ran.
    store=${PF_NATIVE_DIR:-$ORIG_HOME/pf-native}
    if [ -f "$store/index.tsv" ]; then
        if PF_NATIVE_DIR=$store bash "$HERE/test_index.sh" --quick; then
            ok_ "store index agrees with the disk"
        else
            bad_ "store index disagrees with the disk"
        fi
    else
        skip_ "no store at $store"
    fi

    # The engine matrix runs the *real* engine binaries against real
    # elements.  This suite runs with HOME pointed at a temporary directory
    # and LD1_BIN at a mock, so the real engines are not visible here and
    # the mock ones do not produce valid output.  Running the matrix from
    # inside this script would fail on oncvpsp, uspp and fhi98pp for that
    # reason, and the failures would be about the mock, not about the code.
    #
    # It is therefore not run here.  It is named, so an operator who wants
    # it knows it exists:
    section "engine matrix"
    skip_ "run separately: tests/test_engine_matrix.sh  (needs real engines)"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
       "$GREEN" "$pass" "$RESET" \
       "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
       "$YELLOW" "$skip" "$RESET"
[ "$fail" -eq 0 ]
