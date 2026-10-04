#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The index agrees with the store on disk.
#
# The index is what the site serves from and what `pseudoforge native list`
# prints.  When it disagrees with the files it describes, the disagreement is
# silent: a download announced as gzip that arrives plaintext, a format id the
# profile does not declare, a row for a file that was deleted.  None of those
# fail loudly.
#
# This session found three real disagreements:
#
#   * .abinit, .cpmd and eleven other extensions were not in the gzip
#     pattern, so those files stayed plaintext while the index went on
#     writing `encoding=gzip` for them -- the server set Content-Encoding
#     from that field and a download would have arrived corrupt;
#   * `paw-abinit`, `paw-xml`, `gth-cpmd`, `gth-abinit`, `siesta` and
#     `openmx` were all mapped to their raw extension, so two different
#     formats shared one id;
#   * `state_should_run` looked for the plain name only, so --resume
#     after a gzip pass regenerated every element and left the plaintext
#     behind.
#
#   tests/test_index.sh               the default store
#   PF_NATIVE_DIR=/path tests/test_index.sh
#   tests/test_index.sh --quick       sample the per-file magic check
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

STORE=${PF_NATIVE_DIR:-$HOME/pf-native}
IDX=$STORE/index.tsv

QUICK=0
[ "${1:-}" = --quick ] && QUICK=1

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0

ok_()   { printf '  %sPASS%s  %s\n' "$GREEN"  "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED"    "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
section() { printf '\n%s== %s%s\n' "$DIM" "$1" "$RESET"; }

if [ ! -f "$IDX" ]; then
    skip_ "no index at $IDX"
    printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
    exit 0
fi

# What the build script would include, so the count can be checked.
# `find -L` because the store is often reached through a symlink, and
# without -L find reports only the link and stops.
count_disk() {
    find -L "$STORE" -type f \
        ! -name '*.provenance' \
        ! -name 'index.tsv*' \
        ! -name 'PROVENANCE.txt' \
        ! -name 'CITATION.txt' \
        ! -name '.rejected*' \
        ! -name '.*.tsv' \
        ! -name 'LICENSE.txt' \
        ! -name 'manifest' \
        ! -name 'state.tsv' \
        ! -name '*.log' \
        ! -name '*.in' \
        ! -name '*.out' \
        ! -path '*/.rejected/*' \
        ! -path '*/.stamps/*' \
        ! -path '*/logs/*' \
        ! -path '*/reports/*' \
        ! -path '*/tests/*' \
        ! -path '*/inputs/*' \
        -print 2>/dev/null | wc -l
}

# ---------------------------------------------------------------------------
section "the index and the disk agree on the count"

n_disk=$(count_disk)
n_idx=$(awk -F'\t' '$1 !~ /^#/' "$IDX" | wc -l)

[ "$n_disk" = "$n_idx" ] \
    && ok_ "$n_idx rows, $n_disk files on disk" \
    || bad_ "index has $n_idx rows, disk has $n_disk files" \
            "run: pseudoforge native index"

# ---------------------------------------------------------------------------
section "every file is what its name says"

# A .gz that is not gzip, or a plaintext file the index calls gzip, is the
# class of bug that reached a user once already.  Check both directions.
check_magic() {
    local want=$1 f m
    while IFS= read -r -d '' f; do
        m=$(head -c2 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
        if [ "$want" = gzip ] && [ "$m" != "1f8b" ]; then
            printf '%s\n' "$f"
        elif [ "$want" = plain ] && [ "$m" = "1f8b" ]; then
            printf '%s\n' "$f"
        fi
    done
}

# .gz files under pseudos/, excluding the two metadata files that are
# written next to them and are never compressed.
gz_bad=$(
    find -L "$STORE" -type f -path '*/pseudos/*' -name '*.gz' -print0 2>/dev/null \
        | if [ "$QUICK" = 1 ]; then
              # Sample one in fifty, still a few hundred files
              awk -v RS='\0' -v ORS='\0' 'NR % 50 == 0' | check_magic gzip
          else
              check_magic gzip
          fi
)
[ -z "$gz_bad" ] \
    && ok_ "every .gz is a real gzip stream" \
    || bad_ "file(s) named .gz that are not gzip:" "$(printf '%s' "$gz_bad" | head -3)"

# Plaintext under pseudos/ that is not one of the two metadata files.
plain_bad=$(
    find -L "$STORE" -type f -path '*/pseudos/*' \
        ! -name '*.gz' \
        ! -name 'CITATION.txt' \
        ! -name 'LICENSE.txt' \
        -print0 2>/dev/null \
        | if [ "$QUICK" = 1 ]; then
              awk -v RS='\0' -v ORS='\0' 'NR % 50 == 0' | check_magic plain
          else
              check_magic plain
          fi
)
[ -z "$plain_bad" ] \
    && ok_ "no unindexed plaintext beside the gzipped files" \
    || bad_ "plaintext file(s) beside a gzipped store:" "$(printf '%s' "$plain_bad" | head -3)"

# ---------------------------------------------------------------------------
section "the encoding column matches the file"

mismatched=0
checked=0
sample=""
while IFS=$'\t' read -r id el xc fam rel eng fmt prof enc path size sha prov; do
    case "$id" in "#"*|"") continue ;; esac
    f="$STORE/$path"
    [ -f "$f" ] || { mismatched=$((mismatched + 1)); continue; }
    checked=$((checked + 1))

    case $enc in
        gzip)
            m=$(head -c2 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
            if [ "$m" != "1f8b" ]; then
                mismatched=$((mismatched + 1))
                [ -z "$sample" ] && sample="$path (index=gzip, actual=plain)"
            fi ;;
        plain)
            m=$(head -c2 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
            if [ "$m" = "1f8b" ]; then
                mismatched=$((mismatched + 1))
                [ -z "$sample" ] && sample="$path (index=plain, actual=gzip)"
            fi ;;
        *)
            mismatched=$((mismatched + 1))
            [ -z "$sample" ] && sample="$path (unknown encoding '$enc')" ;;
    esac
done < "$IDX"

[ "$mismatched" -eq 0 ] \
    && ok_ "$checked rows: encoding matches the bytes on disk" \
    || bad_ "$mismatched of $checked rows disagree" "$sample"

# ---------------------------------------------------------------------------
section "the format column is a format the profile declares"

# Two formats that shared one raw extension before the fix:
#   .abinit -- atompaw's PAW dataset (paw-abinit) and cp2k-gth's psp3 layout
#              (gth-abinit).  A file labelled just "abinit" was one or the
#              other and the index could not say which.
#   .cpmd   -- opium's CPMD writer and cp2k-gth's CPMD layout.
# The profile disambiguates, and the check below is that the profile's
# decision actually made it into the index.
check_pair() {   # check_pair <profile> <format-id> <expected-min-count>
    local prof=$1 fmt=$2 min=$3 n
    n=$(awk -F'\t' -v p="$prof" -v f="$fmt" '$8 == p && $7 == f { n++ } END { print n + 0 }' "$IDX")
    if [ "$n" -ge "$min" ]; then
        ok_ "$prof: $n row(s) of $fmt"
    else
        bad_ "$prof: $n rows of $fmt, expected at least $min" \
             "the profile declares it and the files are on disk"
    fi
}

check_pair atompaw  paw-abinit  1
check_pair atompaw  paw-xml     1
check_pair atompaw  upf         1
check_pair cp2k-gth gth         1
check_pair cp2k-gth gth-cpmd    1
check_pair cp2k-gth gth-abinit  1

# The inverse: no row should still carry the bare *extension* where it used
# to stand for two formats.  Only extensions whose format id differs from the
# extension belong here.
#
#   abinit  ->  paw-abinit (atompaw) or gth-abinit (cp2k-gth); nothing should
#               be labelled "abinit"
#   psf     ->  siesta (opium's SIESTA writer); nothing should say "psf"
#   vps     ->  openmx (adpack); nothing should say "vps"
#
# `cpmd` is not on the list: it is a format id in its own right (opium's CPMD
# writer), and only cp2k-gth's CPMD layout is disambiguated, to gth-cpmd.  A
# row labelled `cpmd` is an opium file and correct.
for raw in abinit psf vps; do
    n=$(awk -F'\t' -v r="$raw" '$7 == r { n++ } END { print n + 0 }' "$IDX")
    [ "$n" -eq 0 ] \
        && ok_ "no rows labelled with the bare extension '$raw'" \
        || bad_ "$n row(s) still say '$raw'" \
                "run: pseudoforge native index"
done

# And the disambiguation worked in the other direction: opium's CPMD writer
# must still be labelled `cpmd`, not `gth-cpmd`.
n=$(awk -F'\t' -v p="opium" -v f="cpmd" '$8 == p && $7 == f { n++ } END { print n + 0 }' "$IDX")
[ "$n" -ge 1 ] \
    && ok_ "opium's CPMD output is labelled cpmd ($n rows)" \
    || bad_ "opium's CPMD output is missing" \
            "opium declares cpmd; the profile lookup should have kept it" 

# ---------------------------------------------------------------------------
printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$([ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM")" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
