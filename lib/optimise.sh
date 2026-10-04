# shellcheck shell=bash
# ---------------------------------------------------------------------------
# optimise.sh -- choose the cut-off radii by measuring them.
#
#   pseudoforge optimise -e Si -t nc -x pbe --engine oncvpsp --cutoff-scan
#
# The trade every pseudopotential makes is between softness and accuracy:
# wider cut-off radii need fewer plane waves, and reproduce the all-electron
# atom less well away from the configuration they were fitted to. Choosing
# the radii has been left to the user -- by hand, per channel, or by scaling
# a published set with --rcut-scale. This sweeps that scale and picks, by a
# stated rule, from what the tool already measures.
#
# It adds no physics. Every number it ranks by is produced by the existing
# pipeline for an ordinary run: the engine's own success, the transferability
# test (ld1 iswitch=2, or the engine's own test configurations) and, when
# asked for, the pw.x cutoff scan. It runs `generate` once per scale, into its
# own directory, so each candidate is a complete, reproducible project.
#
# The rule
#
#   1. A candidate is eligible if it generated (ok or ok-warn) and its
#      transferability verdict is at least --min-grade (default: good).
#      "no-data" is never eligible: a radius choice made without measuring
#      transferability is a guess, and this command exists to replace one.
#   2. With cutoffs measured for every eligible candidate, the one with the
#      lowest converged ecutwfc wins; ties go to the better verdict, then the
#      smaller eigenvalue error, then the larger scale.
#   3. Without a cutoff scan, the largest eligible scale wins: wider radii are
#      softer, so it is the softest construction that still passes.
#
# What it does not do, said so it is not assumed: it scales all radii
# together, so the ratio between channels is the base recipe's. It does not
# fit a lattice constant; transferability and cutoff are the criteria.
#
# It works where --rcut-scale does -- ld1, oncvpsp, opium, ape -- and refuses
# elsewhere with the same reason generate gives.
# ---------------------------------------------------------------------------

OPT_DEFAULT_SCALES="0.85 0.90 0.95 1.00 1.05 1.10 1.20 1.30"

opt_grade_rank() {
    case $1 in
        excellent) echo 4 ;; good) echo 3 ;; marginal) echo 2 ;; poor) echo 1 ;;
        *) echo 0 ;;
    esac
}

# opt_choose <optimise.tsv> <min-rank>  ->  "<scale>\t<reason>", or fails.
#
# The rule in the header, as code, and on its own so it can be tested
# without running an engine. Rows: scale status verdict max_dE ecut file project.
# If any eligible row lacks a measured cutoff, cutoffs are not compared at all:
# ranking some candidates by cutoff and others by scale would compare a
# measurement with its absence.
opt_choose() {
    awk -F'\t' -v min="$2" '
        function rank(v) { return v == "excellent" ? 4 : v == "good" ? 3 : v == "marginal" ? 2 : v == "poor" ? 1 : 0 }
        /^#/ { next }
        ($2 == "ok" || $2 == "ok-warn") && rank($3) >= min {
            n++; S[n] = $1; R[n] = rank($3); D[n] = $4 + 0; E[n] = ($5 == "-" || $5 == "" ? "" : $5)
            if (E[n] == "") noecut = 1
        }
        END {
            if (!n) exit 1
            best = 1
            for (i = 2; i <= n; i++) {
                if (!noecut) {
                    if (E[i] + 0 < E[best] + 0) { best = i; continue }
                    if (E[i] + 0 > E[best] + 0) continue
                    if (R[i] > R[best]) { best = i; continue }
                    if (R[i] < R[best]) continue
                    if (D[i] < D[best]) { best = i; continue }
                    if (D[i] > D[best]) continue
                }
                if (S[i] + 0 > S[best] + 0) best = i
            }
            print S[best] "\t" (noecut ? "largest scale that passes (no cutoff scan)" : "lowest converged cutoff that passes")
        }' "$1"
}

cmd_optimise() {
    local el="" scales=$OPT_DEFAULT_SCALES min_grade=good out="" recipe="" desc=""
    local -a pass=()
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                sed -n '/^# optimise.sh/,/^# ------/p' "$PF_LIB/optimise.sh" | sed '1d;$d' | sed 's/^# \{0,1\}//'
                return 0 ;;
            -e|--elements) el=${2:-}; shift 2 ;;
            --scales)      scales=${2//,/ }; shift 2 ;;
            --min-grade)   min_grade=${2:-}; shift 2 ;;
            -o|--output)   out=${2:-}; shift 2 ;;
            --save-recipe) recipe=${2:-}; shift 2 ;;
            --rcut-scale)  die "optimise sets --rcut-scale itself; use --scales to choose the ladder" ;;
            *)             pass+=("$1"); shift ;;
        esac
    done

    [ -n "$el" ] || die "usage: pseudoforge optimise -e <element> [generate options] [--scales LIST] [--min-grade G] [--save-recipe NAME]"
    case $el in *,*|*' '*|*-*|all|block:*|series:*)
        die "optimise works on one element at a time; radii are chosen per element" ;; esac
    el=$(el_canon "$el") || die "unknown element: $el"
    case $min_grade in excellent|good|marginal|poor) ;;
        *) die "--min-grade must be excellent, good, marginal or poor" ;; esac
    local s
    for s in $scales; do
        awk -v f="$s" 'BEGIN { exit !(f + 0 > 0) }' || die "--scales: '$s' is not a positive number"
    done

    out=${out:-./optimise-$el}
    mkdir -p "$out" || die "cannot create $out"
    local psm=$PF_ROOT/pseudoforge minrank; minrank=$(opt_grade_rank "$min_grade")

    banner "Optimising $el: cut-off radius scale"
    info "ladder:    $scales"
    info "criterion: transferability at least $min_grade; then softest"
    info "runs:      $out/rc-<scale>/"
    printf '\n'

    local tsv=$out/optimise.tsv first=1
    printf '#scale\tstatus\tverdict\tmax_dE_Ry\tecutwfc\tfile\tproject\n' > "$tsv"
    printf '  %-6s %-8s %-10s %-11s %-8s %s\n' SCALE STATUS VERDICT 'MAX|dE|' ECUT FILE
    for s in $scales; do
        local proj=$out/rc-$s st verdict maxde ecut file
        rm -rf "$proj"
        "$psm" generate -e "$el" "${pass[@]}" --rcut-scale "$s" -o "$proj" > "$out/rc-$s.log" 2>&1
        # An engine without --rcut-scale is refused by generate before it runs;
        # that is the same answer for every scale, so stop at the first.
        if [ "$first" = 1 ] && grep -q 'not available with' "$out/rc-$s.log"; then
            # Through the sink, not straight to stderr: the same refusal has
            # to reach the JSON and web interfaces, not only a terminal.
            local line
            while IFS= read -r line; do
                error "$line"
            done < <(sed 's/\x1b\[[0-9;]*m//g' "$out/rc-$s.log" | grep -E 'ERROR' | sed 's/^ERROR */  /')
            die "optimise needs an engine that honours --rcut-scale"
        fi
        first=0
        st=$(awk -F'\t' -v e="$el" '$1 == e { v = $8 } END { print v }' "$proj/state.tsv" 2>/dev/null)
        file=$(awk -F'\t' -v e="$el" '$1 == e { v = $7 } END { print v }' "$proj/state.tsv" 2>/dev/null)
        verdict=$(awk -F'\t' -v e="$el" '$1 == e { v = $5 } END { print v }' "$proj/tests/transferability.tsv" 2>/dev/null)
        maxde=$(awk -F'\t' -v e="$el" '$1 == e { v = $3 } END { print v }' "$proj/tests/transferability.tsv" 2>/dev/null)
        ecut=$(awk -F'\t' -v e="$el" '$1 == e { v = $2 } END { print v }' "$proj/tests/cutoffs.tsv" 2>/dev/null)
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "${st:-fail}" "${verdict:-no-data}" \
            "${maxde:--}" "${ecut:--}" "${file:--}" "$proj" >> "$tsv"
        printf '  %-6s %-8s %-10s %-11s %-8s %s\n' "$s" "${st:-fail}" "${verdict:-no-data}" \
            "${maxde:--}" "${ecut:--}" "${file:--}"
    done

    # --- the choice ---------------------------------------------------------
    local choice
    choice=$(opt_choose "$tsv" "$minrank")

    printf '\n'
    if [ -z "$choice" ]; then
        local seen
        seen=$(awk -F'\t' '!/^#/ { print $3 }' "$tsv" | sort -u | paste -sd, -)
        error "no scale passed: every candidate either failed or fell below $min_grade"
        error "  verdicts seen: ${seen:-none}"
        case ,$seen, in *,no-data,*)
            error "  no-data means transferability was not measured for this engine/profile;"
            error "  a choice without that measurement would be a guess, so none is made." ;;
        esac
        return 1
    fi

    local best=${choice%%$'\t'*} why=${choice#*$'\t'}
    local brow; brow=$(awk -F'\t' -v s="$best" '$1 == s' "$tsv")
    printf '%s\n' "$best" > "$out/choice"
    ok "chosen: --rcut-scale $best  ($why)"
    info "  $(printf '%s' "$brow" | awk -F'\t' '{ printf "%s, max|dE| %s Ry%s -> %s", $3, $4, ($5 != "-" ? ", ecutwfc " $5 " Ry" : ""), $7 "/pseudos/" $6 }')"

    if [ -n "$recipe" ]; then
        desc="optimised $el: rcut-scale $best, $why; ladder $scales; min grade $min_grade"
        "$psm" recipe save "$recipe" -e "$el" "${pass[@]}" --rcut-scale "$best" \
            --description "$desc" || { error "the recipe could not be saved"; return 1; }
    else
        info "  reproduce with: pseudoforge generate -e $el ${pass[*]} --rcut-scale $best"
    fi
}
