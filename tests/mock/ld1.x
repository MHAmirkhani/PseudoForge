#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# A stand-in for Quantum ESPRESSO's ld1.x, used by the pseudoforge test suite so
# the execution, auto-fix, validation and reporting paths can be exercised on
# machines without a QE build.
#
# It reads a deck on stdin exactly as ld1.x does, writes a structurally valid
# UPF into the current directory, and can be told to fail in the same ways the
# real code fails:
#
#   MOCK_FAIL_ELEMENTS="Fe:chi:2 Cu:augmentation:1"
#       fail for that element, with that class of error, that many times before
#       finally succeeding -- this is what drives the auto-fix loop
#   MOCK_FAIL_ALWAYS="Xe"           never succeed for these elements
#   MOCK_WARN_ELEMENTS="Ni"         succeed but emit an ld1.x "!" warning
#   MOCK_TRUNCATE="Zn"              write a truncated UPF (validation must catch it)
#   MOCK_NAN="Cd"                   write NaN into the radial data
# ---------------------------------------------------------------------------
set -uo pipefail

deck=$(cat)

get() {   # get <namelist-key>
    printf '%s\n' "$deck" | sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" |
        head -1 | sed "s/,[[:space:]]*$//; s/^'//; s/'$//"
}

title=$(get title)
zed=$(get zed)
upf=$(get file_pseudopw)
dft=$(get dft)
rel=$(get rel)
lpaw=$(get lpaw)
ptype=$(get pseudotype)
nlcc=$(get nlcc)
augfun=$(get which_augfun)
beta=$(get beta)
v1=$(get upf_v1_format)
gipaw=$(get lgipaw_reconstruction)

el=${title:-X}
ncards=$(printf '%s\n' "$deck" | awk '/^[[:space:]]*\/[[:space:]]*$/ { last = NR } { l[NR] = $0 }
                                       END { for (i = last + 1; i <= NR; i++) if (l[i] != "") { print l[i]; exit } }')
[ -n "$ncards" ] || ncards=0

cat <<BANNER

     Program LD1 v.7.4 starts (mock)

     Atomic calculation for $el   Z = ${zed:-0}
     dft = ${dft:-PBE}   rel = ${rel:-1}   pseudotype = ${ptype:-3}
BANNER

fail_with() {   # fail_with <routine> <message>
    cat <<ERR

     %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
     Error in routine $1 (1):
     $2
     %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

     stopping ...
ERR
    exit 2
}

# --- transferability test mode (iswitch=2) ---------------------------------
# Emit output shaped like ld1.x's own test report so the pseudoforge parser is
# exercised.  MOCK_DE sets the eigenvalue error it reports, in Ry.
iswitch=$(get iswitch)
if [ "${iswitch:-3}" = 2 ]; then
    nconf=$(get nconf); nconf=${nconf:-1}
    de=${MOCK_DE:-0.0004}
    for ((c = 1; c <= nconf; c++)); do
        cfg=$(printf '%s\n' "$deck" | sed -n "s/^[[:space:]]*configts($c)[[:space:]]*=[[:space:]]*//p" | tr -d "',")
        cat <<CONF

     Configuration: $cfg

      n l     nl                  e AE (Ry)        e PS (Ry)    De AE-PS (Ry)
CONF
        awk -v d="$de" -v c="$c" 'BEGIN {
            split("2S 2P 3S 3P 3D", nm, " ")
            for (i = 1; i <= 3; i++)
                printf "      %d %d     %-4s 1( 2.00)   %14.7f   %14.7f   %12.7f\n",
                       i, i - 1, nm[i], -1.0 - i, -1.0 - i + d * c, d * c
        }'
        printf '\n     dEtot_ae = %12.7f Ry\n' "-1.234567"
        printf '     dEtot_ps = %12.7f Ry,   Delta E= %12.7f Ry\n' "-1.234000" "0.000567"
    done
    echo "     LD1      : done (mock test)"
    exit 0
fi

# --- always-fail list ------------------------------------------------------
for spec in ${MOCK_FAIL_ALWAYS:-}; do
    [ "$spec" = "$el" ] && fail_with compute_chi "no convergence in the pseudo-wavefunction"
done

# --- fail the first N attempts, then succeed --------------------------------
# MOCK_FAIL_ELEMENTS="Fe:chi:2" means "fail Fe twice with a chi error, then let
# the third attempt through", which is exactly what the auto-fix loop must cope
# with.  Attempt counting is kept in MOCK_STATE_DIR.
state_dir=${MOCK_STATE_DIR:-${TMPDIR:-/tmp}/pseudoforge-mock}
mkdir -p "$state_dir" 2>/dev/null
for spec in ${MOCK_FAIL_ELEMENTS:-}; do
    name=${spec%%:*}
    rest=${spec#*:}
    kind=${rest%%:*}
    times=${rest#*:}
    [ "$name" = "$el" ] || continue
    [ "$times" = "$kind" ] && times=1
    seen=0
    [ -f "$state_dir/$el" ] && seen=$(cat "$state_dir/$el")
    seen=$((seen + 1))
    printf '%s' "$seen" > "$state_dir/$el"
    [ "$seen" -gt "$times" ] && break
    case $kind in
        chi)          fail_with compute_chi "no convergence in the pseudo-wavefunction" ;;
        augmentation) fail_with find_qi     "problems with the augmentation functions" ;;
        scf)          fail_with ascheq      "convergence is not achieved in the all-electron atom" ;;
        paw)          fail_with paw_setup   "cannot build the PAW data set" ;;
        *)            fail_with pseudovloc  "unexpected trouble in the local channel" ;;
    esac
done
echo "     pseudopotential written to $upf"
for spec in ${MOCK_WARN_ELEMENTS:-}; do
    [ "$spec" = "$el" ] && echo "     !  the local potential has a ghost state at 0.35 Ry"
done

# --- write the UPF ---------------------------------------------------------
[ -n "$upf" ] || exit 0

zval=$(printf '%s\n' "$deck" | awk '/^[[:space:]]*\/[[:space:]]*$/ { last = NR } { l[NR] = $0 }
        END { s = 0
              for (i = last + 2; i <= NR; i++) if (l[i] != "") { split(l[i], f, " "); if (f[4] > 0) s += f[4] }
              printf "%.2f", s }')
[ -n "$zval" ] && [ "$zval" != "0.00" ] || zval=4.00

case $lpaw in .true.) ptype_str=PAW ;; *) [ "${ptype:-3}" = 2 ] && ptype_str=NC || ptype_str=US ;; esac
case $nlcc in .true.) nlcc_str=T ;; *) nlcc_str=F ;; esac

grid() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "  %.8E%s", i * 0.01, (i % 4 == 0 ? "\n" : "") ; printf "\n" }'; }

if [ "$v1" = ".true." ]; then
    {
        echo "<PP_INFO>"
        echo "  Generated using mock ld1.x for the pseudoforge test suite"
        echo "</PP_INFO>"
        echo "<PP_HEADER>"
        printf '   0                   Version Number\n'
        printf '  %-4s                 Element\n' "$el"
        printf '   %-4s                %s pseudopotential\n' "$ptype_str" "$ptype_str"
        printf '    %s                  Nonlinear Core Correction\n' "$nlcc_str"
        printf ' SLA  PW   PBX  PBC    %s  Exchange-Correlation functional\n' "${dft:-PBE}"
        printf '   %s      Z valence\n' "$zval"
        printf '  45.0000000  360.0000 Suggested cutoff for wfc and rho\n'
        printf '    2                  Max angular momentum component\n'
        printf '  %s                   Number of Projectors\n' "$ncards"
        printf '  %s                   Number of Wavefunctions\n' "$ncards"
        echo "</PP_HEADER>"
        echo "<PP_MESH>"; echo "<PP_R>"; grid 12; echo "</PP_R>"; echo "</PP_MESH>"
        [ "$nlcc_str" = T ] && { echo "<PP_NLCC>"; grid 12; echo "</PP_NLCC>"; }
        echo "<PP_LOCAL>"; grid 12; echo "</PP_LOCAL>"
        echo "<PP_NONLOCAL>"; echo "</PP_NONLOCAL>"
        echo "<PP_RHOATOM>"
        if [ "${MOCK_NAN:-}" = "$el" ]; then echo "  NaN  NaN  NaN  NaN"; else grid 12; fi
        [ "${MOCK_TRUNCATE:-}" = "$el" ] && exit 0
        echo "</PP_RHOATOM>"
    } > "$upf"
else
    {
        echo '<UPF version="2.0.1">'
        echo '  <PP_INFO>'
        echo '    Generated using mock ld1.x for the pseudoforge test suite'
        echo '  </PP_INFO>'
        printf '  <PP_HEADER generated="mock ld1.x" author="pseudoforge-test" date="%s"\n' "$(date +%Y%m%d)"
        printf '     element="%-2s" pseudo_type="%s" relativistic="%s"\n' "$el" "$ptype_str" \
               "$([ "${rel:-1}" = 2 ] && echo full || echo scalar)"
        printf '     is_ultrasoft="%s" is_paw="%s" core_correction="%s"\n' \
               "$([ "$ptype_str" = US ] && echo T || echo F)" \
               "$([ "$ptype_str" = PAW ] && echo T || echo F)" "$nlcc_str"
        printf '     functional="%s" z_valence="%s" ecutwfc="45.000" ecutrho="360.000"\n' "${dft:-PBE}" "$zval"
        printf '     l_max="2" number_of_wfc="%s" number_of_proj="%s"/>\n' "$ncards" "$ncards"
        echo '  <PP_MESH><PP_R>'; grid 12; echo '  </PP_R></PP_MESH>'
        [ "$nlcc_str" = T ] && { echo '  <PP_NLCC>'; grid 12; echo '  </PP_NLCC>'; }
        echo '  <PP_LOCAL>'; grid 12; echo '  </PP_LOCAL>'
        echo '  <PP_NONLOCAL></PP_NONLOCAL>'
        [ "$gipaw" = ".true." ] && echo '  <PP_GIPAW></PP_GIPAW>'
        echo '  <PP_RHOATOM>'
        if [ "${MOCK_NAN:-}" = "$el" ]; then echo '  NaN  NaN  NaN  NaN'; else grid 12; fi
        echo '  </PP_RHOATOM>'
        [ "${MOCK_TRUNCATE:-}" = "$el" ] && exit 0
        echo '</UPF>'
    } > "$upf"
fi

echo "     LD1      : done (mock)"
exit 0
