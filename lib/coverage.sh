# shellcheck shell=bash
# ---------------------------------------------------------------------------
# coverage.sh -- matrix of element × profile coverage
#
# Answers "what's available, what's not" across elements and profiles.
# Shows what is in the store (🟢), buildable (🔵), import-only (🟡),
# and not covered (⚪).
# ---------------------------------------------------------------------------

declare -ga COV_OUT_ELEMENTS=()
declare -ga COV_OUT_PROFILES=()
declare -gA COV_OUT_STATE=()
declare -gA COV_OUT_LABEL=()
declare -gA COV_OUT_FAM=()

_cov_find_native_dir() {
    if [ -n "${PF_NATIVE_DIR:-}" ] && [ -f "$PF_NATIVE_DIR/index.tsv" ]; then
        printf '%s\n' "$PF_NATIVE_DIR"
        return 0
    fi
    local cand
    for cand in "${PF_NATIVE_DIR:-}" "/var/lib/pseudoforge/native" "$HOME/pf-native" "$HOME/pf-var/native" "/tmp/pseudoforge-local/native"; do
        if [ -n "$cand" ] && [ -f "$cand/index.tsv" ]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    printf '%s\n' "${PF_NATIVE_DIR:-/var/lib/pseudoforge/native}"
}

_cov_json_esc() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r//g' -e ':a;N;$!ba;s/\n/\\n/g'
}

coverage_matrix() {
    local filter_prof=${1:-}
    local filter_el=${2:-}

    declare -gA SPEC 2>/dev/null || true
    pf_elements_load 2>/dev/null || true
    pf_profiles_load 2>/dev/null || true
    pf_engines_load 2>/dev/null || true
    pf_metadata_load 2>/dev/null || true

    # Normalize element filter if present
    if [ -n "$filter_el" ]; then
        local s norm=""
        for s in "${EL_ORDER[@]}"; do
            if [ "${s,,}" = "${filter_el,,}" ]; then norm=$s; break; fi
        done
        [ -n "$norm" ] || { error "unknown element: $filter_el"; return 1; }
        filter_el=$norm
    fi

    # Determine profiles to show
    COV_OUT_PROFILES=()
    if [ -n "$filter_prof" ]; then
        COV_OUT_PROFILES=("$filter_prof")
    else
        COV_OUT_PROFILES=("psl-high" "pseudodojo" "gbrv" "sssp" "atompaw")
    fi

    # Determine elements to show
    COV_OUT_ELEMENTS=()
    if [ -n "$filter_el" ]; then
        COV_OUT_ELEMENTS=("$filter_el")
    else
        # When no filter, show standard representative elements across the periodic table
        local el
        for el in "${EL_ORDER[@]}"; do
            COV_OUT_ELEMENTS+=("$el")
        done
    fi

    # Clear previous maps
    COV_OUT_STATE=()
    COV_OUT_LABEL=()
    COV_OUT_FAM=()

    # Pre-index store contents
    local store_dir idx
    store_dir=$(_cov_find_native_dir)
    idx="$store_dir/index.tsv"

    declare -A store_has
    if [ -f "$idx" ]; then
        while IFS=$'\t' read -r _el _prof _fam; do
            [ -n "$_el" ] || continue
            # Keep first or preferred family
            if [ -z "${store_has["$_el|$_prof"]:-}" ]; then
                store_has["$_el|$_prof"]=$_fam
            fi
        done < <(awk -F'\t' '!/^#/ && $1 !~ /_rejected_/ { print $2 "\t" $8 "\t" $4 }' "$idx")
    fi

    # Pre-cache profile characteristics
    declare -A prof_kind prof_first_fam
    local p
    for p in "${COV_OUT_PROFILES[@]}"; do
        prof_kind[$p]=$(params_kind "$p" 2>/dev/null || echo none)
        local ff=${PROF_FAMILIES[$p]:-nc}
        prof_first_fam[$p]=${ff%% *}
    done

    # Compute coverage cell for every (element, profile) pair
    local e p key fam kind
    for e in "${COV_OUT_ELEMENTS[@]}"; do
        for p in "${COV_OUT_PROFILES[@]}"; do
            key="$e|$p"
            kind=${prof_kind[$p]:-none}
            fam=${prof_first_fam[$p]:-nc}

            # 1. Is it in the store?
            if [ -n "${store_has[$key]:-}" ]; then
                fam=${store_has[$key]}
                COV_OUT_STATE[$key]="store"
                COV_OUT_FAM[$key]=$fam
                COV_OUT_LABEL[$key]="🟢 ${fam^^}"
            # 2. Is the profile import-only?
            elif [ "$p" = "sssp" ] || [ "$kind" = "selection" ] || [ "$kind" = "import" ]; then
                COV_OUT_STATE[$key]="import-only"
                COV_OUT_FAM[$key]=""
                COV_OUT_LABEL[$key]="🟡 import"
            # 3. Can it be built here?
            elif [ "$kind" = "engine" ] || prof_covers_element "$p" "$e" "$fam" "pbe" "scalar" 2>/dev/null; then
                COV_OUT_STATE[$key]="buildable"
                COV_OUT_FAM[$key]=$fam
                COV_OUT_LABEL[$key]="🔵 ${fam^^}"
            # 4. Absent / not covered
            else
                COV_OUT_STATE[$key]="absent"
                COV_OUT_FAM[$key]=""
                COV_OUT_LABEL[$key]="⚪ —"
            fi
        done
    done

    return 0
}

coverage_render_human() {
    printf 'Coverage — element × profile\n\n'

    # Header line
    printf '%-8s' "Element"
    local p
    for p in "${COV_OUT_PROFILES[@]}"; do
        printf '%-12s' "$p"
    done
    printf '\n'

    # Divider line
    local sep_len=$(( 8 + ${#COV_OUT_PROFILES[@]} * 12 ))
    [ "$sep_len" -lt 65 ] && sep_len=65
    printf '%s\n' "$(printf '─%.0s' $(seq 1 "$sep_len"))"

    # Element rows
    local e key
    for e in "${COV_OUT_ELEMENTS[@]}"; do
        printf '%-8s' "$e"
        for p in "${COV_OUT_PROFILES[@]}"; do
            key="$e|$p"
            printf '%-12s' "${COV_OUT_LABEL[$key]:-⚪ —}"
        done
        printf '\n'
    done

    printf '\nLegend:  🟢 in store   🔵 buildable   🟡 import-only   ⚪ not covered\n'
}

coverage_render_json() {
    printf '[\n'
    local first=1
    local e p key
    for e in "${COV_OUT_ELEMENTS[@]}"; do
        for p in "${COV_OUT_PROFILES[@]}"; do
            key="$e|$p"
            [ "$first" -eq 1 ] || printf ',\n'
            first=0
            printf '  {\n'
            printf '    "element": "%s",\n' "$(_cov_json_esc "$e")"
            printf '    "profile": "%s",\n' "$(_cov_json_esc "$p")"
            printf '    "state": "%s",\n' "$(_cov_json_esc "${COV_OUT_STATE[$key]:-absent}")"
            printf '    "family": "%s",\n' "$(_cov_json_esc "${COV_OUT_FAM[$key]:-}")"
            printf '    "label": "%s"\n' "$(_cov_json_esc "${COV_OUT_LABEL[$key]:-⚪ —}")"
            printf '  }'
        done
    done
    printf '\n]\n'
}
