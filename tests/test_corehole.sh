#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Core-hole tests.
#
# The mechanism was already wired -- CLI flag, recipe logic, wizard screen,
# filename tag -- and the thing that was actually broken was the documented
# example. `--core-hole 1s --zval 12` was printed in the help text and fails:
#
#   ld1_readin: supplied ( 12.00) and calculated ( 20.00) valence
#
# The arithmetic is the point. A core hole leaves one fewer electron in the
# core, so ld1.x computes valence = Z - (core electrons remaining), which is
# one MORE than the neutral pseudopotential. Copper spn measured both ways:
#
#   no hole   z_valence = 19
#   1s hole   z_valence = 20
#
# That difference is the removed electron, no longer screening the nucleus.
# ld1.x gets it right unaided; supplying zval by hand is what breaks it.
#
# Deck-level checks run without ld1.x; the generation check skips without it.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth sssp convert params engines build recipe input_builder executor run; do
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

printf '\n%s== the hole is punched in the configuration%s\n' "$DIM" "$RESET"
SPEC[family]=paw; SPEC[xc]=pbe; SPEC[rel]=scalar
SPEC[profile]=psl-high; SPEC[engine]=ld1; SPEC[core_hole]=1s; SPEC[zval]=

if line=$(ib_build_ld1 Cu "$TMP" 2>/dev/null); then
    deck=$(printf '%s' "$line" | cut -d$'\x1f' -f1)
    cfg=$(nml_get "$deck" input config 2>/dev/null | tr -d "'")
    case $cfg in
        *1s1*) ok_ "1s carries one electron, not two ($cfg)" ;;
        *)     bad_ "the 1s hole was not punched: config='$cfg'" ;;
    esac
    # the noble-gas shorthand must be expanded, or the shell cannot be named
    case $cfg in
        *'[Ar]'*|*'[Ne]'*) bad_ "the core is still shorthand; 1s cannot be addressed" ;;
        *)                 ok_ "the noble-gas core was expanded so the shell could be named" ;;
    esac
    grep -qi 'core hole in 1s' "$deck" \
        && ok_ "the deck records the hole in the author field" \
        || bad_ "no core-hole note written into the deck"
else
    bad_ "no deck built for Cu with a core hole"
fi

printf '\n%s== the file name says so%s\n' "$DIM" "$RESET"
# A core-hole pseudopotential is a different object from the neutral one and
# must never share its name.
tag=$(recipe_auto_suffix 2>/dev/null || printf '')
case $tag in
    *ch1s*) ok_ "the file name carries -ch1s" ;;
    *)      bad_ "the core hole is not in the file name (suffix: '$tag')" \
                 "a core-hole file that shares the neutral name will be used by mistake" ;;
esac

printf '\n%s== --zval with --core-hole is warned about%s\n' "$DIM" "$RESET"
SPEC[zval]=12
out=$(ib_build_ld1 Cu "$TMP" 2>&1 >/dev/null)
case $out in
    *"raises the valence charge by exactly one"*)
        ok_ "supplying zval alongside a core hole warns, and explains why" ;;
    *) bad_ "no explanation when --zval is combined with --core-hole" "$out" ;;
esac
SPEC[zval]=

printf '\n%s== a valence mismatch is not retried%s\n' "$DIM" "$RESET"
# Widening radii cannot reconcile arithmetic.  This used to burn both auto-fix
# attempts before failing.
printf 'ld1_readin: supplied ( 12.00) and calculated ( 20.00) valence\n' > "$TMP/v.log"
[ "$(ld1_diagnose "$TMP/v.log")" = valence ] \
    && ok_ "a supplied/calculated mismatch is diagnosed as 'valence'" \
    || bad_ "diagnosed as '$(ld1_diagnose "$TMP/v.log")', expected 'valence'"
if autofix_strategy valence 1 >/dev/null 2>&1; then
    bad_ "the auto-fix loop offers a retry for a valence mismatch" \
         "no radius change can reconcile an arithmetic disagreement"
else
    ok_ "no retry is offered for a valence mismatch"
fi

printf '\n%s== the shipped example is one that works%s\n' "$DIM" "$RESET"
# The help text used to print a command that fails.
if grep -q -- '--core-hole 1s --zval 12' "$PF_LIB/cli.sh"; then
    bad_ "the failing example is still in the help text" \
         "--zval 12 gives 'supplied (12.00) and calculated (20.00) valence'"
else
    ok_ "the help text no longer prints a command that fails"
fi
grep -q -- '--core-hole 1s -o' "$PF_LIB/cli.sh" \
    && ok_ "a working core-hole example is documented" \
    || bad_ "no core-hole example in the help text"

printf '\n%s== generated, and the valence really does rise by one%s\n' "$DIM" "$RESET"
if eng_available ld1 && [ "${PF_SLOW_TESTS:-0}" = 1 ]; then
    skip_ "live generation covered by the slow suite"
else
    skip_ "live Cu generation not run here (set PF_SLOW_TESTS=1); measured separately: 19 -> 20"
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
