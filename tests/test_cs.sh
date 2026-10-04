#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Caesium, psl-low.
#
# Cs was the one element that failed the 52-element psl-low/US batch, with
# "implausible z_valence = -5.0".  The cause was upstream's own generation
# deck:
#
#     config='[Xe] 4f14 6s1 6p0 5d0'
#
# [Xe] is 54 electrons and does not contain 4f -- 4f first fills at Z=58 -- so
# that line asks for 68 electrons in an atom with Z=55.  ld1.x dutifully counts
# a core of 60, reports z_valence = 55 - 60 = -5, and writes a UPF that no code
# can use.  It exits 0 while doing it.
#
# The correction is one token, 4f14 -> 4f-1, which is ld1's marker for an
# unoccupied channel and is what upstream itself writes for Cs in the high set.
# The 4f channel is unoccupied and absent from the pseudo-wavefunction list, so
# the corrected deck is bit-for-bit identical to dropping 4f altogether.
#
# What this suite guards is not really the token.  The correction had *already*
# been made once, by hand, directly on the extracted template -- with no test,
# no changelog entry, and nothing to stop tools/extract_pslibrary.sh from
# wiping it on the next run, which it would have done, because extraction
# begins with rm -rf.  So the tests below check that the correction is declared
# in data/psl/ERRATA.tsv and reapplied by the extractor, not merely present on
# disk.  A correction that lives only in a file is one rm -rf from gone.
#
# The heavy paths need ld1.x and are gated behind PF_SLOW_TESTS=1.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats params engines; do
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
ERRATA=$PF_DATA/psl/ERRATA.tsv
BAD_CFG='[Xe] 4f14 6s1 6p0 5d0'
GOOD_CFG='[Xe] 4f-1 6s1 6p0 5d0'

printf '\n%s== the correction is declared, not just applied%s\n' "$DIM" "$RESET"
[ -f "$ERRATA" ] \
    && ok_ "data/psl/ERRATA.tsv exists" \
    || bad_ "no ERRATA.tsv" "a hand-edited template does not survive re-extraction"

for eset in us-low paw-low; do
    row=$(awk -F'\t' -v s="$eset" '$1 == s && $2 == "Cs" { print; exit }' "$ERRATA" 2>/dev/null)
    if [ -n "$row" ]; then
        ok_ "$eset/Cs has an erratum row"
        [ "$(printf '%s' "$row" | cut -f5)" = "$BAD_CFG" ] \
            && ok_ "  it records the exact upstream text" \
            || bad_ "  upstream text in the row is not what upstream ships"
        [ "$(printf '%s' "$row" | cut -f6)" = "$GOOD_CFG" ] \
            && ok_ "  it records the correction" \
            || bad_ "  correction in the row is not $GOOD_CFG"
        # The reason is the part a reader needs; a bare diff explains nothing.
        [ "$(printf '%s' "$row" | cut -f7 | wc -c)" -gt 120 ] \
            && ok_ "  it gives a reason with the measurement behind it" \
            || bad_ "  the reason field is too thin to check the claim against"
    else
        bad_ "$eset/Cs has no erratum row"
    fi
done

printf '\n%s== the shipped recipe carries the correction%s\n' "$DIM" "$RESET"
# This is the regression: if anyone re-extracts without the errata, or reverts
# the template by hand, these fail.
for eset in us-low paw-low; do
    tpl=$PF_DATA/psl/$eset/Cs.spnl.1.0.0.tpl
    if [ ! -f "$tpl" ]; then bad_ "$eset/Cs.spnl.1.0.0.tpl is missing"; continue; fi
    if grep -qF "$BAD_CFG" "$tpl"; then
        bad_ "$eset/Cs has reverted to the upstream config" \
             "z_valence would be -5.0 and the UPF unusable"
    else
        ok_ "$eset/Cs does not carry the impossible config"
    fi
    if grep -qF "config='$GOOD_CFG'" "$tpl"; then
        ok_ "$eset/Cs carries the corrected config"
    else
        bad_ "$eset/Cs config is neither upstream nor the declared correction" \
             "$(grep -m1 'config=' "$tpl")"
    fi
done

printf '\n%s== the extractor reapplies it%s\n' "$DIM" "$RESET"
EX=$ROOT/tools/extract_pslibrary.sh
grep -q 'apply_errata' "$EX" \
    && ok_ "the extractor has an errata stage" \
    || bad_ "extraction would silently drop the correction"
grep -q 'ERRATA_TMP' "$EX" \
    && ok_ "the errata are copied out before the tree is wiped" \
    || bad_ "rm -rf would delete ERRATA.tsv before it could be applied"
# sub() would read "[Xe]" as a character class and quietly not match.
awk '/^apply_errata\(\)/,/^}/' "$EX" | grep -q 'index($0, old)' \
    && ok_ "the rewrite is a literal splice, not a regex substitution" \
    || bad_ "the rewrite uses a regex" "[Xe] is a character class; it would not match"
awk '/^apply_errata\(\)/,/^}/' "$EX" | grep -q 'rewrite did not take' \
    && ok_ "a rewrite that does not take is an error, not a cheerful message" \
    || bad_ "the extractor could report a correction it did not make"
grep -q 'check_configs' "$EX" \
    && ok_ "extraction refuses to ship an impossible configuration" \
    || bad_ "nothing stops the next such defect from being extracted silently"

printf '\n%s== no generation deck asks for more electrons than it has%s\n' "$DIM" "$RESET"
# The class, not the instance.  Test decks (iswitch=2) are excluded: a charged
# reference configuration is a legitimate transferability probe, and upstream
# ships several of them deliberately.
impossible=$(for f in "$PF_DATA"/psl/*/*.tpl; do
    [ -e "$f" ] || continue
    grep -q 'iswitch=3' "$f" || continue
    awk -v f="$f" '
      BEGIN { c["[He]"]=2;  c["[Ne]"]=10; c["[Ar]"]=18
              c["[Kr]"]=36; c["[Xe]"]=54; c["[Rn]"]=86 }
      /zed=/    { if (match($0, /zed=[0-9.]+/)) z = substr($0, RSTART+4, RLENGTH-4) + 0 }
      /config=/ { if (match($0, /config=.[^\x27]*./)) {
                      s = $0
                      sub(/^[^\x27]*\x27/, "", s); sub(/\x27.*$/, "", s); cfg = s } }
      END {
        if (cfg == "" || z == 0) exit
        n = split(cfg, a, " "); t = 0
        for (i = 1; i <= n; i++) {
            if (a[i] in c) { t += c[a[i]]; continue }
            if (match(a[i], /^[0-9]+[spdfg]/)) {
                o = substr(a[i], RLENGTH + 1) + 0
                if (o > 0) t += o        # negative marks an unoccupied channel
            }
        }
        if (t > z + 0.001) printf "%s (zed=%g, config asks %g)\n", f, z, t
      }' "$f"
done)
[ -z "$impossible" ] \
    && ok_ "every generation deck is physically possible" \
    || bad_ "$(printf '%s' "$impossible" | grep -c .) deck(s) overfill the nucleus" "$impossible"

printf '\n%s== provenance names the correction%s\n' "$DIM" "$RESET"
declare -F psl_erratum >/dev/null \
    && ok_ "psl_erratum is available to the interfaces" \
    || bad_ "no lookup for errata"
psl_erratum us-low Cs spnl.1.0.0 >/dev/null 2>&1 \
    && ok_ "the Cs erratum is reachable through the library" \
    || bad_ "psl_erratum cannot find the Cs row"
psl_erratum us-low Si std >/dev/null 2>&1 \
    && bad_ "psl_erratum invents an erratum for an uncorrected recipe" \
    || ok_ "an uncorrected recipe reports no erratum"
grep -q 'recipe.erratum' "$PF_LIB/report.sh" \
    && ok_ "PROVENANCE.txt carries the erratum" \
    || bad_ "a corrected recipe would not say so in its provenance"

printf '\n%s== upstream really does have the defect%s\n' "$DIM" "$RESET"
# If upstream ever fixes it, the erratum must be retired rather than left to
# rewrite text that no longer says what we claim it says.
UP=${PSLIBRARY_DIR:-$HOME/Pseudo Maker/pslibrary.1.0.0}
if [ -f "$UP/us_ps_low.job" ]; then
    grep -qF "$BAD_CFG" "$UP/us_ps_low.job" \
        && ok_ "upstream us_ps_low.job still carries the impossible config" \
        || bad_ "upstream no longer has this defect -- retire the erratum"
    grep -qF "$BAD_CFG" "$UP/paw_ps_low.job" \
        && ok_ "upstream paw_ps_low.job still carries it too" \
        || bad_ "upstream paw deck changed -- recheck the erratum"
else
    skip_ "upstream PSlibrary not present (set PSLIBRARY_DIR to check)"
fi

printf '\n%s== it generates, and what it generates is right%s\n' "$DIM" "$RESET"
if [ "${PF_SLOW_TESTS:-0}" != 1 ]; then
    skip_ "generation gated behind PF_SLOW_TESTS=1 (measured: z_valence 9.0, transfer excellent, both families)"
else
    # The generation below goes through ./pseudoforge, which reads the user's
    # rc file; read it here too, or LD1_BIN is still the bare default and the
    # availability check answers a question nobody asked.
    [ -f "${PF_RC:-$HOME/.pseudoforgerc}" ] && . "${PF_RC:-$HOME/.pseudoforgerc}"
fi
if [ "${PF_SLOW_TESTS:-0}" = 1 ] \
   && [ ! -x "${LD1_BIN:-}" ] && ! command -v "${LD1_BIN:-ld1.x}" >/dev/null 2>&1; then
    skip_ "ld1.x not available (LD1_BIN=${LD1_BIN:-unset})"
elif [ "${PF_SLOW_TESTS:-0}" = 1 ]; then
    export OMP_NUM_THREADS=1
    for fam in us paw; do
        d=$TMP/cs-$fam
        ( cd "$ROOT" && ./pseudoforge generate -e Cs -p psl-low -t "$fam" -x pbe \
              -o "$d" >/dev/null 2>&1 )
        st=$(awk -F'\t' '$1 == "Cs" { print $8 }' "$d/state.tsv" 2>/dev/null)
        [ "$st" = ok ] && ok_ "$fam: Cs generates (status=$st)" \
                       || bad_ "$fam: Cs status=${st:-<none>}"
        upf=$(ls "$d"/pseudos/*.UPF 2>/dev/null | head -1)
        if [ -n "$upf" ]; then
            zv=$(grep -oE 'z_valence="[^"]*"' "$upf" | head -1 | tr -dc '0-9.-')
            # Cs is [Xe] 6s1; this recipe puts 5s2 5p6 6s1 in valence.
            case $zv in
                9|9.*) ok_ "$fam: z_valence = $zv, which is 5s2 5p6 6s1" ;;
                -*)    bad_ "$fam: z_valence = $zv is negative" "the original failure is back" ;;
                *)     bad_ "$fam: z_valence = $zv, expected 9" ;;
            esac
        else
            bad_ "$fam: no UPF produced"
        fi
        grade=$(awk -F'\t' '$1 == "Cs" { print $5 }' "$d/tests/transferability.tsv" 2>/dev/null)
        case $grade in
            excellent|good) ok_ "$fam: transferability is $grade" ;;
            '')             bad_ "$fam: no transferability verdict" ;;
            *)              bad_ "$fam: transferability is $grade, wanted good or better" ;;
        esac
        grep -q 'recipe.erratum=' "$d/PROVENANCE.txt" 2>/dev/null \
            && ok_ "$fam: the run admits it used a corrected recipe" \
            || bad_ "$fam: PROVENANCE.txt does not mention the erratum"
    done
fi

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
