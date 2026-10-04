#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# A stand-in for Quantum ESPRESSO's pw.x, used by the pseudoforge test suite to
# exercise the kinetic-energy cutoff scan without a QE build.
#
# It parses ecutwfc out of the input and returns a total energy that converges
# exponentially towards a limit, which is how a real cutoff scan behaves:
#
#     E(ecut) = E_inf + A * exp(-ecut / tau)
#
#   MOCK_PW_TAU=12     convergence scale in Ry (smaller = converges sooner)
#   MOCK_PW_FAIL=1     never reach self-consistency
# ---------------------------------------------------------------------------
set -uo pipefail

input=$(cat)

get() { printf '%s\n' "$input" | sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" | head -1 | tr -d "',"; }

ecutwfc=$(get ecutwfc)
ecutrho=$(get ecutrho)
prefix=$(get prefix)
[ -n "$ecutwfc" ] || ecutwfc=30

cat <<BANNER

     Program PWSCF v.7.4 starts (mock)

     Kinetic-energy cutoff     =  ${ecutwfc} Ry
     Charge density cutoff     =  ${ecutrho:-0} Ry
BANNER

if [ "${MOCK_PW_FAIL:-0}" = 1 ]; then
    echo "     convergence NOT achieved after 200 iterations: stopping"
    exit 1
fi

read -r etot press <<<"$(awk -v e="$ecutwfc" -v tau="${MOCK_PW_TAU:-12}" 'BEGIN {
    einf = -35.5
    a    = 0.85
    de   = a * exp(-e / tau)
    printf "%.8f %.2f", einf + de, 12.0 * de / a
}')"

cat <<RESULT

     End of self-consistent calculation

!    total energy              =    ${etot} Ry
     estimated scf accuracy    <       1.0E-11 Ry

     Computing stress (Cartesian axis) and pressure

          total   stress  (Ry/bohr**3)                   (kbar)     P=      ${press}

     PWSCF        :      0.50s CPU      0.60s WALL (mock)
RESULT
exit 0
