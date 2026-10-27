# shellcheck shell=bash
# ---------------------------------------------------------------------------
# cutoff.sh -- recommend plane-wave kinetic energy cutoffs for any element
#
# Sources of truth:
#   1. User project scans (tests/cutoffs.tsv in -o <project-dir>)
#   2. SSSP verification tables (SSSP v1.3.0 efficiency & precision)
#   3. PseudoDojo parameters (ONCVPSP qcut)
#
# Never guess. If neither table nor scan covers it, refuse.
# ---------------------------------------------------------------------------

declare -g CUT_ELEMENT=""
declare -g CUT_ACCURACY="efficiency"
declare -g CUT_XC="PBE"
declare -g CUT_WFC=""
declare -g CUT_RHO=""
declare -g CUT_SOURCE=""
declare -g CUT_LIBRARY=""
declare -g CUT_PROVENANCE=""

cutoff_for() {
    local el=${1:-} acc=${2:-efficiency} xc=${3:-PBE} proj=${4:-}
    [ -n "$el" ] || return 1

    pf_elements_load 2>/dev/null || true
    pf_xc_load 2>/dev/null || true

    CUT_ELEMENT="$el"
    CUT_ACCURACY="$acc"
    CUT_XC="$xc"
    CUT_WFC=""
    CUT_RHO=""
    CUT_SOURCE=""
    CUT_LIBRARY=""
    CUT_PROVENANCE=""

    # 1. User project scan (-o <project-dir>)
    if [ -n "$proj" ] && [ -f "$proj/tests/cutoffs.tsv" ]; then
        local scan_row
        scan_row=$(awk -F'\t' -v want="$el" '$1 == want { print $2 "\t" $3 "\t" $4; exit }' "$proj/tests/cutoffs.tsv" 2>/dev/null)
        if [ -n "$scan_row" ]; then
            local swfc srho supf
            swfc=$(printf '%s' "$scan_row" | cut -f1)
            srho=$(printf '%s' "$scan_row" | cut -f2)
            supf=$(printf '%s' "$scan_row" | cut -f3)
            CUT_WFC=$(awk -v v="$swfc" 'BEGIN { if (v == int(v)) print int(v); else print v }')
            CUT_RHO=$(awk -v v="$srho" 'BEGIN { if (v == int(v)) print int(v); else print v }')
            CUT_SOURCE="project scan"
            CUT_LIBRARY="user scan"
            CUT_PROVENANCE="$proj/tests/cutoffs.tsv ($supf)"
            return 0
        fi
    fi

    # 2. SSSP verification tables
    local norm_acc="efficiency"
    case $(lower "$acc") in
        precision|prec|tight|high) norm_acc="precision" ;;
        *) norm_acc="efficiency" ;;
    esac

    local norm_xc
    norm_xc=$(lower "$xc")

    local sssp_rec
    sssp_rec=$(SSSP_ACCURACY="$norm_acc" sssp_entry "$el" "$norm_xc" 2>/dev/null || \
               SSSP_ACCURACY="$norm_acc" sssp_entry "$el" "pbe" 2>/dev/null || true)
    if [ -n "$sssp_rec" ]; then
        local r_fn r_lib r_wfc r_rho
        r_fn=$(printf '%s' "$sssp_rec" | awk -F'\t' '{print $1}')
        r_lib=$(printf '%s' "$sssp_rec" | awk -F'\t' '{print $2}')
        r_wfc=$(printf '%s' "$sssp_rec" | awk -F'\t' '{print $3}')
        r_rho=$(printf '%s' "$sssp_rec" | awk -F'\t' '{print $4}')

        CUT_WFC=$(awk -v v="$r_wfc" 'BEGIN { if (v == int(v)) print int(v); else print v }')
        CUT_RHO=$(awk -v v="$r_rho" 'BEGIN { if (v == int(v)) print int(v); else print v }')
        CUT_SOURCE="SSSP $norm_acc"
        CUT_LIBRARY="$r_lib"
        CUT_PROVENANCE="SSSP v1.3.0 ($r_fn)"
        return 0
    fi

    # 3. PseudoDojo parameters (ONCVPSP qcut)
    local pd_dir="$PF_DATA/params/pseudodojo"
    local xc_tag="PBE"
    [ "$norm_xc" = "pbesol" ] && xc_tag="PBEsol"
    local pd_set="$pd_dir/ONCVPSP-${xc_tag}-PDv0.4/$el"
    [ -d "$pd_set" ] || pd_set="$pd_dir/ONCVPSP-PBE-PDv0.4/$el"

    if [ -d "$pd_set" ]; then
        local in_file
        in_file=$(find "$pd_set" -name "*.in" 2>/dev/null | head -1)
        if [ -n "$in_file" ] && [ -f "$in_file" ]; then
            local max_qcut
            max_qcut=$(awk '
                /l[[:space:]]+rc[[:space:]]+ep/ { g=1; next }
                g && /^[[:space:]]*#/ { exit }
                g && NF>=6 { if ($6+0 > max) max = $6+0 }
                END { if (max > 0) printf "%.2f", max }
            ' "$in_file")
            if [ -n "$max_qcut" ] && awk -v q="$max_qcut" 'BEGIN { exit (q > 0) ? 0 : 1 }'; then
                CUT_WFC=$(awk -v q="$max_qcut" 'BEGIN { printf "%d", (q * q) + 0.5 }')
                CUT_RHO=$(( CUT_WFC * 4 ))
                CUT_SOURCE="PseudoDojo (ONCVPSP qcut)"
                CUT_LIBRARY="PseudoDojo v0.4"
                CUT_PROVENANCE="PseudoDojo 0.4.1 ($(basename "$in_file"))"
                return 0
            fi
        fi
    fi

    # Never guess
    return 1
}

cutoff_render_json() {
    printf '{\n'
    printf '  "element": %s,\n' "$(http_json_str "$CUT_ELEMENT")"
    printf '  "accuracy": %s,\n' "$(http_json_str "$CUT_ACCURACY")"
    printf '  "xc": %s,\n' "$(http_json_str "$CUT_XC")"
    printf '  "ecutwfc": %s,\n' "${CUT_WFC:-0}"
    printf '  "ecutrho": %s,\n' "${CUT_RHO:-0}"
    printf '  "source": %s,\n' "$(http_json_str "$CUT_SOURCE")"
    printf '  "library": %s,\n' "$(http_json_str "$CUT_LIBRARY")"
    printf '  "provenance": %s\n' "$(http_json_str "$CUT_PROVENANCE")"
    printf '}\n'
}

cutoff_render_human() {
    printf '\n'
    printf 'Recommended Cutoff: %s (%s, %s)\n' "$CUT_ELEMENT" "$CUT_ACCURACY" "$CUT_XC"
    printf '  ecutwfc:     %s Ry\n' "$CUT_WFC"
    printf '  ecutrho:     %s Ry\n' "$CUT_RHO"
    printf '  Source:      %s\n' "$CUT_SOURCE"
    printf '  Library:     %s\n' "$CUT_LIBRARY"
    printf '  Provenance:  %s\n' "$CUT_PROVENANCE"
    printf '\n'
}
