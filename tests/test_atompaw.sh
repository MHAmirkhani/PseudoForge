#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# AtomPAW deck-shape tests.
#
# The deck is an ordered answer sheet, not a namelist, and atompaw validates
# none of it.  Every mistake in it is silent in a different way:
#
#   one radius too many  -> read as the answer to the output-format menu, and
#                           the run dies with "Option not recognized 1.78"
#   one radius too few   -> "ABINITOUT" is read as a number
#   an extra projector on a channel that already has a valence shell
#                        -> two near-identical basis functions, a singular
#                           overlap matrix, "failure of ovlp diagonalization"
#   no extra projector when the valence is a single shell
#                        -> one projector, negative overlap eigenvalue,
#                           "your PAW basis is incomplete"
#
# Both rules were established by sweeping the periodic table, not read out of
# the manual: topping every channel up to two projectors passed 21 of 22
# elements before and 10 of 47 after; extras only on empty channels passes 47
# of 47.  These tests pin that shape so it cannot drift back.
#
# They check the deck rather than run the engine, so they need no atompaw.
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

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0
ok_()  { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_() { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

SPEC[xc]=pz; SPEC[rel]=scalar; SPEC[family]=paw; SPEC[profile]=pseudoforge-auto
SPEC[engine]=atompaw

# deck_for <element> -- build one and echo the path
deck_for() {
    local el=$1 line
    line=$(ib_build_atompaw "$el" "$TMP" 2>/dev/null) || return 1
    printf '%s' "$line" | cut -d$'\x1f' -f1
}

# The number of radii between the VANDERBILT line and the first output keyword.
radii_count() {
    awk '/^VANDERBILT/ { seen = 1; getline; next }
         seen && /^[A-Z]/ { exit }
         seen && NF == 1 { n++ }
         END { print n + 0 }' "$1"
}

# The basis size the deck implies: valence shells plus every "y" extra.
basis_count() {
    local d=$1 nv nx
    # valence shells are the "n l occ" lines before the 0 0 0 terminator
    nv=$(awk 'NR > 3 { if ($1 == "0" && $2 == "0" && $3 == "0") exit; if (NF == 3) n++ } END { print n + 0 }' "$d")
    # extras are the y answers in the projector interview
    nx=$(awk '/^VANDERBILT/ { exit } /^y$/ { n++ } END { print n + 0 }' "$d")
    printf '%s\n' "$(( nv + nx ))"
}

printf '\n%s== deck shape%s\n' "$DIM" "$RESET"
for el in H Li C O Na Al Si Ca Fe Cu Zr Ag W Au; do
    d=$(deck_for "$el") || { bad_ "$el: no deck built"; continue; }
    r=$(radii_count "$d"); b=$(basis_count "$d")
    if [ "$r" = "$b" ]; then
        ok_ "$el: $r radii for $b basis functions"
    else
        bad_ "$el: $r radii but $b basis functions" \
             "atompaw would read the surplus as an output-menu choice, or eat ABINITOUT as a number"
    fi
done

printf '\n%s== projector rules%s\n' "$DIM" "$RESET"
# Sodium: one valence shell, so it must gain a p channel to scatter into.
d=$(deck_for Na)
if [ "$(awk '/^VANDERBILT/ { exit } /^y$/ { n++ } END { print n + 0 }' "$d")" -ge 1 ]; then
    ok_ "Na (single valence shell) gains an extra projector"
else
    bad_ "Na got no extra projector" "one projector gives a negative overlap eigenvalue: 'PAW basis is incomplete'"
fi

# Calcium: 4s is occupied, so l=0 must NOT gain a duplicate.
d=$(deck_for Ca)
first_answer=$(awk '/^VANDERBILT/ { exit } /^[yn]$/ { print; exit }' "$d")
if [ "$first_answer" = n ]; then
    ok_ "Ca does not add a duplicate projector to its occupied s channel"
else
    bad_ "Ca added an extra l=0 projector" "a near-duplicate basis function makes the overlap matrix singular"
fi

printf '\n%s== functional guard%s\n' "$DIM" "$RESET"
SPEC[xc]=blyp
if ib_build_atompaw Si "$TMP" >/dev/null 2>&1; then
    bad_ "BLYP was accepted" "this build has no libxc; it must refuse rather than silently substitute LDA"
else
    ok_ "an unsupported functional is refused, not substituted"
fi
SPEC[xc]=pz

printf '\n%s%d passed%s, %s%d failed%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET"
[ "$fail" -eq 0 ]
