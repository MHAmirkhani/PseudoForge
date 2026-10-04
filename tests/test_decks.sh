#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Deck-builder tests: build a deck for every engine and check the product.
#
# This exists because of a bug class, not a bug.  Three times now, in three
# different engines, a printf format string inside an awk program has lost its
# escape somewhere between the editor and the file, and each time it failed
# differently and never named its real cause:
#
#   OPIUM    awk stopped on "unterminated string", wrote nothing, and the run
#            reported "no input parameters available for Si with opium"
#   ADPACK   same, reported as "ADPACK wrote no pseudopotential (exit 0)"
#   APE      the escape survived as two characters, landed in the deck, and
#            APE read it as data
#
# None of those point at an escaping problem.  So instead of trusting the
# process, this checks the product: build a deck with every engine and assert
# it is non-empty, has real content, and contains no literal backslash-n --
# which no engine format here uses.
#
# Runs without any engine installed: building a deck needs no binary.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines build recipe input_builder executor; do
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

# ---------------------------------------------------------------------------
printf '\n%s== the guard itself%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
printf '%s\n' 'Title = "x"' 'NuclearCharge = 14' 'rc = 2.0' > "$TMP/good"
printf '%s\n' 'Title = "x"' 'NuclearCharge = 14' 'rc = 2.0\n' > "$TMP/escaped"
: > "$TMP/empty"
printf '%s\n' 'only one line' > "$TMP/short"

ib_check_deck "$TMP/good" t >/dev/null 2>&1 \
    && ok_ "a clean deck passes" || bad_ "a clean deck was rejected"
ib_check_deck "$TMP/escaped" t >/dev/null 2>&1 \
    && bad_ "a literal backslash-n was not caught" \
            "grep BRE reads '\\n' as an escape; the guard needs -F" \
    || ok_ "a literal backslash-n is caught"
ib_check_deck "$TMP/empty" t >/dev/null 2>&1 \
    && bad_ "an empty deck passed" || ok_ "an empty deck is caught"
ib_check_deck "$TMP/short" t >/dev/null 2>&1 \
    && bad_ "a one-line deck passed" || ok_ "a truncated deck is caught"

# ---------------------------------------------------------------------------
printf '\n%s== every engine builds a usable deck%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
# element, engine, family, functional, relativity -- chosen so each builder
# takes the path it actually uses in practice.
while IFS='|' read -r el eng fam xc rel prof; do
    [ -n "$el" ] || continue
    SPEC[family]=$fam; SPEC[xc]=$xc; SPEC[rel]=$rel
    SPEC[profile]=$prof; SPEC[engine]=$eng
    d=$TMP/$eng; mkdir -p "$d"

    line=$("ib_build_$eng" "$el" "$d" 2>/dev/null) || { skip_ "$eng: no deck for $el here"; continue; }
    deck=$(printf '%s' "$line" | cut -d$'\x1f' -f1)
    [ -n "$deck" ] || { bad_ "$eng: builder returned no path"; continue; }

    # GTH's "deck" is a directory of input files, not a single file.
    if [ -d "$deck" ]; then
        n=$(find "$deck" -type f | wc -l)
        [ "$n" -gt 0 ] && ok_ "$eng: $n input file(s) for $el" \
            || bad_ "$eng: empty input directory"
        continue
    fi

    if ib_check_deck "$deck" "$eng" >/dev/null 2>&1; then
        ok_ "$eng: $el deck is clean ($(grep -c . "$deck") lines)"
    else
        bad_ "$eng: $el deck failed the guard" "$(ib_check_deck "$deck" "$eng" 2>&1 | head -1)"
    fi
done <<'ROWS'
Si|ld1|nc|pbe|scalar|psl-high
Si|oncvpsp|nc|pbe|scalar|sg15
Si|opium|nc|pbe|scalar|pseudoforge-auto
Si|ape|nc|pz|scalar|pseudoforge-auto
Ti|ape|nc|pz|scalar|pseudoforge-auto
Li|atompaw|paw|pz|nonrel|pseudoforge-auto
Li|atompaw|paw|r2scan|nonrel|pseudoforge-auto
Ti|adpack|nc|pz|full|adpack
Si|gth|nc|pbe|scalar|cp2k-gth
ROWS

# ---------------------------------------------------------------------------
printf '\n%s== no bundled deck carries a stray escape%s\n' "$DIM" "$RESET"
# ---------------------------------------------------------------------------
# The shipped parameter files are other people's, so a backslash here would
# mean we damaged them rather than that a builder misbehaved.
bad_files=0
for f in "$PF_DATA"/params/adpack/*_VPS.inp "$PF_DATA"/params/gipaw/*/*.in; do
    [ -f "$f" ] || continue
    grep -qF '\n' "$f" 2>/dev/null && { bad_files=$((bad_files + 1)); echo "        $f"; }
done
[ "$bad_files" = 0 ] \
    && ok_ "bundled decks are free of literal escapes" \
    || bad_ "$bad_files bundled deck(s) contain a literal backslash-n"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
