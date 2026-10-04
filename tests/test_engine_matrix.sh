#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Every engine, every format it declares, checked end to end.
#
# The per-engine tests each check one thing well: test_gth.sh the coefficient
# conversion, test_atompaw.sh the deck shape, test_engine_output.sh the
# rcut-scale refusal.  None of them runs the whole matrix: nine engines,
# each family, each format the registry says they write, with the engine
# named explicitly so a profile default cannot silently substitute for it.
#
#   tests/test_engine_matrix.sh                every engine
#   tests/test_engine_matrix.sh opium          only opium
#   PF_MATRIX_QUICK=1 tests/test_engine_matrix.sh    first format only
#   PF_MATRIX_VERBOSE=1 tests/test_engine_matrix.sh  keep each run's log
#
# Engines that are not installed are skipped, not failed.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PSM=$ROOT/pseudoforge

WANT=${1:-all}
QUICK=${PF_MATRIX_QUICK:-0}
VERBOSE=${PF_MATRIX_VERBOSE:-0}
TIMEOUT=${PF_MATRIX_TIMEOUT:-300}

export PF_VAR_DIR=${PF_VAR_DIR:-$HOME/pf-var}
export PF_NATIVE_DIR=${PF_NATIVE_DIR:-$HOME/pf-var/native}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0

ok_()   { printf '  %sPASS%s  %s\n' "$GREEN"  "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED"    "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
section() { printf '\n%s== %s%s\n' "$DIM" "$1" "$RESET"; }

# ---------------------------------------------------------------------------
# The matrix: engine|profile|family|element|xc|rel|formats
#
# Each element is chosen so the engine's own constraints are respected, and
# each xc/rel is one the profile declares.  OPIUM has two rows because its
# scalar and fully-relativistic writers produce different format sets: the
# scalar run writes nine files, the full run two, and the seven that refuse
# full relativity do so inside the engine.
# ---------------------------------------------------------------------------
MATRIX=(
    "ld1|psl-high|nc|Si|pbe|scalar|upf xml"
    "ld1|psl-high|us|Si|pbe|scalar|upf xml"
    "ld1|psl-high|paw|Si|pbe|scalar|upf xml"
    "oncvpsp|sg15|nc|Si|pbe|scalar|upf psp8 xml"
    "uspp|gbrv|us|Si|pbe|scalar|upf uspp van xml"
    "fhi98pp|fhi|nc|Si|pw|scalar|cpi"
    "opium|opium|nc|Fe|pz|scalar|upf fhi recpot siesta cpmd casino champ qso ncpp"
    "opium|opium|nc|Fe|pz|full|upf teter"
    "gth|cp2k-gth|nc|Si|pbe|scalar|gth gth-cpmd gth-abinit"
    "atompaw|atompaw|paw|Si|pbe|scalar|upf paw-xml paw-abinit"
    "ape|pseudoforge-auto|nc|Si|pbe|scalar|upf"
    "adpack|adpack|nc|Na|pz|full|openmx"
)

if [ "$QUICK" = 1 ]; then
    q=()
    for row in "${MATRIX[@]}"; do
        IFS='|' read -r e p f el xc r fmts <<< "$row"
        first=${fmts%% *}
        q+=("$e|$p|$f|$el|$xc|$r|$first")
    done
    MATRIX=("${q[@]}")
fi

format_ext() {
    awk -F'\t' -v id="$1" '!/^#/ && $1 == id { print $4; exit }' "$ROOT/data/formats.tsv"
}

format_has_validator() {
    case $1 in
        upf|psp8|gth|openmx|cpi|paw-xml|xml) return 0 ;;
        *) return 1 ;;
    esac
}

# find_file <dir> <element> <format-id>
# Each format has a filename suffix the engine writes; the registry's
# extension column is the suffix after the last dot.  qso is special: it
# writes <El>.<tags>.qso.xml, which ends in .xml, so matching on the full
# suffix would need the trailing ".qso" too.  A plain -name "*.<ext>" match
# finds it, and no other .xml is present in an opium run.
# find_file <dir> <element> <format-id>
#
# Most engines name their output <El>.<tags>.<ext>, but fhi98PP writes
# <El>.cpi directly -- a single dot.  Both patterns are tried, and the
# one with the tag is preferred when it matches, because fhi98PP can
# also write a .UPF alongside and the shorter pattern would catch both.
find_file() {
    local dir=$1 el=$2 fmt=$3 ext f
    ext=$(format_ext "$fmt"); [ -n "$ext" ] || ext=$fmt
    f=$(find "$dir/pseudos" -maxdepth 4 -type f -name "$el.*.$ext" 2>/dev/null | head -1)
    [ -n "$f" ] || f=$(find "$dir/pseudos" -maxdepth 4 -type f -name "$el.$ext" 2>/dev/null | head -1)
    printf '%s' "$f"
}

engine_installed() { "$PSM" engines path "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
section "matrix"

for row in "${MATRIX[@]}"; do
    IFS='|' read -r eng prof fam el xc rel fmts <<< "$row"

    [ "$WANT" = all ] || [ "$WANT" = "$eng" ] || continue

    if ! engine_installed "$eng"; then
        skip_ "$eng not installed"
        continue
    fi

    out=$TMP/$eng-$fam-$el-$rel
    fmt_csv=$(printf '%s' "$fmts" | tr ' ' ',')
    start=$(date +%s)

    if ! timeout "$TIMEOUT" "$PSM" generate -e "$el" -t "$fam" -p "$prof" \
            --engine "$eng" -x "$xc" -r "$rel" --format "$fmt_csv" \
            -o "$out" --no-test -q >"$TMP/$eng-$fam-$el-$rel.log" 2>&1; then
        bad_ "$eng/$fam/$el/$rel -- generate failed" \
             "$(tail -3 "$TMP/$eng-$fam-$el-$rel.log")"
        continue
    fi

    got=0; total=0
    missing=""; invalid=""

    for f in $fmts; do
        total=$((total + 1))
        file=$(find_file "$out" "$el" "$f")
        if [ -z "$file" ] || [ ! -s "$file" ]; then
            missing="$missing $f"
            continue
        fi
        got=$((got + 1))
        if format_has_validator "$f"; then
            if ! "$PSM" validate "$file" >/dev/null 2>&1; then
                invalid="$invalid $f"
            fi
        fi
    done

    elapsed=$(( $(date +%s) - start ))
    label="$eng/$fam/$el/$rel"

    if [ -n "$missing" ]; then
        bad_ "$label -- $got/$total (missing:$missing)  ${elapsed}s"
    elif [ -n "$invalid" ]; then
        bad_ "$label -- $got/$total (validator rejected:$invalid)  ${elapsed}s"
    else
        ok_ "$label -- $got/$total formats valid  ${elapsed}s"
    fi
done

# ---------------------------------------------------------------------------
section "manifest records the engine"

for row in "${MATRIX[@]}"; do
    IFS='|' read -r eng prof fam el xc rel fmts <<< "$row"
    [ "$WANT" = all ] || [ "$WANT" = "$eng" ] || continue
    engine_installed "$eng" || continue

    out=$TMP/$eng-$fam-$el-$rel
    man=$out/manifest

    if [ ! -s "$man" ]; then
        bad_ "$eng/$fam/$el/$rel -- no manifest written"
        continue
    fi

    got_eng=$(awk -F= '$1 == "engine" { print $2; exit }' "$man")
    if [ "$got_eng" = "$eng" ]; then
        ok_ "$eng/$fam/$el/$rel -- manifest records engine=$got_eng"
    else
        bad_ "$eng/$fam/$el/$rel -- manifest records engine=${got_eng:-missing}, expected $eng"
    fi
done

# ---------------------------------------------------------------------------
section "resume after gzip does not regenerate"

# The bug this guards against: build-native-store.sh gzips each run's output
# after the fact, and a later --resume pass looked for the plain name only.
# It saw the file missing and regenerated it, and the gzip step then refused
# to overwrite the existing .gz and the plaintext stayed -- doubling the
# store and making the index disagree with the disk.
#
# The fix is in state_should_run: a .gz beside the plain name counts as the
# same file.  This section gzips each row's pseudos/ and runs generate again
# with the same arguments; the second run must skip every element, leave the
# .gz files alone, and write no new plaintext.

for row in "${MATRIX[@]}"; do
    IFS='|' read -r eng prof fam el xc rel fmts <<< "$row"
    [ "$WANT" = all ] || [ "$WANT" = "$eng" ] || continue
    engine_installed "$eng" || continue

    out=$TMP/$eng-$fam-$el-$rel
    [ -d "$out/pseudos" ] || continue

    # The state.tsv says which element's file the run recorded.  Every row
    # here is one element, so a re-run should be a complete no-op.
    before_count=$(find "$out/pseudos" -maxdepth 1 -type f 2>/dev/null | wc -l)
    before_gz=$(find "$out/pseudos" -maxdepth 1 -name '*.gz' -type f 2>/dev/null | wc -l)

    # Gzip every pseudopotential the first run produced, leaving the two
    # metadata files alone -- that is what build-native-store.sh does.
    find "$out/pseudos" -maxdepth 1 -type f         ! -name '*.gz' ! -name 'CITATION.txt' ! -name 'LICENSE.txt'         -print0 2>/dev/null \
        | xargs -0 -r gzip -9 -n 2>/dev/null

    after_gzip_count=$(find "$out/pseudos" -maxdepth 1 -type f 2>/dev/null | wc -l)
    after_gzip_gz=$(find "$out/pseudos" -maxdepth 1 -name '*.gz' -type f 2>/dev/null | wc -l)

    # Second run with the same args.  --resume is the default; the run
    # should report "already done" for every element and write nothing.
    fmt_csv=$(printf '%s' "$fmts" | tr ' ' ',')
    timeout "$TIMEOUT" "$PSM" generate -e "$el" -t "$fam" -p "$prof" \
        --engine "$eng" -x "$xc" -r "$rel" --format "$fmt_csv" \
        -o "$out" --no-test -q >"$TMP/$eng-$fam-$el-$rel.resume.log" 2>&1

    final_count=$(find "$out/pseudos" -maxdepth 1 -type f 2>/dev/null | wc -l)
    final_gz=$(find "$out/pseudos" -maxdepth 1 -name '*.gz' -type f 2>/dev/null | wc -l)
    plain_after=$(find "$out/pseudos" -maxdepth 1 -type f \
        ! -name '*.gz' ! -name 'CITATION.txt' ! -name 'LICENSE.txt' 2>/dev/null | wc -l)

    label="$eng/$fam/$el/$rel"
    if [ "$plain_after" -ne 0 ]; then
        bad_ "$label -- resume wrote $plain_after plaintext file(s)" \
             "state_should_run did not recognise the gzipped name"
    elif [ "$final_gz" -ne "$after_gzip_gz" ]; then
        bad_ "$label -- resume changed the .gz count ($after_gzip_gz -> $final_gz)"
    elif [ "$final_count" -ne "$after_gzip_count" ]; then
        bad_ "$label -- resume changed the file count ($after_gzip_count -> $final_count)"
    else
        ok_ "$label -- resume was a no-op ($after_gzip_gz .gz files)"
    fi
done

# ---------------------------------------------------------------------------
if [ "$VERBOSE" = 1 ]; then
    section "logs"
    for f in "$TMP"/*.log; do
        [ -s "$f" ] || continue
        printf '\n── %s ──\n' "$(basename "$f")"
        tail -20 "$f"
    done
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
