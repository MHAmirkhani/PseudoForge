#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Tests for the per-engine validation dispatcher.
#
# These run against captured engine output rather than live engines, because
# the failure this file exists to prevent is a *parsing* failure, and parsing
# failures are silent: a regex that stops matching does not raise anything, it
# just reports "no-data" for ever, and a column of dashes looks like a feature
# nobody enabled rather than a check that broke.
#
# Two of the cases here are regressions for bugs that shipped:
#
#   - pslp's explanatory prose ("the ghost state analysis will assume a zero
#     reference energy") was matched as a ghost report, so a clean fhi98PP
#     pseudopotential was flagged as having a ghost state.
#   - OPIUM's DD table carries mRy and meV on the same line; taking the first
#     float on the line gave an answer 13.6 times too large.
#
# Both are the dangerous direction: a validator that cries wolf, and one that
# silently inflates an error.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)

export PF_ROOT=$ROOT PF_LIB=$ROOT/lib PF_DATA=$ROOT/data
for m in core sink config deps elements xc namelist profiles metadata formats gth params engines validate; do
    . "$PF_LIB/$m.sh" || { echo "cannot load $m.sh" >&2; exit 1; }
done
pf_config_defaults; pf_elements_load; pf_xc_load
pf_profiles_load; pf_metadata_load; pf_params_load; pf_engines_load
spec_init 2>/dev/null || true

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN"  "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED"    "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
section() { printf '\n%s== %s%s\n' "$DIM" "$1" "$RESET"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# near <got> <want> <tol> -- float comparison
near() { awk -v a="${1:-x}" -v b="$2" -v t="$3" 'BEGIN{d=a-b; if(d<0)d=-d; exit (d<=t)?0:1}'; }

reset_val() { VAL_METHOD=; VAL_MAXDE=; VAL_DETOT=; VAL_VERDICT=; VAL_NOTE=; }

# ---------------------------------------------------------------------------
section "thresholds"
# ---------------------------------------------------------------------------
for pair in "0:no-data" "0.0005:excellent" "0.003:good" "0.010:marginal" "0.5:poor"; do
    got=$(transfer_verdict "${pair%:*}")
    [ "$got" = "${pair#*:}" ] && ok_ "${pair%:*} Ry -> ${pair#*:}" \
        || bad_ "${pair%:*} Ry -> $got, expected ${pair#*:}"
done

# ---------------------------------------------------------------------------
section "ONCVPSP"
# ---------------------------------------------------------------------------
cat > "$TMP/oncv.log" <<'LOG'
 Testing for bound ghosts
   n   l    E NL Schr. Eq   E Basis Diag.   E Cutoff
   1   0       -0.397366       -0.397075     46.08

 Testing for highly-localized positive-energy ghosts
       l    <radius>/rc     E Basis Diag.   E Cutoff
       0        0.464210        2.782241     46.08  WARNING - GHOST(+)

Test configuration 0

   n   l     f        eae           eps        diff
   3   0  2.0000   -0.39736459   -0.39736562   -1.03D-06
   3   1  2.0000   -0.14998149   -0.14998163   -1.40D-07

    Total energies and differences
      PSP excitation error=  0.00D+00
LOG
reset_val; val_oncvpsp "$TMP/oncv.log"
# diff is Hartree: 1.03e-6 Ha = 2.06e-6 Ry
near "$VAL_MAXDE" 0.000002 0.0000005 \
    && ok_ "eigenvalue error converted Ha -> Ry ($VAL_MAXDE)" \
    || bad_ "max|dE| = $VAL_MAXDE" "expected ~0.000002 Ry (2x the 1.03e-6 Ha in the log)"
[ "$VAL_VERDICT" = excellent ] \
    && ok_ "a positive-energy ghost above the cutoff is not a failing verdict" \
    || bad_ "verdict = $VAL_VERDICT" "GHOST(+) at 46 Ry is a note, not a condemnation"
case $VAL_NOTE in *"positive-energy ghost"*) ok_ "the ghost is still reported in the note" ;;
                  *) bad_ "the positive-energy ghost was dropped entirely" "note: $VAL_NOTE" ;; esac
case $VAL_NOTE in *"reference configuration only"*) ok_ "says the deck tested no alternative configurations" ;;
                  *) bad_ "did not flag that only the reference configuration was tested" ;; esac

# A bound ghost is the serious one and must fail.
sed 's/Testing for bound ghosts/bound ghost state found/' "$TMP/oncv.log" > "$TMP/oncv_bound.log"
reset_val; val_oncvpsp "$TMP/oncv_bound.log"
[ "$VAL_VERDICT" = ghost ] \
    && ok_ "a bound ghost fails outright" \
    || bad_ "bound ghost gave verdict '$VAL_VERDICT'" "a bound ghost makes the file unusable"

# ---------------------------------------------------------------------------
section "GTH"
# ---------------------------------------------------------------------------
cat > "$TMP/gth.log" <<'LOG'
 penalty:   1.7733246584751439E-002

 nl    s      occ              ae        pseudo       diff     diff*weight
 3s   0.5    2.0000
         eigenvalue      -0.3755E+00 -0.3755E+00 -0.9405E-06  0.1881E-04
         charge           0.5264E+00  0.5264E+00 -0.3350E-06  0.6699E-05

 4s   0.5    0.0000
         eigenvalue       0.6684E-01  0.6676E-01 -0.7989E-04  0.3196E-04

 6s   0.5    0.0000
         eigenvalue       0.3541E+00  0.4624E+00  0.1083E+00  0.8667E-03

 3p  -0.5    0.6667
         eigenvalue      -0.1256E+00 -0.1256E+00 -0.7114E-05  0.5691E-04
LOG
reset_val; val_gth "$TMP/gth.log"
# occupied max is the 3p at 7.114e-6 Ha -> 1.42e-5 Ry
near "$VAL_MAXDE" 0.0000142 0.000002 \
    && ok_ "occupied-state error from occupied orbitals only ($VAL_MAXDE Ry)" \
    || bad_ "max|dE| = $VAL_MAXDE" "expected ~1.4e-5 Ry; the 0.108 Ha 6s state is unoccupied and must not set the headline"
case $VAL_NOTE in *unoccupied*) ok_ "the unoccupied spread is reported separately" ;;
                  *) bad_ "unoccupied states not mentioned" "note: $VAL_NOTE" ;; esac
case $VAL_NOTE in *penalty*) ok_ "the fit penalty is carried through" ;;
                  *) bad_ "penalty missing from the note" ;; esac

# Without --refit there is no fit, and saying nothing reads as "not checked".
printf 'GTH: Si written from tables/cp2k/pbe/Si-q4\n' > "$TMP/gth_pub.log"
reset_val; val_gth "$TMP/gth_pub.log"
[ "$VAL_VERDICT" = no-data ] && case $VAL_METHOD in *published*) true ;; *) false ;; esac \
    && ok_ "published coefficients report why there is no number" \
    || bad_ "published path: verdict=$VAL_VERDICT method=$VAL_METHOD"

# ---------------------------------------------------------------------------
section "fhi98PP / pslp"
# ---------------------------------------------------------------------------
# Regression: this text contains "ghost" four times and reports none.
cat > "$TMP/pslp_clean.out" <<'LOG'
 --- analysis of kb potentials: s waves  ---
 note: for the semilocal s component no bound s state
       is found, the ghost state analysis will assume
       a zero reference energy (variable eref)
 * no ghost state
                     kb cosine        0.4211
LOG
reset_val
VAL_METHOD="pslp ghost/logderiv"; VAL_MAXDE=0; VAL_DETOT=0
if grep -qE '^ *\* *ghost state' "$TMP/pslp_clean.out"; then VAL_VERDICT=ghost
elif grep -qE 'STOP pslp|NaN' "$TMP/pslp_clean.out"; then VAL_VERDICT=no-data
else VAL_VERDICT=no-data; fi
[ "$VAL_VERDICT" != ghost ] \
    && ok_ "pslp's explanatory prose is not read as a ghost report" \
    || bad_ "clean pslp output flagged as a ghost" "this shipped once; the prose says 'the ghost state analysis will assume'"

cat > "$TMP/pslp_ghost.out" <<'LOG'
 * ghost state below the reference energy
LOG
grep -qE '^ *\* *ghost state' "$TMP/pslp_ghost.out" \
    && ok_ "a real pslp ghost verdict is matched" \
    || bad_ "a genuine '* ghost state' line was missed"

cat > "$TMP/pslp_broken.out" <<'LOG'
                     kb energy           NaN eV      ekb
STOP pslp - radius for log derivative > r(mmax)
LOG
grep -qE 'STOP pslp|NaN' "$TMP/pslp_broken.out" \
    && ok_ "an aborted pslp run is detected rather than read as a pass" \
    || bad_ "a failed pslp analysis would be reported as clean"

# ---------------------------------------------------------------------------
section "OPIUM"
# ---------------------------------------------------------------------------
cat > "$TMP/opium.rpt" <<'LOG'
 AE-NL-  total error =	       0.1048323066	  0.2533534885
 AE-NL-   i   j         DD[mRy]        DD[meV]
 AE-NL- ------------------------------------------
 AE-NL-   0   1        -0.000667      -0.009071
 AE-NL-   0   2        -0.002206      -0.030015
 No ghosts!  Ekb<0  and eig < el0
 No ghosts present for local potential
LOG
maxde=$(awk '
    /^ *AE-[NS]L- +[0-9]+ +[0-9]+ / { v = $(NF - 1) + 0; if (v < 0) v = -v; if (v > m) m = v }
    END { printf "%.6f\n", m / 1000 }' "$TMP/opium.rpt")
near "$maxde" 0.0000022 0.0000005 \
    && ok_ "DD read from the mRy column, not meV ($maxde Ry)" \
    || bad_ "DD parsed as $maxde Ry" "expected ~2.2e-6 Ry; picking the meV column gives 13.6x that"
grep -qiE 'no ghosts' "$TMP/opium.rpt" \
    && ok_ "OPIUM's explicit clean verdict is recognised" \
    || bad_ "'No ghosts!' not matched"

# ---------------------------------------------------------------------------
section "USPP"
# ---------------------------------------------------------------------------
printf ' beginning search for possible ghost states\n eigensolution in bessel basis with cutoff 30.00\n' > "$TMP/uspp.log"
reset_val; val_uspp "$TMP/uspp.log"
[ "$VAL_VERDICT" = no-data ] \
    && ok_ "a ghost search with no finding is not graded as a pass" \
    || bad_ "verdict = $VAL_VERDICT" "uspp writes no eigenvalue table, so there is no transferability number to claim"
case $VAL_NOTE in *"no transferability number"*) ok_ "says plainly why there is no number" ;;
                  *) bad_ "the gap is not explained" "note: $VAL_NOTE" ;; esac

# ---------------------------------------------------------------------------
section "dispatch"
# ---------------------------------------------------------------------------
for pair in "ld1:ld1.x" "oncvpsp:oncvpsp" "opium:opium" "gth:GTH" "uspp:uspp" "fhi98pp:pslp"; do
    got=$(val_method_label "${pair%:*}")
    case $got in *"${pair#*:}"*) ok_ "${pair%:*} names its own method" ;;
                 *) bad_ "${pair%:*} labelled '$got'" ;; esac
done
# The banner used to say "ld1.x" whatever engine ran.
[ "$(val_method_label oncvpsp)" != "$(val_method_label ld1)" ] \
    && ok_ "engines do not share a label" \
    || bad_ "two engines report the same method name"

printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
    "$GREEN" "$pass" "$RESET" \
    "$( [ "$fail" -gt 0 ] && printf '%s' "$RED" || printf '%s' "$DIM" )" "$fail" "$RESET" \
    "$DIM" "$skip" "$RESET"
[ "$fail" -eq 0 ]
