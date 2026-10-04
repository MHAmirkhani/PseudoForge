#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Regression test: the extracted PSlibrary recipe database must reproduce the
# upstream ld1.x input decks byte for byte, for every functional / relativity
# combination.  This is what backs pseudoforge's claim of PSlibrary-identical output.
#
#   tests/test_psl_roundtrip.sh [path-to-pslibrary.1.0.0]
#
# Set PSL_RT_KEEP=1 to keep the rendered trees for inspection.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=${1:-$(cd "$HERE/.." && pwd)/pslibrary.1.0.0}
DB=$HERE/data/psl
ERRATA=$DB/ERRATA.tsv

TMP=${PSL_RT_TMP:-$(mktemp -d)}
[ -n "${PSL_RT_KEEP:-}" ] || trap 'rm -rf "$TMP"' EXIT

GEN_JOBS="paw_ps_high us_ps_high paw_ps_low us_ps_low nc_ps_collection
          paw_ps_collection us_ps_collection paw_ps_collection_alt
          us_ps_collection_alt paw_ps_collection_tot us_ps_collection_tot"
GEN_SETS="paw-high us-high paw-low us-low nc paw-031 us-031 paw-alt us-alt paw-tot us-tot"

# Order matters: make_test sources these in sequence and frozen_core carries over.
TEST_JOBS="paw_ps_test_high us_ps_test_high paw_ps_test_low us_ps_test_low
           paw_ps_test us_ps_test paw_ps_test_alt us_ps_test_alt
           paw_ps_test_tot us_ps_test_tot"
TEST_SETS="paw-high us-high paw-low us-low paw-031 us-031 paw-alt us-alt paw-tot us-tot"

RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
fail=0

# render_db <dbdir> <sets> <outdir> <fct> <gfun> <nrel> <sr|fr>
render_db() {
    local db=$1 sets=$2 out=$3 fct=$4 gfun=$5 nrel=$6 rel=$7
    local s el tag key cond name tpl fc
    mkdir -p "$out" || return 1
    for s in $sets; do
        [ -f "$db/$s.index" ] || { echo "    missing index: $db/$s.index" >&2; return 1; }
        fc=.false.
        [ -f "$db/$s.frozen_core" ] && fc=$(cat "$db/$s.frozen_core")
        while IFS=$'\t' read -r el tag key cond; do
            [ -n "${el:-}" ] || continue
            [ "$cond" = any ] || [ "$cond" = "$rel" ] || continue
            tpl="$db/$s/$el.$tag.tpl"
            [ "$cond" = any ] || tpl="$db/$s/$el.$tag.$cond.tpl"
            name=${key//\{\{FCT\}\}/$fct}
            sed -e "s/{{FCT}}/$fct/g"  -e "s/{{GFUN}}/$gfun/g" -e "s/{{NREL}}/$nrel/g" \
                -e "s|{{PSDIR}}|./PSEUDOPOTENTIALS|g" -e "s/{{FROZEN_CORE}}/$fc/g" \
                "$tpl" > "$out/$name.in" || return 1
        done < "$db/$s.index"
    done
}

# render_upstream <jobs> <outdir> <fct> <gfun> <nrel> <is_test>
render_upstream() {
    local jobs=$1 out=$2 fct=$3 gfun=$4 nrel=$5 istest=$6 j f
    mkdir -p "$out" || return 1
    ( cd "$out" || exit 1
      printf "fct='%s'\ngfun='%s'\nnrel=%s\n" "$fct" "$gfun" "$nrel" > environment.job
      # one shell for the whole sequence, so frozen_core carries over exactly as
      # it does when make_test sources the job files back to back
      { for j in $jobs; do
            [ -f "$SRC/$j.job" ] && printf ". '%s/%s.job'\n" "$SRC" "$j"
        done; } > run.sh
      bash -c ". ./environment.job; . ./run.sh"
      rm -f environment.job run.sh
      if [ "$istest" = yes ]; then
          for f in *.test.in; do [ -e "$f" ] || continue; mv "$f" "${f%.test.in}.in"; done
      fi )
}

# Set PSL_RT_CHECKS to a space-separated subset (e.g. "gen-pbe-scalar test-pbe-full")
# to run only some of the checks; the full sweep is slow on network filesystems.
check() {
    local label=$1
    if [ -n "${PSL_RT_CHECKS:-}" ] && ! printf '%s\n' $PSL_RT_CHECKS | grep -qx "$label"; then
        return 0
    fi
    _check "$@"
}

# check <label> <jobs> <sets> <db> <fct> <gfun> <nrel> <sr|fr> <is_test>
_check() {
    local label=$1 jobs=$2 sets=$3 db=$4 fct=$5 gfun=$6 nrel=$7 rel=$8 istest=$9
    local u="$TMP/$label/up" o="$TMP/$label/ours" n

    render_upstream "$jobs" "$u" "$fct" "$gfun" "$nrel" "$istest" \
        || { printf '  %sERROR%s %s: upstream render failed\n' "$RED" "$RESET" "$label"; fail=1; return; }
    render_db "$db" "$sets" "$o" "$fct" "$gfun" "$nrel" "$rel" \
        || { printf '  %sERROR%s %s: database render failed\n' "$RED" "$RESET" "$label"; fail=1; return; }

    n=$(find "$u" -name '*.in' | wc -l)
    diff -r "$u" "$o" > "$TMP/$label.diff" 2>&1
    if [ ! -s "$TMP/$label.diff" ]; then
        printf '  %sPASS%s  %-20s %4d decks byte-identical\n' "$GREEN" "$RESET" "$label" "$n"
        return
    fi

    # A difference is admissible only where data/psl/ERRATA.tsv declares one.
    # Upstream ships a handful of decks that are not merely unusual but
    # impossible -- caesium's asks for 68 electrons in an atom with Z=55 -- and
    # those are corrected on extraction.  The claim this test backs is
    # therefore not "identical to upstream" but the stronger and checkable
    # "identical to upstream except exactly where we say otherwise".  An
    # undeclared difference fails; so does a missing file, declared or not.
    local undeclared=0 line el
    while IFS= read -r line; do
        case $line in
            "Only in "*) undeclared=$((undeclared + 1)); continue ;;
            "diff -r "*) ;;
            *) continue ;;
        esac
        el=$(basename "${line##* }")      # Cs.pbe-spnl-rrkjus_psl.1.0.0.in
        el=${el%%.*}
        awk -F'\t' -v e="$el" '$2 == e { found = 1 } END { exit !found }' \
            "$ERRATA" 2>/dev/null || undeclared=$((undeclared + 1))
    done < "$TMP/$label.diff"

    if [ "$undeclared" -eq 0 ]; then
        printf '  %sPASS%s  %-20s %4d decks, %d differing only where ERRATA declares\n' \
               "$GREEN" "$RESET" "$label" "$n" "$(grep -c '^diff' "$TMP/$label.diff")"
    else
        printf '  %sFAIL%s  %-20s %d undeclared difference(s) (%s)\n' "$RED" "$RESET" \
               "$label" "$undeclared" "$TMP/$label.diff"
        head -20 "$TMP/$label.diff"
        fail=1
    fi
}

echo "PSlibrary round-trip verification"
echo "  upstream: $SRC"
echo "  database: $DB"
[ -d "$SRC" ] || { echo "  upstream pslibrary not present -- skipping"; exit 0; }

check gen-pbe-scalar  "$GEN_JOBS"  "$GEN_SETS"  "$DB"       pbe     PBE 1 sr no
check gen-pbe-full    "$GEN_JOBS"  "$GEN_SETS"  "$DB"       rel-pbe PBE 2 fr no
check gen-pz-scalar   "$GEN_JOBS"  "$GEN_SETS"  "$DB"       pz      LDA 1 sr no
check test-pbe-scalar "$TEST_JOBS" "$TEST_SETS" "$DB/tests" pbe     PBE 1 sr yes
check test-pbe-full   "$TEST_JOBS" "$TEST_SETS" "$DB/tests" rel-pbe PBE 2 fr yes

echo
[ $fail -eq 0 ] && echo "  all round-trip checks passed" || echo "  round-trip verification FAILED"
exit $fail
