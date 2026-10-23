#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ADPACK tests.
#
# ADPACK is the ninth engine and the one that needed a source patch before it
# would run at all: released 2.2 puts about 9 MB of radial work arrays on the
# stack in MBK() and segfaults partway through every element on a default 8 MB
# limit.  That fix touches no physics, and one test here checks exactly that.
#
# Three of these are regressions for mistakes made while wiring it up, all of
# the same shape -- a check that looked reasonable and rejected valid files:
#
#   - retargeting eq.type breaks the deck.  <log.deri.R> carries two values per
#     channel when eq.type is "dirac"; rewriting the keyword alone leaves that
#     table the wrong shape and ADPACK stops with "Format error for
#     log.deri.R", pointing at a block nobody touched.
#   - "Vps.public" is not a keyword in this format.  It was invented, and it
#     rejected every valid .vps.
#   - a bare "****" search flags the banner of asterisks the file opens with,
#     not a Fortran overflow.
#
# The deck logic runs without ADPACK installed; the rest skips if it is absent.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp params engines build recipe input_builder executor upf; do
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
SPEC[xc]=pz; SPEC[rel]=full; SPEC[family]=nc
SPEC[profile]=adpack; SPEC[engine]=adpack

printf '\n%s== bundled decks%s\n' "$DIM" "$RESET"
n=$(ls "$PF_DATA/params/adpack"/*_VPS.inp 2>/dev/null | wc -l)
[ "$n" = 29 ] && ok_ "29 vendor VPS decks bundled" || bad_ "$n VPS decks, expected 29"
[ -f "$PF_DATA/params/adpack/SOURCE.txt" ] \
    && ok_ "SOURCE.txt records where the decks came from" \
    || bad_ "no SOURCE.txt beside the bundled decks"

# The decks must be unmodified.  They are someone else's parameters.
if [ -d "$HOME/Pseudo Maker/adpack-modern/work" ]; then
    diffs=0
    for f in "$PF_DATA/params/adpack"/*_VPS.inp; do
        b=$(basename "$f")
        cmp -s "$f" "$HOME/Pseudo Maker/adpack-modern/work/$b" || diffs=$((diffs + 1))
    done
    [ "$diffs" = 0 ] \
        && ok_ "bundled decks are byte-identical to the distribution" \
        || bad_ "$diffs deck(s) differ from upstream" "these are the author's parameters and must not be edited"
else
    skip_ "upstream work/ not available to compare against"
fi

printf '\n%s== deck retargeting%s\n' "$DIM" "$RESET"
deck_for() {
    local line
    line=$(ib_build_adpack "$1" "$TMP" 2>/dev/null) || return 1
    printf '%s' "$line" | cut -d$'\x1f' -f1
}
d=$(deck_for Ti) || { echo "  could not build a Ti deck"; }
if [ -n "${d:-}" ] && [ -s "$d" ]; then
    ok_ "a deck is produced for Ti"

    # Only xc.type may differ from the published deck.
    nd=$(diff "$PF_DATA/params/adpack/Ti_VPS.inp" "$d" | grep -c '^[<>]')
    [ "$nd" -le 2 ] \
        && ok_ "only the functional line is retargeted ($nd changed line(s))" \
        || bad_ "$nd lines differ from the published deck" "everything but xc.type belongs to ADPACK"

    # eq.type must be left exactly as published -- see the header.
    got=$(awk '/^[[:space:]]*eq\.type/ { print $2; exit }' "$d")
    want=$(awk '/^[[:space:]]*eq\.type/ { print $2; exit }' "$PF_DATA/params/adpack/Ti_VPS.inp")
    [ "$got" = "$want" ] \
        && ok_ "eq.type is left as published ($got)" \
        || bad_ "eq.type rewritten $want -> $got" \
                "<log.deri.R> is shaped for the deck's solver; ADPACK stops with 'Format error for log.deri.R'"

    # and the block it is coupled to must still be intact
    rows=$(awk '/<log\.deri\.R/ { inb = 1; next } inb && /log\.deri\.R>/ { exit } inb { c++ } END { print c + 0 }' "$d")
    [ "$rows" -gt 0 ] && ok_ "the <log.deri.R> block survives retargeting ($rows rows)" \
        || bad_ "the <log.deri.R> block is missing from the retargeted deck"
else
    bad_ "no deck produced for Ti"
fi

# An element ADPACK does not ship must be refused, not synthesised.
if deck_for Si >/dev/null 2>&1; then
    bad_ "a deck was produced for Si" "ADPACK ships none; its radii and scheme were chosen by hand and cannot be invented"
else
    ok_ "an element with no published deck is refused rather than synthesised"
fi

printf '\n%s== functional mapping%s\n' "$DIM" "$RESET"
for pair in "pz:LDA" "pw:LDA" "pbe:GGA" "pbesol:GGA"; do
    SPEC[xc]=${pair%%:*}
    got=$(ib_adpack_xc 2>/dev/null)
    [ "$got" = "${pair#*:}" ] && ok_ "${pair%%:*} -> ${pair#*:}" || bad_ "${pair%%:*} -> '$got'"
done
# A meta-GGA request is proxied to PBE, as it is for every engine except
# AtomPAW, and lands on ADPACK's GGA.  What matters is that the substitution is
# visible, not that it is refused -- the deck must say GGA and the run must say
# it substituted.  (This assertion was wrong the first time it was written: it
# demanded a refusal, and the tool's uniform proxy behaviour was correct.)
SPEC[xc]=scan
got=$(ib_adpack_xc 2>/dev/null)
[ "$got" = GGA ]     && ok_ "a meta-GGA request is proxied to PBE and lands on ADPACK's GGA"     || bad_ "meta-GGA request gave '$got'"
[ "$(xc_generator scan)" = pbe ]     && ok_ "the proxy resolves to PBE for adpack, not to scan"     || bad_ "xc_generator(scan) = $(xc_generator scan) with adpack selected"
SPEC[xc]=pz

printf '\n%s== .vps validation%s\n' "$DIM" "$RESET"
# A minimal file carrying the three keywords a real .vps has, plus the banner
# of asterisks every ADPACK output opens with.
# Copied from real ADPACK output rather than typed out.  A hand-written
# fixture drifts: an earlier version of this test wrote "Pseudo.Potentials"
# without the angle bracket, which is not what the format uses, and it began
# failing the moment the validator was corrected to match the real delimiter.
real_vps=$(ls "$HERE/fixtures/vps"/*.vps 2>/dev/null | head -1)
if [ -n "$real_vps" ]; then
    cp "$real_vps" "$TMP/good.vps"
else
    skip_ "no .vps fixture to validate against"
    printf 'valence.electron 6.0
grid.num 1000
<Pseudo.Potentials
 1.0 -1.2
Pseudo.Potentials>
' > "$TMP/good.vps"
fi
out=$(vps_validate "$TMP/good.vps"); rc=$?
[ "$rc" = 0 ] \
    && ok_ "a valid .vps passes despite its asterisk banner" \
    || bad_ "valid .vps rejected: $out" "the banner is decoration, not a Fortran overflow"

printf '%s\n' "$out" | grep -q 'OpenMX' \
    && ok_ "the note says OpenMX rather than implying UPF" \
    || bad_ "no OpenMX note on a valid file"

# A real overflow sits inside a numeric row and must still be caught.
# Corrupt a real numeric row, so the test bites on the file shape that
# actually ships rather than on a synthetic one.
awk 'NF >= 3 && !done && $1 ~ /^-?[0-9]+\.[0-9]/ && $2 ~ /^-?[0-9]+\.[0-9]/ { $2 = "******"; done = 1 } { print }' \
    "$TMP/good.vps" > "$TMP/of.vps"
if vps_validate "$TMP/of.vps" >/dev/null 2>&1; then
    bad_ "a numeric-row overflow was not caught"
else
    ok_ "an overflow inside numeric data is still caught"
fi

# Truncation must be caught by structure, not by size.
grep -v 'Pseudo.Potentials' "$TMP/good.vps" > "$TMP/trunc.vps"
if vps_validate "$TMP/trunc.vps" >/dev/null 2>&1; then
    bad_ "a .vps with no potential table passed"
else
    ok_ "a missing Pseudo.Potentials block is caught"
fi

printf '\n%s== engine registration%s\n' "$DIM" "$RESET"
eng_exists adpack && ok_ "adpack is in the engine registry" || bad_ "adpack not registered"
in_list nc "${ENG_FAMILIES[adpack]:-}" && ok_ "declares the NC family" || bad_ "families: ${ENG_FAMILIES[adpack]:-none}"
[ "${ENG_NATIVE_UPF[adpack]:-}" = no ] \
    && ok_ "declares that it does not write UPF" \
    || bad_ "adpack claims native UPF"
[ -n "${ENG_VERSION[adpack]:-}" ] || pf_manifest_load
[ -n "${ENG_VERSION[adpack]:-}" ] \
    && ok_ "manifest records a version (${ENG_VERSION[adpack]})" \
    || bad_ "no manifest version for adpack"
fmt_exists openmx && ok_ "the openmx format is registered" || bad_ "openmx format missing"
fmt_engine_can adpack openmx && ok_ "adpack is declared as the openmx writer" || bad_ "adpack cannot write openmx"

printf '\n%s== the build fix changes no physics%s\n' "$DIM" "$RESET"
F=$HOME/Pseudo\ Maker/adpack-modern
if [ -f "$F/PATCH-stack-overflow.diff" ]; then
    # Every changed line must be a declaration, an allocation, a free, or a
    # comment.  A number appearing in the patch would mean a parameter moved.
    suspicious=$(grep -E '^[+-]' "$F/PATCH-stack-overflow.diff" \
        | grep -vE '^(\+\+\+|---)' \
        | grep -vE '^[+-][[:space:]]*(/\*|\*|//)' \
        | grep -E '[0-9]+\.[0-9]+' \
        | grep -vE 'ASIZE|sizeof|malloc|free|8 MB|9\.0 MB|4\.8 MB' | wc -l)
    [ "$suspicious" = 0 ] \
        && ok_ "no numeric parameter appears in the stack-overflow patch" \
        || bad_ "$suspicious line(s) in the patch carry a decimal number" \
                "a build fix must not touch a tolerance, radius or default"
    grep -q 'malloc' "$F/PATCH-stack-overflow.diff" \
        && ok_ "the patch is an allocation change" \
        || bad_ "the patch does not allocate -- is it still the stack fix?"
else
    skip_ "adpack-modern patch not present"
fi

printf '\n%s== build refusal%s\n' "$DIM" "$RESET"
build_out=$(build_engine adpack 2>&1 || true)
printf '%s\n' "$build_out" | grep -q 'installed externally' \
    && ok_ "pf build adpack reports external install" \
    || bad_ "pf build adpack did not report external install" "$build_out"
printf '%s\n' "$build_out" | grep -q 'no build recipe for' \
    && bad_ "pf build adpack fell through to 'no build recipe'" "$build_out" \
    || ok_ "pf build adpack does not say 'no build recipe'"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
